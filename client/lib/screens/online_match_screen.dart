import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/strings.dart' show formatTimestamp;
import '../services/api_client.dart';
import '../services/online_game_session.dart';
import '../services/online_service.dart';
import '../state/game_controller.dart';
import '../widgets/decisions.dart' show promptDecisionsFor;
import '../widgets/event_feed.dart' show showDramaPopupsFor;
import 'game_screen.dart';

/// One online match: polls the server while waiting (for players or for
/// the other seats' turns) and opens the regular game screen on this
/// seat's turn. Out-of-turn pending decisions (marriage consent, …) are
/// prompted right from the waiting view.
class OnlineMatchScreen extends StatefulWidget {
  const OnlineMatchScreen({
    super.key,
    required this.service,
    required this.matchId,
  });

  final OnlineService service;
  final String matchId;

  @override
  State<OnlineMatchScreen> createState() => _OnlineMatchScreenState();
}

class _OnlineMatchScreenState extends State<OnlineMatchScreen> {
  Map<String, dynamic>? _view;
  String? _error;
  Timer? _poll;
  bool _playing = false;
  bool _promptingDecisions = false;

  /// Absolute event positions already surfaced as out-of-turn drama popups
  /// (so the 10 s poll never re-pops the same coronation). Seeded with the
  /// history on first load so opening the screen never replays old drama.
  final Set<int> _shownDrama = {};
  bool _dramaSeeded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_playing) _refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final view = await widget.service.api.match(
        widget.matchId,
        widget.service.playerId!,
      );
      if (!mounted) return;
      setState(() {
        _view = view;
        _error = null;
      });
      await _maybeShowDrama(view);
      await _maybePromptDecisions(view);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  /// Strong, story-worthy events (a coronation of THIS player, a human
  /// player losing their realm or ruler) get a popup the moment they happen
  /// — even while this seat is only watching — instead of waiting for the
  /// next own turn. Each is shown once (tracked by absolute event position).
  Future<void> _maybeShowDrama(Map<String, dynamic> view) async {
    if (_playing || _promptingDecisions) return;
    if (view['status'] != 'active') return;
    // On the player's own turn the turn-start recap (GameScreen handoff)
    // shows these popups — don't also pop them here right before they play.
    if (view['your_turn'] == true) return;
    final stateJson = view['state'];
    if (stateJson == null) return;
    final session = OnlineGameSession(
      api: widget.service.api,
      matchId: widget.matchId,
      playerId: widget.service.playerId!,
      view: view,
    );
    final mySlot = session.yourSlot;
    final state = session.state;
    final base = state.prunedEventCount;

    // First load: remember the whole history as "seen" so we never replay
    // drama from before the screen was opened.
    if (!_dramaSeeded) {
      _dramaSeeded = true;
      for (var i = 0; i < state.events.length; i++) {
        _shownDrama.add(base + i);
      }
      return;
    }

    const strong = {'crowned', 'realmOverrun', 'rulerCaptured'};
    final fresh = <gc.GameEvent>[];
    for (var i = 0; i < state.events.length; i++) {
      final pos = base + i;
      if (!_shownDrama.add(pos)) continue; // already handled
      final e = state.events[i];
      if (strong.contains(e.type)) fresh.add(e);
    }
    if (fresh.isEmpty || !mounted) return;
    _promptingDecisions = true; // reuse the lock so dialogs never overlap
    try {
      await showDramaPopupsFor(context, fresh, mySlot);
    } finally {
      _promptingDecisions = false;
    }
  }

  /// Decisions addressed to this seat are answerable out of turn
  /// (marriage consent, convert-or-die) — prompt them from the waiting
  /// view instead of letting them sit until the next own turn.
  Future<void> _maybePromptDecisions(Map<String, dynamic> view) async {
    if (_playing || _promptingDecisions) return;
    if (view['status'] != 'active' || view['your_turn'] == true) return;
    final stateJson = view['state'];
    if (stateJson == null) return;
    final session = OnlineGameSession(
      api: widget.service.api,
      matchId: widget.matchId,
      playerId: widget.service.playerId!,
      view: view,
    );
    final mySlot = session.yourSlot;
    final pending = session.state.pendingDecisions.any(
      (d) => d.decidingSlot == mySlot,
    );
    if (!pending) return;
    _promptingDecisions = true;
    try {
      final controller = GameController(session);
      if (mounted) await promptDecisionsFor(context, controller, mySlot);
    } finally {
      _promptingDecisions = false;
    }
    if (mounted) await _refresh();
  }

  Future<void> _play() async {
    final view = _view;
    if (view == null ||
        view['your_turn'] != true ||
        view['update_required'] == true) {
      return;
    }
    final session = OnlineGameSession(
      api: widget.service.api,
      matchId: widget.matchId,
      playerId: widget.service.playerId!,
      view: view,
    );
    _playing = true;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameScreen.online(session: session)),
    );
    _playing = false;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = _view;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online-Partie'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (view != null)
            IconButton(
              tooltip: view['status'] == 'waiting' &&
                      view['creator_id'] == widget.service.playerId
                  ? 'Partie löschen'
                  : 'Partie verlassen',
              onPressed: _leave,
              icon: Icon(
                view['status'] == 'waiting' &&
                        view['creator_id'] == widget.service.playerId
                    ? Icons.delete_outline
                    : Icons.logout,
              ),
            ),
        ],
      ),
      body: view == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : _body(theme, view),
    );
  }

  Widget _body(ThemeData theme, Map<String, dynamic> view) {
    final status = view['status'] as String;
    final yourTurn = view['your_turn'] == true;
    final players = (view['players'] as List).cast<Map>();
    Map? awaitedSeat;
    for (final p in players) {
      if (p['player_id'] == view['awaited_player_id']) awaitedSeat = p;
    }
    // An older server omits display_name — fall back to the generic
    // waiting line / plain country names instead of showing "null".
    final awaitedName = awaitedSeat == null
        ? null
        : awaitedSeat['display_name'] as String?;
    // The exact realm being played — when the awaited player holds several
    // realms it differs from their home slot. Falls back to the home slot
    // for older servers that don't send it.
    final awaitedSlot =
        view['awaited_slot'] as int? ?? awaitedSeat?['dynasty_index'] as int?;
    final updateRequired = view['update_required'] == true;
    final myId = widget.service.playerId;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          ListTile(
            leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
            title: Text(_error!),
          ),
        Card(
          child: ListTile(
            leading: Icon(switch (status) {
              'waiting' => Icons.hourglass_top,
              'active' => yourTurn ? Icons.play_circle : Icons.schedule,
              _ => Icons.emoji_events,
            }),
            title: Text(switch (status) {
              'waiting' =>
                'Wartet auf Spieler (${players.length} beigetreten)',
              'active' => yourTurn
                  ? 'Du bist am Zug !'
                  : awaitedName != null
                      ? '$awaitedName '
                          '(${gc.countryNames[awaitedSlot!]}) '
                          'ist am Zug …'
                      : 'Warten auf Mitspieler …',
              _ =>
                view['winner'] == widget.service.playerId
                    ? 'Sieg ! Die Partie ist beendet.'
                    : 'Die Partie ist beendet.',
            }),
            subtitle: view['turn_deadline'] == null
                ? null
                : Text(
                    'Zugfrist: '
                    '${formatTimestamp(view['turn_deadline'] as String)}',
                  ),
          ),
        ),
        if (updateRequired)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: Icon(
                Icons.system_update,
                color: theme.colorScheme.onErrorContainer,
              ),
              title: Text(
                'App-Update erforderlich',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
              subtitle: Text(
                'Diese Partie läuft auf Version '
                '${view['server_app_version'] ?? '?'}. Bitte aktualisiere '
                'die App, um deinen Zug zu machen.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ),
        if (status == 'waiting') ...[
          const SizedBox(height: 8),
          const Text(
            'Teile den Raum-Code, damit deine Mitspieler beitreten können:',
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SelectableText(
                view['id'] as String? ?? widget.matchId,
                style: theme.textTheme.headlineMedium?.copyWith(
                  letterSpacing: 6,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                tooltip: 'Raum-Code kopieren',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(
                      text: view['id'] as String? ?? widget.matchId,
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Raum-Code kopiert')),
                  );
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text('Spieler', style: theme.textTheme.titleSmall),
        for (final p in players)
          Builder(
            builder: (context) {
              // Every realm this seat currently plays — one player can hold
              // several after a conquest or inheritance (control follows the
              // ruler). An eliminated seat controls none.
              final controlled =
                  (p['controlled_slots'] as List?)?.cast<int>() ??
                  [p['dynasty_index'] as int];
              final isYou = p['player_id'] == myId;
              final isAwaited = p['player_id'] == view['awaited_player_id'];
              final realms = controlled.isEmpty
                  ? 'ausgeschieden'
                  : [for (final s in controlled) gc.countryNames[s]].join(', ');
              return ListTile(
                dense: true,
                leading: Icon(
                  isAwaited ? Icons.play_arrow : Icons.person,
                  size: 18,
                ),
                title: Text(
                  '${p['display_name'] != null ? '${p['display_name']} — ' : ''}'
                  '$realms${isYou ? ' (du)' : ''}',
                ),
                subtitle: Text(
                  'Zugreihenfolge ${(p['turn_order'] as int) + 1}'
                  '${controlled.length > 1 ? ' · ${controlled.length} Reiche' : ''}',
                ),
              );
            },
          ),
        const SizedBox(height: 16),
        // The creator opens the game once everyone joined — no fixed
        // player count; nobody can join after the start.
        if (status == 'waiting' &&
            view['creator_id'] == widget.service.playerId) ...[
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.flag),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Spiel starten'),
            ),
          ),
          if (players.length == 1)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Du kannst auch allein gegen die 29 Computer-Reiche '
                'starten — danach kann niemand mehr beitreten.',
                textAlign: TextAlign.center,
              ),
            ),
        ],
        if (status == 'waiting' &&
            view['creator_id'] != widget.service.playerId)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Warte, bis der Gastgeber das Spiel startet …',
              textAlign: TextAlign.center,
            ),
          ),
        if (status == 'active' && yourTurn && !updateRequired)
          FilledButton.icon(
            onPressed: _play,
            icon: const Icon(Icons.play_arrow),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Zug spielen'),
            ),
          ),
      ],
    );
  }

  /// Leave/delete this match (mirrors the lobby's per-match action):
  /// the creator deletes a waiting match, otherwise the seat is freed —
  /// in a running game the realm falls to the AI.
  Future<void> _leave() async {
    final view = _view;
    if (view == null) return;
    final status = view['status'] as String;
    final deletes = status == 'waiting' &&
        view['creator_id'] == widget.service.playerId;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(deletes ? 'Partie löschen?' : 'Partie verlassen?'),
        content: Text(switch (status) {
          'waiting' when deletes =>
            'Die wartende Partie wird für alle Spieler gelöscht.',
          'waiting' => 'Dein Platz wird wieder frei.',
          'active' =>
            'Dein Reich wird ab sofort vom Computer weitergespielt — '
                'eine Rückkehr ist nicht möglich.',
          _ => 'Die beendete Partie verschwindet aus deiner Liste.',
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(deletes ? 'Löschen' : 'Verlassen'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await widget.service.api.leaveMatch(
        matchId: widget.matchId,
        playerId: widget.service.playerId!,
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _start() async {
    try {
      final view = await widget.service.api.startMatch(
        matchId: widget.matchId,
        playerId: widget.service.playerId!,
      );
      if (!mounted) return;
      setState(() {
        _view = view;
        _error = null;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }
}
