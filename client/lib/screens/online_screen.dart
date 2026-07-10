import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart' show formatTimestamp;
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
          kEnvServerUrl.isEmpty ? 'Online einrichten' : 'Spielernamen wählen',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // With a build-time server URL (--dart-define) the address is
            // fixed — only the name is asked.
            if (kEnvServerUrl.isEmpty)
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Server-Adresse',
                  hintText: 'https://kaiser.example.com',
                ),
              ),
            TextField(
              controller: nameController,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Dein Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verbinden'),
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
  Future<OnlineSetupResult?> _askSetup(OnlineSetupMode mode) {
    return Navigator.of(context).push<OnlineSetupResult>(
      MaterialPageRoute(
        builder: (_) => OnlineSetupScreen(
          mode: mode,
          displayName: _service?.displayName,
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
    final result = await _askSetup(OnlineSetupMode.joinPublic);
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
        'Partie löschen?',
        'Die wartende Partie wird für alle Spieler gelöscht.',
      ),
      'waiting' => ('Partie verlassen?', 'Dein Platz wird wieder frei.'),
      'active' => (
        'Partie verlassen?',
        'Dein Reich wird ab sofort vom Computer weitergespielt — '
            'eine Rückkehr ist nicht möglich.',
      ),
      _ => (
        'Partie entfernen?',
        'Die beendete Partie verschwindet aus deiner Liste.',
      ),
    };
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              status == 'waiting' && isCreator ? 'Löschen' : 'Verlassen',
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
        title: const Text('Online spielen'),
        actions: [
          IconButton(
            tooltip: kEnvServerUrl.isEmpty ? 'Server & Name' : 'Spielername',
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
                    label: const Text('Neue Partie'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _joinMatch,
                    icon: const Icon(Icons.login),
                    label: const Text('Beitreten per Code'),
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
          Text(
            'Asynchrones Mehrspieler-Kaisern',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Wähle deinen Spielernamen, erstelle eine Partie und teile '
            'den Raum-Code — gespielt wird, wenn du am Zug bist.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _configure,
            icon: const Icon(Icons.person),
            label: const Text('Spielernamen wählen'),
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
              'Angemeldet als ${service.displayName}',
              style: theme.textTheme.labelLarge,
            ),
          ),
          const Divider(height: 1),
          if (_matches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Noch keine Online-Partien — erstelle eine oder '
                'tritt per Raum-Code bei.',
              ),
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
                'waiting' => 'Wartet auf Spieler (${m['joined']} beigetreten)',
                'active' =>
                  m['your_turn'] == true
                      ? 'Du bist am Zug !'
                      : m['awaited_name'] != null
                      ? '${m['awaited_name']} ist am Zug …'
                      // Nobody is awaited: with a running war preparation
                      // that is the duel waiting for its start — say WHEN
                      // instead of a misleading "Warten auf Mitspieler".
                      : m['war_scheduled_at'] != null
                      ? '⚔️ Krieg vereinbart — Beginn: '
                            '${formatWarStartTime(DateTime.parse(m['war_scheduled_at'] as String).millisecondsSinceEpoch)}'
                      : m['war_preparing'] == true
                      ? '⚔️ Krieg steht bevor — Beginn nach Ablauf der Frist'
                      : 'Die Partie läuft …',
                _ => 'Beendet',
              }),
              subtitle: Text(
                'Raum ${m['id']}'
                '${m['turn_deadline'] != null ? ' — ${m['war_preparing'] == true ? 'Kriegsbeginn' : 'Frist'} ${formatTimestamp(m['turn_deadline'] as String)}' : ''}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Raum-Code kopieren',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: m['id'] as String));
                      _toast('Raum-Code kopiert');
                    },
                  ),
                  IconButton(
                    tooltip: m['status'] == 'waiting' && m['is_creator'] == true
                        ? 'Partie löschen'
                        : 'Partie verlassen',
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
                'Öffentliche Partien',
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
        ? 'kein Zeitlimit'
        : hours == 168
        ? '7 Tage/Zug'
        : '$hours h/Zug';
    final host = m['creator_name'] as String?;
    return ListTile(
      leading: const Icon(Icons.public),
      title: Text(host != null ? 'Partie von $host' : 'Offene Partie'),
      subtitle: Text('Raum ${m['id']} · ${m['joined']} beigetreten · $timer'),
      trailing: FilledButton(
        onPressed: () => _joinPublic(m['id'] as String),
        child: const Text('Beitreten'),
      ),
      onTap: () => _joinPublic(m['id'] as String),
    );
  }
}

