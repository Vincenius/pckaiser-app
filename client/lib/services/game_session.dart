import 'package:game_core/game_core.dart';

/// One running game as the UI sees it — local hot-seat or online. The
/// GameController drives gameplay exclusively through this interface;
/// only persistence/orchestration differ (ARCHITECTURE.md):
///
/// * Local: the full state lives on the device, actions apply through
///   the engine directly, every completed turn auto-saves.
/// * Online: the state is the SERVER's per-seat filtered copy; every
///   action round-trips (`rngSeed` never leaves the server, so the
///   client cannot roll dice), and rejections surface as the same
///   [ActionException]s the engine throws locally.
abstract class GameSession {
  GameState get state;

  bool get isOnline;

  /// The match's turn timer in hours (online, from the host settings);
  /// null = no timer, or a local game. The warPlan dialog derives the
  /// offered duel start slots from it.
  int? get turnTimeoutHours;

  /// False online: the server is authoritative, actions are final.
  bool get canUndo;

  /// Online: it is currently NOT this device's turn (someone else is
  /// awaited) — the play screen hands back to the waiting lobby.
  bool get awaitingRemote;

  /// Applies a player action (validated by engine/server); throws
  /// [ActionException] with a player-facing message when rejected.
  Future<ActionResult> apply(PlayerAction action);

  /// Restores an undo snapshot — local only ([canUndo]).
  void restore(GameState snapshot);

  /// Awaited war-round input from [slot] ("Runde beenden"): in a
  /// human-vs-human war the attacker's round end hands the input to the
  /// defender; otherwise the AI sides respond and the round advances.
  /// Returns the round's events for the report popup.
  Future<List<GameEvent>> endWarRound(int slot);

  /// Ends the seated player's turn and advances until the next human
  /// input is awaited. Returns the events emitted along the way.
  Future<List<GameEvent>> endTurnAndAdvance();

  /// A war that interrupted an AI's turn just ended outside the normal
  /// round flow: complete that turn and advance (server does this
  /// automatically — a refresh suffices online).
  Future<void> resumeAfterWar();

  /// Persists the current state where applicable (local auto-save).
  Future<void> save();
}
