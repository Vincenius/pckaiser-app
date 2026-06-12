import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_core/game_core.dart' as gc;

import '../services/api_client.dart';
import '../services/online_service.dart';

/// Online lobby (V2): configure the server + name once, then create
/// matches, join via match ID and watch whose turn it is. The in-match
/// play UI rides on the same screen the moment it is your turn — until
/// the async play integration lands, the lobby shows the live match
/// status (see ARCHITECTURE.md "Turn Flow (online)").
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  OnlineService? _service;
  List<dynamic> _matches = const [];
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
        const Duration(seconds: 20), (_) => _reload(silent: true));
  }

  Future<void> _reload({bool silent = false}) async {
    final service = _service;
    if (service == null || !service.isConfigured) return;
    if (!silent) setState(() => _loading = true);
    try {
      final matches = await service.api.myMatches(service.playerId!);
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _error = null;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _configure() async {
    final service = _service;
    if (service == null) return;
    final urlController =
        TextEditingController(text: service.serverUrl ?? 'http://');
    final nameController =
        TextEditingController(text: service.displayName ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Online einrichten'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: urlController,
            decoration: const InputDecoration(
                labelText: 'Server-Adresse',
                hintText: 'https://kaiser.example.com'),
          ),
          TextField(
            controller: nameController,
            maxLength: 20,
            decoration: const InputDecoration(labelText: 'Dein Name'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Verbinden')),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await service.configure(
        serverUrl: urlController.text.trim(),
        displayName: nameController.text.trim(),
      );
      if (!mounted) return;
      setState(() {});
      await _reload();
      _refresh ??= Timer.periodic(
          const Duration(seconds: 20), (_) => _reload(silent: true));
    } on ApiError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _createMatch() async {
    final setup = await _askSetup(humanCountChoice: true);
    if (setup == null) return;
    final service = _service!;
    try {
      final view = await service.api.createMatch(
        playerId: service.playerId!,
        humanCount: setup.humanCount,
        settings: {
          'turn_timeout_hours': setup.turnTimeoutHours,
        },
        setup: setup.toJson(),
      );
      await _reload();
      if (!mounted) return;
      final id = view['id'] as String;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Partie erstellt'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Teile diese Partie-ID mit deinen Mitspielern:'),
            const SizedBox(height: 8),
            SelectableText(id,
                style: Theme.of(context).textTheme.titleSmall),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: id));
                Navigator.pop(context);
              },
              child: const Text('ID kopieren'),
            ),
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
    } on ApiError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _joinMatch() async {
    final idController = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Partie beitreten'),
        content: TextField(
          controller: idController,
          decoration: const InputDecoration(labelText: 'Partie-ID'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, idController.text.trim()),
              child: const Text('Weiter')),
        ],
      ),
    );
    if (id == null || id.isEmpty) return;
    final setup = await _askSetup(humanCountChoice: false);
    if (setup == null) return;
    final service = _service!;
    try {
      await service.api.joinMatch(
        matchId: id,
        playerId: service.playerId!,
        setup: setup.toJson(),
      );
      await _reload();
    } on ApiError catch (e) {
      _toast(e.message);
    }
  }

  /// Founder setup (and for the host: match size + turn timer).
  Future<_MatchSetup?> _askSetup({required bool humanCountChoice}) async {
    final founderController =
        TextEditingController(text: _service?.displayName ?? '');
    final dorfController = TextEditingController();
    var gender = 0;
    int? slot;
    var humanCount = 2;
    int? timeoutHours = 24;
    return showDialog<_MatchSetup>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(humanCountChoice ? 'Neue Online-Partie' : 'Dein Reich'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (humanCountChoice) ...[
                Row(children: [
                  const Expanded(child: Text('Menschliche Spieler')),
                  DropdownButton<int>(
                    value: humanCount,
                    items: [
                      for (var n = 1; n <= 16; n++)
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (v) => setState(() => humanCount = v ?? 2),
                  ),
                ]),
                Row(children: [
                  const Expanded(child: Text('Zug-Zeitlimit')),
                  DropdownButton<int?>(
                    value: timeoutHours,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Aus')),
                      DropdownMenuItem(value: 12, child: Text('12 h')),
                      DropdownMenuItem(value: 24, child: Text('24 h')),
                      DropdownMenuItem(value: 48, child: Text('48 h')),
                      DropdownMenuItem(value: 168, child: Text('7 Tage')),
                    ],
                    onChanged: (v) => setState(() => timeoutHours = v),
                  ),
                ]),
                const Divider(),
              ],
              TextField(
                controller: founderController,
                maxLength: 20,
                decoration:
                    const InputDecoration(labelText: 'Name des Herrschers'),
              ),
              Row(children: [
                const Expanded(child: Text('Geschlecht')),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('M')),
                    ButtonSegment(value: 1, label: Text('W')),
                  ],
                  selected: {gender},
                  onSelectionChanged: (s) => setState(() => gender = s.first),
                ),
              ]),
              DropdownButtonFormField<int?>(
                initialValue: slot,
                decoration: const InputDecoration(labelText: 'Land'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Zufällig')),
                  for (var s = 1; s <= gc.World.realmCount; s++)
                    DropdownMenuItem(
                        value: s, child: Text(gc.countryNames[s])),
                ],
                onChanged: (v) => setState(() => slot = v),
              ),
              TextField(
                controller: dorfController,
                maxLength: 20,
                decoration:
                    const InputDecoration(labelText: 'Name deines Dorfes'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () {
                final founder = founderController.text.trim();
                final dorf = dorfController.text.trim();
                if (founder.isEmpty || dorf.isEmpty) return;
                Navigator.pop(
                  context,
                  _MatchSetup(
                    founderName: founder,
                    gender: gender,
                    countrySlot: slot,
                    dorfName: dorf,
                    humanCount: humanCount,
                    turnTimeoutHours: timeoutHours,
                  ),
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
            tooltip: 'Server & Name',
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
      floatingActionButton: service != null && service.isConfigured
          ? FloatingActionButton.extended(
              onPressed: _createMatch,
              icon: const Icon(Icons.add),
              label: const Text('Neue Partie'),
            )
          : null,
    );
  }

  Widget _setupPrompt(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_outlined, size: 56),
            const SizedBox(height: 12),
            Text('Asynchrones Mehrspieler-Kaisern',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Verbinde dich mit einem PC-Kaiser-Server, erstelle eine '
              'Partie und teile die Partie-ID — gespielt wird, wenn du '
              'am Zug bist.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _configure,
              icon: const Icon(Icons.cloud),
              label: const Text('Server einrichten'),
            ),
          ]),
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
              leading: Icon(Icons.error_outline,
                  color: theme.colorScheme.error),
              title: Text(_error!),
            ),
          ListTile(
            title: Text('Angemeldet als ${service.displayName}',
                style: theme.textTheme.labelLarge),
            subtitle: Text(service.serverUrl ?? ''),
            trailing: TextButton(
              onPressed: _joinMatch,
              child: const Text('Beitreten per ID'),
            ),
          ),
          const Divider(height: 1),
          if (_matches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Noch keine Online-Partien — erstelle eine oder '
                  'tritt per Partie-ID bei.'),
            ),
          for (final m in _matches.cast<Map>())
            ListTile(
              leading: Icon(switch (m['status'] as String) {
                'waiting' => Icons.hourglass_top,
                'active' => m['your_turn'] == true
                    ? Icons.play_circle
                    : Icons.schedule,
                _ => Icons.emoji_events,
              }),
              title: Text(switch (m['status'] as String) {
                'waiting' =>
                  'Wartet auf Spieler (${m['joined']}/${m['human_count']})',
                'active' => m['your_turn'] == true
                    ? 'Du bist am Zug !'
                    : 'Warten auf Mitspieler …',
                _ => 'Beendet',
              }),
              subtitle: Text('Partie ${(m['id'] as String).substring(0, 8)}…'
                  '${m['turn_deadline'] != null ? ' — Frist ${m['turn_deadline']}' : ''}'),
              trailing: IconButton(
                tooltip: 'Partie-ID kopieren',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: m['id'] as String));
                  _toast('Partie-ID kopiert');
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _MatchSetup {
  _MatchSetup({
    required this.founderName,
    required this.gender,
    required this.countrySlot,
    required this.dorfName,
    required this.humanCount,
    required this.turnTimeoutHours,
  });

  final String founderName;
  final int gender;
  final int? countrySlot;
  final String dorfName;
  final int humanCount;
  final int? turnTimeoutHours;

  Map<String, dynamic> toJson() => {
        'founder_name': founderName,
        'gender': gender,
        if (countrySlot != null) 'country_slot': countrySlot,
        'dorf_name': dorfName,
      };
}
