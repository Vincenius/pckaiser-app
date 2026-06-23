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

  /// Creates a match in `waiting` under a fresh 5-letter room code; the
  /// creator takes the first seat and later starts the game explicitly
  /// ([startMatch]) — no fixed player count.
  Future<MatchRecord> createMatch({
    required String playerId,
    required MatchSettings settings,
    required Map<String, dynamic> setup,
  }) async {
    await _requirePlayer(playerId);
    // Retry on the rare code collision with an existing match.
    var id = matchCode();
    while (await _store.match(id) != null) {
      id = matchCode();
    }
    final match = MatchRecord(
      id: id,
      settings: settings,
      players: [],
    );
    _seat(match, playerId, setup);
    await _store.saveMatch(match);
    return match;
  }

  /// Joins a waiting match (up to 16 human seats).
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
    if (match.players.length >= 16) {
      throw ApiException(400, 'match is full');
    }
    _seat(match, playerId, setup);
    // Legacy fixed-size matches (pre room codes) still auto-start when
    // the last announced seat fills.
    if (match.humanCount != null &&
        match.players.length == match.humanCount) {
      await _start(match);
    }
    match.updatedAt = _clock();
    await _store.saveMatch(match);
    return match;
  }

  /// Starts a waiting match — only the creator (first seat) may. The
  /// world is built for exactly the joined players; nobody can join a
  /// started game.
  Future<MatchRecord> startMatch({
    required String matchId,
    required String playerId,
  }) async {
    await _requirePlayer(playerId);
    final match = await _requireMatch(matchId);
    if (match.status != MatchStatus.waiting) {
      throw ApiException(400, 'match already started');
    }
    if (match.players.isEmpty || match.players.first.playerId != playerId) {
      throw ApiException(403, 'only the creator can start the match');
    }
    await _start(match);
    match.updatedAt = _clock();
    await _store.saveMatch(match);
    return match;
  }

  /// Leaving a match. Waiting: the creator leaving deletes the whole
  /// match, a joiner just frees their seat. Active: the player's realm(s)
  /// fall to the AI and the game continues without them — if their input
  /// was awaited, the AI resolves it right away (same fallbacks as the
  /// timeout sweep). Finished: the seat is dropped so the match leaves
  /// the player's list. A match nobody is seated in anymore is deleted.
  /// Returns true when the match itself was deleted.
  Future<bool> leaveMatch({
    required String matchId,
    required String playerId,
  }) async {
    final match = await _requireMatch(matchId);
    final seat = match.playerById(playerId);
    if (seat == null) {
      throw ApiException(403, 'player is not part of this match');
    }

    if (match.status == MatchStatus.waiting &&
        match.players.first.playerId == playerId) {
      await _store.deleteMatch(match.id);
      return true;
    }

    if (match.status == MatchStatus.active) {
      var state = _load(match);
      final ignored = <GameEvent>[];
      // Answer the leaver's open decisions with their defaults while the
      // dynasty still counts as human (mirrors the timeout sweep).
      for (final d in [...state.pendingDecisions]) {
        if (state.dynasty(d.decidingSlot).humanPlayer != seat.turnOrder) {
          continue;
        }
        state = _apply(
            state,
            ResolveDecision(
                slot: d.decidingSlot, decisionId: d.id, choice: const {}),
            ignored);
      }
      state = _mutate(state, (s, rng, ev) {
        // Control follows the ruler: every dynasty this player holds
        // (after conquests/inheritances) becomes an AI dynasty.
        for (final d in s.dynasties) {
          if (d.status != DynastyStatus.human ||
              d.humanPlayer != seat.turnOrder) {
            continue;
          }
          d.status = DynastyStatus.ai;
          d.humanPlayer = null;
          ev.add(GameEvent(
            year: s.year,
            slot: d.index,
            type: 'playerLeft',
            visibility: EventVisibility.public,
          ));
        }
        // A war that now awaits nobody (the leaver's side fell to the
        // AI) runs to its end like a pure AI war.
        var guard = 0;
        while (s.activeWar != null &&
            warActingSlot(s) == null &&
            guard++ < 30) {
          if (s.activeWar!.phase == WarPhase.settlement) {
            autoSettleClaim(s, rng, ev);
          } else {
            endWarRoundWithAi(s, rng, ev);
          }
        }
      }, ignored);
      // If it was the leaver's turn, the now-AI turn completes and play
      // advances to the next human (or the game ends humansDefeated).
      state = _resumeAfterWarIfOver(state, ignored);
      match.players.remove(seat);
      await _commit(match, state, notify: true);
    } else {
      match.players.remove(seat);
      match.updatedAt = _clock();
    }

    if (match.players.isEmpty) {
      await _store.deleteMatch(match.id);
      return true;
    }
    await _store.saveMatch(match);
    return false;
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
  /// document never leaves the server. [clientAppVersion] is the build the
  /// requesting client runs; when it differs from this server's the view
  /// flags `update_required` so the client blocks the turn before it starts
  /// (the turn submission rejects it authoritatively either way).
  Future<Map<String, dynamic>> view(
    String matchId,
    String playerId, {
    String? clientAppVersion,
  }) async {
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
    // The realm this seat's view is filtered for, so the player can see and
    // play (or decide on) whichever of their realms is up — control follows
    // the ruler, so one player can hold several. See [_viewSlot].
    final playSlot = _viewSlot(state, seat, awaited, playerId);
    return {
      'id': match.id,
      'status': match.status.name,
      'human_count': match.humanCount,
      // The first seat is the creator — they alone may start the match.
      'creator_id':
          match.players.isEmpty ? null : match.players.first.playerId,
      'players': [
        for (final p in match.players)
          {
            'player_id': p.playerId,
            'display_name':
                (await _store.player(p.playerId))?.displayName ??
                    p.founderName,
            'turn_order': p.turnOrder,
            // The seat's HOME slot (where they started).
            'dynasty_index': p.slot,
            // Every realm this seat currently plays — control follows the
            // ruler, so a conquest or inheritance can leave one player on
            // several realms. The turn-order UI lists them all.
            'controlled_slots': _controlledSlots(state, p.turnOrder, p.slot),
          },
      ],
      'settings': match.settings.toJson(),
      'turn_deadline': match.turnDeadline?.toIso8601String(),
      'winner': match.winnerPlayerId,
      // The realm the client should play/show this turn (see [playSlot]).
      'your_slot': playSlot,
      // The exact realm whose input is awaited (may differ from the
      // awaited player's home slot when they hold several realms).
      'awaited_slot': state == null ? null : _awaitedSlot(state),
      'awaited_player_id': awaited,
      'your_turn': awaited == playerId,
      'server_app_version': appVersion,
      'update_required':
          clientAppVersion != null && clientAppVersion != appVersion,
      'state':
          state == null ? null : visibleStateFor(state, playSlot).toJson(),
    };
  }

  /// The realm the requesting seat's view is filtered for. On their turn:
  /// the awaited realm (they may hold several — control follows the ruler).
  /// Off-turn: a controlled realm with a pending decision they must answer,
  /// so an out-of-turn decision on a conquered/inherited realm is visible
  /// and promptable instead of stuck until that realm's own turn — else
  /// their home seat.
  int _viewSlot(
      GameState? state, MatchPlayer seat, String? awaited, String playerId) {
    if (state == null) return seat.slot;
    if (awaited == playerId) return _awaitedSlot(state)!;
    for (final d in state.pendingDecisions) {
      if (state.dynasty(d.decidingSlot).humanPlayer == seat.turnOrder) {
        return d.decidingSlot;
      }
    }
    return seat.slot;
  }

  /// The realm slots the seat with [turnOrder] currently plays as a human.
  /// Falls back to the seat's [homeSlot] before the world is built (waiting
  /// match) so the lobby still lists everyone's chosen country.
  List<int> _controlledSlots(GameState? state, int turnOrder, int homeSlot) {
    if (state == null) return [homeSlot];
    return [
      for (var s = 1; s <= World.realmCount; s++)
        if (state.dynasty(s).status == DynastyStatus.human &&
            state.dynasty(s).humanPlayer == turnOrder)
          s,
    ];
  }

  Future<List<Map<String, dynamic>>> matchesForPlayer(String playerId) async {
    await _requirePlayer(playerId);
    final matches = await _store.matchesForPlayer(playerId);
    matches.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final result = <Map<String, dynamic>>[];
    for (final m in matches) {
      final awaited = m.status == MatchStatus.active && m.stateJson != null
          ? _awaitedPlayerId(m, _load(m))
          : null;
      result.add({
        'id': m.id,
        'status': m.status.name,
        'human_count': m.humanCount,
        'joined': m.players.length,
        // Creator = first seat; a waiting match is deleted (not left)
        // by its creator — drives the lobby's delete/leave labels.
        'is_creator':
            m.players.isNotEmpty && m.players.first.playerId == playerId,
        'turn_deadline': m.turnDeadline?.toIso8601String(),
        'your_turn': awaited == playerId,
        // Whose move it is — lets the lists say "Anna ist am Zug" instead
        // of a generic waiting line.
        'awaited_name': awaited == null
            ? null
            : (await _store.player(awaited))?.displayName ??
                m.playerById(awaited)?.founderName,
        'updated_at': m.updatedAt.toIso8601String(),
      });
    }
    return result;
  }

  // --- Turn submission ---------------------------------------------------

  /// `POST /matches/:id/turn` — either `{action: {...}}` (in-turn action,
  /// war action or pending decision) or `{end_turn: true}`.
  Future<Map<String, dynamic>> submit({
    required String matchId,
    required String playerId,
    String? clientAppVersion,
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
    // A new app version may change the rules — every seat must run the same
    // build before it may take its turn (426 Upgrade Required). null is the
    // internal/test path; the HTTP layer always forwards the client's
    // version. The view's `update_required` flag warns the client first.
    if (clientAppVersion != null && clientAppVersion != appVersion) {
      throw ApiException(
          426,
          'Diese Partie läuft auf App-Version $appVersion. Bitte '
          'aktualisiere die App, um deinen Zug zu machen.');
    }
    var state = _load(match);
    final awaited = _awaitedPlayerId(match, state);
    // Events emitted by THIS submission — returned to the caller so the
    // client can show its result popups (battle reports, spy reveals).
    final emitted = <GameEvent>[];

    if (endTurn) {
      if (awaited != playerId) throw ApiException(403, 'not your turn');
      if (state.activeWar != null) {
        throw ApiException(400, 'a war must end before the turn can');
      }
      // The recap baseline ("seen up to here") moves when the player ends
      // their turn — mirrors the local client's markRecapSeen. Keyed on the
      // realm actually played (currentPlayer), which equals the home seat
      // for a single-realm player but is the awaited realm for a player who
      // holds several.
      state.recapBaselines[state.currentPlayer] =
          state.prunedEventCount + state.events.length;
      state = _endTurnAndAdvance(state, emitted);
    } else if (actionJson != null) {
      final PlayerAction action;
      try {
        action = PlayerAction.fromJson(actionJson);
      } on Object {
        throw ApiException(400, 'malformed action');
      }
      // The action must act for a realm this seat currently controls — not
      // only their home slot: control follows the ruler, so a player can
      // come to play several realms (conquest, inheritance).
      if (action.slot < 1 ||
          action.slot > World.realmCount ||
          state.dynasty(action.slot).humanPlayer != seat.turnOrder) {
        throw ApiException(403, 'action acts for a foreign realm');
      }
      if (action is ResolveDecision) {
        // Pending decisions are answered out of turn (ARCHITECTURE
        // "Pending decisions") — the engine validates id and slot.
        state = _apply(state, action, emitted);
      } else {
        if (awaited != playerId) throw ApiException(403, 'not your turn');
        if (action is WarEndRound) {
          // The engine entry point for awaited war-round input: a
          // human-vs-human attacker hands the round to the defender,
          // otherwise the AI sides respond and the round advances. Drive
          // the AWAITED war slot — for a player who holds several realms
          // that is the warring realm, not necessarily their home seat
          // (a home-seat slot would skip the handover and the defender's
          // half of the round).
          final warSlot = _awaitedSlot(state)!;
          state = _mutate(
              state,
              (s, rng, ev) => endWarRoundFor(s, warSlot, rng, ev),
              emitted);
          // Mark the war report "seen up to here" for the side that just
          // finished its round (mirrors the local client's markRecapSeen on
          // endWarRound): the opponent's next round of battles then arrives
          // as a fresh recap, so the turn-start war report shows only what
          // happened since — not every battle of the war, every round. Set
          // before _resumeAfterWarIfOver so a post-war AI advance still lands
          // in this player's next recap card.
          state.recapBaselines[warSlot] =
              state.prunedEventCount + state.events.length;
        } else {
          state = _apply(state, action, emitted);
        }
        state = _resumeAfterWarIfOver(state, emitted);
      }
    } else {
      throw ApiException(400, 'provide action or end_turn');
    }

    await _commit(match, state, notify: true);
    await _store.saveMatch(match);
    final result = await view(matchId, playerId);
    result['events'] = [
      for (final e in emitted)
        if (e.visibleTo(seat.slot)) e.toJson(),
    ];
    return result;
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
      final ignored = <GameEvent>[];
      if (state.activeWar != null) {
        // The awaited combatant idles: their war round falls back to the
        // AI war logic for this side (ARCHITECTURE "war clock"), then
        // their round end is submitted for them — in a human-vs-human
        // war an idle attacker thereby hands over to the defender. An
        // idle winner's open claim settlement settles like the AI's.
        final idleSlot = warActingSlot(state);
        state = _mutate(state, (s, rng, ev) {
          final war = s.activeWar;
          if (war == null) return;
          if (war.phase == WarPhase.settlement) {
            autoSettleClaim(s, rng, ev);
            return;
          }
          if (idleSlot != null) runAiWarMovement(s, idleSlot, rng, ev);
          if (s.activeWar != null) {
            endWarRoundFor(s, idleSlot ?? war.attackerSlot, rng, ev);
          }
        }, ignored);
        state = _resumeAfterWarIfOver(state, ignored);
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
                    slot: awaitedSlot, decisionId: d.id, choice: const {}),
                ignored);
          }
          state = _endTurnAndAdvance(state, ignored);
        }
      }
      await _commit(match, state, notify: true);
      await _store.saveMatch(match);
    }
    return expired.length;
  }

  // --- Pipeline helpers ----------------------------------------------------

  GameState _load(MatchRecord match) => GameState.fromJson(match.stateJson!);

  GameState _apply(
      GameState state, PlayerAction action, List<GameEvent> emitted) {
    try {
      final result = applyAction(state, action, Rng(state.rngSeed));
      emitted.addAll(result.events);
      return result.state;
    } on ActionException catch (e) {
      throw ApiException(400, e.message);
    }
  }

  GameState _mutate(
    GameState state,
    void Function(GameState, Rng, List<GameEvent>) f,
    List<GameEvent> emitted,
  ) {
    final next = state.copy();
    final rng = Rng(next.rngSeed);
    final events = <GameEvent>[];
    f(next, rng, events);
    next.rngSeed = rng.seed;
    next.events.addAll(events);
    emitted.addAll(events);
    return next;
  }

  GameState _endTurnAndAdvance(GameState state, List<GameEvent> emitted) {
    final ended = completeTurn(state, Rng(state.rngSeed));
    emitted.addAll(ended.events);
    final advanced = advanceUntilHuman(ended.state, Rng(ended.state.rngSeed));
    emitted.addAll(advanced.events);
    return advanced.state;
  }

  /// A war that interrupted an AI's turn leaves that turn half-finished
  /// when it ends — complete it and let the remaining AIs play (mirrors
  /// the client's GameController.resumeAfterWar).
  GameState _resumeAfterWarIfOver(GameState state, List<GameEvent> emitted) {
    if (state.activeWar != null || _gameOver(state)) return state;
    if (state.dynasty(state.currentPlayer).status == DynastyStatus.human) {
      return state;
    }
    return _endTurnAndAdvance(state, emitted);
  }

  bool _gameOver(GameState state) =>
      state.events.isNotEmpty &&
      const {'gameWon', 'gameDraw', 'humansDefeated'}
          .contains(state.events.last.type);

  /// Realm slot whose human input the match is waiting for, or null.
  int? _awaitedSlot(GameState state) {
    if (_gameOver(state)) return null;
    if (state.activeWar != null) {
      // The war's acting side (alternates between two human combatants).
      return warActingSlot(state);
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
    final previous = match.stateJson == null ? null : _load(match);
    final previousAwaited =
        previous == null ? null : _awaitedPlayerId(match, previous);
    final hadWar =
        match.stateJson != null && (match.stateJson!['activeWar'] != null);
    // Decisions that already existed before this commit were nudged when
    // they first appeared — re-pushing them on every later commit (e.g. on
    // each AI turn while a player's election vote sits open) was the source
    // of the notification spam. Only NEW decisions get a push below.
    final previousDecisionIds = previous == null
        ? const <String>{}
        : {for (final d in previous.pendingDecisions) d.id};

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
    if (state.activeWar != null && !hadWar) {
      // Both human combatants learn about a fresh war (ARCHITECTURE
      // "war clock") — the awaited one must act, the other may delegate
      // their next round to the clock or play it live.
      final war = state.activeWar!;
      for (final slot in [war.attackerSlot, war.defenderSlot]) {
        final id = _playerForSlot(match, state, slot);
        if (id == null) continue;
        final p = await _store.player(id);
        if (p != null) await _push.warStarted(p, match);
      }
    } else if (awaited != previousAwaited) {
      final player = await _store.player(awaited);
      if (player != null) await _push.yourTurn(player, match);
    }
    // Out-of-turn decisions get their own nudge — but only once, when the
    // decision first appears (see previousDecisionIds), never re-pushed on
    // every subsequent commit.
    final notified = <String>{};
    for (final d in state.pendingDecisions) {
      if (previousDecisionIds.contains(d.id)) continue;
      final decider = _playerForSlot(match, state, d.decidingSlot);
      // At most one decision nudge per player per commit, even when an
      // election creates several decisions for the same seat at once.
      if (decider != null && decider != awaited && notified.add(decider)) {
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
    // Room codes are read out loud and typed by hand — accept lowercase.
    final match =
        await _store.match(id.length == 5 ? id.toUpperCase() : id);
    if (match == null) throw ApiException(404, 'unknown match');
    return match;
  }
}
