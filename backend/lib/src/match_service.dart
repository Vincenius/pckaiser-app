/// Match orchestration (ARCHITECTURE.md "Turn Flow (online)"): the same
/// game_core pipeline the local client drives, persisted per match. The
/// server validates every submission; clients never mutate state.
library;

import 'package:game_core/game_core.dart';

import 'models.dart';
import 'push_service.dart';
import 'store.dart';

/// Errors mapped onto HTTP statuses by the API layer: 400 validation,
/// 403 wrong turn/seat, 404 missing. [message] is client-facing.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class MatchService {
  MatchService(this._store, this._push, {DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc());

  final GameStore _store;
  final PushService _push;
  final DateTime Function() _clock;

  // --- Players ----------------------------------------------------------

  Future<PlayerRecord> registerPlayer({
    String? id,
    required String displayName,
    String? fcmToken,
  }) async {
    if (displayName.trim().isEmpty) {
      throw ApiException(400, 'display_name must not be empty');
    }
    final player = PlayerRecord(
      id: id ?? uuidV4(),
      displayName: displayName.trim(),
      fcmToken: fcmToken,
    );
    await _store.savePlayer(player);
    return player;
  }

  Future<PlayerRecord> updatePlayer(
    String id, {
    String? displayName,
    String? fcmToken,
  }) async {
    final player = await _requirePlayer(id);
    if (displayName != null && displayName.trim().isNotEmpty) {
      player.displayName = displayName.trim();
    }
    if (fcmToken != null) player.fcmToken = fcmToken;
    await _store.savePlayer(player);
    return player;
  }

  // --- Match lifecycle ---------------------------------------------------

  /// Creates a match in `waiting`; the creator takes the first seat. A
  /// single-human match starts immediately.
  Future<MatchRecord> createMatch({
    required String playerId,
    required int humanCount,
    required MatchSettings settings,
    required Map<String, dynamic> setup,
  }) async {
    await _requirePlayer(playerId);
    if (humanCount < 1 || humanCount > 16) {
      throw ApiException(400, 'human_count must be 1–16');
    }
    final match = MatchRecord(
      id: uuidV4(),
      humanCount: humanCount,
      settings: settings,
      players: [],
    );
    _seat(match, playerId, setup);
    if (match.players.length == humanCount) {
      await _start(match);
    }
    await _store.saveMatch(match);
    return match;
  }

  /// Joins a waiting match; the last seat starts the game.
  Future<MatchRecord> joinMatch({
    required String matchId,
    required String playerId,
    required Map<String, dynamic> setup,
  }) async {
    await _requirePlayer(playerId);
    final match = await _requireMatch(matchId);
    if (match.status != MatchStatus.waiting) {
      throw ApiException(400, 'match is not open for joining');
    }
    if (match.playerById(playerId) != null) {
      throw ApiException(400, 'player already joined');
    }
    _seat(match, playerId, setup);
    if (match.players.length == match.humanCount) {
      await _start(match);
    }
    match.updatedAt = _clock();
    await _store.saveMatch(match);
    return match;
  }

  void _seat(MatchRecord match, String playerId, Map<String, dynamic> setup) {
    final founderName = (setup['founder_name'] as String?)?.trim() ?? '';
    final dorfName = (setup['dorf_name'] as String?)?.trim() ?? '';
    final gender = setup['gender'] as int? ?? 0;
    if (founderName.isEmpty || dorfName.isEmpty) {
      throw ApiException(400, 'founder_name and dorf_name are required');
    }
    if (gender != 0 && gender != 1) {
      throw ApiException(400, 'gender must be 0 or 1');
    }
    final taken = {for (final p in match.players) p.slot};
    var slot = setup['country_slot'] as int?;
    if (slot != null) {
      if (slot < 1 || slot > World.realmCount) {
        throw ApiException(400, 'country_slot must be 1–30');
      }
      if (taken.contains(slot)) {
        throw ApiException(400, 'country_slot already taken');
      }
    } else {
      // First free slot after a random offset — uniform enough and
      // deterministic to test with a seeded settings RNG is overkill.
      final free = [
        for (var s = 1; s <= World.realmCount; s++)
          if (!taken.contains(s)) s,
      ];
      free.shuffle();
      slot = free.first;
    }
    match.players.add(MatchPlayer(
      playerId: playerId,
      turnOrder: match.players.length,
      slot: slot,
      founderName: founderName,
      gender: gender,
      dorfName: dorfName,
    ));
  }

  /// All seats filled: build the world and run to the first awaited human
  /// (mirrors the client's LocalGameSession.create).
  Future<void> _start(MatchRecord match) async {
    final humans = [...match.players]
      ..sort((a, b) => a.turnOrder.compareTo(b.turnOrder));
    final setup = GameSetup(
      humans: [
        for (final p in humans)
          HumanPlayerSetup(
            founderName: p.founderName,
            gender: p.gender,
            countrySlot: p.slot,
            dorfName: p.dorfName,
          ),
      ],
      reformationYear: match.settings.reformationYear,
      ottomanYear: match.settings.ottomanYear,
      seed: match.settings.seed,
    );
    var state = newGame(setup);
    state = startGame(state, Rng(state.rngSeed)).state;
    if (state.dynasty(state.currentPlayer).status != DynastyStatus.human) {
      state = advanceUntilHuman(state, Rng(state.rngSeed)).state;
    }
    match.status = MatchStatus.active;
    await _commit(match, state, notify: true);
  }

  // --- Views -------------------------------------------------------------

  /// The match as the requesting participant may see it: metadata plus
  /// the state filtered through `visibleStateFor` — the authoritative
  /// document never leaves the server.
  Future<Map<String, dynamic>> view(String matchId, String playerId) async {
    final match = await _requireMatch(matchId);
    final seat = match.playerById(playerId);
    if (seat == null) {
      throw ApiException(403, 'player is not part of this match');
    }
    GameState? state;
    if (match.stateJson != null) {
      state = _load(match);
    }
    final awaited = state == null ? null : _awaitedPlayerId(match, state);
    return {
      'id': match.id,
      'status': match.status.name,
      'human_count': match.humanCount,
      'players': [
        for (final p in match.players)
          {
            'player_id': p.playerId,
            'turn_order': p.turnOrder,
            'dynasty_index': p.slot,
          },
      ],
      'settings': match.settings.toJson(),
      'turn_deadline': match.turnDeadline?.toIso8601String(),
      'winner': match.winnerPlayerId,
      'your_slot': seat.slot,
      'awaited_player_id': awaited,
      'your_turn': awaited == playerId,
      'state':
          state == null ? null : visibleStateFor(state, seat.slot).toJson(),
    };
  }

  Future<List<Map<String, dynamic>>> matchesForPlayer(String playerId) async {
    await _requirePlayer(playerId);
    final matches = await _store.matchesForPlayer(playerId);
    matches.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      for (final m in matches)
        {
          'id': m.id,
          'status': m.status.name,
          'human_count': m.humanCount,
          'joined': m.players.length,
          'turn_deadline': m.turnDeadline?.toIso8601String(),
          'your_turn': m.status == MatchStatus.active &&
              m.stateJson != null &&
              _awaitedPlayerId(m, _load(m)) == playerId,
          'updated_at': m.updatedAt.toIso8601String(),
        },
    ];
  }

  // --- Turn submission ---------------------------------------------------

  /// `POST /matches/:id/turn` — either `{action: {...}}` (in-turn action,
  /// war action or pending decision) or `{end_turn: true}`.
  Future<Map<String, dynamic>> submit({
    required String matchId,
    required String playerId,
    Map<String, dynamic>? actionJson,
    bool endTurn = false,
  }) async {
    final match = await _requireMatch(matchId);
    final seat = match.playerById(playerId);
    if (seat == null) {
      throw ApiException(403, 'player is not part of this match');
    }
    if (match.status != MatchStatus.active) {
      throw ApiException(400, 'match is not active');
    }
    var state = _load(match);
    final awaited = _awaitedPlayerId(match, state);

    if (endTurn) {
      if (awaited != playerId) throw ApiException(403, 'not your turn');
      if (state.activeWar != null) {
        throw ApiException(400, 'a war must end before the turn can');
      }
      state = _endTurnAndAdvance(state);
    } else if (actionJson != null) {
      final PlayerAction action;
      try {
        action = PlayerAction.fromJson(actionJson);
      } on Object {
        throw ApiException(400, 'malformed action');
      }
      if (action.slot != seat.slot) {
        throw ApiException(403, 'action acts for a foreign realm');
      }
      if (action is ResolveDecision) {
        // Pending decisions are answered out of turn (ARCHITECTURE
        // "Pending decisions") — the engine validates id and slot.
        state = _apply(state, action);
      } else {
        if (awaited != playerId) throw ApiException(403, 'not your turn');
        if (action is WarEndRound) {
          // The engine entry point for awaited war-round input: the AI
          // sides respond, then the round advances.
          state = _mutate(state, endWarRoundWithAi);
        } else {
          state = _apply(state, action);
        }
        state = _resumeAfterWarIfOver(state);
      }
    } else {
      throw ApiException(400, 'provide action or end_turn');
    }

    await _commit(match, state, notify: true);
    await _store.saveMatch(match);
    return view(matchId, playerId);
  }

  // --- Timeouts ----------------------------------------------------------

  /// Auto-resolves expired awaited input (ARCHITECTURE "Timeouts"):
  /// a war round falls back to the AI war logic, decisions resolve with
  /// their defaults, a turn simply ends with no actions. Players are
  /// never eliminated for idling. Returns the number of matches swept.
  Future<int> sweepExpired() async {
    final now = _clock();
    final expired = await _store.expiredMatches(now);
    for (final match in expired) {
      var state = _load(match);
      if (state.activeWar != null) {
        // The awaited combatant idles: their units hold position, the AI
        // side moves, the round advances.
        state = _mutate(state, endWarRoundWithAi);
        state = _resumeAfterWarIfOver(state);
      } else {
        final awaitedSlot = _awaitedSlot(state);
        if (awaitedSlot != null) {
          // Resolve the idle player's pending decisions with their
          // defaults, then end the turn with no actions.
          for (final d in [...state.pendingDecisions]) {
            if (d.decidingSlot != awaitedSlot) continue;
            state = _apply(
                state,
                ResolveDecision(
                    slot: awaitedSlot, decisionId: d.id, choice: const {}));
          }
          state = _endTurnAndAdvance(state);
        }
      }
      await _commit(match, state, notify: true);
      await _store.saveMatch(match);
    }
    return expired.length;
  }

  // --- Pipeline helpers ----------------------------------------------------

  GameState _load(MatchRecord match) =>
      GameState.fromJson(adoptLatestRules(match.stateJson!));

  GameState _apply(GameState state, PlayerAction action) {
    try {
      return applyAction(state, action, Rng(state.rngSeed)).state;
    } on ActionException catch (e) {
      throw ApiException(400, e.message);
    }
  }

  GameState _mutate(
    GameState state,
    void Function(GameState, Rng, List<GameEvent>) f,
  ) {
    final next = state.copy();
    final rng = Rng(next.rngSeed);
    final events = <GameEvent>[];
    f(next, rng, events);
    next.rngSeed = rng.seed;
    next.events.addAll(events);
    return next;
  }

  GameState _endTurnAndAdvance(GameState state) {
    final ended = completeTurn(state, Rng(state.rngSeed));
    return advanceUntilHuman(ended.state, Rng(ended.state.rngSeed)).state;
  }

  /// A war that interrupted an AI's turn leaves that turn half-finished
  /// when it ends — complete it and let the remaining AIs play (mirrors
  /// the client's GameController.resumeAfterWar).
  GameState _resumeAfterWarIfOver(GameState state) {
    if (state.activeWar != null || _gameOver(state)) return state;
    if (state.dynasty(state.currentPlayer).status == DynastyStatus.human) {
      return state;
    }
    return _endTurnAndAdvance(state);
  }

  bool _gameOver(GameState state) =>
      state.events.isNotEmpty &&
      const {'gameWon', 'gameDraw', 'humansDefeated'}
          .contains(state.events.last.type);

  /// Realm slot whose human input the match is waiting for, or null.
  int? _awaitedSlot(GameState state) {
    if (_gameOver(state)) return null;
    final war = state.activeWar;
    if (war != null) {
      for (final slot in [war.attackerSlot, war.defenderSlot]) {
        if (state.dynasty(slot).status == DynastyStatus.human) return slot;
      }
      return null;
    }
    if (state.dynasty(state.currentPlayer).status == DynastyStatus.human) {
      return state.currentPlayer;
    }
    return null;
  }

  String? _awaitedPlayerId(MatchRecord match, GameState state) {
    final slot = _awaitedSlot(state);
    if (slot == null) return null;
    // Control follows the ruler: the slot's dynasty carries the human
    // player index (= turn order) after conquests and inheritances.
    final humanIndex = state.dynasty(slot).humanPlayer;
    if (humanIndex == null) return match.playerBySlot(slot)?.playerId;
    for (final p in match.players) {
      if (p.turnOrder == humanIndex) return p.playerId;
    }
    return null;
  }

  /// Writes the new state into the record, refreshes status/winner and
  /// the deadline, and sends the pushes for the new situation.
  Future<void> _commit(
    MatchRecord match,
    GameState state, {
    required bool notify,
  }) async {
    final previousAwaited =
        match.stateJson == null ? null : _awaitedPlayerId(match, _load(match));
    final hadWar = match.stateJson != null &&
        (match.stateJson!['activeWar'] != null);

    match.stateJson = state.toJson();
    match.updatedAt = _clock();

    if (_gameOver(state)) {
      match.status = MatchStatus.finished;
      match.turnDeadline = null;
      final last = state.events.last;
      if (last.type == 'gameWon') {
        final humanIndex = state.dynasty(last.slot).humanPlayer;
        for (final p in match.players) {
          if (p.turnOrder == humanIndex) match.winnerPlayerId = p.playerId;
        }
      }
      return;
    }

    final awaited = _awaitedPlayerId(match, state);
    final timeout = state.activeWar != null
        ? Duration(seconds: match.settings.warRoundTimeoutSeconds)
        : match.settings.turnTimeoutHours == null
            ? null
            : Duration(hours: match.settings.turnTimeoutHours!);
    match.turnDeadline =
        awaited == null || timeout == null ? null : _clock().add(timeout);

    if (!notify || awaited == null) return;
    final player = await _store.player(awaited);
    if (player == null) return;
    if (state.activeWar != null && !hadWar) {
      await _push.warStarted(player, match);
    } else if (awaited != previousAwaited) {
      await _push.yourTurn(player, match);
    }
    // Out-of-turn decisions get their own nudge.
    for (final d in state.pendingDecisions) {
      final decider = _playerForSlot(match, state, d.decidingSlot);
      if (decider != null && decider != awaited) {
        final p = await _store.player(decider);
        if (p != null) await _push.yourDecision(p, match);
      }
    }
  }

  String? _playerForSlot(MatchRecord match, GameState state, int slot) {
    final humanIndex = state.dynasty(slot).humanPlayer;
    if (humanIndex == null) return null;
    for (final p in match.players) {
      if (p.turnOrder == humanIndex) return p.playerId;
    }
    return null;
  }

  // --- Lookups -----------------------------------------------------------

  Future<PlayerRecord> _requirePlayer(String id) async {
    final player = await _store.player(id);
    if (player == null) throw ApiException(404, 'unknown player');
    return player;
  }

  Future<MatchRecord> _requireMatch(String id) async {
    final match = await _store.match(id);
    if (match == null) throw ApiException(404, 'unknown match');
    return match;
  }
}
