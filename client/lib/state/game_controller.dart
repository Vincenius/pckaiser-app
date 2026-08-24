import 'dart:async';

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

  /// Read-only viewer over a state while another player's turn runs
  /// (online off-turn "Reich ansehen"): the whole UI is keyed to the fixed
  /// [viewSlot] instead of the engine's active player, no handoff blocker,
  /// and every action dispatch is a silent no-op — the server would 403 an
  /// off-turn submission anyway, this just keeps the UI honest.
  GameController.readOnly(this._session, {required int viewSlot})
    : _viewSlotOverride = viewSlot {
    _handoffToSlot = viewSlot;
    _lastSeat = viewSlot;
  }

  final GameSession _session;
  final List<GameState> _undoStack = [];

  int? _viewSlotOverride;

  /// True for the off-turn viewer: no actions, fixed view slot.
  bool get readOnly => _viewSlotOverride != null;

  /// Switches the viewed realm (read-only mode only) — a player can hold
  /// several realms (control follows the ruler, §15.4).
  void setViewSlot(int slot) {
    if (_viewSlotOverride == null || _viewSlotOverride == slot) return;
    _viewSlotOverride = slot;
    notifyListeners();
  }

  /// All realm slots the seated player currently controls, including
  /// [currentSlot] — one per realm they hold.
  Set<int> get ownedSlots => humanControlledSlots(state, currentSlot);

  bool _handoffPending = false;
  int _handoffToSlot = 0;
  int _lastSeat = 0;
  bool _busy = false;

  /// The war unit the player has selected on the map (index into the
  /// human war side's troop list); null = nothing selected.
  int? selectedWarUnit;

  /// Tile indices (`y * width + x`) the winner has drag-selected to annex
  /// in the post-war settlement. Lives on the controller (not the screen)
  /// so the map's drag paint and the war panel's "Annektieren" button share
  /// one set; the engine plans a valid, affordable subset on confirm.
  final Set<int> settlementSelection = <int>{};

  /// Toggles a tile in/out of the settlement annex selection (tap).
  void toggleSettlementTile(int index) {
    if (!settlementSelection.remove(index)) settlementSelection.add(index);
    notifyListeners();
  }

  /// Adds a tile to the settlement annex selection (tap).
  void addSettlementTile(int index) {
    if (settlementSelection.add(index)) notifyListeners();
  }

  /// Replaces the whole settlement annex selection (box drag resize),
  /// notifying once.
  void setSettlementSelection(Iterable<int> tiles) {
    settlementSelection
      ..clear()
      ..addAll(tiles);
    notifyListeners();
  }

  void clearSettlementSelection() {
    if (settlementSelection.isEmpty) return;
    settlementSelection.clear();
    notifyListeners();
  }

  /// Tiles (index `y * width + x`) selected for transfer in the
  /// "Felder übertragen" multi-select — highlighted on the map while the
  /// pick is armed. Confirmed once via the banner's "Felder übertragen"
  /// button, not per tile.
  final Set<int> transferSelection = <int>{};

  /// Target realm of the active "Felder übertragen" multi-select; null
  /// when no transfer selection is in progress.
  int? _transferTargetSlot;
  int? get transferTargetSlot => _transferTargetSlot;

  /// Arms the "Felder übertragen" multi-select: subsequent map taps toggle
  /// tiles in [transferSelection] (see [toggleTransferTile]). The actual
  /// tile pick is armed separately via [startTilePick].
  void startTransferSelection(int targetSlot) {
    _transferTargetSlot = targetSlot;
    transferSelection.clear();
    notifyListeners();
  }

  /// Toggles a tile in/out of the transfer selection (tap).
  void toggleTransferTile(int index) {
    if (!transferSelection.remove(index)) transferSelection.add(index);
    notifyListeners();
  }

  /// Bulk-replaces the transfer selection (box drag) — one notify.
  void setTransferSelection(Iterable<int> tiles) {
    transferSelection
      ..clear()
      ..addAll(tiles);
    notifyListeners();
  }

  /// Ends the transfer multi-select (and the tile pick beneath it).
  void cancelTransferSelection() {
    if (_transferTargetSlot == null) return;
    _endTilePick();
    notifyListeners();
  }

  /// Hint banner text while a map tile pick is active (e.g. "station the
  /// new troop"); null = no pick pending.
  String? tilePickHint;

  /// Whether the active tile pick can be cancelled via the banner's
  /// cancel button. False for forced picks (e.g. seat relocation).
  bool tilePickCancellable = true;

  Future<bool> Function(int x, int y)? _tilePick;

  bool get tilePickActive => _tilePick != null;

  /// Routes the next map taps to [onPick] instead of the tile sheet.
  /// [onPick] returns true to accept the tile (ends the pick) or false to
  /// reject it (the pick stays active).
  void startTilePick({
    required String hint,
    required Future<bool> Function(int x, int y) onPick,
    bool cancellable = true,
  }) {
    tilePickHint = hint;
    tilePickCancellable = cancellable;
    _tilePick = onPick;
    notifyListeners();
  }

  /// Tears down any armed tile pick plus the transfer selection that rides
  /// on it. Does NOT notify — callers notify (or are mid-flow, e.g. a
  /// controller-listener repaint).
  void _endTilePick() {
    _tilePick = null;
    tilePickHint = null;
    _seatPickCompleter?.complete(null);
    _seatPickCompleter = null;
    seatPickCandidates = const {};
    _transferTargetSlot = null;
    transferSelection.clear();
  }

  void cancelTilePick() {
    if (_tilePick == null) return;
    _endTilePick();
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

  /// The online match's turn timer in hours (null = no timer / local) —
  /// bounds the duel start slots the warPlan dialog offers.
  int? get turnTimeoutHours => _session.turnTimeoutHours;

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
    final override = _viewSlotOverride;
    if (override != null) return override;
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

  /// The game-ending event, when the game is over. The scan skips the
  /// `redacted` placeholders an online (filtered) state keeps in place of
  /// events hidden from this seat — the game end itself is always public.
  GameEvent? get gameEndEvent {
    for (var i = state.events.length - 1; i >= 0; i--) {
      final event = state.events[i];
      if (event.type == 'redacted') continue;
      return switch (event.type) {
        'gameWon' || 'gameDraw' || 'humansDefeated' => event,
        _ => null,
      };
    }
    return null;
  }

  bool get gameOver => gameEndEvent != null;

  /// The human slot that must act in the current war (the acting side —
  /// in a human-vs-human war the input alternates within each round).
  int? get warHumanSlot => warActingSlot(state);

  /// The war-participant slot the seated (or viewing) player controls
  /// during the PREPARATION window, or null. Unlike [warHumanSlot] it
  /// stays set after this side answered its warPlan (online the panel
  /// must keep offering the per-unit stance orders until the war starts)
  /// and works for the read-only viewer.
  int? get warPrepSlot {
    final war = state.activeWar;
    if (war == null || war.phase != WarPhase.preparation) return null;
    final owned = ownedSlots;
    for (final slot in [war.attackerSlot, war.defenderSlot]) {
      if (owned.contains(slot)) return slot;
    }
    return null;
  }

  /// War-preparation orders are the actions allowed through the read-only
  /// viewer: online the DEFENDER lines up their troops while another
  /// player's turn runs, and either combatant may revise its start plan
  /// (control mode + proposed times, `WarPrepPlan` — user request
  /// 2026-08-09). The server accepts both out of turn while the
  /// preparation window runs. Taking command back from the no-show
  /// autopilot mid-war (`ResumeWarCommand` — user request 2026-08-24) is
  /// allowed the same way: the delegated side is never the awaited player
  /// either.
  bool _prepStanceAllowed(PlayerAction action) =>
      ((action is SetTroopStance || action is WarPrepPlan) &&
          action.slot == warPrepSlot) ||
      (action is ResumeWarCommand && action.slot == warAutoSlot);

  /// The war-participant slot the seated (or viewing) player controls that
  /// is currently delegated to the no-show autopilot (`war.autoSlots`)
  /// during the ROUNDS phase — they may take command back at any time
  /// (`ResumeWarCommand`, user request 2026-08-24). Null outside an active
  /// war's rounds, or when their side is not delegated.
  int? get warAutoSlot {
    final war = state.activeWar;
    if (war == null || war.phase != WarPhase.rounds) return null;
    final owned = ownedSlots;
    for (final slot in [war.attackerSlot, war.defenderSlot]) {
      if (owned.contains(slot) && war.autoSlots.contains(slot)) return slot;
    }
    return null;
  }

  /// The war ([attacker, defender, year] — §11.1 allows one war per realm
  /// per year) whose defender briefing already fired. An explicit marker:
  /// the old approach inferred "brief exactly once" from whether the
  /// `warDeclared` event was still inside the recap window, which coupled
  /// a one-time UI popup to recap-baseline timing.
  String? _warBriefedKey;

  /// True exactly once per war for its defender: whether the "Krieg !"
  /// orientation popup is still owed. Marks the war as briefed.
  ///
  /// `[FIX 2026-08-24, user report]` The in-memory marker alone was not
  /// enough: ONLINE every turn — and every war round — enters through a
  /// freshly built GameScreen/GameController, so [_warBriefedKey] was
  /// always null again and the defender got the briefing round after
  /// round. It is an OPENING briefing, so it is anchored in the war state
  /// too: only the first round owes it, and only while this side has not
  /// yet given any war input (`actedSlots`, kept by the server; empty in
  /// local hot-seat play, where the marker below already does the job).
  bool takeWarBriefing(int slot) {
    final war = state.activeWar;
    if (war == null ||
        war.phase != WarPhase.rounds ||
        war.defenderSlot != slot) {
      return false;
    }
    if (war.round > 0 || war.actedSlots.contains(slot)) return false;
    final key = '${war.attackerSlot}-${war.defenderSlot}-${state.year}';
    if (_warBriefedKey == key) return false;
    _warBriefedKey = key;
    return true;
  }

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
    if (_busy || readOnly) return ActionResult(state, const []);
    final snapshot = state;
    _busy = true;
    notifyListeners();
    try {
      final result = await _session.apply(action);
      if (_session.canUndo) _undoStack.add(snapshot);
      return result;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Randomized or irreversible action — clears the undo stack.
  Future<ActionResult> applyIrreversible(PlayerAction action) async {
    if (_busy || readOnly) return ActionResult(state, const []);
    _busy = true;
    notifyListeners();
    try {
      final result = await _session.apply(action);
      _undoStack.clear();
      return result;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    // An armed tile pick captured indices from the pre-undo state (e.g.
    // "station troop n") — cancel it so it can't act on the reverted list.
    _endTilePick();
    _session.restore(_undoStack.removeLast());
    notifyListeners();
  }

  /// Ends the seated player's turn: clears undo, lets the AI play, then
  /// requests a handoff to the next human (auto-saved inside). Online the
  /// server advances; when another player is awaited afterwards,
  /// [awaitingRemote] turns true and the play screen hands back.
  Future<void> endTurn() async {
    if (_busy || readOnly) return;
    _busy = true;
    _endTilePick();
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
    if (_busy || readOnly) return const [];
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

  /// Tile indices (`y * width + x`) that should be highlighted on the
  /// map — set during a seat pick, rendered as pulsing gold rings.
  Set<int> seatPickCandidates = const <int>{};

  /// Completer for the seat pick: resolved when the user taps a valid
  /// tile or cancels.
  Completer<(int, int)?>? _seatPickCompleter;

  /// Opens a map pick for seat relocation: highlights [candidates] on the
  /// map (unless [highlightCandidates] is false), shows a banner, and
  /// returns the tapped tile or null on cancel.
  Future<(int, int)?> pickSeatOnMap({
    required String hint,
    required Set<int> candidates,
    bool cancellable = false,
    bool highlightCandidates = true,
  }) {
    _seatPickCompleter?.complete(null);
    final completer = Completer<(int, int)?>();
    _seatPickCompleter = completer;
    seatPickCandidates = highlightCandidates ? candidates : const <int>{};
    final map = state.map;
    startTilePick(
      hint: hint,
      cancellable: cancellable,
      onPick: (x, y) async {
        if (candidates.contains(map.index(x, y))) {
          _seatPickCompleter = null;
          seatPickCandidates = const {};
          completer.complete((x, y));
          return true;
        }
        return false;
      },
    );
    return completer.future;
  }

  /// Set by the screen that owns the Flame map: centers the view on a
  /// tile. Lets the war panel — which has no access to the map — scroll
  /// the board to a unit picked from its LIST.
  void Function(int x, int y)? focusTile;

  /// Selects the war unit at [index] (index into the war side's troop
  /// list); null clears the selection.
  ///
  /// [focusMap] centers the map on that unit — passed by the war panel's
  /// unit chips (user request 2026-08-08: picking an army from the list
  /// must scroll the map to it), NOT by taps on the map itself, where the
  /// unit is under the finger already and a jump would be disorienting.
  void selectWarUnit(int? index, {bool focusMap = false}) {
    selectedWarUnit = index;
    if (focusMap && index != null) {
      final slot = state.activeWar?.phase == WarPhase.preparation
          ? warPrepSlot
          : warHumanSlot;
      final troops = slot == null ? const [] : state.realm(slot).troops;
      if (index < troops.length) {
        focusTile?.call(troops[index].x, troops[index].y);
      }
    }
    notifyListeners();
  }

  /// War actions from the war panel (move, plunder, peace wish,
  /// settlement picks). A settlement finish can end the war and return
  /// the seat to the paused turn's player — hot-seat then needs a
  /// handoff before the successor's view appears.
  Future<ActionResult> applyWarAction(PlayerAction action) async {
    if (_busy || (readOnly && !_prepStanceAllowed(action))) {
      return ActionResult(state, const []);
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await _session.apply(action);
      _undoStack.clear();
      if (state.activeWar == null) selectedWarUnit = null;
      _maybeRequestSeatHandoff();
      return result;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Resolves a pending decision for [slot]. Allowed from the read-only
  /// viewer for the seat's OWN slots: online, decisions are answered out
  /// of turn by design (the warPlan prompt of a war preparation is the
  /// main case — the defender answers it right from the map view).
  Future<void> resolveDecision(
    String decisionId,
    int slot,
    Map<String, dynamic> choice,
  ) async {
    if (_busy || (readOnly && !ownedSlots.contains(slot))) return;
    _busy = true;
    notifyListeners();
    try {
      await _session.apply(
        ResolveDecision(slot: slot, decisionId: decisionId, choice: choice),
      );
      // Decision outcomes are randomized/irreversible — snapshots from
      // before the resolution must not stay undoable.
      _undoStack.clear();
      // A resolution can move the seat (a defender delegating a war hands
      // the round back to the attacker) — hot-seat then needs the blocker
      // before the successor's view appears.
      _maybeRequestSeatHandoff();
      await _session.save();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
