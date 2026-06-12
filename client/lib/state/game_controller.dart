import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';

import '../services/local_game_session.dart';

/// UI-facing game state for one running local game: wraps the session,
/// manages the in-turn undo stack, drives AI advancement and wars, and
/// tracks hot-seat handoffs and the "since your last turn" recap baseline.
class GameController extends ChangeNotifier {
  GameController(this._session) {
    _handoffPending = humanCount > 0;
    // The seat, not the engine's active player: a save resumed inside a
    // war pause must hand the device to the human war side.
    _handoffToSlot = currentSlot;
  }

  final LocalGameSession _session;
  final List<GameState> _undoStack = [];

  bool _handoffPending = false;
  int _handoffToSlot = 0;
  bool _busy = false;

  /// The war unit the player has selected on the map (index into the
  /// human war side's troop list); null = nothing selected.
  int? selectedWarUnit;

  /// Hint banner text while a map tile pick is active (e.g. "station the
  /// new troop"); null = no pick pending.
  String? tilePickHint;
  bool Function(int x, int y)? _tilePick;

  bool get tilePickActive => _tilePick != null;

  /// Routes the next map taps to [onPick] instead of the tile sheet.
  /// [onPick] returns true to accept the tile (ends the pick) or false to
  /// reject it (the pick stays active).
  void startTilePick({
    required String hint,
    required bool Function(int x, int y) onPick,
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
  bool resolveTilePick(int x, int y) {
    final pick = _tilePick;
    if (pick == null) return false;
    if (pick(x, y)) {
      _tilePick = null;
      tilePickHint = null;
    }
    notifyListeners();
    return true;
  }

  GameState get state => _session.state;

  /// What the seated player may see (hidden information). Filtered for
  /// [currentSlot] — the *seat*, not necessarily the engine's active
  /// player (see [currentSlot]).
  GameState get visibleState => visibleStateFor(state, currentSlot);

  /// The slot of the player seated at the device. Normally the engine's
  /// active player; during a war pause (an AI's turn stands paused while
  /// its human war opponent acts) it is the human war side — keying the
  /// whole UI (map filter, status row, menus) off the seat keeps the
  /// human from seeing or controlling the paused AI realm.
  int get currentSlot {
    final war = state.activeWar;
    if (war != null &&
        state.dynasty(state.currentPlayer).status != DynastyStatus.human) {
      return warHumanSlot ?? state.currentPlayer;
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

  /// The human slot that must act in the current war.
  int? get warHumanSlot {
    final war = state.activeWar;
    if (war == null) return null;
    for (final slot in [war.attackerSlot, war.defenderSlot]) {
      if (state.dynasty(slot).status == DynastyStatus.human) return slot;
    }
    return null;
  }

  List<PendingDecision> get decisionsForCurrent => state.pendingDecisions
      .where((d) => d.decidingSlot == currentSlot)
      .toList();

  /// Events the seated player has not seen yet — the recap card. The
  /// baseline is an absolute event position (`prunedEventCount + index`,
  /// stable across pruning) stored in the game state, so it survives app
  /// restarts.
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
    notifyListeners();
  }

  void markRecapSeen(int slot) {
    // Written into the session's live state (persisted with the next
    // auto-save) — endTurn copies the state right after, carrying it over.
    state.recapBaselines[slot] = state.prunedEventCount + state.events.length;
  }

  /// Deterministic in-turn action — undoable (PROJECT_REQUIREMENTS).
  ActionResult applyUndoable(PlayerAction action) {
    final snapshot = state;
    final result = _session.apply(action);
    _undoStack.add(snapshot);
    notifyListeners();
    return result;
  }

  /// Randomized or irreversible action — clears the undo stack.
  ActionResult applyIrreversible(PlayerAction action) {
    final result = _session.apply(action);
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
  /// requests a handoff to the next human (auto-saved inside).
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
      _handoffPending =
          humanCount > 1 ||
          state.dynasty(state.currentPlayer).status == DynastyStatus.human;
      // A war against a human defender pauses the AI advance; the war UI
      // takes over instead of a handoff.
      if (state.activeWar != null) {
        _handoffPending = true;
        _handoffToSlot = warHumanSlot ?? _handoffToSlot;
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Ends a war round: the AI side moves, then the round advances. When
  /// the war finishes, AI turns resume until a human's action phase.
  /// Returns the round's events (battles, plunders, war end) so the UI
  /// can show them as a report popup.
  Future<List<GameEvent>> endWarRound() async {
    if (_busy) return const [];
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
      // One shared engine entry point (client + V2 server): the AI sides
      // respond, then the round advances — see endWarRoundWithAi.
      events = _session.mutate(endWarRoundWithAi);
      await _resumeAfterWarIfOver();
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
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// After a war ends outside the turn flow, resume the AI advance.
  Future<void> _resumeAfterWarIfOver() async {
    if (state.activeWar != null) {
      await _session.save();
      return;
    }
    // A war that interrupted AI processing leaves the AI attacker's turn
    // half-finished: its action phase already ran, so complete the turn
    // directly (no second runAiTurn) and then let the remaining AIs play.
    if (state.dynasty(state.currentPlayer).status != DynastyStatus.human) {
      final completed = completeTurn(state, Rng(state.rngSeed));
      final advanced = advanceUntilHuman(
        completed.state,
        Rng(completed.state.rngSeed),
      );
      _session.restore(advanced.state);
      _handoffPending = true;
      _handoffToSlot = state.currentPlayer;
    }
    await _session.save();
  }

  void selectWarUnit(int? index) {
    selectedWarUnit = index;
    notifyListeners();
  }

  /// War actions from the war panel (move, plunder, peace wish).
  ActionResult applyWarAction(PlayerAction action) {
    final result = _session.apply(action);
    _undoStack.clear();
    if (state.activeWar == null) selectedWarUnit = null;
    notifyListeners();
    return result;
  }

  /// Resolves a pending decision for [slot].
  Future<void> resolveDecision(
    String decisionId,
    int slot,
    Map<String, dynamic> choice,
  ) async {
    _session.apply(
      ResolveDecision(slot: slot, decisionId: decisionId, choice: choice),
    );
    await _session.save();
    notifyListeners();
  }
}
