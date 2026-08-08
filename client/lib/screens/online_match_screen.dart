import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/labels.dart' show realmName;
import '../l10n/strings.dart' show formatTimestamp, tr;
import '../services/api_client.dart';
import '../services/online_game_session.dart';
import '../services/online_service.dart';
import '../state/game_controller.dart';
import '../widgets/connection_error.dart';
import '../widgets/decisions.dart' show formatWarStartTime, promptDecisionsFor;
import '../widgets/event_feed.dart' show showDramaPopupsFor;
import '../widgets/room_card.dart' show roomIcon, roomStartLine, roomTitle;
import '../widgets/update_banner.dart';
import 'game_screen.dart';
import 'map_viewer_screen.dart';

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
  /// Last failed server call — typed so the screen can distinguish a
  /// transport failure (retryable, nothing happened) from a rejection.
  ApiError? _error;
  Timer? _poll;
  bool _playing = false;
  bool _promptingDecisions = false;
  bool _refreshing = false;

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

  /// Poll/manual/return-from-play entry point. Guards against overlapping
  /// refreshes (the 10 s poll firing while a manual refresh — or a slow
  /// request, or an open drama/decision dialog — is still in flight): an
  /// older response resolving last would clobber a newer _view with stale
  /// state. The post-decision re-fetch below runs nested via [_fetchView],
  /// which bypasses this guard but is already serialized under it.
  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await _fetchView();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _fetchView() async {
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
      setState(() => _error = e);
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

    // The realm-loss family ('internalStrife' … 'seatLost') is only
    // popup-worthy when a HUMAN seat fell — the payload flag decides in
    // showDramaPopupsFor; listing them here just feeds the candidates.
    const strong = {
      'crowned',
      'realmOverrun',
      'rulerCaptured',
      'playerKicked',
      'internalStrife',
      'bankruptcy',
      'islamicSuccessionCrisis',
      'seatLost',
    };
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
    // An outdated build may not submit anything (the server would 426 the
    // answer) — the update banner explains the situation instead.
    if (view['update_required'] == true) return;
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
    } on gc.ActionException catch (e) {
      // The server rejected the answer (decision already resolved, turn
      // advanced, transport failure). Without feedback the identical
      // dialog re-pops on every 10 s poll and the answer silently
      // vanishes; the re-fetch below drops a stale decision for good.
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      _promptingDecisions = false;
    }
    // Re-fetch to reflect the answered decision. Nested inside the guarded
    // _refresh, so call _fetchView directly (the guard is already held).
    if (mounted) await _fetchView();
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
        title: Text(tr('online.matchTitle')),
        actions: [
          IconButton(
            tooltip: tr('online.refresh'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (view != null)
            IconButton(
              tooltip:
                  view['status'] == 'waiting' &&
                      view['creator_id'] == widget.service.playerId
                  ? tr('online.deleteGame')
                  : tr('online.leaveGame'),
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
          ? (_error == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      ConnectionErrorTile(error: _error!, onRetry: _fetchView),
                    ],
                  ))
          : _body(theme, view),
    );
  }

  /// The status-card line of an ACTIVE match. War-aware: during the rounds
  /// the awaited player "fights" rather than "takes a turn"; while a
  /// both-live duel waits for its start NOBODY is awaited — that wait says
  /// when the war begins instead of a misleading "Warten auf Mitspieler".
  String _activeTitle({
    required bool yourTurn,
    required String? awaitedName,
    required int? awaitedSlot,
    required Map? warJson,
  }) {
    if (yourTurn) return tr('onlineYourTurn');
    final phase = warJson?['phase'];
    if (awaitedName != null) {
      if (awaitedSlot == null) return '$awaitedName ${tr('onlineIsPlaying')}';
      final attacker = warJson?['attackerSlot'] as int?;
      final defender = warJson?['defenderSlot'] as int?;
      if (phase == 'rounds' &&
          (awaitedSlot == attacker || awaitedSlot == defender)) {
        final enemy = awaitedSlot == attacker ? defender : attacker;
        return tr('online.isFighting', {
          'name': awaitedName,
          'realm': realmName(awaitedSlot),
          'enemy': realmName(enemy!),
        });
      }
      return '$awaitedName (${realmName(awaitedSlot)}) '
          '${tr('onlineIsPlaying')}';
    }
    if (phase == 'preparation') {
      final scheduledMs = warJson?['scheduledStartMs'] as int?;
      return scheduledMs != null && scheduledMs > 0
          ? '${tr('onlineWarScheduledPrefix')}${formatWarStartTime(scheduledMs)}'
          : tr('onlineWarPending');
    }
    return tr('onlineInProgress');
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
    final started = status != 'waiting';
    // Matchmaking room (widgets/room_card.dart): server-hosted, no host to
    // wait for — it starts when it is full or when its deadline passes.
    final template =
        ((view['settings'] as Map?)?['template']) as String?;
    final roomSeats = view['seats'] as int? ?? 0;
    final awaitedPid = view['awaited_player_id'];
    // War context for the status card (see [_activeTitle]); the deadline
    // label below also flips to "Kriegsbeginn" during the preparation.
    final warJson = (view['state'] as Map?)?['activeWar'] as Map?;
    final warPreparing = warJson?['phase'] == 'preparation';

    // One row PER controlled realm, so a seat holding several realms (control
    // follows the ruler after a conquest/inheritance) appears at each realm's
    // own turn position. Within a game year the seats play in SLOT order
    // (realm 1 → 30), not join order, so the rows are sorted by slot once the
    // game has started. Eliminated seats (no realm) get a single trailing row.
    // Before the start every seat controls only its home realm → one row each.
    final rows =
        <
          ({
            int slot,
            String realm,
            String? name,
            String? playerId,
            int idleTurns,
            bool isYou,
            bool isAwaited,
          })
        >[];
    final eliminated = <({String? name, bool isYou})>[];
    for (final p in players) {
      final controlled =
          (p['controlled_slots'] as List?)?.cast<int>() ??
          [p['dynasty_index'] as int];
      final name = p['display_name'] as String?;
      final isYou = p['player_id'] == myId;
      if (controlled.isEmpty) {
        eliminated.add((name: name, isYou: isYou));
        continue;
      }
      for (final s in controlled) {
        rows.add((
          slot: s,
          realm: realmName(s),
          name: name,
          playerId: p['player_id'] as String?,
          idleTurns: p['idle_turns'] as int? ?? 0,
          isYou: isYou,
          isAwaited: p['player_id'] == awaitedPid && s == awaitedSlot,
        ));
      }
    }
    // The creator may replace a persistently idle seat (3 missed turns) with
    // the AI — mirrors the server's kick guard.
    final iAmCreator = started && view['creator_id'] == myId;
    if (started) rows.sort((a, b) => a.slot.compareTo(b.slot));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          ConnectionErrorTile(error: _error!, onRetry: _fetchView),
        Card(
          child: ListTile(
            leading: Icon(switch (status) {
              'waiting' when template != null => roomIcon(template),
              'waiting' => Icons.hourglass_top,
              'active' => yourTurn ? Icons.play_circle : Icons.schedule,
              _ => Icons.emoji_events,
            }),
            title: Text(switch (status) {
              // A template key only a NEWER server knows has no local name —
              // fall back like RoomCard does instead of rendering "null".
              'waiting' when template != null =>
                '${roomTitle(template) ?? tr('online.openGame')} · '
                    '${tr('online.seatsOf', {'n': players.length, 'max': roomSeats})}',
              'waiting' => tr('online.waitingJoined', {'n': players.length}),
              'active' => _activeTitle(
                  yourTurn: yourTurn,
                  awaitedName: awaitedName,
                  awaitedSlot: awaitedSlot,
                  warJson: warJson,
                ),
              _ =>
                view['winner'] == widget.service.playerId
                    ? tr('online.victoryFinished')
                    : tr('online.gameFinished'),
            }),
            subtitle: status == 'waiting' && template != null
                ? Text(roomStartLine(
                    joined: players.length,
                    seats: roomSeats,
                    autoStartAt: view['auto_start_at'] as String?,
                  ))
                : view['turn_deadline'] == null
                ? null
                : Text(
                    '${warPreparing ? tr('online.warStartLabel') : tr('online.turnDeadlineLabel')}: '
                    '${formatTimestamp(view['turn_deadline'] as String)}',
                  ),
          ),
        ),
        if (updateRequired)
          UpdateRequiredBanner(
            serverVersion: view['server_app_version'] as String?,
          ),
        if (status == 'waiting') ...[
          const SizedBox(height: 8),
          Text(tr('online.shareRoomCode')),
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
                tooltip: tr('online.copyRoomCode'),
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(
                      text: view['id'] as String? ?? widget.matchId,
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('online.roomCodeCopied'))),
                  );
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          started ? tr('online.turnOrder') : tr('online.players'),
          style: theme.textTheme.titleSmall,
        ),
        // After the start each realm carries its 1-based position in the
        // year's slot-play order; before it there is no order to show yet.
        for (final (i, r) in rows.indexed)
          ListTile(
            dense: true,
            leading: Icon(
              r.isAwaited ? Icons.play_arrow : Icons.person,
              size: 18,
            ),
            title: Text(
              '${r.name != null ? '${r.name} — ' : ''}'
              '${r.realm}${r.isYou ? tr('online.youSuffix') : ''}',
            ),
            subtitle: started
                ? Text(
                    '${tr('online.turnNumber', {'n': i + 1})}'
                    '${r.idleTurns >= 3 ? ' · ${tr('online.idleTurns', {'n': r.idleTurns})}' : ''}',
                  )
                : null,
            trailing:
                iAmCreator && !r.isYou && r.idleTurns >= 3 && r.playerId != null
                ? TextButton.icon(
                    icon: const Icon(Icons.person_off, size: 18),
                    label: Text(tr('online.kick')),
                    onPressed: () => _kick(r.playerId!, r.name ?? r.realm),
                  )
                : null,
          ),
        for (final r in eliminated)
          ListTile(
            dense: true,
            leading: const Icon(Icons.person_off, size: 18),
            title: Text(
              '${r.name != null ? '${r.name} — ' : ''}'
              '${tr('online.eliminated')}'
              '${r.isYou ? tr('online.youSuffix') : ''}',
            ),
          ),
        const SizedBox(height: 16),
        // The creator opens the game once everyone joined — no fixed
        // player count; nobody can join after the start.
        if (status == 'waiting' &&
            view['creator_id'] == widget.service.playerId) ...[
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.flag),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(tr('online.startGame')),
            ),
          ),
          if (players.length == 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                tr('online.soloStartHint'),
                textAlign: TextAlign.center,
              ),
            ),
        ],
        // A matchmaking room has no host to wait for — say what actually
        // makes it start (the server sends no creator_id for one).
        if (status == 'waiting' && template != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr('online.roomWaiting', {'n': roomSeats}),
              textAlign: TextAlign.center,
            ),
          )
        else if (status == 'waiting' &&
            view['creator_id'] != widget.service.playerId)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr('online.waitForHost'),
              textAlign: TextAlign.center,
            ),
          ),
        if (status == 'active' && yourTurn && !updateRequired)
          FilledButton.icon(
            onPressed: _play,
            icon: const Icon(Icons.play_arrow),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(tr('online.playTurn')),
            ),
          ),
        // Off-turn: let the seat study the board and their own realm(s)
        // (read-only, Info menu included) while waiting for the others. The
        // server already ships this seat's filtered state, so no extra
        // request is needed. During a WAR PREPARATION involving this seat
        // the same view is where the troops are lined up (each unit's
        // stance individually) — say so on the button.
        if (status == 'active' && !yourTurn && view['state'] != null)
          OutlinedButton.icon(
            onPressed: () => _viewMap(view),
            icon: Icon(
              warPreparing && _iAmWarParticipant(view)
                  ? Icons.gavel
                  : Icons.map_outlined,
            ),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                warPreparing && _iAmWarParticipant(view)
                    ? tr('online.warPrepDeploy')
                    : tr('online.viewRealmAndMap'),
              ),
            ),
          ),
      ],
    );
  }

  /// Whether one of this seat's controlled realms fights in the active
  /// war (drives the preparation wording of the off-turn map button).
  bool _iAmWarParticipant(Map<String, dynamic> view) {
    final warJson = (view['state'] as Map?)?['activeWar'] as Map?;
    if (warJson == null) return false;
    final mySlots = <int>{};
    for (final p in (view['players'] as List).cast<Map>()) {
      if (p['player_id'] != widget.service.playerId) continue;
      mySlots.addAll(
        (p['controlled_slots'] as List?)?.cast<int>() ??
            [p['dynasty_index'] as int],
      );
    }
    return mySlots.contains(warJson['attackerSlot'] as int?) ||
        mySlots.contains(warJson['defenderSlot'] as int?);
  }

  /// Opens the read-only realm/map view for this seat while another player
  /// is at the turn. Pauses polling like [_play] so a background refresh
  /// can't pop a drama dialog over the viewer; refreshes again on return.
  Future<void> _viewMap(Map<String, dynamic> view) async {
    final session = OnlineGameSession(
      api: widget.service.api,
      matchId: widget.matchId,
      playerId: widget.service.playerId!,
      view: view,
    );
    // Who the match is waiting for, mirrored from the status card above.
    String? waitingFor;
    final awaitedSlot = view['awaited_slot'] as int?;
    for (final p in (view['players'] as List).cast<Map>()) {
      if (p['player_id'] == view['awaited_player_id']) {
        final name = p['display_name'] as String?;
        if (name != null && awaitedSlot != null) {
          waitingFor =
              '$name (${realmName(awaitedSlot)}) ${tr('onlineIsPlaying')}';
        }
      }
    }
    _playing = true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapViewerScreen(
          session: session,
          viewerSlot: session.yourSlot,
          waitingFor: waitingFor,
        ),
      ),
    );
    _playing = false;
    await _refresh();
  }

  /// Leave/delete this match (mirrors the lobby's per-match action):
  /// the creator deletes a waiting match, otherwise the seat is freed —
  /// in a running game the realm falls to the AI.
  Future<void> _leave() async {
    final view = _view;
    if (view == null) return;
    final status = view['status'] as String;
    final deletes =
        status == 'waiting' && view['creator_id'] == widget.service.playerId;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(deletes ? tr('online.deleteGameQ') : tr('online.leaveGameQ')),
        content: Text(switch (status) {
          'waiting' when deletes => tr('online.deleteWaitingBody'),
          'waiting' => tr('online.leaveWaitingBody'),
          'active' => tr('online.leaveActiveBody'),
          _ => tr('online.removeFinishedBody'),
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(deletes ? 'delete' : 'online.leave')),
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
      setState(() => _error = e);
    }
  }

  /// Creator only: replace a persistently idle seat with the AI. The
  /// server enforces the same "3 missed turns" guard.
  Future<void> _kick(String targetPlayerId, String label) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('online.kickPlayerQ')),
        content: Text(tr('online.kickPlayerBody', {'name': label})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('online.kick')),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      final view = await widget.service.api.kickPlayer(
        matchId: widget.matchId,
        playerId: widget.service.playerId!,
        targetPlayerId: targetPlayerId,
      );
      if (!mounted) return;
      setState(() {
        _view = view;
        _error = null;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
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
      setState(() => _error = e);
    }
  }
}
