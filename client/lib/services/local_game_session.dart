import 'package:game_core/game_core.dart';

import 'game_session.dart';
import 'save_service.dart';

/// Drives a local hot-seat game: wraps the game_core turn pipeline and
/// auto-saves after every completed turn, before the device is handed to
/// the next player (PROJECT_REQUIREMENTS.md "Auto-save triggers after
/// every turn completion"). With [persist] off (the tutorial) the session
/// is ephemeral: nothing is ever written to disk.
class LocalGameSession implements GameSession {
  LocalGameSession(
    this.slotName,
    this._state,
    this._saves, {
    this.persist = true,
  });

  /// Creates a new game in [slotName], runs the first upkeep and persists
  /// the initial save (unless [persist] is off).
  static Future<LocalGameSession> create({
    required String slotName,
    required GameSetup setup,
    required SaveService saves,
    bool persist = true,
  }) async {
    var state = newGame(setup);
    state = startGame(state, Rng(state.rngSeed)).state;
    // startGame leaves the first *living* slot active — usually an AI
    // (slot 1, Brandenburg). Let the AI realms play until the first
    // human's action phase, so the human seat never controls an AI realm.
    if (setup.humans.isNotEmpty &&
        state.dynasty(state.currentPlayer).status != DynastyStatus.human) {
      state = advanceUntilHuman(state, Rng(state.rngSeed)).state;
    }
    final session = LocalGameSession(slotName, state, saves, persist: persist);
    await session.save();
    return session;
  }

  /// Resumes a saved game. SAVE MIGRATION, guarded: healthy saves are
  /// always parked on a human action phase (auto-save runs after
  /// endTurnAndAdvance) or inside a war — for those the check below is a
  /// no-op. Only a save from before the first-player fix, parked on an AI
  /// slot, is advanced to the first human action phase once and re-saved
  /// (the human seat would otherwise control a foreign AI realm).
  static Future<LocalGameSession> resume({
    required String slotName,
    required SaveService saves,
  }) async {
    var state = await saves.load(slotName);
    final hasHumans = state.dynasties.any(
      (d) => d.status == DynastyStatus.human,
    );
    if (hasHumans &&
        state.activeWar == null &&
        state.dynasty(state.currentPlayer).status != DynastyStatus.human) {
      state = advanceUntilHuman(state, Rng(state.rngSeed)).state;
      await saves.save(slotName, state);
    }
    return LocalGameSession(slotName, state, saves);
  }

  final String slotName;
  final SaveService _saves;

  /// False for the throwaway tutorial game: every save becomes a no-op,
  /// so it never appears in the saved-games list.
  final bool persist;

  GameState _state;

  @override
  GameState get state => _state;

  @override
  bool get isOnline => false;

  @override
  int? get turnTimeoutHours => null;

  @override
  bool get canUndo => true;

  @override
  bool get awaitingRemote => false;

  /// What the seated player may see (hot-seat hidden information).
  GameState get visibleState => visibleStateFor(_state, _state.currentPlayer);

  /// Applies an in-turn action for the active player (synchronous under
  /// the hood — the Future exists for the shared [GameSession] surface).
  @override
  Future<ActionResult> apply(PlayerAction action) async {
    final rng = Rng(_state.rngSeed);
    final result = applyAction(_state, action, rng);
    _state = result.state;
    // A warPlan answer — or a revised plan (`WarPrepPlan`, 2026-08-09) —
    // may complete the war preparation: run the start rules right away.
    // Hot-seat passes no deadline: both players are at the device, so even
    // a both-live war starts as soon as both chose.
    if ((action is ResolveDecision || action is WarPrepPlan) &&
        _state.activeWar?.phase == WarPhase.preparation) {
      final extra = mutate(
        (s, rng, events) => resolveWarPreparation(s, rng, events),
      );
      return ActionResult(_state, [...result.events, ...extra]);
    }
    return result;
  }

  /// Restores a snapshot — the in-turn undo path (deterministic actions
  /// only; the stack is managed by the GameController).
  @override
  void restore(GameState snapshot) {
    _state = snapshot;
  }

  /// Runs an in-place mutation (AI war movement, war round advance) on a
  /// copy of the state. Used by the war UI driver.
  List<GameEvent> mutate(
    void Function(GameState state, Rng rng, List<GameEvent> events) f,
  ) {
    final next = _state.copy();
    final rng = Rng(next.rngSeed);
    final events = <GameEvent>[];
    f(next, rng, events);
    next.rngSeed = rng.seed;
    next.events.addAll(events);
    _state = next;
    return events;
  }

  /// One shared engine entry point (client + server): a human-vs-human
  /// attacker hands the round to the defender, otherwise the AI sides
  /// respond and the round advances.
  @override
  Future<List<GameEvent>> endWarRound(int slot) async =>
      mutate((state, rng, events) => endWarRoundFor(state, slot, rng, events));

  /// Ends the active player's turn, advances the pipeline and auto-saves.
  /// The returned events feed the "since your last turn" recap.
  Future<TurnResult> endTurn() async {
    final rng = Rng(_state.rngSeed);
    final result = completeTurn(_state, rng);
    _state = result.state;
    await save();
    return result;
  }

  /// Ends the turn, then lets the AI realms play until a human's action
  /// phase (or a human-defended war) is reached; auto-saves the result.
  @override
  Future<List<GameEvent>> endTurnAndAdvance() async {
    final rng = Rng(_state.rngSeed);
    final ended = completeTurn(_state, rng);
    final advanced = advanceUntilHuman(ended.state, Rng(ended.state.rngSeed));
    _state = advanced.state;
    await save();
    return [...ended.events, ...advanced.events];
  }

  /// A war that interrupted AI processing leaves the AI attacker's turn
  /// half-finished: its action phase already ran, so complete the turn
  /// directly (no second runAiTurn) and then let the remaining AIs play.
  @override
  Future<void> resumeAfterWar() async {
    if (_state.activeWar != null) {
      await save();
      return;
    }
    if (_state.dynasty(_state.currentPlayer).status != DynastyStatus.human) {
      final completed = completeTurn(_state, Rng(_state.rngSeed));
      final advanced = advanceUntilHuman(
        completed.state,
        Rng(completed.state.rngSeed),
      );
      _state = advanced.state;
    }
    await save();
  }

  /// Persists the current state (used after war rounds resolve); a no-op
  /// for ephemeral sessions.
  @override
  Future<void> save() async {
    if (!persist) return;
    await _saves.save(slotName, _state);
  }
}
