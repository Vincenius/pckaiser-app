import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';

import '../services/game_session.dart';

/// UI-facing game state for one running game (local hot-seat or online):
/// wraps the session, manages the in-turn undo stack (local only), drives
/// AI advancement and wars, and tracks handoffs and the "since your last
/// turn" recap baseline. All actions are async — local sessions complete
/// immediately, online sessions round-trip to the server.
class GameController extends ChangeNotifier {
  GameController(this._session) {
    _handoffPending = _session.isOnline ? true : humanCount > 0;
    // The seat, not the engine's active player: a save resumed inside a
    // war pause must hand the device to the human war side.
    _handoffToSlot = currentSlot;
    _lastSeat = currentSlot;
  }

  final GameSession _session;
  final List<GameState> _undoStack = [];

  bool _handoffPending = false;
  int _handoffToSlot = 0;
  int _lastSeat = 0;
  bool _busy = false;

  /// The war unit the player has selected on the map (index into the
  /// human war side's troop list); null = nothing selected.
  int? selectedWarUnit;

  /// Hint banner text while a map tile pick is active (e.g. "station the
  /// new troop"); null = no pick pending.
  String? tilePickHint;
  Future<bool> Function(int x, int y)? _tilePick;

  bool get tilePickActive => _tilePick != null;

  /// Routes the next map taps to [onPick] instead of the tile sheet.
  /// [onPick] returns true to accept the tile (ends the pick) or false to
  /// reject it (the pick stays active).
  void startTilePick({
    required String hint,
    required Future<bool> Function(int x, int y) onPick,
  }) {
    tilePickHint = hint;
    _tilePick = onPick;
    notifyListeners();
  }

  void cancelTilePick() {
    if (_tilePick == null) return;
    _tilePick = null;
    tilePickHint = null;
    notifyListeners();
  }

  /// Feeds a map tap into the active pick; returns false when none is.
  Future<bool> resolveTilePick(int x, int y) async {
    final pick = _tilePick;
    if (pick == null) return false;
    if (await pick(x, y)) {
      _tilePick = null;
      tilePickHint = null;
    }
    notifyListeners();
    return true;
  }

  GameState get state => _session.state;

  /// True for online seats — the server is authoritative.
  bool get isOnline => _session.isOnline;

  /// Online: another player is awaited — the play screen should hand
  /// back to the waiting lobby.
  bool get awaitingRemote => _session.awaitingRemote;

  /// What the seated player may see (hidden information). Filtered for
  /// [currentSlot] — the *seat*, not necessarily the engine's active
  /// player (see [currentSlot]). Online states arrive pre-filtered from
  /// the server; the local filter is idempotent on them.
  GameState get visibleState => visibleStateFor(state, currentSlot);

  /// The slot of the player seated at the device. Normally the engine's
  /// active player; during a war it is the war side whose input is
  /// awaited (the acting human side — `warActingSlot`), which pauses
  /// another realm's turn: an AI attacker's, or in a human-vs-human war
  /// the human attacker's while the defender responds. Keying the whole
  /// UI (map filter, status row, menus) off the seat keeps the seated
  /// player from seeing or controlling the paused realm.
  int get currentSlot {
    if (state.activeWar != null) {
      final acting = warActingSlot(state);
      if (acting != null) return acting;
    }
    return state.currentPlayer;
  }

  /// True while a war pauses another realm's turn: the seated player may
  /// only act in the war, so the regular menus are locked (they would
  /// issue actions outside the seat's own turn).
  bool get warPauseActive => currentSlot != state.currentPlayer;

  Realm get currentRealm => state.realm(currentSlot);

  int get humanCount =>
      state.dynasties.where((d) => d.status == DynastyStatus.human).length;

  bool get busy => _busy;

  /// True while the device should show the "hand to player X" blocker.
  bool get handoffPending => _handoffPending;
  int get handoffToSlot => _handoffToSlot;

  bool get canUndo => _undoStack.isNotEmpty;

  /// False online: the server never takes an action back.
  bool get supportsUndo => _session.canUndo;

  bool get gameOver =>
      state.events.isNotEmpty &&
      (state.events.last.type == 'gameWon' ||
          state.events.last.type == 'gameDraw' ||
          state.events.last.type == 'humansDefeated');

  /// The active war, when the seated player participates in it.
  ActiveWar? get warForCurrentPlayer {
    final war = state.activeWar;
    if (war == null) return null;
    final humanSide = [
      war.attackerSlot,
      war.defenderSlot,
    ].where((s) => state.dynasty(s).status == DynastyStatus.human);
    if (humanSide.isEmpty) return null;
    return war;
  }

  /// The human slot that must act in the current war (the acting side —
  /// in a human-vs-human war the input alternates within each round).
  int? get warHumanSlot => warActingSlot(state);

  List<PendingDecision> get decisionsForCurrent => state.pendingDecisions
      .where((d) => d.decidingSlot == currentSlot)
      .toList();

  /// Events the seated player has not seen yet — the recap card. The
  /// baseline is an absolute event position (`prunedEventCount + index`,
  /// stable across pruning) stored in the game state, so it survives app
  /// restarts (and lives server-side for online seats).
  List<GameEvent> recapFor(int slot) {
    final baseline = state.recapBaselines[slot] ?? 0;
    final from = (baseline - state.prunedEventCount).clamp(
      0,
      state.events.length,
    );
    return [
      for (var i = from; i < state.events.length; i++)
        if (state.events[i].visibleTo(slot)) state.events[i],
    ];
  }

  void confirmHandoff() {
    _handoffPending = false;
    _lastSeat = currentSlot;
    notifyListeners();
  }

  /// Hot-seat: when the seat changed hands (a human-vs-human war passes
  /// the input between the two sides, a war end returns it to the paused
  /// turn's player), raise the handoff blocker so the device can be
  /// passed without leaking the successor's view.
  void _maybeRequestSeatHandoff() {
    final seat = currentSlot;
    if (seat == _lastSeat) return;
    _lastSeat = seat;
    // Online a device seats exactly one player — no handoff, the screen
    // hands back to the lobby via [awaitingRemote] instead.
    if (_session.isOnline) return;
    if (state.dynasty(seat).status != DynastyStatus.human) return;
    _handoffPending = true;
    _handoffToSlot = seat;
  }

  void markRecapSeen(int slot) {
    // Written into the session's live state (persisted with the next
    // auto-save) — endTurn copies the state right after, carrying it
    // over. Online the server moves the baseline at end_turn; this local
    // write only keeps the recap from re-showing within the turn.
    state.recapBaselines[slot] = state.prunedEventCount + state.events.length;
  }

  /// Deterministic in-turn action — undoable locally
  /// (PROJECT_REQUIREMENTS); online there is no undo, the action is final.
  Future<ActionResult> applyUndoable(PlayerAction action) async {
    final snapshot = state;
    final result = await _session.apply(action);
    if (_session.canUndo) _undoStack.add(snapshot);
    notifyListeners();
    return result;
  }

  /// Randomized or irreversible action — clears the undo stack.
  Future<ActionResult> applyIrreversible(PlayerAction action) async {
    final result = await _session.apply(action);
    _undoStack.clear();
    notifyListeners();
    return result;
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _session.restore(_undoStack.removeLast());
    notifyListeners();
  }

  /// Ends the seated player's turn: clears undo, lets the AI play, then
  /// requests a handoff to the next human (auto-saved inside). Online the
  /// server advances; when another player is awaited afterwards,
  /// [awaitingRemote] turns true and the play screen hands back.
  Future<void> endTurn() async {
    if (_busy) return;
    _busy = true;
    _tilePick = null;
    tilePickHint = null;
    _undoStack.clear();
    markRecapSeen(currentSlot);
    notifyListeners();
    try {
      await _session.endTurnAndAdvance();
      _handoffToSlot = state.currentPlayer;
      if (_session.isOnline) {
        // One device seats exactly one player online: a handoff appears
        // only when the next awaited input is again this seat's.
        _handoffPending = !_session.awaitingRemote && !gameOver;
      } else {
        _handoffPending =
            humanCount > 1 ||
            state.dynasty(state.currentPlayer).status == DynastyStatus.human;
      }
      // A war against a human defender pauses the AI advance; the war UI
      // takes over instead of a handoff.
      if (state.activeWar != null && !_session.awaitingRemote) {
        _handoffPending = true;
        _handoffToSlot = warHumanSlot ?? _handoffToSlot;
      }
      _lastSeat = currentSlot;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Ends the seated player's war-round input: in a human-vs-human war
  /// the attacker hands the round to the defender, otherwise the AI side
  /// moves and the round advances. When the war finishes, AI turns
  /// resume until a human's action phase. Returns the round's events
  /// (battles, plunders, war end) so the UI can show them as a report
  /// popup.
  Future<List<GameEvent>> endWarRound() async {
    if (_busy) return const [];
    final actingSlot = warHumanSlot;
    _busy = true;
    selectedWarUnit = null;
    notifyListeners();
    var events = const <GameEvent>[];
    // Pre-round positions of the AI side's units: the human can't watch
    // the AI act, so the round report lists the enemy's movements.
    final beforePositions = <int, List<(String, int, int)>>{};
    final warBefore = state.activeWar;
    if (warBefore != null) {
      for (final slot in [warBefore.attackerSlot, warBefore.defenderSlot]) {
        if (state.dynasty(slot).status != DynastyStatus.human) {
          beforePositions[slot] = [
            for (final t in state.realm(slot).troops) (t.name, t.x, t.y),
          ];
        }
      }
    }
    try {
      _undoStack.clear();
      // One shared engine entry point (client + server): a human-vs-human
      // attacker hands over, otherwise the AI sides respond and the round
      // advances — see endWarRoundFor.
      if (actingSlot != null) {
        events = await _session.endWarRound(actingSlot);
        // Mark the war report "seen up to here" for the side that just acted,
        // so the next war turn's report shows only the opponent's response,
        // not every battle since this player's last full turn. Online the
        // server already moved the baseline (and ran any post-war AI advance
        // after it); re-doing it here would hide those post-war events from
        // the recap — so only the local engine needs this.
        if (!_session.isOnline) markRecapSeen(actingSlot);
      }
      await _resumeAfterWarIfOver();
      _maybeRequestSeatHandoff();
    } finally {
      _busy = false;
      notifyListeners();
    }
    return [...events, ..._enemyMovementEvents(beforePositions)];
  }

  /// Synthetic (report-only, never stored) events describing what the AI
  /// side's units did this round. Skipped once the war is over — the
  /// post-war troop return would otherwise read as movement.
  List<GameEvent> _enemyMovementEvents(
    Map<int, List<(String, int, int)>> before,
  ) {
    if (before.isEmpty || state.activeWar == null) return const [];
    final events = <GameEvent>[];
    for (final entry in before.entries) {
      final troops = state.realm(entry.key).troops;
      if (troops.isEmpty) continue;
      // Match after-units to a distinct same-named before-entry, in list
      // order (names can repeat — same scheme as the war snapshots).
      final used = List<bool>.filled(entry.value.length, false);
      var moves = 0;
      for (final troop in troops) {
        for (var i = 0; i < entry.value.length; i++) {
          final (name, x, y) = entry.value[i];
          if (used[i] || name != troop.name) continue;
          used[i] = true;
          if (x != troop.x || y != troop.y) {
            moves++;
            events.add(
              GameEvent(
                year: state.year,
                slot: entry.key,
                type: 'enemyMoved',
                visibility: EventVisibility.public,
                payload: {
                  'unit': troop.name,
                  'fromX': x,
                  'fromY': y,
                  'x': troop.x,
                  'y': troop.y,
                },
              ),
            );
          }
          break;
        }
      }
      if (moves == 0) {
        events.add(
          GameEvent(
            year: state.year,
            slot: entry.key,
            type: 'enemyHolds',
            visibility: EventVisibility.public,
          ),
        );
      }
    }
    return events;
  }

  /// Call after a war action ended the war outside [endWarRound] (capital
  /// capture during a march): resumes the paused AI advance and saves.
  Future<void> resumeAfterWar() async {
    if (_busy || state.activeWar != null) return;
    _busy = true;
    notifyListeners();
    try {
      await _resumeAfterWarIfOver();
      _maybeRequestSeatHandoff();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// After a war ends outside the turn flow, resume the AI advance
  /// (local; the server does this inside the submission online).
  Future<void> _resumeAfterWarIfOver() async {
    if (state.activeWar != null) {
      await _session.save();
      return;
    }
    // A war that interrupted AI processing leaves the AI attacker's turn
    // half-finished — the session completes it and advances.
    final pausedAiTurn =
        !_session.isOnline &&
        state.dynasty(state.currentPlayer).status != DynastyStatus.human;
    await _session.resumeAfterWar();
    if (pausedAiTurn) {
      _handoffPending = true;
      _handoffToSlot = state.currentPlayer;
    }
  }

  void selectWarUnit(int? index) {
    selectedWarUnit = index;
    notifyListeners();
  }

  /// War actions from the war panel (move, plunder, peace wish,
  /// settlement picks). A settlement finish can end the war and return
  /// the seat to the paused turn's player — hot-seat then needs a
  /// handoff before the successor's view appears.
  Future<ActionResult> applyWarAction(PlayerAction action) async {
    final result = await _session.apply(action);
    _undoStack.clear();
    if (state.activeWar == null) selectedWarUnit = null;
    _maybeRequestSeatHandoff();
    notifyListeners();
    return result;
  }

  /// Resolves a pending decision for [slot].
  Future<void> resolveDecision(
    String decisionId,
    int slot,
    Map<String, dynamic> choice,
  ) async {
    await _session.apply(
      ResolveDecision(slot: slot, decisionId: decisionId, choice: choice),
    );
    await _session.save();
    notifyListeners();
  }
}
