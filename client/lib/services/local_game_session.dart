import 'package:game_core/game_core.dart';

import 'save_service.dart';

/// Drives a local hot-seat game: wraps the game_core turn pipeline and
/// auto-saves after every completed turn, before the device is handed to
/// the next player (PROJECT_REQUIREMENTS.md "Auto-save triggers after
/// every turn completion").
class LocalGameSession {
  LocalGameSession(this.slotName, this._state, this._saves);

  /// Creates a new game in [slotName], runs the first upkeep and persists
  /// the initial save.
  static Future<LocalGameSession> create({
    required String slotName,
    required GameSetup setup,
    required SaveService saves,
  }) async {
    var state = newGame(setup);
    state = startGame(state, Rng(state.rngSeed)).state;
    final session = LocalGameSession(slotName, state, saves);
    await saves.save(slotName, state);
    return session;
  }

  /// Resumes a saved game.
  static Future<LocalGameSession> resume({
    required String slotName,
    required SaveService saves,
  }) async {
    return LocalGameSession(slotName, await saves.load(slotName), saves);
  }

  final String slotName;
  final SaveService _saves;

  GameState _state;
  GameState get state => _state;

  /// What the seated player may see (hot-seat hidden information).
  GameState get visibleState => visibleStateFor(_state, _state.currentPlayer);

  /// Applies an in-turn action for the active player.
  ActionResult apply(PlayerAction action) {
    final rng = Rng(_state.rngSeed);
    final result = applyAction(_state, action, rng);
    _state = result.state;
    return result;
  }

  /// Ends the active player's turn, advances the pipeline and auto-saves.
  /// The returned events feed the "since your last turn" recap.
  Future<TurnResult> endTurn() async {
    final rng = Rng(_state.rngSeed);
    final result = completeTurn(_state, rng);
    _state = result.state;
    await _saves.save(slotName, _state);
    return result;
  }
}
