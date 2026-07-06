import 'package:game_core/game_core.dart';

import 'api_client.dart';
import 'game_session.dart';

/// One online match seat: the state is the SERVER's per-seat filtered
/// copy; every action round-trips through `/matches/:id/turn` and the
/// response replaces the local copy. Server rejections (400/403) carry
/// the engine's player-facing German messages and are rethrown as the
/// same [ActionException] the local engine throws — the entire game UI
/// works unchanged on top.
class OnlineGameSession implements GameSession {
  OnlineGameSession({
    required this.api,
    required this.matchId,
    required this.playerId,
    required Map<String, dynamic> view,
  }) : _state = GameState.fromJson(
         (view['state'] as Map).cast<String, dynamic>(),
       ),
       _yourTurn = view['your_turn'] == true,
       yourSlot = view['your_slot'] as int;

  final ApiClient api;
  final String matchId;
  final String playerId;

  /// The seat's realm slot (1–30).
  final int yourSlot;

  GameState _state;
  bool _yourTurn;

  @override
  GameState get state => _state;

  @override
  bool get isOnline => true;

  @override
  bool get canUndo => false;

  @override
  bool get awaitingRemote => !_yourTurn;

  @override
  Future<ActionResult> apply(PlayerAction action) async {
    final view = await _submit(action: action.toJson());
    return ActionResult(_state, _eventsOf(view));
  }

  @override
  void restore(GameState snapshot) {
    throw StateError('online games cannot undo — the server is authoritative');
  }

  @override
  Future<List<GameEvent>> endWarRound(int slot) async {
    final view = await _submit(action: WarEndRound(slot: slot).toJson());
    return _eventsOf(view);
  }

  @override
  Future<List<GameEvent>> endTurnAndAdvance() async {
    final view = await _submit(endTurn: true);
    return _eventsOf(view);
  }

  /// The server resumes a paused AI turn itself when a war ends — every
  /// submission response already carries the post-resume state.
  @override
  Future<void> resumeAfterWar() async {}

  /// The server persists every submission; nothing to do client-side.
  @override
  Future<void> save() async {}

  /// Re-fetches the match (poll path while waiting).
  Future<void> refresh() async {
    _ingest(await api.match(matchId, playerId));
  }

  Future<Map<String, dynamic>> _submit({
    Map<String, dynamic>? action,
    bool endTurn = false,
  }) async {
    try {
      final view = endTurn
          ? await api.endTurn(matchId: matchId, playerId: playerId)
          : await api.submitAction(
              matchId: matchId,
              playerId: playerId,
              action: action!,
            );
      _ingest(view);
      return view;
    } on ApiError catch (e) {
      // 400/403: engine validation / wrong turn. 426: this build is out of
      // date for the match (a newer app version changed the rules). All
      // carry a player-facing German message — surface it like any other
      // rejected action so the existing UI shows it.
      if (e.statusCode == 400 || e.statusCode == 403 || e.statusCode == 426) {
        throw ActionException(e.message);
      }
      rethrow;
    }
  }

  void _ingest(Map<String, dynamic> view) {
    final stateJson = view['state'];
    if (stateJson != null) {
      _state = GameState.fromJson((stateJson as Map).cast<String, dynamic>());
    }
    _yourTurn = view['your_turn'] == true;
  }

  List<GameEvent> _eventsOf(Map<String, dynamic> view) => [
    for (final e in (view['events'] as List?) ?? const [])
      GameEvent.fromJson((e as Map).cast<String, dynamic>()),
  ];
}
