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

    test('openSlots reports taken countries and the realm count', () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42, mapSize: 'klein'),
        setup: setupFor('Anna', 3),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 5));
      // Anyone may ask — no membership required (it only lists free realms).
      final slots = await service.openSlots(match.id);
      expect(slots['status'], 'waiting');
      expect(slots['realm_count'], MapSize.klein.defaultRealmCount);
      expect((slots['taken_slots'] as List).toSet(), {3, 5});
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

    // Test-only state surgery: make a war declarable right now between slots
    // 1 and 2 — year past 1010, troops on both sides, a shared border, slot 1
    // to move. Leaves dynasty statuses untouched (so it works for a solo
    // match's AI slot 2 and a two-human match alike).
    Future<void> armWar(MatchRecord match) async {
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
      state.currentPlayer = 1;
      record.stateJson = state.toJson();
      await store.saveMatch(record);
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

    test(
        'between-turns public events reach the next recap — the filtered '
        'view keeps absolute event positions', () async {
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b);

      // Simulate an older game: the master log already holds plenty of
      // foreign upkeep Anna may not see. Removing (instead of redacting)
      // these used to shift every later filtered index past her baseline
      // and silently empty the online recap.
      var record = (await store.match(match.id))!;
      var state = GameState.fromJson(record.stateJson!);
      for (var i = 0; i < 200; i++) {
        state.events.add(GameEvent(
            year: state.year,
            slot: 2 + i % 5,
            type: 'turnUpkeep',
            visibility: EventVisibility.owner));
      }
      record.stateJson = state.toJson();
      await store.saveMatch(record);

      // Anna ends her turn — the server moves her recap baseline.
      await service.submit(matchId: match.id, playerId: a.id, endTurn: true);

      // Between her turns the Kaiserwahl concludes (world phase surgery).
      record = (await store.match(match.id))!;
      state = GameState.fromJson(record.stateJson!);
      state.events.add(GameEvent(
          year: state.year,
          slot: 3,
          type: 'crowned',
          visibility: EventVisibility.public,
          payload: {'office': 'kaiser', 'name': 'Otto'}));
      record.stateJson = state.toJson();
      await store.saveMatch(record);

      // Anna's next view: the client's recap computation must surface the
      // coronation (this is the reported bug — "keine Info nach der
      // Kaiserwahl" in an online game).
      final view = await service.view(match.id, a.id);
      final filtered =
          GameState.fromJson((view['state'] as Map).cast<String, dynamic>());
      final baseline = filtered.recapBaselines[1] ?? 0;
      final from = (baseline - filtered.prunedEventCount)
          .clamp(0, filtered.events.length);
      final recap = [
        for (var i = from; i < filtered.events.length; i++)
          if (filtered.events[i].visibleTo(1)) filtered.events[i],
      ];
      expect(recap.map((e) => e.type), contains('crowned'));
      expect(recap.map((e) => e.type), isNot(contains('redacted')));
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
          reason: 'the attacker owes the first warPlan answer');
      // 0.1.13 preparation window: no turn timer configured ⇒ no deadline;
      // the war waits for both warPlan answers.
      expect(declared['turn_deadline'], isNull,
          reason: 'the war clock waits for the preparation to finish');

      // Both sides choose live control. Without a turn timer the both-live
      // duel starts as soon as the second answer lands — the war clock arms.
      var prep = GameState.fromJson((await store.match(match.id))!.stateJson!);
      final planA = prep.pendingDecisions
          .singleWhere((d) => d.type == 'warPlan' && d.decidingSlot == 1);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: ResolveDecision(
            slot: 1, decisionId: planA.id, choice: {'auto': false}).toJson(),
      );
      prep = GameState.fromJson((await store.match(match.id))!.stateJson!);
      final planB = prep.pendingDecisions
          .singleWhere((d) => d.type == 'warPlan' && d.decidingSlot == 2);
      final resolved = await service.submit(
        matchId: match.id,
        playerId: b.id,
        actionJson: ResolveDecision(
            slot: 2, decisionId: planB.id, choice: {'auto': false}).toJson(),
      );
      expect(resolved['turn_deadline'], isNotNull,
          reason: 'the short war clock replaces the turn timer');
      expect(
          GameState.fromJson((resolved['state'] as Map).cast<String, dynamic>())
              .activeWar!
              .phase,
          WarPhase.rounds);

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

      // Berta's round end advances the round — the initiative ALTERNATES
      // (engine rule 2026-07-19): the defender opens the odd rounds, so
      // round 1 awaits Berta again.
      final advanced = await service.submit(
        matchId: match.id,
        playerId: b.id,
        actionJson: WarEndRound(slot: 2).toJson(),
      );
      expect(advanced['awaited_player_id'], b.id,
          reason: 'the defender has the initiative in odd rounds');
      final advancedState = GameState.fromJson(
          (advanced['state'] as Map).cast<String, dynamic>());
      expect(advancedState.activeWar!.round, 1);

      // Round 1 mirrors round 0 with the sides swapped: Berta hands over,
      // Anna's round end advances to round 2 (Anna opens again).
      final handedBack = await service.submit(
        matchId: match.id,
        playerId: b.id,
        actionJson: WarEndRound(slot: 2).toJson(),
      );
      expect(handedBack['awaited_player_id'], a.id);
      final round2 = await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: WarEndRound(slot: 1).toJson(),
      );
      expect(round2['awaited_player_id'], a.id,
          reason: 'the attacker has the initiative in even rounds');
      expect(
          GameState.fromJson((round2['state'] as Map).cast<String, dynamic>())
              .activeWar!
              .round,
          2);
    });

    test('human-vs-AI war runs on the full turn clock, not the war clock',
        () async {
      var now = DateTime.utc(2026, 1, 1);
      service = MatchService(store, LogPushService(), clock: () => now);
      final a = await service.registerPlayer(displayName: 'Anna');
      // Solo match: slot 2 is AI — a human-vs-AI war.
      final match = await createStarted(
        a.id,
        MatchSettings(
            seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600),
        setupFor('Anna', 1),
      );
      await armWar(match);

      final declared = await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      expect(declared['awaited_player_id'], a.id);
      final post =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(post.activeWar, isNotNull);
      expect(
          post.dynasty(post.activeWar!.defenderSlot).status, DynastyStatus.ai);
      expect((await store.match(match.id))!.turnDeadline,
          now.add(const Duration(hours: 24)),
          reason: 'a human fighting an AI gets the normal turn time, '
              'not the 10-minute war clock');
    });

    test('human-vs-human war keeps the short war clock', () async {
      var now = DateTime.utc(2026, 1, 1);
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);

      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      // Preparation window: the FULL turn timer (user design 2026-07-24).
      expect((await store.match(match.id))!.turnDeadline,
          now.add(const Duration(hours: 24)),
          reason: 'the preparation window is the full turn timer');

      // Both choose live control — with a timer, the both-live duel WAITS
      // for the deadline (fair start), even though everyone has answered.
      for (final (playerId, slot) in [(a.id, 1), (b.id, 2)]) {
        final st =
            GameState.fromJson((await store.match(match.id))!.stateJson!);
        final plan = st.pendingDecisions
            .singleWhere((d) => d.type == 'warPlan' && d.decidingSlot == slot);
        await service.submit(
          matchId: match.id,
          playerId: playerId,
          actionJson: ResolveDecision(
              slot: slot,
              decisionId: plan.id,
              choice: {'auto': false}).toJson(),
        );
      }
      final waiting =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(waiting.activeWar!.phase, WarPhase.preparation,
          reason: 'both live → wait for the fair deadline start');
      expect((await store.match(match.id))!.turnDeadline,
          now.add(const Duration(hours: 24)));

      // The deadline sweep starts the duel; the short war clock takes over.
      now = now.add(const Duration(hours: 24, minutes: 1));
      expect(await service.sweepExpired(), 1);
      final started =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(started.activeWar!.phase, WarPhase.rounds);
      expect(started.activeWar!.autoSlots, isEmpty);
      expect((await store.match(match.id))!.turnDeadline,
          now.add(const Duration(seconds: 600)),
          reason: 'a live human-vs-human duel runs on the short war clock');
    });

    // Answers slot X's open warPlan decision for [playerId].
    Future<Map<String, dynamic>> answerPlan(MatchRecord match, String playerId,
        int slot, Map<String, dynamic> choice) async {
      final st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      final plan = st.pendingDecisions
          .singleWhere((d) => d.type == 'warPlan' && d.decidingSlot == slot);
      return service.submit(
        matchId: match.id,
        playerId: playerId,
        actionJson:
            ResolveDecision(slot: slot, decisionId: plan.id, choice: choice)
                .toJson(),
      );
    }

    test(
        'war preparation: per-unit troop stances are accepted OUT OF '
        'TURN — and only there', () async {
      var now = DateTime.utc(2026, 1, 1);
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);

      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );

      // The DEFENDER is never the awaited player during the preparation —
      // their per-unit stance orders must land anyway (they line up their
      // troops from the map view, user rule 2026-07-13).
      await service.submit(
        matchId: match.id,
        playerId: b.id,
        actionJson:
            SetTroopStance(slot: 2, unitIndex: 0, stance: TroopStance.attack)
                .toJson(),
      );
      final prep =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(prep.activeWar!.phase, WarPhase.preparation);
      expect(prep.realm(2).troops.first.stance, TroopStance.attack);

      // A foreign realm's troops stay untouchable.
      await expectLater(
        service.submit(
          matchId: match.id,
          playerId: b.id,
          actionJson:
              SetTroopStance(slot: 1, unitIndex: 0, stance: TroopStance.attack)
                  .toJson(),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );

      // Once the war leaves the preparation the allowance ends: both
      // answer live, the deadline sweep starts the rounds — the defender
      // (not the acting side) is rejected like any off-turn action.
      await answerPlan(match, a.id, 1, {'auto': false});
      await answerPlan(match, b.id, 2, {'auto': false});
      now = now.add(const Duration(hours: 24, minutes: 1));
      expect(await service.sweepExpired(), 1);
      final started =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(started.activeWar!.phase, WarPhase.rounds);
      expect(warActingSlot(started), 1, reason: 'the attacker acts first');
      await expectLater(
        service.submit(
          matchId: match.id,
          playerId: b.id,
          actionJson: SetTroopStance(
                  slot: 2, unitIndex: 0, stance: TroopStance.holdPosition)
              .toJson(),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    });

    test('an agreed warPlan slot arms the deadline at the appointment',
        () async {
      final start = DateTime.utc(2026, 1, 1);
      var now = start;
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      expect((await store.match(match.id))!.turnDeadline,
          start.add(const Duration(hours: 24)),
          reason: 'fallback until a common slot is agreed');

      // Anna offers 30:00/32:00, Berta 30:00/34:00 — agreement at 30:00,
      // deliberately LATER than the 24 h fallback: both sides chose it.
      final slot30 =
          start.add(const Duration(hours: 30)).millisecondsSinceEpoch;
      await answerPlan(match, a.id, 1, {
        'auto': false,
        'slots': [
          slot30,
          start.add(const Duration(hours: 32)).millisecondsSinceEpoch,
        ],
      });
      await answerPlan(match, b.id, 2, {
        'auto': false,
        'slots': [
          slot30,
          start.add(const Duration(hours: 34)).millisecondsSinceEpoch,
        ],
      });

      final waiting =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(waiting.activeWar!.phase, WarPhase.preparation);
      expect(waiting.activeWar!.scheduledStartMs, slot30);
      expect((await store.match(match.id))!.turnDeadline,
          start.add(const Duration(hours: 30)),
          reason: 'the deadline IS the appointment');

      // The lobby list carries the war-start info: nobody is awaited while
      // the duel waits, so the client needs these fields for its line.
      final listed = (await service.matchesForPlayer(a.id))
          .singleWhere((m) => m['id'] == match.id);
      expect(listed['war_preparing'], isTrue);
      expect(listed['war_scheduled_at'],
          start.add(const Duration(hours: 30)).toIso8601String());
      expect(listed['awaited_name'], isNull);

      // The old fallback instant passes without starting anything.
      now = start.add(const Duration(hours: 24, minutes: 5));
      expect(await service.sweepExpired(), 0);

      // At the appointment the duel starts, both sides live.
      now = start.add(const Duration(hours: 30, minutes: 1));
      expect(await service.sweepExpired(), 1);
      final started =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(started.activeWar!.phase, WarPhase.rounds);
      expect(started.activeWar!.autoSlots, isEmpty);
      expect((await store.match(match.id))!.turnDeadline,
          now.add(const Duration(seconds: 600)));
    });

    test('"sofort" (the current hour) starts the duel on the next sweep',
        () async {
      // The clock sits exactly on a full hour, so the client's "sofort"
      // slot is this very instant.
      final start = DateTime.utc(2026, 1, 1);
      var now = start;
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      final sofort = start.millisecondsSinceEpoch;
      await answerPlan(match, a.id, 1, {
        'auto': false,
        'slots': [sofort],
      });
      final resolved = await answerPlan(match, b.id, 2, {
        'auto': false,
        'slots': [sofort],
      });
      final state = GameState.fromJson(
          (resolved['state'] as Map).cast<String, dynamic>());
      // Both agreed on "sofort" (a current-hour instant): the duel WAITS for
      // the server deadline, which is that already-current instant — the
      // sweep fires it at once (prompt, but not in the submit request).
      expect(state.activeWar!.phase, WarPhase.preparation,
          reason: 'both live → the sweep starts the past-deadline duel');
      expect(state.activeWar!.scheduledStartMs, sofort);
      expect((await store.match(match.id))!.turnDeadline, start);

      now = start.add(const Duration(minutes: 1));
      expect(await service.sweepExpired(), 1);
      final started =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(started.activeWar!.phase, WarPhase.rounds);
      expect(started.activeWar!.autoSlots, isEmpty);
      expect((await store.match(match.id))!.turnDeadline,
          now.add(const Duration(seconds: 600)));
    });

    test('no common slot keeps the full-turn fallback', () async {
      final start = DateTime.utc(2026, 1, 1);
      var now = start;
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      await answerPlan(match, a.id, 1, {
        'auto': false,
        'slots': [start.add(const Duration(hours: 16)).millisecondsSinceEpoch],
      });
      await answerPlan(match, b.id, 2, {
        'auto': false,
        'slots': [start.add(const Duration(hours: 17)).millisecondsSinceEpoch],
      });
      final waiting =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(waiting.activeWar!.phase, WarPhase.preparation);
      expect(waiting.activeWar!.scheduledStartMs, isNull);
      expect((await store.match(match.id))!.turnDeadline,
          start.add(const Duration(hours: 24)),
          reason: 'no overlap → the full-turn fallback stands');
    });

    // `[DESIGNED 2026-08-09, user request]` The war-start plan stays
    // revisable for the whole preparation window (`WarPrepPlan`): both
    // combatants may re-pick their times until they overlap, and switch
    // between commanding live and the autopilot.
    test('revised times fix the appointment and re-arm the deadline',
        () async {
      final start = DateTime.utc(2026, 1, 1);
      var now = start;
      final pushes = _RecordingPushService();
      service = MatchService(store, pushes, clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      final at16 = start.add(const Duration(hours: 16)).millisecondsSinceEpoch;
      final at17 = start.add(const Duration(hours: 17)).millisecondsSinceEpoch;
      await answerPlan(match, a.id, 1, {
        'auto': false,
        'slots': [at16],
      });
      await answerPlan(match, b.id, 2, {
        'auto': false,
        'slots': [at17],
      });
      expect((await store.match(match.id))!.turnDeadline,
          start.add(const Duration(hours: 24)),
          reason: 'no overlap yet — the full-turn fallback stands');

      // Berta adds Anna's hour — out of turn, hours into the window.
      now = start.add(const Duration(hours: 2));
      await service.submit(
        matchId: match.id,
        playerId: b.id,
        actionJson:
            WarPrepPlan(slot: 2, auto: false, slots: [at17, at16]).toJson(),
      );
      var st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(st.activeWar!.phase, WarPhase.preparation);
      expect(st.activeWar!.scheduledStartMs, at16);
      expect((await store.match(match.id))!.turnDeadline,
          start.add(const Duration(hours: 16)),
          reason: 'the newly agreed instant becomes the deadline');
      expect(pushes.kinds.where((k) => k == 'warStartFixed').length, 4,
          reason: 'both sides are told about the fixed appointment again');

      // Withdrawing it falls back to the window's ORIGINAL deadline — not
      // to a fresh full turn timer (which a pair could push forever).
      await service.submit(
        matchId: match.id,
        playerId: b.id,
        actionJson: WarPrepPlan(slot: 2, auto: false, slots: [at17]).toJson(),
      );
      st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(st.activeWar!.scheduledStartMs, isNull);
      expect((await store.match(match.id))!.turnDeadline,
          start.add(const Duration(hours: 24)));
    });

    test('a delegated duelist may take command again before the war starts',
        () async {
      final start = DateTime.utc(2026, 1, 1);
      var now = start;
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      // Berta delegates in a hurry — with one live side the early-start
      // rule would normally begin the rounds at once...
      await answerPlan(match, b.id, 2, {'auto': true});
      // ...but Anna has not answered, so the window still runs.
      var st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(st.activeWar!.phase, WarPhase.preparation);
      expect(st.activeWar!.autoSlots, {2});

      // Second thoughts, out of turn: Berta takes the field after all.
      now = start.add(const Duration(hours: 1));
      await service.submit(
        matchId: match.id,
        playerId: b.id,
        actionJson: WarPrepPlan(slot: 2, auto: false, slots: const []).toJson(),
      );
      st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(st.activeWar!.autoSlots, isEmpty);

      // Anna answers live: a both-live duel now waits for the deadline
      // instead of having been fast-forwarded past Berta.
      await answerPlan(match, a.id, 1, {'auto': false});
      st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(st.activeWar!.phase, WarPhase.preparation);
      now = start.add(const Duration(hours: 24, minutes: 1));
      expect(await service.sweepExpired(), 1);
      st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(st.activeWar!.phase, WarPhase.rounds);
      expect(st.activeWar!.autoSlots, isEmpty);
    });

    test('a plan revision is rejected once the duel runs', () async {
      var now = DateTime.utc(2026, 1, 1);
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      await answerPlan(match, a.id, 1, {'auto': false});
      await answerPlan(match, b.id, 2, {'auto': false});
      now = now.add(const Duration(hours: 24, minutes: 1));
      expect(await service.sweepExpired(), 1);
      // The rounds run: the defender is not the acting side, and the plan
      // is no longer up for revision either way.
      await expectLater(
        service.submit(
          matchId: match.id,
          playerId: b.id,
          actionJson: WarPrepPlan(slot: 2, auto: true).toJson(),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    });

    // Regressions (2026-08-13) around revising an agreed appointment.
    test('withdrawing an appointment past the fallback still gives notice',
        () async {
      final start = DateTime.utc(2026, 1, 1);
      var now = start;
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      // Both agree on an instant BEYOND the 24 h fallback — legal, they
      // chose it together.
      final at40 = start.add(const Duration(hours: 40)).millisecondsSinceEpoch;
      await answerPlan(match, a.id, 1, {
        'auto': false,
        'slots': [at40],
      });
      await answerPlan(match, b.id, 2, {
        'auto': false,
        'slots': [at40],
      });
      expect((await store.match(match.id))!.turnDeadline,
          start.add(const Duration(hours: 40)));

      // Six hours after the fallback ran out, Berta withdraws. The
      // deadline falls back to an instant long past — arming that as-is
      // would start the duel on the next sweep, ambushing Anna, who is
      // waiting for the agreed hour.
      now = start.add(const Duration(hours: 30));
      await service.submit(
        matchId: match.id,
        playerId: b.id,
        actionJson: WarPrepPlan(slot: 2, auto: false, slots: const []).toJson(),
      );
      final deadline = (await store.match(match.id))!.turnDeadline!;
      expect(deadline, now.add(const Duration(seconds: 600)),
          reason: 'a stale fallback buys one war round of grace');
      expect(await service.sweepExpired(), 0);
      final st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(st.activeWar!.phase, WarPhase.preparation);
    });

    test('a "sofort" agreement still starts the duel on the next sweep',
        () async {
      // The grace above must not delay the case it was never about: both
      // sides picking the top of the current hour.
      final start = DateTime.utc(2026, 1, 1, 12, 30);
      var now = start;
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      final sofort = DateTime.utc(2026, 1, 1, 12).millisecondsSinceEpoch;
      await answerPlan(match, a.id, 1, {
        'auto': false,
        'slots': [sofort],
      });
      await answerPlan(match, b.id, 2, {
        'auto': false,
        'slots': [sofort],
      });
      expect((await store.match(match.id))!.turnDeadline,
          DateTime.utc(2026, 1, 1, 12));
      expect(await service.sweepExpired(), 1);
      final st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(st.activeWar!.phase, WarPhase.rounds);
    });

    test('a non-integer start proposal is dropped, not 500', () async {
      var now = DateTime.utc(2026, 1, 1);
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      final sofort = now.millisecondsSinceEpoch;
      // `List.cast<int>()` is lazy: a garbage entry used to slip past both
      // the action parser and the sanitizer and only blow up deep inside
      // the engine — a 500. A decision answer's `choice` is free-form, so
      // the bad entry is filtered out …
      await answerPlan(match, a.id, 1, {
        'auto': false,
        'slots': <dynamic>['morgen', sofort],
      });
      // … while the typed `WarPrepPlan.slots` is a plain bad request.
      await expectLater(
        service.submit(
          matchId: match.id,
          playerId: b.id,
          actionJson: {
            'type': 'warPrepPlan',
            'slot': 2,
            'auto': false,
            'slots': <dynamic>[sofort, 'gleich'],
          },
        ),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
      await service.submit(
        matchId: match.id,
        playerId: b.id,
        actionJson: WarPrepPlan(slot: 2, auto: false, slots: [sofort]).toJson(),
      );
      final st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(st.activeWar!.planSlots[1], [sofort]);
      expect(st.activeWar!.planSlots[2], [sofort]);
      expect(st.activeWar!.scheduledStartMs, sofort);
    });

    test('an absurd start proposal is dropped instead of poisoning the match',
        () async {
      var now = DateTime.utc(2026, 1, 1);
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      // Beyond DateTime's legal millisecond range: agreeing on it would
      // make every later commit of this match throw.
      const absurd = 9223372036854775;
      await answerPlan(match, a.id, 1, {
        'auto': false,
        'slots': [absurd],
      });
      await answerPlan(match, b.id, 2, {
        'auto': false,
        'slots': [absurd],
      });
      final st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(st.activeWar!.scheduledStartMs, isNull,
          reason: 'the proposal never reached the engine');
      expect((await store.match(match.id))!.turnDeadline,
          now.add(const Duration(hours: 24)),
          reason: 'the window keeps its full-turn fallback');
    });

    test(
        'a duelist who never acted is handed to the autopilot when their '
        'first round clock expires', () async {
      var now = DateTime.utc(2026, 1, 1);
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      final sofort = now.millisecondsSinceEpoch; // now sits on a full hour
      for (final (playerId, slot) in [(a.id, 1), (b.id, 2)]) {
        await answerPlan(match, playerId, slot, {
          'auto': false,
          'slots': [sofort],
        });
      }
      // Both agreed on "sofort" (a current-hour instant): the sweep begins
      // the rounds at once — the start is no longer in the submit request.
      now = now.add(const Duration(minutes: 1));
      expect(await service.sweepExpired(), 1);
      expect(
          GameState.fromJson((await store.match(match.id))!.stateJson!)
              .activeWar!
              .phase,
          WarPhase.rounds);

      // Anna acted (round end hands over to Berta) — she is "present".
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: WarEndRound(slot: 1).toJson(),
      );
      final handed =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(handed.activeWar!.actedSlots, contains(1));

      // Berta never shows up: her first round clock expires.
      now = now.add(const Duration(seconds: 601));
      expect(await service.sweepExpired(), 1);
      final swept =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(swept.activeWar, isNotNull);
      expect(swept.activeWar!.autoSlots, contains(2),
          reason: 'a total no-show is delegated for the rest of the war');
      expect(swept.activeWar!.autoSlots, isNot(contains(1)),
          reason: 'Anna acted — she stays live');
      expect((await store.match(match.id))!.turnDeadline,
          now.add(const Duration(hours: 24)),
          reason: 'no longer a live duel: Anna gets the full turn clock');
    });

    test(
        'a no-show duelist may take command back mid-war, out of turn '
        '(2026-08-24, user request)', () async {
      var now = DateTime.utc(2026, 1, 1);
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      final sofort = now.millisecondsSinceEpoch;
      for (final (playerId, slot) in [(a.id, 1), (b.id, 2)]) {
        await answerPlan(match, playerId, slot, {
          'auto': false,
          'slots': [sofort],
        });
      }
      now = now.add(const Duration(minutes: 1));
      expect(await service.sweepExpired(), 1);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: WarEndRound(slot: 1).toJson(),
      );
      // Berta never shows up: her first round clock expires and she is
      // handed to the autopilot for the rest of the war.
      now = now.add(const Duration(seconds: 601));
      expect(await service.sweepExpired(), 1);
      var st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(st.activeWar!.autoSlots, contains(2));

      // Berta takes command back — accepted OUT OF TURN: the war's raw
      // `actingSlot` never actually left her (round 2 opens with the
      // defender per the per-round alternation, `endWarRound`'s
      // `_firstHumanSide`/`warRoundOrder`) — nobody was awaiting her only
      // because she was delegated. The instant she un-delegates, that
      // becomes a real await instead of the autopilot quietly playing it.
      await service.submit(
        matchId: match.id,
        playerId: b.id,
        actionJson: ResumeWarCommand(slot: 2).toJson(),
      );
      st = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(st.activeWar!.autoSlots, isEmpty);
      final afterResume = await service.view(match.id, b.id);
      expect(afterResume['state'], isNotNull,
          reason: 'the war is still running, not auto-resolved');
      expect(afterResume['awaited_player_id'], b.id,
          reason: 'Berta is genuinely awaited now, not silently autopiloted');
      expect((await store.match(match.id))!.turnDeadline, isNotNull,
          reason: 'Berta gets a live war-round clock, not a stale one');

      // Proof she can act live: her own round input is now accepted where
      // the autopilot would otherwise have played it for her.
      await service.submit(
        matchId: match.id,
        playerId: b.id,
        actionJson: WarEndRound(slot: 2).toJson(),
      );
      final afterHerMove = GameState.fromJson(
          (await store.match(match.id))!.stateJson!);
      expect(afterHerMove.activeWar, isNotNull);
      expect(afterHerMove.activeWar!.autoSlots, isEmpty,
          reason: 'she stays live for the rest of the war');
    });

    test(
        'a duel neither player ever touches resolves itself instead of '
        'dragging one turn timer per round (2026-08-08)', () async {
      var now = DateTime.utc(2026, 1, 1);
      final start = now;
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      final sofort = now.millisecondsSinceEpoch;
      for (final (playerId, slot) in [(a.id, 1), (b.id, 2)]) {
        await answerPlan(
            match, playerId, slot, {'auto': false, 'slots': [sofort]});
      }

      // From here NOBODY ever submits again: run the sweep at every
      // deadline the server arms. Before the fix the no-show rule only
      // fired for the FIRST absentee (its gate went false as soon as one
      // side was delegated), so the second one kept the full turn clock
      // for all 20 rounds — the war, and with it the whole match, was
      // blocked for 20 days.
      for (var i = 0; i < 40; i++) {
        final record = (await store.match(match.id))!;
        final state = GameState.fromJson(record.stateJson!);
        if (state.activeWar == null) break;
        expect(record.turnDeadline, isNotNull,
            reason: 'a running war must always carry a clock — without one '
                'nothing can ever advance the match again');
        now = record.turnDeadline!.add(const Duration(minutes: 1));
        await service.sweepExpired();
      }
      final done = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(done.activeWar, isNull, reason: 'the war resolved itself');
      expect(now.difference(start), lessThan(const Duration(days: 3)),
          reason: 'two absent duelists must not stall the match for weeks');
    });

    test('a war left with no live side is fast-forwarded, never frozen',
        () async {
      var now = DateTime.utc(2026, 1, 1);
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      final sofort = now.millisecondsSinceEpoch;
      for (final (playerId, slot) in [(a.id, 1), (b.id, 2)]) {
        await answerPlan(
            match, playerId, slot, {'auto': false, 'slots': [sofort]});
      }
      now = now.add(const Duration(minutes: 1));
      await service.sweepExpired();

      // Surgery: both sides on the autopilot mid-rounds. Nobody is awaited
      // then, so the old code armed NO deadline — the match was dead for
      // good (a running war blocks every normal turn). The state is written
      // straight to the store, exactly like a match that entered this state
      // on an older build; the frozen-match sweep must revive it.
      final record = (await store.match(match.id))!;
      final state = GameState.fromJson(record.stateJson!);
      expect(state.activeWar!.phase, WarPhase.rounds);
      state.activeWar!.autoSlots.addAll([1, 2]);
      record.stateJson = state.toJson();
      record.turnDeadline = null;
      await store.saveMatch(record);

      now = now.add(const Duration(minutes: 1));
      expect(await service.sweepExpired(), 1,
          reason: 'the frozen match is picked up without a deadline');
      final healed =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(healed.activeWar, isNull,
          reason: 'a war nobody plays live must fast-forward to its end');
      expect((await store.match(match.id))!.turnDeadline, isNotNull,
          reason: 'the match runs on again');
    });

    test('an agreed start pushes "fixed" once and one reminder ~15 min ahead',
        () async {
      final start = DateTime.utc(2026, 1, 1);
      var now = start;
      final pushes = _RecordingPushService();
      service = MatchService(store, pushes, clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      final slot18 =
          start.add(const Duration(hours: 18)).millisecondsSinceEpoch;
      for (final (playerId, slot) in [(a.id, 1), (b.id, 2)]) {
        await answerPlan(match, playerId, slot, {
          'auto': false,
          'slots': [slot18],
        });
      }
      expect(pushes.kinds.where((k) => k == 'warStartFixed').length, 2,
          reason: 'both sides learn the fixed start once');

      // Outside the reminder window: nothing.
      now = start.add(const Duration(hours: 17));
      await service.sweepExpired();
      expect(pushes.kinds.where((k) => k == 'warStartSoon'), isEmpty);

      // ~15 min ahead: one reminder per live side — and never a second.
      now = start.add(const Duration(hours: 17, minutes: 50));
      await service.sweepExpired();
      expect(pushes.kinds.where((k) => k == 'warStartSoon').length, 2);
      await service.sweepExpired();
      expect(pushes.kinds.where((k) => k == 'warStartSoon').length, 2,
          reason: 'the reminder is deduplicated per start time');
    });

    test('the prep-deadline sweep of a no-show sends no stale "fixed" push',
        () async {
      final start = DateTime.utc(2026, 1, 1);
      var now = start;
      final pushes = _RecordingPushService();
      service = MatchService(store, pushes, clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await twoHumanMatch(a, b,
          settings: MatchSettings(
              seed: 42, turnTimeoutHours: 24, warRoundTimeoutSeconds: 600));
      await armWar(match);
      await service.submit(
        matchId: match.id,
        playerId: a.id,
        actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
      );
      // Anna answers; Berta never does. The deadline sweep force-delegates
      // Berta and STARTS the war — the warPlan decision vanishes in that
      // commit too, but a "war start fixed" push now would announce a start
      // that already happened.
      await answerPlan(match, a.id, 1, {'auto': false});
      now = start.add(const Duration(hours: 24, minutes: 1));
      expect(await service.sweepExpired(), 1);
      final started =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(started.activeWar!.phase, WarPhase.rounds);
      expect(pushes.kinds.where((k) => k == 'warStartFixed'), isEmpty,
          reason: 'the sweep starts the war — no stale appointment push');
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
        'a mid-list leave renumbers the remaining seats so everyone can '
        'still play after the start', () async {
      final (a, b) = await twoPlayers();
      final c = await service.registerPlayer(displayName: 'Clara');
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));
      await service.joinMatch(
          matchId: match.id, playerId: c.id, setup: setupFor('Clara', 3));

      // B (the middle seat) leaves while waiting: without renumbering,
      // Clara keeps turnOrder 2 while the started game maps her dynasty to
      // positional index 1 — she could never take a turn.
      await service.leaveMatch(matchId: match.id, playerId: b.id);
      final record = (await store.match(match.id))!;
      expect(record.players.map((p) => p.turnOrder), [0, 1]);

      await service.startMatch(matchId: match.id, playerId: a.id);
      final viewA = await service.view(match.id, a.id);
      final viewC = await service.view(match.id, c.id);
      // Both seats are recognized: exactly one of them is awaited.
      expect({viewA['your_turn'], viewC['your_turn']}, {true, false});
      expect(viewA['awaited_player_id'], isNotNull);
      // Clara's dynasty is mapped back to her seat, not to a ghost.
      final awaited = viewA['awaited_player_id'] as String;
      expect([a.id, c.id], contains(awaited));
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

  group('public matches', () {
    test('lists only public waiting matches with their settings', () async {
      final host = await service.registerPlayer(displayName: 'Host');
      final pub = await service.createMatch(
        playerId: host.id,
        settings: MatchSettings(seed: 1, isPublic: true, turnTimeoutHours: 24),
        setup: setupFor('Host', 1),
      );
      // A private match must never appear in the discovery list.
      await service.createMatch(
        playerId: host.id,
        settings: MatchSettings(seed: 2, isPublic: false),
        setup: setupFor('Host', 2),
      );

      final list = await service.publicMatches();
      expect(list.map((m) => m['id']), [pub.id]);
      expect(list.first['creator_name'], 'Host');
      expect(list.first['joined'], 1);
      expect((list.first['settings'] as Map)['turn_timeout_hours'], 24);
    });

    test('a started public match drops off the list', () async {
      final host = await service.registerPlayer(displayName: 'Host');
      final m = await service.createMatch(
        playerId: host.id,
        settings: MatchSettings(seed: 1, isPublic: true),
        setup: setupFor('Host', 1),
      );
      await service.startMatch(matchId: m.id, playerId: host.id);
      expect(await service.publicMatches(), isEmpty);
    });

    test('a full public room is not advertised (nothing left to join)',
        () async {
      final host = await service.registerPlayer(displayName: 'Host');
      // Smallest world: 6 realms ⇒ 6 human seats at most.
      final m = await service.createMatch(
        playerId: host.id,
        settings: MatchSettings(
            seed: 1, isPublic: true, mapSize: 'klein', realmCount: 6),
        setup: setupFor('Host', 1),
      );
      for (var i = 2; i <= 6; i++) {
        final p = await service.registerPlayer(displayName: 'Gast$i');
        await service.joinMatch(
            matchId: m.id, playerId: p.id, setup: setupFor('Gast$i', i));
      }
      expect(await service.publicMatches(), isEmpty,
          reason: 'every seat is taken — a join could only fail');

      // One seat frees up again → the room reappears.
      final leaver = (await store.match(m.id))!.players.last.playerId;
      await service.leaveMatch(matchId: m.id, playerId: leaver);
      expect((await service.publicMatches()).map((e) => e['id']), [m.id]);
    });
  });

  group('matchmaking rooms', () {
    /// The open room of [key], as the lobby sees it.
    Future<Map<String, dynamic>> room(String key) async {
      final list = await service.publicMatches();
      return list.firstWhere((m) => (m['settings'] as Map)['template'] == key);
    }

    /// Seats [count] fresh players in [matchId] (slots 1..count).
    Future<void> fill(String matchId, int count, {int from = 1}) async {
      for (var i = from; i < from + count; i++) {
        final p = await service.registerPlayer(displayName: 'Spieler$i');
        await service.joinMatch(
            matchId: matchId, playerId: p.id, setup: setupFor('Spieler$i', i));
      }
    }

    test('one open room per template, matchmaking rooms listed first',
        () async {
      final host = await service.registerPlayer(displayName: 'Host');
      await service.createMatch(
        playerId: host.id,
        settings: MatchSettings(seed: 1, isPublic: true),
        setup: setupFor('Host', 1),
      );
      await service.ensureTemplateMatches();
      // A second call must not open duplicates — one room per kind is the
      // whole point (else the players split across half-full rooms).
      await service.ensureTemplateMatches();

      final list = await service.publicMatches();
      expect(
        [for (final m in list) (m['settings'] as Map)['template']],
        ['blitz', 'standard', 'kaiserreich', null],
      );
      expect(list.first['seats'], 4);
      expect((list.first['settings'] as Map)['map_size'], 'klein');
      expect((list.first['settings'] as Map)['turn_timeout_hours'], 12);
      expect((list.first['settings'] as Map)['war_round_timeout'], 300);
      expect(list[2]['seats'], 10);
      expect((list[2]['settings'] as Map)['realm_count'], 30);
    });

    test('a filled room starts itself and is replaced by a fresh one',
        () async {
      await service.ensureTemplateMatches();
      final blitz = (await room('blitz'))['id'] as String;
      await fill(blitz, 4);

      final started = (await store.match(blitz))!;
      expect(started.status, MatchStatus.active);
      expect(started.stateJson, isNotNull);

      final replacement = await room('blitz');
      expect(replacement['id'], isNot(blitz));
      expect(replacement['joined'], 0);
    });

    test('an unfilled room starts on its fallback deadline', () async {
      var now = DateTime.utc(2026, 7, 29, 12);
      final store = InMemoryStore();
      final service = MatchService(store, LogPushService(), clock: () => now);
      await service.ensureTemplateMatches();
      final list = await service.publicMatches();
      final blitz = list.firstWhere(
          (m) => (m['settings'] as Map)['template'] == 'blitz')['id'] as String;

      // Two players are not enough to schedule anything yet.
      for (var i = 1; i <= 2; i++) {
        final p = await service.registerPlayer(displayName: 'S$i');
        await service.joinMatch(
            matchId: blitz, playerId: p.id, setup: setupFor('S$i', i));
      }
      expect((await store.match(blitz))!.autoStartAt, isNull);

      // The third arms the 24 h fallback start.
      final third = await service.registerPlayer(displayName: 'S3');
      await service.joinMatch(
          matchId: blitz, playerId: third.id, setup: setupFor('S3', 3));
      expect((await store.match(blitz))!.autoStartAt,
          DateTime.utc(2026, 7, 30, 12));

      now = DateTime.utc(2026, 7, 30, 11);
      expect(await service.sweepTemplates(), 0,
          reason: 'the deadline has not passed yet');
      expect((await store.match(blitz))!.status, MatchStatus.waiting);

      now = DateTime.utc(2026, 7, 30, 13);
      expect(await service.sweepTemplates(), 1);
      final started = (await store.match(blitz))!;
      expect(started.status, MatchStatus.active);
      expect(started.players, hasLength(3),
          reason: 'the remaining realms simply stay AI');

      // And the room is replaced, so the lobby keeps offering a Blitz game.
      final open = await service.publicMatches();
      expect(
        open.where((m) => (m['settings'] as Map)['template'] == 'blitz'),
        hasLength(1),
      );
    });

    test('leaving a waiting room frees the seat and disarms the start',
        () async {
      await service.ensureTemplateMatches();
      final standard = (await room('standard'))['id'] as String;
      await fill(standard, 4);
      expect((await store.match(standard))!.autoStartAt, isNotNull);

      final last = (await store.match(standard))!.players.last.playerId;
      final deleted =
          await service.leaveMatch(matchId: standard, playerId: last);
      expect(deleted, isFalse, reason: 'the room belongs to the server');
      final left = (await store.match(standard))!;
      expect(left.players, hasLength(3));
      expect(left.autoStartAt, isNull,
          reason: 'back below the threshold that armed it');

      // Even the FIRST seat leaving must not delete the room (an ordinary
      // waiting match dies with its creator — a matchmaking room has none).
      for (final seat in [...left.players]) {
        expect(
          await service.leaveMatch(
              matchId: standard, playerId: seat.playerId),
          isFalse,
        );
      }
      expect((await store.match(standard))!.players, isEmpty);
    });

    test('a matchmaking room cannot be started or deleted by hand', () async {
      await service.ensureTemplateMatches();
      final id = (await room('kaiserreich'))['id'] as String;
      final p = await service.registerPlayer(displayName: 'Erste');
      await service.joinMatch(
          matchId: id, playerId: p.id, setup: setupFor('Erste', 1));

      await expectLater(
        service.startMatch(matchId: id, playerId: p.id),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)),
      );
      // The lobby must not offer this seat a "delete game" button either.
      final view = await service.view(id, p.id);
      expect(view['creator_id'], isNull);
      expect(view['seats'], 10);
      final mine = await service.matchesForPlayer(p.id);
      expect(mine.single['is_creator'], isFalse);
      expect(mine.single['template'], 'kaiserreich');
    });

    test('a template key from a later build degrades to an ordinary match',
        () async {
      // A stored room whose template this build no longer knows (a removed
      // kind). The server plays it as an ordinary match — the wire must
      // say so too, or the client would render a room the server would let
      // its creator start and delete.
      final host = await service.registerPlayer(displayName: 'Alt');
      await store.saveMatch(MatchRecord(
        id: 'RETRO',
        settings: MatchSettings(seed: 5, isPublic: true, template: 'retired'),
        players: [],
      ));
      await service.joinMatch(
          matchId: 'RETRO', playerId: host.id, setup: setupFor('Alt', 1));

      final mine = await service.matchesForPlayer(host.id);
      final row = mine.singleWhere((m) => m['id'] == 'RETRO');
      expect(row['template'], isNull);
      expect(row['is_creator'], isTrue);
      final open = await service.publicMatches();
      final listed = open.singleWhere((m) => m['id'] == 'RETRO');
      expect((listed['settings'] as Map).containsKey('template'), isFalse);
      final view = await service.view('RETRO', host.id);
      expect(view['creator_id'], host.id);
      expect((view['settings'] as Map).containsKey('template'), isFalse);

      await service.startMatch(matchId: 'RETRO', playerId: host.id);
      expect((await store.match('RETRO'))!.status, MatchStatus.active);
    });

    test('a client cannot host a room by claiming a template key', () async {
      final host = await service.registerPlayer(displayName: 'Schlau');
      // The API strips `template` from client settings (api.dart) — the
      // service itself only ever sees it from a template room.
      final settings = MatchSettings.fromJson({
        'is_public': true,
        'map_size': 'klein',
      }..remove('template'));
      final m = await service.createMatch(
        playerId: host.id,
        settings: settings,
        setup: setupFor('Schlau', 1),
      );
      expect((await store.match(m.id))!.settings.template, isNull);
      // …and stays a normal match: its creator starts and deletes it.
      await service.startMatch(matchId: m.id, playerId: host.id);
      expect((await store.match(m.id))!.status, MatchStatus.active);
    });
  });

  group('settings off the wire', () {
    test('too-early event years never 500 the start — floored instead',
        () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await createStarted(
        a.id,
        MatchSettings(
            seed: 42, reformationYear: 500, ottomanYear: 3, warStartYear: -1),
        setupFor('Solo', 1),
      );
      expect(match.status, MatchStatus.active);
      final state = GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(state.reformationYear, minEventYear);
      expect(state.ottomanYear, minEventYear);
      expect(state.warStartYear, 1000);
    });

    test('zero/negative timers are floored at the parse boundary', () {
      final settings = MatchSettings.fromJson(
          {'turn_timeout_hours': 0, 'war_round_timeout': -5});
      expect(settings.turnTimeoutHours, 1);
      expect(settings.warRoundTimeoutSeconds, 60);
      // No timer stays no timer.
      expect(MatchSettings.fromJson({}).turnTimeoutHours, isNull);
    });
  });

  group('idle kick', () {
    test('repeated timeouts accrue idle turns; the creator kicks to AI',
        () async {
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

      // Nobody plays — sweep until Berta has missed the kick threshold.
      var guard = 0;
      while (((await store.match(match.id))!.playerById(b.id)!.idleTurns) <
              MatchService.idleKickThreshold &&
          guard++ < 40) {
        now = now.add(const Duration(hours: 25));
        await service.sweepExpired();
      }
      final beforeKick = (await store.match(match.id))!;
      expect(beforeKick.playerById(b.id)!.idleTurns,
          greaterThanOrEqualTo(MatchService.idleKickThreshold));
      final bSlot = beforeKick.playerById(b.id)!.slot;

      // Only the creator may kick.
      expect(
        () => service.kickPlayer(
            matchId: match.id, requesterId: b.id, targetPlayerId: a.id),
        throwsA(isA<ApiException>()),
      );

      await service.kickPlayer(
          matchId: match.id, requesterId: a.id, targetPlayerId: b.id);
      final after = (await store.match(match.id))!;
      expect(after.playerById(b.id), isNull, reason: 'kicked seat removed');
      final state = GameState.fromJson(after.stateJson!);
      expect(state.dynasty(bSlot).status, DynastyStatus.ai);
      expect(state.events.any((e) => e.type == 'playerKicked'), isTrue,
          reason: 'all players learn about the replacement');
    });

    test('kicking a seat below the threshold is rejected', () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        settings: MatchSettings(seed: 42, turnTimeoutHours: 24),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));
      await service.startMatch(matchId: match.id, playerId: a.id);
      expect(
        () => service.kickPlayer(
            matchId: match.id, requesterId: a.id, targetPlayerId: b.id),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
      );
    });

    test('submitting a turn resets the idle streak', () async {
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

      // Lapse both seats' first turn so the next awaited player carries a
      // non-zero idle count, then have them play.
      now = now.add(const Duration(hours: 25));
      await service.sweepExpired();
      now = now.add(const Duration(hours: 25));
      await service.sweepExpired();

      final awaited =
          (await service.view(match.id, a.id))['awaited_player_id'] as String;
      expect((await store.match(match.id))!.playerById(awaited)!.idleTurns,
          greaterThanOrEqualTo(1));
      await service.submit(matchId: match.id, playerId: awaited, endTurn: true);
      expect((await store.match(match.id))!.playerById(awaited)!.idleTurns, 0,
          reason: 'showing up clears the streak');
    });
  });

  group('settings flow into the game', () {
    test('warStartYear and gender-equal succession reach the game state',
        () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await createStarted(
        a.id,
        MatchSettings(
            seed: 42,
            warStartYear: 1015,
            genderEqualSuccession: false,
            suggestChildNames: false),
        setupFor('Solo', 1),
      );
      final state =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(state.warStartYear, 1015);
      expect(state.genderEqualSuccession, isFalse);
      expect(state.suggestChildNames, isFalse);
    });

    test('ai difficulty reaches the game state (unknown values → mittel)',
        () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await createStarted(
        a.id,
        MatchSettings(seed: 42, aiDifficulty: 'schwer'),
        setupFor('Solo', 1),
      );
      final state =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(state.aiDifficulty, AiDifficulty.schwer);

      final b = await service.registerPlayer(displayName: 'Solo2');
      final match2 = await createStarted(
        b.id,
        MatchSettings(seed: 43, aiDifficulty: 'nightmare'),
        setupFor('Solo2', 1),
      );
      final state2 =
          GameState.fromJson((await store.match(match2.id))!.stateJson!);
      expect(state2.aiDifficulty, AiDifficulty.mittel,
          reason: 'an unvalidated online settings payload must not crash');
    });

    test(
        'map size and realm count reach the game state (out of range → '
        'clamped, never a 500)', () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await createStarted(
        a.id,
        MatchSettings(seed: 42, mapSize: 'klein', realmCount: 10),
        setupFor('Solo', 1),
      );
      final state =
          GameState.fromJson((await store.match(match.id))!.stateJson!);
      expect(state.map.width, MapSize.klein.width);
      expect(state.map.height, MapSize.klein.height);
      expect(state.realmCount, 10);

      // Out-of-range realm count and an unknown size degrade gracefully.
      final b = await service.registerPlayer(displayName: 'Solo2');
      final match2 = await createStarted(
        b.id,
        MatchSettings.fromJson(
            {'seed': 43, 'map_size': 'winzig', 'realm_count': 99}),
        setupFor('Solo2', 1),
      );
      final state2 =
          GameState.fromJson((await store.match(match2.id))!.stateJson!);
      expect(state2.map.width, MapSize.gross.width);
      expect(state2.realmCount, MapSize.gross.maxRealmCount);
    });

    test(
        'a seat color reaches the realm; a duplicate falls back to the '
        'default (2026-07-27)', () async {
      final host = await service.registerPlayer(displayName: 'Host');
      final match = await service.createMatch(
        playerId: host.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Host', 1)..['color'] = 0xFFD32F2F,
      );
      final joiner = await service.registerPlayer(displayName: 'Gast');
      await service.joinMatch(
        matchId: match.id,
        playerId: joiner.id,
        setup: setupFor('Gast', 2)..['color'] = 0xFFD32F2F, // already taken
      );
      final open = await service.openSlots(match.id);
      expect(open['taken_colors'], [0xFFD32F2F],
          reason: 'the duplicate pick was dropped, not stored twice');
      final started =
          await service.startMatch(matchId: match.id, playerId: host.id);
      final state =
          GameState.fromJson((await store.match(started.id))!.stateJson!);
      expect(state.realm(1).colorArgb, 0xFFD32F2F);
      expect(state.realm(2).colorArgb, isNull,
          reason: 'the losing racer keeps the slot-derived default');
    });

    test('a non-opaque color falls back to the default (2026-07-27)', () async {
      // Display-only, but rendered on every player's map — a doctored
      // client must not seat an invisible (alpha 0) realm.
      final host = await service.registerPlayer(displayName: 'Host');
      final match = await service.createMatch(
        playerId: host.id,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Host', 1)..['color'] = 0x00D32F2F, // alpha 0
      );
      final open = await service.openSlots(match.id);
      expect(open['taken_colors'], isEmpty);
    });

    test('joining a small match rejects a country beyond the realms in play',
        () async {
      final host = await service.registerPlayer(displayName: 'Host');
      final match = await service.createMatch(
        playerId: host.id,
        settings: MatchSettings(seed: 42, mapSize: 'klein'),
        setup: setupFor('Host', 1),
      );
      final joiner = await service.registerPlayer(displayName: 'Gast');
      await expectLater(
        service.joinMatch(
          matchId: match.id,
          playerId: joiner.id,
          setup: setupFor('Gast', 13), // klein plays slots 1–12
        ),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  group('retention (sweepStale)', () {
    late _RecordingPushService push;
    late DateTime now;

    setUp(() {
      push = _RecordingPushService();
      now = DateTime.utc(2026, 7, 27, 12);
      service = MatchService(store, push, clock: () => now);
    });

    /// A stored record aged so its last activity lies [silence] in the past.
    MatchRecord record(String id, MatchStatus status, Duration silence,
            {List<MatchPlayer> players = const []}) =>
        MatchRecord(
          id: id,
          settings: MatchSettings(seed: 1),
          players: players,
          status: status,
          createdAt: now.subtract(silence),
          updatedAt: now.subtract(silence),
        );

    test('finished matches are deleted 30 days after the last update',
        () async {
      await store.saveMatch(record(
          'FRESH', MatchStatus.finished, const Duration(days: 29)));
      await store.saveMatch(
          record('STALE', MatchStatus.finished, const Duration(days: 31)));
      expect(await service.sweepStale(), 1);
      expect(await store.match('FRESH'), isNotNull,
          reason: 'still inside the result-screen grace period');
      expect(await store.match('STALE'), isNull);
    });

    test('abandoned waiting lobbies are deleted after 7 days', () async {
      await store.saveMatch(
          record('FRESH', MatchStatus.waiting, const Duration(days: 6)));
      await store.saveMatch(
          record('STALE', MatchStatus.waiting, const Duration(days: 8)));
      expect(await service.sweepStale(), 1);
      expect(await store.match('FRESH'), isNotNull);
      expect(await store.match('STALE'), isNull);
    });

    test('a silent active match is warned once, then deleted after the lead',
        () async {
      final p = await service.registerPlayer(displayName: 'Still');
      final seat = MatchPlayer(
        playerId: p.id,
        turnOrder: 0,
        slot: 1,
        founderName: 'Still',
        gender: 1,
        dorfName: 'Stilldorf',
      );
      await store.saveMatch(record(
          'QUIET', MatchStatus.active, const Duration(days: 352),
          players: [seat]));

      // Inside the warning window: push goes out, nothing is deleted.
      expect(await service.sweepStale(), 0);
      expect(push.kinds, containsOnce('matchExpiring'));
      expect((await store.match('QUIET'))!.expiryWarnedAt, now);

      // The next daily run re-warns nobody and still keeps the match.
      now = now.add(const Duration(days: 1));
      expect(await service.sweepStale(), 0);
      expect(push.kinds, containsOnce('matchExpiring'));

      // Warning lead over AND the retention age reached: deleted.
      now = now.add(const Duration(days: 14));
      expect(await service.sweepStale(), 1);
      expect(await store.match('QUIET'), isNull);
    });

    test('activity after the warning cancels the pending expiry', () async {
      await store.saveMatch(
          record('WOKEN', MatchStatus.active, const Duration(days: 360)));
      expect(await service.sweepStale(), 0); // warned
      expect((await store.match('WOKEN'))!.expiryWarnedAt, isNotNull);

      // Somebody plays: every commit moves updatedAt past the warning.
      final match = (await store.match('WOKEN'))!;
      match.updatedAt = now.add(const Duration(hours: 1));
      await store.saveMatch(match);

      now = now.add(const Duration(days: 20));
      expect(await service.sweepStale(), 0,
          reason: 'the silence clock restarted with the new activity');
      expect((await store.match('WOKEN'))!.expiryWarnedAt, isNull);
    });

    test('active matches inside the retention window are untouched', () async {
      await store.saveMatch(
          record('YOUNG', MatchStatus.active, const Duration(days: 300)));
      expect(await service.sweepStale(), 0);
      expect(push.kinds, isEmpty);
      expect((await store.match('YOUNG'))!.expiryWarnedAt, isNull);
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

/// Records which push kinds were sent — for the duel-scheduling tests.
class _RecordingPushService implements PushService {
  final List<String> kinds = [];

  @override
  Future<void> yourTurn(PlayerRecord player, MatchRecord match) async =>
      kinds.add('yourTurn');

  @override
  Future<void> yourDecision(PlayerRecord player, MatchRecord match) async =>
      kinds.add('yourDecision');

  @override
  Future<void> warStarted(PlayerRecord player, MatchRecord match) async =>
      kinds.add('warStarted');

  @override
  Future<void> warStartFixed(
          PlayerRecord player, MatchRecord match, DateTime start,
          {required bool agreed, bool toAttacker = false}) async =>
      kinds.add('warStartFixed');

  @override
  Future<void> warStartSoon(PlayerRecord player, MatchRecord match) async =>
      kinds.add('warStartSoon');

  @override
  Future<void> matchExpiring(PlayerRecord player, MatchRecord match) async =>
      kinds.add('matchExpiring');
}
