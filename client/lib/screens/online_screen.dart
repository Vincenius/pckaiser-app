import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart' show formatTimestamp, tr;
import '../services/api_client.dart';
import '../services/match_setup.dart';
import '../services/online_service.dart';
import '../widgets/decisions.dart' show formatWarStartTime;
import 'online_match_screen.dart';
import 'online_setup_screen.dart';

/// Online lobby (V2): configure the server + name once (a build-time
/// `--dart-define=PCKAISER_SERVER_URL` skips the address step), then
/// create matches, join via match ID and open a match — playing happens
/// on the regular game screen when it is your turn (ARCHITECTURE.md
/// "Turn Flow (online)").
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  OnlineService? _service;
  List<dynamic> _matches = const [];
  List<dynamic> _publicMatches = const [];
  bool _loading = true;
  String? _error;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final service = await OnlineService.load();
    if (!mounted) return;
    setState(() => _service = service);
    if (!service.isConfigured) {
      setState(() => _loading = false);
      return;
    }
    await _reload();
    // Clients poll on foreground (no WebSockets in V2's first cut).
    _refresh = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _reload(silent: true),
    );
  }

  bool _reloading = false;

  Future<void> _reload({bool silent = false}) async {
    final service = _service;
    if (service == null || !service.isConfigured) return;
    // No overlap: on a slow network the 20s poll could otherwise race a
    // running reload and a stale response would win the setState.
    if (_reloading) return;
    _reloading = true;
    if (!silent) setState(() => _loading = true);
    try {
      final matches = await service.api.myMatches(service.playerId!);
      // Open public games anyone may join — best-effort: an older server
      // without the endpoint shouldn't break the player's own match list.
      List<dynamic> public = const [];
      try {
        public = await service.api.publicMatches();
      } on ApiError {
        public = const [];
      }
      if (!mounted) return;
      // Hide public games the player already joined (they appear above).
      final mine = {for (final m in matches.cast<Map>()) m['id']};
      setState(() {
        _matches = matches;
        _publicMatches = [
          for (final m in public.cast<Map>())
            if (!mine.contains(m['id'])) m,
        ];
        _error = null;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } finally {
      _reloading = false;
    }
  }

  Future<void> _configure() async {
    final service = _service;
    if (service == null) return;
    final urlController = TextEditingController(
      text: service.serverUrl ?? 'http://',
    );
    final nameController = TextEditingController(
      text: service.displayName ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // Players only ever pick their name — the server address is a
        // dev concern, shown solely when no build-time URL is set.
        title: Text(
          kEnvServerUrl.isEmpty
              ? tr('online.setupTitle')
              : tr('online.choosePlayerName'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // With a build-time server URL (--dart-define) the address is
            // fixed — only the name is asked.
            if (kEnvServerUrl.isEmpty)
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: tr('online.serverAddress'),
                  hintText: 'https://kaiser.example.com',
                ),
              ),
            TextField(
              controller: nameController,
              maxLength: 20,
              decoration: InputDecoration(labelText: tr('online.yourName')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('online.connect')),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await service.configure(
        serverUrl: urlController.text.trim(),
        displayName: nameController.text.trim(),
      );
      // First-time setup: ask for notification permission right away and
      // upload the FCM token (ARCHITECTURE.md "FCM").
      await service.syncPushToken();
      if (!mounted) return;
      setState(() {});
      await _reload();
      _refresh ??= Timer.periodic(
        const Duration(seconds: 20),
        (_) => _reload(silent: true),
      );
    } on ApiError catch (e) {
      _toast(e.message);
    }
  }

  /// Opens the full-screen setup (same design as the local new-game
  /// screen) and pops back with the player's choices — no dialog.
  Future<OnlineSetupResult?> _askSetup(OnlineSetupMode mode, {String? matchId}) {
    return Navigator.of(context).push<OnlineSetupResult>(
      MaterialPageRoute(
        builder: (_) => OnlineSetupScreen(
          mode: mode,
          displayName: _service?.displayName,
          // Lets the setup screen grey out countries already taken in the
          // match (public join: known id; by-code: looked up once entered).
          api: mode == OnlineSetupMode.host ? null : _service?.api,
          matchId: matchId,
        ),
      ),
    );
  }

  Future<void> _createMatch() async {
    final result = await _askSetup(OnlineSetupMode.host);
    if (result == null) return;
    final setup = result.setup;
    final service = _service!;
    try {
      final view = await service.api.createMatch(
        playerId: service.playerId!,
        settings: setup.settingsJson(),
        setup: setup.setupJson(),
      );
      await _reload();
      if (!mounted) return;
      await _open(view['id'] as String);
    } on ApiError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _open(String matchId) async {
    final service = _service;
    if (service == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnlineMatchScreen(service: service, matchId: matchId),
      ),
    );
    await _reload();
  }

  /// Join via room code — the setup screen asks for code and empire in one.
  Future<void> _joinMatch() async {
    final result = await _askSetup(OnlineSetupMode.joinByCode);
    if (result == null) return;
    await _join(result.roomCode!, result.setup);
  }

  /// Join a public game straight from the open-games list (no code needed).
  Future<void> _joinPublic(String id) async {
    final result = await _askSetup(OnlineSetupMode.joinPublic, matchId: id);
    if (result == null) return;
    await _join(id, result.setup);
  }

  Future<void> _join(String id, MatchSetup setup) async {
    final service = _service!;
    try {
      await service.api.joinMatch(
        matchId: id,
        playerId: service.playerId!,
        setup: setup.setupJson(),
      );
      await _reload();
      if (mounted) await _open(id);
    } on ApiError catch (e) {
      _toast(e.message);
    }
  }

  /// Leave/delete with a status-appropriate confirmation: a waiting
  /// match dies with its creator, a running seat falls to the AI.
  Future<void> _leaveMatch(
    String matchId, {
    required String status,
    required bool isCreator,
  }) async {
    final (title, message) = switch (status) {
      'waiting' when isCreator => (
        tr('online.deleteGameQ'),
        tr('online.deleteWaitingBody'),
      ),
      'waiting' => (tr('online.leaveGameQ'), tr('online.leaveWaitingBody')),
      'active' => (tr('online.leaveGameQ'), tr('online.leaveActiveBody')),
      _ => (tr('online.removeGameQ'), tr('online.removeFinishedBody')),
    };
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              tr(status == 'waiting' && isCreator ? 'delete' : 'online.leave'),
            ),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final service = _service;
    if (service == null) return;
    try {
      await service.api.leaveMatch(
        matchId: matchId,
        playerId: service.playerId!,
      );
      await _reload();
    } on ApiError catch (e) {
      _toast(e.message);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = _service;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('online')),
        actions: [
          IconButton(
            tooltip: kEnvServerUrl.isEmpty
                ? tr('online.serverAndName')
                : tr('online.playerNameTooltip'),
            onPressed: _configure,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: service == null
          ? const Center(child: CircularProgressIndicator())
          : !service.isConfigured
          ? _setupPrompt(theme)
          : _lobby(theme, service),
      // Pinned (like the setup screens' start button): create/join stay
      // reachable however long the match list grows.
      bottomNavigationBar: service != null && service.isConfigured
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _createMatch,
                    icon: const Icon(Icons.add),
                    label: Text(tr('online.newMatch')),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _joinMatch,
                    icon: const Icon(Icons.login),
                    label: Text(tr('online.joinByCode')),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _setupPrompt(ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_outlined, size: 56),
          const SizedBox(height: 12),
          Text(tr('online.pitchTitle'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(tr('online.pitchBody'), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _configure,
            icon: const Icon(Icons.person),
            label: Text(tr('online.choosePlayerName')),
          ),
        ],
      ),
    ),
  );

  Widget _lobby(ThemeData theme, OnlineService service) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_error != null)
            ListTile(
              leading: Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(_error!),
            ),
          ListTile(
            title: Text(
              tr('online.signedInAs', {'name': service.displayName}),
              style: theme.textTheme.labelLarge,
            ),
          ),
          const Divider(height: 1),
          if (_matches.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('online.noMatchesYet')),
            ),
          for (final m in _matches.cast<Map>())
            ListTile(
              leading: Icon(switch (m['status'] as String) {
                'waiting' => Icons.hourglass_top,
                'active' =>
                  m['your_turn'] == true ? Icons.play_circle : Icons.schedule,
                _ => Icons.emoji_events,
              }),
              title: Text(switch (m['status'] as String) {
                'waiting' => tr('online.waitingJoined', {'n': m['joined']}),
                'active' =>
                  m['your_turn'] == true
                      ? tr('onlineYourTurn')
                      : m['awaited_name'] != null
                      ? '${m['awaited_name']} ${tr('onlineIsPlaying')}'
                      // Nobody is awaited: with a running war preparation
                      // that is the duel waiting for its start — say WHEN
                      // instead of a misleading "Warten auf Mitspieler".
                      : m['war_scheduled_at'] != null
                      ? '${tr('onlineWarScheduledPrefix')}'
                            '${formatWarStartTime(DateTime.parse(m['war_scheduled_at'] as String).millisecondsSinceEpoch)}'
                      : m['war_preparing'] == true
                      ? tr('onlineWarPending')
                      : tr('onlineInProgress'),
                _ => tr('online.finished'),
              }),
              subtitle: Text(
                '${tr('onlineRoom', {'id': m['id']})}'
                '${m['turn_deadline'] != null ? ' — ${m['war_preparing'] == true ? tr('online.warStartLabel') : tr('online.deadlineLabel')} ${formatTimestamp(m['turn_deadline'] as String)}' : ''}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: tr('online.copyRoomCode'),
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: m['id'] as String));
                      _toast(tr('online.roomCodeCopied'));
                    },
                  ),
                  IconButton(
                    tooltip: m['status'] == 'waiting' && m['is_creator'] == true
                        ? tr('online.deleteGame')
                        : tr('online.leaveGame'),
                    icon: Icon(
                      m['status'] == 'waiting' && m['is_creator'] == true
                          ? Icons.delete_outline
                          : Icons.logout,
                      size: 18,
                    ),
                    onPressed: () => _leaveMatch(
                      m['id'] as String,
                      status: m['status'] as String,
                      isCreator: m['is_creator'] == true,
                    ),
                  ),
                ],
              ),
              onTap: () => _open(m['id'] as String),
            ),
          if (_publicMatches.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                tr('online.publicGames'),
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final m in _publicMatches.cast<Map>())
              _publicMatchTile(theme, m),
          ],
        ],
      ),
    );
  }

  Widget _publicMatchTile(ThemeData theme, Map m) {
    final settings = (m['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final hours = settings['turn_timeout_hours'] as int?;
    final timer = hours == null
        ? tr('online.noTimeLimit')
        : hours == 168
        ? tr('online.sevenDaysPerTurn')
        : tr('online.hoursPerTurn', {'hours': hours});
    final host = m['creator_name'] as String?;
    return ListTile(
      leading: const Icon(Icons.public),
      title: Text(
        host != null
            ? tr('online.gameBy', {'name': host})
            : tr('online.openGame'),
      ),
      subtitle: Text(
        '${tr('onlineRoom', {'id': m['id']})} · '
        '${tr('online.joinedCount', {'n': m['joined']})} · $timer',
      ),
      trailing: FilledButton(
        onPressed: () => _joinPublic(m['id'] as String),
        child: Text(tr('online.join')),
      ),
      onTap: () => _joinPublic(m['id'] as String),
    );
  }
}

