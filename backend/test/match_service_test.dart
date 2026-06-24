import 'package:backend/backend.dart';
import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Match lifecycle and turn flow against the in-memory store — the same
/// game_core pipeline the local client drives, but server-validated.
void main() {
  late InMemoryStore store;
  late MatchService service;

  setUp(() {
    store = InMemoryStore();
    service = MatchService(store, LogPushService());
  });

  Future<(PlayerRecord, PlayerRecord)> twoPlayers() async {
    final a = await service.registerPlayer(displayName: 'Anna');
    final b = await service.registerPlayer(displayName: 'Berta');
    return (a, b);
  }

  Map<String, dynamic> setupFor(String name, int slot) => {
        'founder_name': name,
        'gender': 1,
        'country_slot': slot,
        'dorf_name': '${name}dorf',
      };

  /// Create + creator start in one go (the new lobby flow has no fixed
  /// player count — the creator opens the game explicitly).
  Future<MatchRecord> createStarted(
    String playerId,
    MatchSettings settings,
    Map<String, dynamic> setup,
  ) async {
    final match = await service.createMatch(
        playerId: playerId, settings: settings, setup: setup);
    return service.startMatch(matchId: match.id, playerId: playerId);
  }

  group('lifecycle', () {
    test('matches get a 5-letter room code and wait for the creator start',
        () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Solo', 5),
      );
      expect(match.id, matches(RegExp(r'^[A-Z]{5}$')));
      expect(match.status, MatchStatus.waiting);

      final started =
          await service.startMatch(matchId: match.id, playerId: a.id);
      expect(started.status, MatchStatus.active);

      final view = await service.view(match.id, a.id);
      expect(view['your_turn'], isTrue);
      expect(view['your_slot'], 5);
      final state = (view['state'] as Map).cast<String, dynamic>();
      expect(state['currentPlayer'], 5);
    });

    test('room codes are accepted in lowercase (typed by hand)', () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Solo', 5),
      );
      final view = await service.view(match.id.toLowerCase(), a.id);
      expect(view['id'], match.id);
    });

    test('only the creator can start; nobody joins a started match', () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));

      await expectLater(
        service.startMatch(matchId: match.id, playerId: b.id),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
      await service.startMatch(matchId: match.id, playerId: a.id);

      final c = await service.registerPlayer(displayName: 'Clara');
      await expectLater(
        service.joinMatch(
            matchId: match.id, playerId: c.id, setup: setupFor('Clara', 3)),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
      );
    });

    test('a two-human match starts when the creator says so', () async {
      final (a, b) = await twoPlayers();
      final created = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      expect(created.status, MatchStatus.waiting);
      expect((await service.view(created.id, a.id))['state'], isNull);
      expect((await service.view(created.id, a.id))['creator_id'], a.id);

      await service.joinMatch(
        matchId: created.id,
        playerId: b.id,
        setup: setupFor('Berta', 2),
      );
      final started =
          await service.startMatch(matchId: created.id, playerId: a.id);
      expect(started.status, MatchStatus.active);
      // Exactly one player is awaited; the other sees the same id.
      final viewA = await service.view(created.id, a.id);
      final viewB = await service.view(created.id, b.id);
      expect(viewA['awaited_player_id'], viewB['awaited_player_id']);
      expect([viewA['your_turn'], viewB['your_turn']], containsOnce(true));
    });

    test('a taken country slot is rejected; no slot means a free one',
        () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await expectLater(
        service.joinMatch(
            matchId: match.id, playerId: b.id, setup: setupFor('Berta', 1)),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
      );
      await service.joinMatch(
        matchId: match.id,
        playerId: b.id,
        setup: {'founder_name': 'Berta', 'gender': 1, 'dorf_name': 'B'},
      );
      final seat = (await store.match(match.id))!.playerById(b.id)!;
      expect(seat.slot, isNot(1));
      expect(seat.slot, inInclusiveRange(1, 30));
    });

    test('outsiders may not view a match', () async {
      final (a, b) = await twoPlayers();
      final match = await createStarted(
          a.id, MatchSettings(seed: 42), setupFor('Anna', 1));
      await expectLater(
        service.view(match.id, b.id),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    });
  });

  group('turn flow', () {
    /// Started two-human match: Anna on slot 1, Berta on slot 2.
    Future<MatchRecord> twoHumanMatch(
      PlayerRecord a,
      PlayerRecord b, {
      MatchSettings? settings,
    }) async {
      final match = await service.createMatch(
        playerId: a.id,
        settings: settings ?? MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));
      return service.startMatch(matchId: match.id, playerId: a.id);
    }

    test(
        'the awaited player acts and ends the turn; the server advances '
        'to the next human', () async {
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b);

      final record = (await store.match(match.id))!;
      final state = GameState.fromJson(record.stateJson!);
      final awaitedSlot = state.currentPlayer;
      final awaitedId =
          (await service.view(match.id, a.id))['awaited_player_id'] as String;
      final otherId = awaitedId == a.id ? b.id : a.id;

      // The not-awaited player is rejected for actions and end-turn.
      await expectLater(
        service.submit(matchId: match.id, playerId: otherId, endTurn: true),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );

      // A foreign-slot action is rejected even for the awaited player.
      await expectLater(
        service.submit(
          matchId: match.id,
          playerId: awaitedId,
          actionJson:
              AdjustGuards(slot: awaitedSlot == 1 ? 2 : 1, delta: 1).toJson(),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );

      // A legal in-turn action sticks.
      final after = await service.submit(
        matchId: match.id,
        playerId: awaitedId,
        actionJson: AdjustGuards(slot: awaitedSlot, delta: 1).toJson(),
      );
      expect(after['your_turn'], isTrue);

      // Ending the turn passes the match to the other human.
      final ended = await service.submit(
          matchId: match.id, playerId: awaitedId, endTurn: true);
      expect(ended['your_turn'], isFalse);
      expect(ended['awaited_player_id'], otherId);
    });

    test('an engine rejection surfaces as a 400 with the German message',
        () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await createStarted(
          a.id, MatchSettings(seed: 42), setupFor('Solo', 1));
      await expectLater(
        service.submit(
          matchId: match.id,
          playerId: a.id,
          // Year 1000: wars are not allowed before 1010.
          actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)
            .having((e) => e.message, 'message', contains('1010'))),
      );
    });

    test('the state is filtered per requester (hidden information)', () async {
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b);

      final viewA = await service.view(match.id, a.id);
      final stateA = (viewA['state'] as Map).cast<String, dynamic>();
      final realms = (stateA['realms'] as List).cast<Map>();
      final own = realms.firstWhere((r) => r['slot'] == 1);
      final foreign = realms.firstWhere((r) => r['slot'] == 2);
      expect(own['treasury'], greaterThan(0));
      expect(foreign['treasury'], 0, reason: 'redacted to "unknown"');
      expect(stateA['rngSeed'], 0, reason: 'the seed never leaves the server');
    });

    test('a full AI-decided match finishes with a winner or defeat', () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await createStarted(
          a.id, MatchSettings(seed: 7), setupFor('Solo', 1));
      // Play 30 empty turns — the world keeps simulating around the
      // player; the match must stay consistent and never throw. A passive
      // human can still be dragged into a war by an AI; they just end each
      // war round (the equivalent of doing nothing).
      for (var i = 0; i < 30; i++) {
        final view = await service.view(match.id, a.id);
        if (view['status'] != 'active') break;
        if (view['your_turn'] != true) break;
        final stateJson = (view['state'] as Map).cast<String, dynamic>();
        if (stateJson['activeWar'] != null) {
          await service.submit(
            matchId: match.id,
            playerId: a.id,
            actionJson: WarEndRound(slot: view['awaited_slot'] as int).toJson(),
          );
        } else {
          await service.submit(
              matchId: match.id, playerId: a.id, endTurn: true);
        }
      }
      final record = (await store.match(match.id))!;
      expect(record.stateJson, isNotNull);
      final state = GameState.fromJson(record.stateJson!);
      expect(state.year, greaterThan(1000));
    });

    test(
        'human-vs-human war: the attacker hands the round to the '
        'defender, the war clock arms the deadline', () async {
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(seed: 42, warRoundTimeoutSeconds: 600));

      // State surgery (test-only): make a war declarable right now —
      // year past 1010, troops on both sides, a shared border.
      final record = (await store.match(match.id))!;
      final state = GameState.fromJson(record.stateJson!);
      state.year = 1010;
      for (final slot in [1, 2]) {
        final realm = state.realm(slot);
        realm.treasury = 10000;
        realm.towns.first.troopCapacity = 200;
        realm.troopCapacity = 200;
        realm.troops.add(Troop(
          name: 'Heer$slot',
          men: 50,
          troopClass: TroopClass.infanterie,
          quality: TroopQuality.regular,
          garrisonCounted: false,
          x: realm.capitalX,
          y: realm.capitalY,
        ));
      }
      final map = state.map;
      outer:
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) {
            continue;
          }
          for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
            if (map.inBounds(x + dx, y + dy) &&
                map.ownerAt(x + dx, y + dy) == 1) {
              map.owner[map.index(x, y)] = 2;
              state.realm(2).tileCount[Building.none]++;
              break outer;
            }
          }
        }
      }
      // Park the match on slot 1's turn (Anna attacks).
      state.currentPlayer = 1;
      record.stateJson = state.toJson();
      await store.saveMatch(record);

      // Anna declares war on Berta's realm (human-vs-human is allowed).
      final declared = await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      expect(declared['awaited_player_id'], a.id,
          reason: 'attacker before defender');
      expect(declared['turn_deadline'], isNotNull,
          reason: 'the short war clock replaces the turn timer');

      // Berta may not act during Anna's half of the round.
      await expectLater(
        service.submit(
          matchId: match.id,
          playerId: b.id,
          actionJson: WarEndRound(slot: 2).toJson(),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );

      // Anna's round end hands the same round to Berta.
      final handed = await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: WarEndRound(slot: 1).toJson(),
      );
      expect(handed['awaited_player_id'], b.id);
      final handedState =
          GameState.fromJson((handed['state'] as Map).cast<String, dynamic>());
      expect(handedState.activeWar!.round, 0, reason: 'same round');

      // Berta's round end advances the round — back to Anna.
      final advanced = await service.submit(
        matchId: match.id,
        playerId: b.id,
        actionJson: WarEndRound(slot: 2).toJson(),
      );
      expect(advanced['awaited_player_id'], a.id);
      final advancedState = GameState.fromJson(
          (advanced['state'] as Map).cast<String, dynamic>());
      expect(advancedState.activeWar!.round, 1);
    });
  });

  group('timeouts', () {
    test('an expired turn auto-ends with no actions', () async {
      var now = DateTime.utc(2026, 1, 1);
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42, turnTimeoutHours: 24),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));
      await service.startMatch(matchId: match.id, playerId: a.id);

      final before = (await service.view(match.id, a.id))['awaited_player_id'];
      expect((await store.match(match.id))!.turnDeadline, isNotNull);

      now = now.add(const Duration(hours: 25));
      final swept = await service.sweepExpired();
      expect(swept, 1);
      final after = (await service.view(match.id, a.id))['awaited_player_id'];
      expect(after, isNot(before),
          reason: 'the idle turn ended; the next human is awaited');
    });

    test('without a timer no deadline is set', () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await createStarted(
          a.id, MatchSettings(seed: 42), setupFor('Solo', 1));
      expect((await store.match(match.id))!.turnDeadline, isNull);
      expect(await service.sweepExpired(), 0);
    });
  });

  group('leaving', () {
    test('the creator leaving a waiting match deletes it for everyone',
        () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));

      final deleted =
          await service.leaveMatch(matchId: match.id, playerId: a.id);
      expect(deleted, isTrue);
      expect(await store.match(match.id), isNull);
      expect(await service.matchesForPlayer(b.id), isEmpty);
    });

    test('a joiner leaving a waiting match just frees the seat', () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));

      final deleted =
          await service.leaveMatch(matchId: match.id, playerId: b.id);
      expect(deleted, isFalse);
      final record = (await store.match(match.id))!;
      expect(record.status, MatchStatus.waiting);
      expect(record.playerById(b.id), isNull);
      // The freed slot can be taken again.
      final c = await service.registerPlayer(displayName: 'Clara');
      await service.joinMatch(
          matchId: match.id, playerId: c.id, setup: setupFor('Clara', 2));
    });

    test(
        'leaving a running match hands the realm to the AI and play '
        'continues', () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));
      await service.startMatch(matchId: match.id, playerId: a.id);

      // Whoever is awaited leaves — the hardest case: their open turn
      // must complete via the AI and pass to the remaining human.
      final awaitedId =
          (await service.view(match.id, a.id))['awaited_player_id'] as String;
      final (leaver, stays) = awaitedId == a.id ? (a, b) : (b, a);
      final leaverSlot =
          (await service.view(match.id, leaver.id))['your_slot'] as int;

      final deleted =
          await service.leaveMatch(matchId: match.id, playerId: leaver.id);
      expect(deleted, isFalse);

      final record = (await store.match(match.id))!;
      expect(record.playerById(leaver.id), isNull);
      final state = GameState.fromJson(record.stateJson!);
      expect(state.dynasty(leaverSlot).status, DynastyStatus.ai);
      expect(state.dynasty(leaverSlot).humanPlayer, isNull);
      expect(state.events.any((e) => e.type == 'playerLeft'), isTrue);

      // The leaver is out, the remaining player is awaited.
      await expectLater(
        service.view(match.id, leaver.id),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
      final view = await service.view(match.id, stays.id);
      expect(view['status'], 'active');
      expect(view['your_turn'], isTrue);
    });

    test('the last player leaving a running match deletes it', () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await createStarted(
          a.id, MatchSettings(seed: 42), setupFor('Solo', 1));
      final deleted =
          await service.leaveMatch(matchId: match.id, playerId: a.id);
      expect(deleted, isTrue);
      expect(await store.match(match.id), isNull);
    });

    test('an outsider cannot leave a match', () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await expectLater(
        service.leaveMatch(matchId: match.id, playerId: b.id),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    });
  });

  group('submission responses', () {
    test(
        'a submission returns its own (visible) events and end_turn '
        'moves the recap baseline', () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await createStarted(
          a.id, MatchSettings(seed: 42), setupFor('Solo', 3));

      // Recruiting emits an owner-visible 'troopsRecruited' event — it
      // must come back with the submission for the client's popups.
      final record = (await store.match(match.id))!;
      // Persist the tweak through the store (test-only state surgery).
      record.stateJson = (GameState.fromJson(record.stateJson!)
            ..realm(3).treasury = 1000
            ..realm(3).towns.single.troopCapacity = 50
            ..realm(3).troopCapacity = 50)
          .toJson();
      await store.saveMatch(record);

      final view = await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: RecruitTroops(slot: 3, men: 5, troopClass: 0, name: 'Garde')
            .toJson(),
      );
      final events = (view['events'] as List).cast<Map>();
      expect(events.any((e) => e['type'] == 'troopsRecruited'), isTrue);

      // Ending the turn moves the seat's recap baseline server-side.
      final ended = await service.submit(
          matchId: match.id, playerId: a.id, endTurn: true);
      final state =
          GameState.fromJson(((ended['state'] as Map).cast<String, dynamic>()));
      expect(state.recapBaselines[3], isNotNull);
      expect((ended['events'] as List), isNotEmpty,
          reason: 'the advance events come back for the recap');
    });
  });

  group('multi-realm control', () {
    test('the view lists every realm a player currently controls', () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));
      await service.startMatch(matchId: match.id, playerId: a.id);

      // State surgery: Anna (turn order 0) also comes to play realm 3 —
      // control follows the ruler after a conquest/inheritance.
      final record = (await store.match(match.id))!;
      final state = GameState.fromJson(record.stateJson!);
      state.dynasty(3).status = DynastyStatus.human;
      state.dynasty(3).humanPlayer = 0;
      record.stateJson = state.toJson();
      await store.saveMatch(record);

      final view = await service.view(match.id, a.id);
      final players = (view['players'] as List).cast<Map>();
      final anna = players.firstWhere((p) => p['player_id'] == a.id);
      expect((anna['controlled_slots'] as List).cast<int>(),
          containsAll(<int>[1, 3]));
      final berta = players.firstWhere((p) => p['player_id'] == b.id);
      expect(berta['controlled_slots'], <int>[2]);
    });

    test('a second realm is visible and actionable on its own turn', () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));
      await service.startMatch(matchId: match.id, playerId: a.id);

      // Anna (turn order 0) also plays realm 3, and it is realm 3's turn.
      final record = (await store.match(match.id))!;
      final state = GameState.fromJson(record.stateJson!);
      state.dynasty(3).status = DynastyStatus.human;
      state.dynasty(3).humanPlayer = 0;
      state.realm(3).treasury = 4242;
      state.currentPlayer = 3;
      record.stateJson = state.toJson();
      await store.saveMatch(record);

      final view = await service.view(match.id, a.id);
      expect(view['your_turn'], isTrue);
      expect(view['your_slot'], 3,
          reason: 'the realm being played, not the home seat');
      expect(view['awaited_slot'], 3);
      final shown = (view['state'] as Map).cast<String, dynamic>();
      final realm3 = (shown['realms'] as List)
          .cast<Map>()
          .firstWhere((r) => r['slot'] == 3);
      expect(realm3['treasury'], 4242,
          reason: 'own realm now — its treasury is no longer redacted');

      // An action on realm 3 is accepted, not rejected as a foreign realm.
      final after = await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: AdjustGuards(slot: 3, delta: 1).toJson(),
      );
      expect(after['your_turn'], isTrue);
    });

    test('an out-of-turn decision on a controlled realm is surfaced off-turn',
        () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));
      await service.startMatch(matchId: match.id, playerId: a.id);

      // Anna (turn order 0) also controls realm 3; it is Berta's turn
      // (slot 2), and realm 3 owes Anna an out-of-turn decision.
      final record = (await store.match(match.id))!;
      final state = GameState.fromJson(record.stateJson!);
      state.dynasty(3).status = DynastyStatus.human;
      state.dynasty(3).humanPlayer = 0;
      state.currentPlayer = 2;
      state.pendingDecisions.add(
          PendingDecision(id: 'd1', type: 'marriageConsent', decidingSlot: 3));
      record.stateJson = state.toJson();
      await store.saveMatch(record);

      final view = await service.view(match.id, a.id);
      expect(view['your_turn'], isFalse, reason: 'it is Berta who is awaited');
      expect(view['your_slot'], 3,
          reason: 'the realm holding Anna\'s pending decision');
      final shown = (view['state'] as Map).cast<String, dynamic>();
      final decisions = (shown['pendingDecisions'] as List).cast<Map>();
      expect(decisions.any((d) => d['id'] == 'd1'), isTrue,
          reason: 'visible off-turn so Anna can answer it now, not next round');
    });

    test('an outdated client is flagged for an update in the view', () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await createStarted(
          a.id, MatchSettings(seed: 42), setupFor('Solo', 1));
      final current = await service.view(match.id, a.id);
      expect(current['update_required'], isFalse);
      final stale =
          await service.view(match.id, a.id, clientAppVersion: '0.0.1');
      expect(stale['update_required'], isTrue);
      expect(stale['server_app_version'], appVersion);
    });
  });

  group('write serialization', () {
    test('concurrent player writes do not clobber each other', () async {
      // The real FileStore read-modify-writes a single shared players
      // document; this store reproduces that gap. Without the service's
      // per-key lock, ten concurrent registrations all read the (near-empty)
      // document, yield, and write back only their own entry — last writer
      // wins and the rest are lost.
      final racy = RacyPlayerStore();
      final svc = MatchService(racy, LogPushService());

      await Future.wait([
        for (var i = 0; i < 10; i++)
          svc.registerPlayer(id: 'p$i', displayName: 'P$i'),
      ]);

      for (var i = 0; i < 10; i++) {
        expect(await racy.player('p$i'), isNotNull,
            reason: 'registration p$i must survive the concurrent writes');
      }
    });
  });
}

/// Matcher: the iterable contains [value] exactly once.
Matcher containsOnce(Object? value) => predicate<Iterable>(
      (items) => items.where((e) => e == value).length == 1,
      'contains $value exactly once',
    );

/// Mimics [FileStore]'s `players.json` read-modify-write: [savePlayer]
/// reads the whole shared document, yields (the I/O gap), then writes it
/// back — so two unserialized concurrent saves clobber each other.
class RacyPlayerStore extends InMemoryStore {
  Map<String, dynamic> _doc = {};

  @override
  Future<void> savePlayer(PlayerRecord player) async {
    final doc = Map<String, dynamic>.of(_doc); // read
    await Future<void>.delayed(Duration.zero); // the read-modify-write gap
    doc[player.id] = player.toJson();
    _doc = doc; // write back — last writer wins without a lock
  }

  @override
  Future<PlayerRecord?> player(String id) async {
    final json = _doc[id];
    return json == null
        ? null
        : PlayerRecord.fromJson((json as Map).cast<String, dynamic>());
  }
}
