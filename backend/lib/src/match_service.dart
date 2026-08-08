/// Match orchestration (ARCHITECTURE.md "Turn Flow (online)"): the same
/// game_core pipeline the local client drives, persisted per match. The
/// server validates every submission; clients never mutate state.
library;

import 'dart:async';

import 'package:game_core/game_core.dart';

import 'match_templates.dart';
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

/// The realm count a match's world is (or will be) built with: the host's
/// choice clamped into the map size's valid range — settings come off the
/// wire, and an out-of-range value must degrade, never 500 the start.
int realmCountFor(MatchSettings settings) {
  final size = MapSize.fromName(settings.mapSize);
  final count = settings.realmCount ?? size.defaultRealmCount;
  return count.clamp(size.minRealmCount, size.maxRealmCount);
}

/// Human seats a match can hold: capped by the realms in play (and the
/// original's 16). Guards joins AND keeps full rooms out of the public
/// discovery list.
int seatCapFor(MatchSettings settings) {
  final realmCount = realmCountFor(settings);
  final cap = realmCount < 16 ? realmCount : 16;
  // A matchmaking room never seats more than its start target — reaching
  // the target starts the match, so the target IS its cap.
  final template = templateFor(settings);
  return template != null && template.seats < cap ? template.seats : cap;
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
    final match = MatchRecord(
      id: await _freshMatchId(),
      settings: settings,
      players: [],
    );
    _seat(match, playerId, setup);
    await _store.saveMatch(match);
    return match;
  }

  /// An unused room code — retries on the rare collision.
  Future<String> _freshMatchId() async {
    var id = matchCode();
    while (await _store.match(id) != null) {
      id = matchCode();
    }
    return id;
  }

  // --- Matchmaking rooms (match_templates.dart) --------------------------

  /// Lock key for the room bookkeeping — creating the replacement room must
  /// not race a second creator (two rooms of the same kind would split the
  /// players, which is exactly what the templates exist to prevent).
  static const String _templatesKey = 'templates';

  /// Tops the lobby up so every [matchTemplates] entry has exactly one open
  /// room. Called at server start, from the minute sweep and right after a
  /// room started — a started room is replaced immediately.
  Future<void> ensureTemplateMatches() {
    return _locked(_templatesKey, () async {
      final open = await _store.publicWaitingMatches();
      final have = {
        for (final m in open)
          if (m.settings.template != null) m.settings.template,
      };
      for (final template in matchTemplates) {
        if (have.contains(template.key)) continue;
        await _store.saveMatch(MatchRecord(
          id: await _freshMatchId(),
          settings: template.newSettings(),
          players: [],
        ));
      }
    });
  }

  /// Starts every matchmaking room whose fallback deadline has passed (it
  /// never filled up, so it starts with the humans it has and AI for the
  /// rest), then tops the lobby up. Returns the number of rooms started.
  Future<int> sweepTemplates() async {
    final now = _clock();
    var started = 0;
    for (final candidate in await _store.publicWaitingMatches()) {
      if (templateFor(candidate.settings) == null) continue;
      if (candidate.autoStartAt == null ||
          candidate.autoStartAt!.isAfter(now)) {
        continue;
      }
      final didStart = await _locked(candidate.id, () async {
        // Re-read under the lock like the other sweeps: a join between the
        // scan and the lock may have filled (and started) the room already.
        final match = await _store.match(candidate.id);
        if (match == null ||
            match.status != MatchStatus.waiting ||
            match.players.isEmpty ||
            match.autoStartAt == null ||
            match.autoStartAt!.isAfter(now)) {
          return false;
        }
        await _start(match);
        match.updatedAt = _clock();
        await _store.saveMatch(match);
        return true;
      });
      if (didStart) started++;
    }
    await ensureTemplateMatches();
    return started;
  }

  /// Joins a waiting match (up to 16 human seats). A matchmaking room
  /// starts on its own once full — and is replaced by a fresh open room.
  Future<MatchRecord> joinMatch({
    required String matchId,
    required String playerId,
    required Map<String, dynamic> setup,
  }) async {
    final match = await _locked(_canonicalId(matchId), () async {
      await _requirePlayer(playerId);
      final match = await _requireMatch(matchId);
      if (match.status != MatchStatus.waiting) {
        throw ApiException(400, 'match is not open for joining');
      }
      if (match.playerById(playerId) != null) {
        throw ApiException(400, 'player already joined');
      }
      if (match.players.length >= seatCapFor(match.settings)) {
        throw ApiException(400, 'match is full');
      }
      _seat(match, playerId, setup);
      final template = templateFor(match.settings);
      if (template != null) {
        if (match.players.length >= template.seats) {
          // Full — the room starts at once (nobody has to press anything).
          await _start(match);
        } else if (match.players.length >= template.fallbackSeats &&
            match.autoStartAt == null) {
          // Enough players to be worth playing: from here the room starts
          // on a deadline even if the last seats stay empty.
          match.autoStartAt = _clock().add(MatchTemplate.fallbackDelay);
        }
      } else if (match.humanCount != null &&
          match.players.length == match.humanCount) {
        // Legacy fixed-size matches (pre room codes) still auto-start when
        // the last announced seat fills.
        await _start(match);
      }
      match.updatedAt = _clock();
      await _store.saveMatch(match);
      return match;
    });
    // The lobby must always offer an open room of every kind — replace one
    // that just started (outside the match lock, it takes the room lock).
    if (match.status != MatchStatus.waiting &&
        templateFor(match.settings) != null) {
      await ensureTemplateMatches();
    }
    return match;
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
      // A matchmaking room has no host: it starts when it is full or when
      // its fallback deadline passes, never by hand.
      if (templateFor(match.settings) != null) {
        throw ApiException(400, 'this match starts automatically');
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

    final template = templateFor(match.settings);
    if (match.status == MatchStatus.waiting && template != null) {
      // A matchmaking room belongs to the server, not to its first joiner:
      // leaving only frees the seat, and even an emptied room stays open
      // for the next player instead of being deleted.
      match.players.remove(seat);
      for (var i = 0; i < match.players.length; i++) {
        match.players[i].turnOrder = i;
      }
      // Back below the threshold that armed the fallback start — disarm it,
      // or the room would start understaffed at the old deadline.
      if (match.players.length < template.fallbackSeats) {
        match.autoStartAt = null;
      }
      match.updatedAt = _clock();
      await _store.saveMatch(match);
      return false;
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
    final int? requestedColor;
    try {
      founderName = (setup['founder_name'] as String?)?.trim() ?? '';
      dorfName = (setup['dorf_name'] as String?)?.trim() ?? '';
      gender = setup['gender'] as int? ?? 0;
      requestedSlot = setup['country_slot'] as int?;
      requestedColor = setup['color'] as int?;
    } on TypeError {
      throw ApiException(400, 'invalid field type in setup');
    }
    if (founderName.isEmpty || dorfName.isEmpty) {
      throw ApiException(400, 'founder_name and dorf_name are required');
    }
    if (gender != 0 && gender != 1) {
      throw ApiException(400, 'gender must be 0 or 1');
    }
    final realmCount = realmCountFor(match.settings);
    final taken = {for (final p in match.players) p.slot};
    var slot = requestedSlot;
    if (slot != null) {
      if (slot < 1 || slot > realmCount) {
        throw ApiException(400, 'country_slot must be 1–$realmCount');
      }
      if (taken.contains(slot)) {
        throw ApiException(400, 'country_slot already taken');
      }
    } else {
      // First free slot after a random offset — uniform enough and
      // deterministic to test with a seeded settings RNG is overkill.
      final free = [
        for (var s = 1; s <= realmCount; s++)
          if (!taken.contains(s)) s,
      ];
      free.shuffle();
      slot = free.first;
    }
    // A color another seat already picked silently falls back to the
    // slot-derived default instead of rejecting the join — the openSlots
    // hint is best-effort, so two players CAN race for the same swatch.
    // Same fallback for a value outside fully-opaque 32-bit ARGB: the
    // color is display-only but rendered on EVERY player's map, and a
    // doctored client could otherwise seat e.g. an invisible (alpha 0)
    // realm. The swatch list itself is not pinned server-side — future
    // clients may offer more choices without a backend change.
    final takenColors = {
      for (final p in match.players)
        if (p.color != null) p.color,
    };
    final opaque = requestedColor != null &&
        requestedColor >= 0xFF000000 &&
        requestedColor <= 0xFFFFFFFF;
    match.players.add(MatchPlayer(
      playerId: playerId,
      turnOrder: match.players.length,
      slot: slot,
      founderName: founderName,
      gender: gender,
      dorfName: dorfName,
      color: opaque && !takenColors.contains(requestedColor)
          ? requestedColor
          : null,
    ));
  }

  /// All seats filled: build the world and run to the first awaited human
  /// (mirrors the client's LocalGameSession.create).
  Future<void> _start(MatchRecord match) async {
    // A scheduled start (matchmaking room) is spent once the game runs.
    match.autoStartAt = null;
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
            color: p.color,
          ),
      ],
      // Event years come off the wire like the realm count — floored to the
      // engine minimums, because GameSetup THROWS on a too-early year and
      // that ArgumentError would 500 (and permanently block) every start of
      // this match. The war-start year has no engine minimum; ≥1000 mirrors
      // the client's shared validateEventYears rule.
      reformationYear: match.settings.reformationYear < minEventYear
          ? minEventYear
          : match.settings.reformationYear,
      ottomanYear: match.settings.ottomanYear < minEventYear
          ? minEventYear
          : match.settings.ottomanYear,
      warStartYear:
          match.settings.warStartYear < 1000 ? 1000 : match.settings.warStartYear,
      genderEqualSuccession: match.settings.genderEqualSuccession,
      suggestChildNames: match.settings.suggestChildNames,
      aiDifficulty: AiDifficulty.fromName(match.settings.aiDifficulty),
      mapSize: MapSize.fromName(match.settings.mapSize),
      realmCount: realmCountFor(match.settings),
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

  /// Client-facing settings JSON. A stored template key this build no
  /// longer knows degrades the match to an ordinary one everywhere on the
  /// server (see [templateFor]) — withhold it, or the client would present
  /// a room the server no longer treats as one (no `seats`, creator-owned,
  /// deletable) as a matchmaking room.
  Map<String, dynamic> _clientSettings(MatchSettings settings) {
    final json = settings.toJson(includeSeed: false);
    if (templateFor(settings) == null) json.remove('template');
    return json;
  }

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
      // The first seat is the creator — they alone may start the match. A
      // WAITING matchmaking room has no creator at all (it starts on its
      // own); once it runs, its first joiner takes over the host duties
      // that outlive the start, i.e. kicking a permanently idle seat.
      'creator_id': match.players.isEmpty ||
              (match.status == MatchStatus.waiting &&
                  templateFor(match.settings) != null)
          ? null
          : match.players.first.playerId,
      // Matchmaking room: how many seats start it, and when it starts even
      // if it never fills (null = not scheduled yet).
      'seats': templateFor(match.settings)?.seats,
      'auto_start_at': match.autoStartAt?.toIso8601String(),
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
      'settings': _clientSettings(match.settings),
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
      for (var s = 1; s <= state.realmCount; s++)
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
        // by its creator — drives the lobby's delete/leave labels. A
        // waiting matchmaking room has no creator (see [view]): leaving it
        // only frees the seat, so the row must not offer "delete".
        'is_creator': m.players.isNotEmpty &&
            m.players.first.playerId == playerId &&
            !(m.status == MatchStatus.waiting &&
                templateFor(m.settings) != null),
        // Matchmaking room: type, start target and scheduled fallback start.
        // Via [templateFor], not the raw stored key: a template removed in
        // a later build degrades to an ordinary match server-side, and the
        // client must render it as one (delete/leave labels, no seat bar).
        'template': templateFor(m.settings)?.key,
        'seats': templateFor(m.settings)?.seats,
        'auto_start_at': m.autoStartAt?.toIso8601String(),
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
        'war_scheduled_at':
            warPreparing && scheduledMs != null && scheduledMs > 0
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
    // Matchmaking rooms first, in their fixed lobby order (see
    // [matchTemplates]); ordinary player-hosted games after them, newest
    // first. The client renders the two groups as separate sections.
    int rank(MatchRecord m) {
      final template = templateFor(m.settings);
      return template == null ? matchTemplates.length : matchTemplates.indexOf(template);
    }

    matches.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : b.createdAt.compareTo(a.createdAt);
    });
    final result = <Map<String, dynamic>>[];
    for (final m in matches) {
      // A full room can't be joined — advertising it would only hand every
      // tapper a "match is full" error (same cap joinMatch enforces).
      if (m.players.length >= seatCapFor(m.settings)) continue;
      final creatorId = m.players.isEmpty ? null : m.players.first.playerId;
      result.add({
        'id': m.id,
        'status': m.status.name,
        'joined': m.players.length,
        'settings': _clientSettings(m.settings),
        // Matchmaking room: seats that start it, and the scheduled fallback
        // start once enough players are in (null = not scheduled yet).
        'seats': templateFor(m.settings)?.seats,
        'auto_start_at': m.autoStartAt?.toIso8601String(),
        'creator_name': creatorId == null
            ? null
            : (await _store.player(creatorId))?.displayName ??
                m.players.first.founderName,
        'created_at': m.createdAt.toIso8601String(),
      });
    }
    return result;
  }

  /// The country slots already claimed in a waiting match — lets a joiner's
  /// setup screen grey out taken realms (and cap the list at the match's
  /// realm count) before it even tries to join. Purely a UX hint: the join
  /// call still validates authoritatively. Open to anyone, since it reveals
  /// only which of the map's realms are still free, nothing about the game.
  Future<Map<String, dynamic>> openSlots(String matchId) async {
    final match = await _requireMatch(matchId);
    return {
      'status': match.status.name,
      'realm_count': realmCountFor(match.settings),
      'taken_slots': [for (final p in match.players) p.slot],
      'taken_colors': [
        for (final p in match.players)
          if (p.color != null) p.color,
      ],
    };
  }

  // --- Turn submission ---------------------------------------------------

  /// `POST /matches/:id/turn` — either `{action: {...}}` (in-turn action,
  /// war action or pending decision) or `{end_turn: true}`.
  Future<Map<String, dynamic>> submit({
    required String matchId,
    required String playerId,
    String? clientAppVersion,
    String? clientLocale,
    Map<String, dynamic>? actionJson,
    bool endTurn = false,
  }) {
    return _locked(
        _canonicalId(matchId),
        () => _submit(
              matchId: matchId,
              playerId: playerId,
              clientAppVersion: clientAppVersion,
              clientLocale: clientLocale,
              actionJson: actionJson,
              endTurn: endTurn,
            ));
  }

  Future<Map<String, dynamic>> _submit({
    required String matchId,
    required String playerId,
    String? clientAppVersion,
    String? clientLocale,
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
    // Format any engine rejection (ActionException, via coreMessage) in THIS
    // seat's language, not the server's default. messageLocale is a
    // presentation-only global; the apply block below is fully synchronous
    // (no await between here and where the exception is thrown and its
    // message rendered), so a concurrent match's submission cannot race it.
    messageLocale = clientLocale ?? 'de';
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
          action.slot > state.realmCount ||
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
      // One unsweepable match must not abort the whole run: before this
      // guard a single match whose state threw (corrupt document, engine
      // assertion) killed every LATER match's timeout too — the deployment
      // silently stopped advancing.
      bool didSweep;
      try {
        didSweep = await _locked(stale.id, () async {
          // Re-read under the lock: a turn submitted between the bulk scan
          // above and acquiring this lock may already have advanced the
          // match past its old deadline, so it must no longer be swept.
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
      } on Object catch (e, stack) {
        print('[sweep] match ${stale.id} failed: $e\n$stack');
        didSweep = false;
      }
      if (didSweep) swept++;
    }
    swept += await _sweepFrozenMatches();
    await _sendWarStartReminders(now);
    return swept;
  }

  /// Self-heal for matches that carry NO deadline although something is
  /// awaited — they can never be picked up by [sweepExpired] again and are
  /// frozen for good. The one known producer was a war whose every side
  /// ended up on the autopilot: nothing is awaited, so no clock was armed
  /// and the war stood still forever (the match with it, since a running
  /// war blocks every normal turn). The root causes are fixed in
  /// [_commit]/[_sweepMatch]; this pass repairs matches that already went
  /// into that state on an older build. Returns how many it revived.
  Future<int> _sweepFrozenMatches() async {
    var revived = 0;
    for (final candidate in await _store.allMatches()) {
      if (candidate.status != MatchStatus.active ||
          candidate.turnDeadline != null ||
          candidate.stateJson == null) {
        continue;
      }
      // Cheap pre-filter off the raw JSON: only a running war can freeze a
      // match this way. A timer-less match legitimately has no deadline.
      if (candidate.stateJson!['activeWar'] == null) continue;
      try {
        final healed = await _locked(candidate.id, () async {
          final match = await _store.match(candidate.id);
          if (match == null ||
              match.status != MatchStatus.active ||
              match.turnDeadline != null ||
              match.stateJson?['activeWar'] == null) {
            return false;
          }
          final state = _load(match);
          if (_awaitedSlot(state) != null) return false; // not frozen
          print('[sweep] reviving frozen match ${match.id}');
          await _sweepMatch(match);
          return true;
        });
        if (healed) revived++;
      } on Object catch (e, stack) {
        print('[sweep] reviving ${candidate.id} failed: $e\n$stack');
      }
    }
    return revived;
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

  // --- Retention (ARCHITECTURE.md "Retention") ---------------------------

  /// How long a finished match stays visible in its players' lists (the
  /// result screen) before the retention sweep deletes it.
  static const Duration finishedRetention = Duration(days: 30);

  /// How long an untouched waiting lobby is kept. Nothing of value is lost
  /// on deletion — no game state exists yet.
  static const Duration waitingRetention = Duration(days: 7);

  /// How long a completely silent ACTIVE match is kept. Matches WITH a turn
  /// timer never get this old — the timeout sweep advances them at every
  /// deadline, refreshing `updatedAt` — so in practice this only reaps
  /// timer-less matches whose remaining humans all went silent. Players are
  /// never eliminated for idling, so the bar is deliberately high.
  static const Duration activeRetention = Duration(days: 365);

  /// Warning lead before an active match is deleted: every seat gets a
  /// `MATCH_EXPIRING` push, and the deletion waits at least this long after
  /// the warning so a returning player can always save the match.
  static const Duration activeExpiryWarningLead = Duration(days: 14);

  /// Deletes stale matches (run daily, not in the minute sweep):
  /// finished → [finishedRetention] after the last update (players had the
  /// result in their list the whole time); waiting → [waitingRetention];
  /// active → warned via push at [activeRetention] − [activeExpiryWarningLead]
  /// of silence, deleted [activeExpiryWarningLead] after the warning at the
  /// earliest. Any activity clears a pending warning. Returns the number of
  /// matches deleted.
  Future<int> sweepStale() async {
    final now = _clock();
    var deleted = 0;
    for (final candidate in await _store.allMatches()) {
      final didDelete = await _locked(candidate.id, () async {
        // Re-read under the lock, like sweepExpired: the bulk scan races
        // ordinary match operations.
        final match = await _store.match(candidate.id);
        if (match == null) return false;
        final age = now.difference(match.updatedAt);
        switch (match.status) {
          case MatchStatus.waiting:
            if (age < waitingRetention) return false;
            // Matchmaking rooms take this path too, and should: a room
            // nobody joined for a week is stuck below its start threshold
            // and would block its template forever. Deleting it costs
            // nothing (no game state yet) and [ensureTemplateMatches]
            // immediately opens a fresh one in its place.
            await _store.deleteMatch(match.id);
            return true;
          case MatchStatus.finished:
            if (age < finishedRetention) return false;
            await _store.deleteMatch(match.id);
            return true;
          case MatchStatus.active:
            return _sweepStaleActive(match, now, age);
        }
      });
      if (didDelete) deleted++;
    }
    return deleted;
  }

  /// Warn-then-delete for a silent active match — see [sweepStale].
  Future<bool> _sweepStaleActive(
      MatchRecord match, DateTime now, Duration age) async {
    // Activity since the warning cancels the pending expiry: `updatedAt`
    // moves on every submitted action and every timeout-sweep advance,
    // while saving the warning timestamp itself deliberately does not.
    if (match.expiryWarnedAt != null &&
        match.updatedAt.isAfter(match.expiryWarnedAt!)) {
      match.expiryWarnedAt = null;
      await _store.saveMatch(match);
    }
    if (age < activeRetention - activeExpiryWarningLead) return false;
    if (match.expiryWarnedAt == null) {
      match.expiryWarnedAt = now;
      await _store.saveMatch(match);
      for (final seat in match.players) {
        final p = await _store.player(seat.playerId);
        if (p != null) await _push.matchExpiring(p, match);
      }
      return false;
    }
    // Even a match found long past `activeRetention` (e.g. the server was
    // down) gets its full warning lead before deletion.
    if (age < activeRetention ||
        now.difference(match.expiryWarnedAt!) < activeExpiryWarningLead) {
      return false;
    }
    await _store.deleteMatch(match.id);
    return true;
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
      // semantics of the current round stay intact; only in a duel between
      // two HUMAN seats (a human fighting a real AI realm keeps the full
      // turn clock per round, as before).
      //
      // `[FIX 2026-08-08]` The gate used to be `_warIsHumanVsHuman`, which
      // is false as soon as ONE side has been delegated — so the SECOND
      // absent duelist was never handed over and the war crawled on at a
      // full turn timer per round: a 20-round duel between two absent
      // players took 20 DAYS, with the whole match frozen behind it (a
      // running war blocks every normal turn).
      final noShow = idleSlot != null &&
          _warIsHumanDuel(state) &&
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
  ///
  /// Runs the unattended-war guard first: a war whose every side sits on
  /// the autopilot awaits nobody, so no clock can be armed for it — left
  /// standing it freezes the match for good. Fast-forward it here, at the
  /// one place every war-touching path already funnels through.
  GameState _resumeAfterWarIfOver(GameState state, List<GameEvent> emitted) {
    if (warIsUnattended(state)) {
      state = _mutate(state, fastForwardUnattendedWar, emitted);
    }
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

  /// True when both combatants are HUMAN SEATS — unlike [_warIsHumanVsHuman]
  /// this stays true once a side has been delegated to the autopilot. It is
  /// what the no-show rule keys on: a duel between two players is the case
  /// where an absent side must be handed over, no matter whether the other
  /// side is already on autopilot.
  bool _warIsHumanDuel(GameState state) {
    final war = state.activeWar;
    if (war == null) return false;
    return state.dynasty(war.attackerSlot).status == DynastyStatus.human &&
        state.dynasty(war.defenderSlot).status == DynastyStatus.human;
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
    // Clock selection: the war PREPARATION window runs on the FULL turn
    // timer (user design 2026-07-24 — the reaction window before the duel,
    // and the fallback start when no proposals overlapped; armed even when
    // nobody is awaited, so a both-live start fires exactly at the deadline
    // via the sweep). War ROUNDS of a live human-vs-human duel run
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
      // deadline IS the appointment. It may lie later than the full-turn
      // fallback (both sides chose it) and also works in a match without
      // a turn timer. Idempotent across commits — re-arming to the same
      // instant never moves the start.
      match.turnDeadline =
          DateTime.fromMillisecondsSinceEpoch(scheduledMs, isUtc: true);
    } else if (!(prep && wasPrep)) {
      final Duration? timeout;
      if (prep) {
        // The full turn timer: the "auto" duel start when no proposals
        // overlapped is a whole turn, not half of one (user design).
        timeout = turnTimeout;
      } else if (state.activeWar != null && _warIsHumanVsHuman(state)) {
        timeout = Duration(seconds: match.settings.warRoundTimeoutSeconds);
      } else {
        timeout = turnTimeout;
      }
      match.turnDeadline = timeout == null || (awaited == null && !prep)
          ? null
          : _clock().add(timeout);
    }

    // Deadlock guard: a RUNNING war that awaits nobody and carries no
    // deadline can never be advanced again by anything — no seat can act
    // on it and the sweep only ever looks at expired deadlines. The
    // unattended-war fast-forward (`_resumeAfterWarIfOver`) makes that
    // unreachable, but the cost of being wrong is a permanently dead match,
    // so arm a short retry instead of trusting it. Applies even without a
    // turn timer: a war nobody can move is not a match "waiting for a
    // player", it is stuck.
    if (match.status == MatchStatus.active &&
        state.activeWar != null &&
        awaited == null &&
        match.turnDeadline == null) {
      match.turnDeadline = _clock().add(const Duration(minutes: 1));
    }

    // Duel scheduling: the moment BOTH warPlan answers are in, tell both
    // sides when the duel starts — their agreed slot, or the fallback
    // deadline when no proposals overlapped. Fires exactly once (on the
    // SECOND answer: the previous state still had a warPlan decision, this
    // one has none). Not gated on a turn timer — without one the war begins
    // at once, so the waiting side (typically the attacker, who chose first)
    // still learns the other has now chosen (start ⇒ now). The prep-deadline
    // SWEEP also consumes unanswered warPlan decisions (force-delegating the
    // no-show), but there the war has just STARTED — announcing a start time
    // then would be stale; that path only exists with a turn timer while the
    // war has left preparation, hence the (prep || no-timer) gate. Sent
    // before the awaited-null return below: during a both-live wait nobody
    // is awaited.
    if (notify &&
        state.activeWar != null &&
        (prep || match.settings.turnTimeoutHours == null) &&
        previous != null &&
        previous.pendingDecisions.any((d) => d.type == 'warPlan') &&
        !state.pendingDecisions.any((d) => d.type == 'warPlan')) {
      final war = state.activeWar!;
      final agreed = scheduledMs != null && scheduledMs > 0;
      final start = agreed
          ? DateTime.fromMillisecondsSinceEpoch(scheduledMs, isUtc: true)
          : (match.turnDeadline ?? _clock());
      for (final slot in [war.attackerSlot, war.defenderSlot]) {
        final id = _playerForSlot(match, state, slot);
        if (id == null) continue;
        final p = await _store.player(id);
        if (p != null) {
          await _push.warStartFixed(p, match, start,
              agreed: agreed, toAttacker: slot == war.attackerSlot);
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
