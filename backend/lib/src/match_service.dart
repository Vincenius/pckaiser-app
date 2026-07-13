/// Match orchestration (ARCHITECTURE.md "Turn Flow (online)"): the same
/// game_core pipeline the local client drives, persisted per match. The
/// server validates every submission; clients never mutate state.
library;

import 'dart:async';

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

  /// Per-key in-flight operation, chained so the mutations that
  /// read-modify-write one persisted document run one at a time. Without it
  /// two awaited operations on the same match (e.g. a turn submission racing
  /// the once-a-minute timeout sweep) both read the same stored state and
  /// the second save silently overwrites the first — a lost update. Keyed by
  /// canonical match id, plus a single [_playersKey] for the shared players
  /// file. The server runs on one isolate, so an in-process lock suffices.
  final Map<String, Future<void>> _locks = {};
  static const String _playersKey = 'players';

  /// Runs [body] after any prior operation on [key] completes, making the
  /// read-modify-write atomic with respect to other [_locked] calls.
  Future<T> _locked<T>(String key, Future<T> Function() body) async {
    final previous = _locks[key];
    final gate = Completer<void>();
    _locks[key] = gate.future;
    try {
      await previous; // the gate always completes normally — never throws
      return await body();
    } finally {
      gate.complete();
      // Drop the entry once we are the tail so the map can't grow unbounded.
      if (identical(_locks[key], gate.future)) _locks.remove(key);
    }
  }

  /// Room codes are read out loud and typed by hand — match them
  /// case-insensitively (legacy UUID ids are left as-is).
  String _canonicalId(String id) => id.length == 5 ? id.toUpperCase() : id;

  // --- Players ----------------------------------------------------------

  Future<PlayerRecord> registerPlayer({
    String? id,
    required String displayName,
    String? fcmToken,
  }) {
    if (displayName.trim().isEmpty) {
      throw ApiException(400, 'display_name must not be empty');
    }
    // All players share one document; serialize writes so concurrent
    // registrations / token refreshes don't clobber each other.
    return _locked(_playersKey, () async {
      // Re-registration is the client's rename upsert and passes no
      // token — keep the stored record's token (and original createdAt)
      // or the player silently stops receiving turn pushes.
      final existing = id == null ? null : await _store.player(id);
      final player = PlayerRecord(
        id: id ?? uuidV4(),
        displayName: displayName.trim(),
        fcmToken: fcmToken ?? existing?.fcmToken,
        createdAt: existing?.createdAt,
      );
      await _store.savePlayer(player);
      return player;
    });
  }

  Future<PlayerRecord> updatePlayer(
    String id, {
    String? displayName,
    String? fcmToken,
  }) {
    return _locked(_playersKey, () async {
      final player = await _requirePlayer(id);
      if (displayName != null && displayName.trim().isNotEmpty) {
        player.displayName = displayName.trim();
      }
      if (fcmToken != null) player.fcmToken = fcmToken;
      await _store.savePlayer(player);
      return player;
    });
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
  }) {
    return _locked(_canonicalId(matchId), () async {
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
    });
  }

  /// Starts a waiting match — only the creator (first seat) may. The
  /// world is built for exactly the joined players; nobody can join a
  /// started game.
  Future<MatchRecord> startMatch({
    required String matchId,
    required String playerId,
  }) {
    return _locked(_canonicalId(matchId), () async {
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
    });
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
  }) {
    return _locked(_canonicalId(matchId), () => _leaveMatch(matchId, playerId));
  }

  Future<bool> _leaveMatch(String matchId, String playerId) async {
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
      await _dropSeatToAi(match, seat, eventType: 'playerLeft');
    } else {
      match.players.remove(seat);
      if (match.status == MatchStatus.waiting) {
        // Keep turnOrder contiguous: _start maps dynasties to the seats'
        // POSITIONAL index (newGame's humanPlayer is 0..n-1), and a later
        // join assigns turnOrder = players.length — a gap would orphan the
        // seat behind it and a reused number would map to the wrong seat.
        for (var i = 0; i < match.players.length; i++) {
          match.players[i].turnOrder = i;
        }
      }
      match.updatedAt = _clock();
    }

    if (match.players.isEmpty) {
      await _store.deleteMatch(match.id);
      return true;
    }
    await _store.saveMatch(match);
    return false;
  }

  /// Consecutive timed-out turns after which the creator may kick a seat.
  static const int idleKickThreshold = 3;

  /// Kicks an idle seat and replaces its realm(s) with the AI — creator
  /// only, only once the seat has missed [idleKickThreshold] turns in a
  /// row. Everyone learns about it via a public `playerKicked` event.
  Future<MatchRecord> kickPlayer({
    required String matchId,
    required String requesterId,
    required String targetPlayerId,
  }) {
    return _locked(_canonicalId(matchId), () async {
      await _requirePlayer(requesterId);
      final match = await _requireMatch(matchId);
      if (match.status != MatchStatus.active) {
        throw ApiException(400, 'match is not active');
      }
      if (match.players.isEmpty ||
          match.players.first.playerId != requesterId) {
        throw ApiException(403, 'only the creator can remove a player');
      }
      final target = match.playerById(targetPlayerId);
      if (target == null) {
        throw ApiException(404, 'player is not part of this match');
      }
      if (target.playerId == requesterId) {
        throw ApiException(400, 'the creator cannot remove themselves');
      }
      if (target.idleTurns < idleKickThreshold) {
        throw ApiException(400, 'player has not been idle long enough');
      }
      await _dropSeatToAi(match, target, eventType: 'playerKicked');
      if (match.players.isEmpty) {
        await _store.deleteMatch(match.id);
      } else {
        await _store.saveMatch(match);
      }
      return match;
    });
  }

  /// Hands every realm a seat still holds to the AI and removes the seat:
  /// resolves its open decisions with their defaults, flips its dynasties
  /// to AI (emitting [eventType] per realm), runs any now-ownerless war to
  /// its end and lets a half-finished AI turn continue — then commits the
  /// new state. Shared by [leaveMatch] (`playerLeft`) and [kickPlayer]
  /// (`playerKicked`). The caller persists/deletes the record.
  Future<void> _dropSeatToAi(
    MatchRecord match,
    MatchPlayer seat, {
    required String eventType,
  }) async {
    var state = _load(match);
    final ignored = <GameEvent>[];
    // Answer the seat's open decisions with their defaults while the
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
          type: eventType,
          visibility: EventVisibility.public,
        ));
      }
      // A war that now awaits nobody (the dropped side fell to the AI)
      // runs to its end like a pure AI war.
      var guard = 0;
      while (s.activeWar != null && warActingSlot(s) == null && guard++ < 30) {
        if (s.activeWar!.phase == WarPhase.settlement) {
          autoSettleClaim(s, rng, ev);
        } else {
          endWarRoundWithAi(s, rng, ev);
        }
      }
    }, ignored);
    // If it was this seat's turn, the now-AI turn completes and play
    // advances to the next human (or the game ends humansDefeated).
    state = _resumeAfterWarIfOver(state, ignored);
    match.players.remove(seat);
    await _commit(match, state, notify: true);
  }

  void _seat(MatchRecord match, String playerId, Map<String, dynamic> setup) {
    // The setup map comes straight from the request body — a wrong field
    // TYPE is a client error (400), not a server 500.
    final String founderName;
    final String dorfName;
    final int gender;
    final int? requestedSlot;
    try {
      founderName = (setup['founder_name'] as String?)?.trim() ?? '';
      dorfName = (setup['dorf_name'] as String?)?.trim() ?? '';
      gender = setup['gender'] as int? ?? 0;
      requestedSlot = setup['country_slot'] as int?;
    } on TypeError {
      throw ApiException(400, 'invalid field type in setup');
    }
    if (founderName.isEmpty || dorfName.isEmpty) {
      throw ApiException(400, 'founder_name and dorf_name are required');
    }
    if (gender != 0 && gender != 1) {
      throw ApiException(400, 'gender must be 0 or 1');
    }
    final taken = {for (final p in match.players) p.slot};
    var slot = requestedSlot;
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
      warStartYear: match.settings.warStartYear,
      genderEqualSuccession: match.settings.genderEqualSuccession,
      suggestChildNames: match.settings.suggestChildNames,
      aiDifficulty: AiDifficulty.fromName(match.settings.aiDifficulty),
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
      'creator_id': match.players.isEmpty ? null : match.players.first.playerId,
      'players': [
        for (final p in match.players)
          {
            'player_id': p.playerId,
            'display_name':
                (await _store.player(p.playerId))?.displayName ?? p.founderName,
            'turn_order': p.turnOrder,
            // The seat's HOME slot (where they started).
            'dynasty_index': p.slot,
            // Every realm this seat currently plays — control follows the
            // ruler, so a conquest or inheritance can leave one player on
            // several realms. The turn-order UI lists them all.
            'controlled_slots': _controlledSlots(state, p.turnOrder, p.slot),
            // Consecutive timed-out turns — the creator's UI offers a kick
            // once this reaches [idleKickThreshold].
            'idle_turns': p.idleTurns,
          },
      ],
      'settings': match.settings.toJson(includeSeed: false),
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
      'state': state == null ? null : visibleStateFor(state, playSlot).toJson(),
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
      String? awaited;
      try {
        awaited = m.status == MatchStatus.active && m.stateJson != null
            ? _awaitedPlayerId(m, _load(m))
            : null;
      } catch (_) {
        // One corrupt/legacy match document must not 500 the whole list —
        // the match still shows up, just without the "whose turn" line.
      }
      // War-start info for the lobby line: while a both-live duel waits for
      // its start, NOBODY is awaited — without these fields the list could
      // only say a generic "waiting". Read straight off the state JSON (no
      // full GameState load for a list line).
      final warJson = m.stateJson?['activeWar'] as Map?;
      final warPreparing =
          m.status == MatchStatus.active && warJson?['phase'] == 'preparation';
      final scheduledMs = warJson?['scheduledStartMs'] as int?;
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
        // A war preparation is running (the duel start may be what the
        // match is waiting for) — and the agreed start, if the sides
        // found a common warPlan slot.
        'war_preparing': warPreparing,
        'war_scheduled_at': warPreparing && scheduledMs != null && scheduledMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(scheduledMs, isUtc: true)
                .toIso8601String()
            : null,
        'updated_at': m.updatedAt.toIso8601String(),
      });
    }
    return result;
  }

  /// Open public matches anyone may join — the lobby's discovery list.
  /// Carries enough to decide whether to join (settings + how full it is +
  /// who hosts it) but never the game state. Newest first.
  Future<List<Map<String, dynamic>>> publicMatches() async {
    final matches = await _store.publicWaitingMatches();
    matches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final result = <Map<String, dynamic>>[];
    for (final m in matches) {
      final creatorId = m.players.isEmpty ? null : m.players.first.playerId;
      result.add({
        'id': m.id,
        'status': m.status.name,
        'joined': m.players.length,
        'settings': m.settings.toJson(includeSeed: false),
        'creator_name': creatorId == null
            ? null
            : (await _store.player(creatorId))?.displayName ??
                m.players.first.founderName,
        'created_at': m.createdAt.toIso8601String(),
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
  }) {
    return _locked(
        _canonicalId(matchId),
        () => _submit(
              matchId: matchId,
              playerId: playerId,
              clientAppVersion: clientAppVersion,
              actionJson: actionJson,
              endTurn: endTurn,
            ));
  }

  Future<Map<String, dynamic>> _submit({
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
        // A warPlan answer may complete the war preparation: apply the
        // start rules. With a turn timer, a both-live duel waits for the
        // deadline (fair start, `_sweepMatch` forces it); without one the
        // early-start rules alone govern.
        if (state.activeWar?.phase == WarPhase.preparation) {
          state = _mutate(
              state,
              (s, rng, ev) => resolveWarPreparation(s, rng, ev,
                  waitWhenAllManual: match.settings.turnTimeoutHours != null),
              emitted);
          state = _resumeAfterWarIfOver(state, emitted);
        }
      } else if (action is SetTroopStance &&
          state.activeWar?.phase == WarPhase.preparation &&
          state.activeWar!.isParticipant(action.slot)) {
        // War-preparation troop orders are accepted OUT OF TURN like
        // decisions: both combatants line their units up individually
        // (hold / attack) before the war starts — the defender is never
        // the awaited player during the preparation window, and once both
        // sides answered nobody is. The controlled-realm check above
        // already ran; the action only sets a unit's autopilot stance.
        state = _apply(state, action, emitted);
      } else {
        if (awaited != playerId) throw ApiException(403, 'not your turn');
        // No-show bookkeeping (online duel scheduling): ANY interactive
        // input during the war rounds marks this side as present
        // (`war.actedSlots`). A side that never acted before its round
        // clock expires is handed to the autopilot by the sweep.
        final actsInWarRound = state.activeWar?.phase == WarPhase.rounds &&
            state.activeWar!.isParticipant(action.slot);
        // Beyond controlling the realm, the action must act for the realm
        // whose input is actually awaited (the running turn, or the war's
        // acting side). A seat holding several realms may otherwise act for
        // realm B during realm A's turn — doubling B's once-per-turn
        // actions (grain sale, movement points) every year.
        if (action.slot != _awaitedSlot(state)) {
          throw ApiException(
              403,
              'action acts for a realm whose turn is '
              'not running');
        }
        if (action is WarEndRound) {
          // The engine entry point for awaited war-round input: a
          // human-vs-human attacker hands the round to the defender,
          // otherwise the AI sides respond and the round advances. Drive
          // the AWAITED war slot — for a player who holds several realms
          // that is the warring realm, not necessarily their home seat
          // (a home-seat slot would skip the handover and the defender's
          // half of the round).
          final warSlot = _awaitedSlot(state)!;
          state = _mutate(state,
              (s, rng, ev) => endWarRoundFor(s, warSlot, rng, ev), emitted);
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
        if (actsInWarRound) state.activeWar?.actedSlots.add(action.slot);
        state = _resumeAfterWarIfOver(state, emitted);
      }
    } else {
      throw ApiException(400, 'provide action or end_turn');
    }

    // The seat showed up and submitted — clear its idle streak (the
    // creator's kick-idle option keys off consecutive timed-out turns).
    seat.idleTurns = 0;

    await _commit(match, state, notify: true);
    await _store.saveMatch(match);
    final result = await view(matchId, playerId);
    // Filter the returned events against EVERY realm this seat controls, not
    // just its home slot — control follows the ruler, so a player on a
    // conquered/inherited realm must still receive that realm's own (owner /
    // participants) battle reports and spy reveals. `seat.slot` is always
    // included so public events survive even if the seat lost its realms.
    final visibleSlots = {
      seat.slot,
      ..._controlledSlots(state, seat.turnOrder, seat.slot),
    };
    result['events'] = [
      for (final e in emitted)
        if (visibleSlots.any(e.visibleTo)) e.toJson(),
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
    var swept = 0;
    for (final stale in expired) {
      final didSweep = await _locked(stale.id, () async {
        // Re-read under the lock: a turn submitted between the bulk scan
        // above and acquiring this lock may already have advanced the match
        // past its old deadline, so it must no longer be swept.
        final match = await _store.match(stale.id);
        if (match == null ||
            match.status != MatchStatus.active ||
            match.turnDeadline == null ||
            !match.turnDeadline!.isBefore(now)) {
          return false;
        }
        await _sweepMatch(match);
        return true;
      });
      if (didSweep) swept++;
    }
    await _sendWarStartReminders(now);
    return swept;
  }

  /// ~15 minutes before an AGREED duel start, nudge both live combatants
  /// once ("dein Krieg beginnt in Kürze"). Only for a start time both
  /// sides explicitly chose (warPlan slot matching) — the half-turn
  /// fallback gets no reminder, exactly as before scheduling.
  /// `match.warReminderFor` dedups per start time across sweep runs.
  Future<void> _sendWarStartReminders(DateTime now) async {
    const lead = Duration(minutes: 15);
    // Reuses the expiry scan with a 15-min lookahead: "deadline before
    // now+15min but not yet expired" is exactly the reminder window.
    for (final candidate in await _store.expiredMatches(now.add(lead))) {
      if (candidate.turnDeadline == null ||
          candidate.turnDeadline!.isBefore(now)) {
        continue; // actually expired — sweepExpired handles it
      }
      await _locked(candidate.id, () async {
        final match = await _store.match(candidate.id);
        if (match == null ||
            match.status != MatchStatus.active ||
            match.turnDeadline == null ||
            match.turnDeadline!.isBefore(now) ||
            match.warReminderFor == match.turnDeadline) {
          return;
        }
        final state = _load(match);
        final war = state.activeWar;
        final scheduled = war?.scheduledStartMs;
        if (war == null ||
            war.phase != WarPhase.preparation ||
            scheduled == null ||
            scheduled <= 0) {
          return;
        }
        match.warReminderFor = match.turnDeadline;
        await _store.saveMatch(match);
        for (final slot in [war.attackerSlot, war.defenderSlot]) {
          if (war.autoSlots.contains(slot)) continue;
          final id = _playerForSlot(match, state, slot);
          if (id == null) continue;
          final p = await _store.player(id);
          if (p != null) await _push.warStartSoon(p, match);
        }
      });
    }
  }

  Future<void> _sweepMatch(MatchRecord match) async {
    var state = _load(match);
    final ignored = <GameEvent>[];
    if (state.activeWar?.phase == WarPhase.preparation) {
      // The war-start reaction window expired: unanswered sides default
      // to the stance autopilot and the war begins — a both-live duel
      // starts exactly at the deadline (fair, nobody misses it), a fully
      // delegated war fast-forwards to its end.
      state = _mutate(
          state,
          (s, rng, ev) => resolveWarPreparation(s, rng, ev, force: true),
          ignored);
      state = _resumeAfterWarIfOver(state, ignored);
    } else if (state.activeWar != null) {
      // The awaited combatant idles: their war round falls back to the
      // AI war logic for this side (ARCHITECTURE "war clock"), then
      // their round end is submitted for them — in a human-vs-human
      // war an idle attacker thereby hands over to the defender. An
      // idle winner's open claim settlement settles like the AI's.
      final idleSlot = warActingSlot(state);
      // No-show rule (online duel scheduling): a duelist who NEVER acted
      // in this war and lets their round clock expire is handed to the
      // stance autopilot for the REST of the war — an absent player would
      // otherwise drag every remaining round out by one short clock each.
      // Applied AFTER this round's classic fallback so the handover
      // semantics of the current round stay intact; only in a live
      // human-vs-human duel (a human fighting an AI keeps the full turn
      // clock per round, as before).
      final noShow = idleSlot != null &&
          _warIsHumanVsHuman(state) &&
          state.activeWar!.phase == WarPhase.rounds &&
          !state.activeWar!.actedSlots.contains(idleSlot);
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
        if (noShow) s.activeWar?.autoSlots.add(idleSlot);
      }, ignored);
      state = _resumeAfterWarIfOver(state, ignored);
    } else {
      final awaitedSlot = _awaitedSlot(state);
      if (awaitedSlot != null) {
        // The awaited seat never showed up — count this missed turn so the
        // creator can replace a persistently idle player with the AI.
        final humanIndex = state.dynasty(awaitedSlot).humanPlayer;
        final idleSeat =
            humanIndex == null ? null : match.playerByTurnOrder(humanIndex);
        if (idleSeat != null) idleSeat.idleTurns += 1;
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

  /// True when an active war has a HUMAN on both sides (a live duel that runs
  /// on the short war clock). A human-vs-AI war instead uses the normal turn
  /// clock — see [_commit]'s timeout. A side that delegated the war to the
  /// autopilot (`warDefense` decision) no longer counts as human.
  bool _warIsHumanVsHuman(GameState state) {
    final war = state.activeWar;
    if (war == null) return false;
    return warSideIsHuman(state, war, war.attackerSlot) &&
        warSideIsHuman(state, war, war.defenderSlot);
  }

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
    return match.playerByTurnOrder(humanIndex)?.playerId;
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
        final winner =
            humanIndex == null ? null : match.playerByTurnOrder(humanIndex);
        if (winner != null) match.winnerPlayerId = winner.playerId;
      }
      return;
    }

    final awaited = _awaitedPlayerId(match, state);
    final turnTimeout = match.settings.turnTimeoutHours == null
        ? null
        : Duration(hours: match.settings.turnTimeoutHours!);
    // Clock selection: the war PREPARATION window runs on HALF the turn
    // timer (user design — the reaction window before the duel; armed even
    // when nobody is awaited, so a both-live start fires exactly at the
    // deadline via the sweep). War ROUNDS of a live human-vs-human duel run
    // on the short war clock; a human fighting an AI (or a delegated
    // opponent) gets the FULL turn clock instead — "time like a normal
    // turn". null turnTimeoutHours ⇒ no deadline (match waits; the
    // preparation then starts via the early-start rules alone).
    final prep = state.activeWar?.phase == WarPhase.preparation;
    final scheduledMs = state.activeWar?.scheduledStartMs;
    // The preparation window is ONE fixed deadline, armed when the war is
    // declared. Later commits during the same preparation (the warPlan
    // answers themselves, out-of-turn decisions) must NOT re-arm it —
    // every answer would otherwise push the "fair start" of a both-live
    // duel another half turn timer into the future.
    final wasPrep = previous?.activeWar?.phase == WarPhase.preparation;
    if (prep && scheduledMs != null && scheduledMs > 0) {
      // The sides AGREED on a duel start (warPlan slot matching): the
      // deadline IS the appointment. It may lie later than the half-turn
      // fallback (both sides chose it) and also works in a match without
      // a turn timer. Idempotent across commits — re-arming to the same
      // instant never moves the start.
      match.turnDeadline =
          DateTime.fromMillisecondsSinceEpoch(scheduledMs, isUtc: true);
    } else if (!(prep && wasPrep)) {
      final Duration? timeout;
      if (prep) {
        timeout = turnTimeout == null
            ? null
            : Duration(seconds: turnTimeout.inSeconds ~/ 2);
      } else if (state.activeWar != null && _warIsHumanVsHuman(state)) {
        timeout = Duration(seconds: match.settings.warRoundTimeoutSeconds);
      } else {
        timeout = turnTimeout;
      }
      match.turnDeadline = timeout == null || (awaited == null && !prep)
          ? null
          : _clock().add(timeout);
    }

    // Duel scheduling: the moment BOTH warPlan answers are in while the
    // preparation still waits (both live), tell both sides when the duel
    // starts — their agreed slot, or the fallback deadline when no
    // proposals overlapped. Sent before the awaited-null return below:
    // during this wait nobody is awaited.
    if (notify &&
        prep &&
        previous != null &&
        previous.pendingDecisions.any((d) => d.type == 'warPlan') &&
        !state.pendingDecisions.any((d) => d.type == 'warPlan') &&
        match.turnDeadline != null) {
      final war = state.activeWar!;
      for (final slot in [war.attackerSlot, war.defenderSlot]) {
        final id = _playerForSlot(match, state, slot);
        if (id == null) continue;
        final p = await _store.player(id);
        if (p != null) {
          await _push.warStartFixed(p, match, match.turnDeadline!,
              agreed: scheduledMs != null && scheduledMs > 0);
        }
      }
    }

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
    return match.playerByTurnOrder(humanIndex)?.playerId;
  }

  // --- Lookups -----------------------------------------------------------

  Future<PlayerRecord> _requirePlayer(String id) async {
    final player = await _store.player(id);
    if (player == null) throw ApiException(404, 'unknown player');
    return player;
  }

  Future<MatchRecord> _requireMatch(String id) async {
    final match = await _store.match(_canonicalId(id));
    if (match == null) throw ApiException(404, 'unknown match');
    return match;
  }
}
