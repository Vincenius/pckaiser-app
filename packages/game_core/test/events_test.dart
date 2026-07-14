import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

GameState freshGame(
        {int seed = 2026, int reformation = 1020, int ottoman = 1040}) =>
    startGame(
            newGame(GameSetup(
              humans: [
                HumanPlayerSetup(
                    founderName: 'Anna',
                    gender: 1,
                    countrySlot: 1,
                    dorfName: 'A'),
              ],
              reformationYear: reformation,
              ottomanYear: ottoman,
              seed: seed,
            )),
            Rng(seed))
        .state;

void main() {
  group('Reformation & Ottoman invasion (§18.3/§18.4)', () {
    test('Reformation converts one AI dynasty at the chosen year', () {
      final state = freshGame();
      state.year = state.reformationYear - 1;
      final events = <GameEvent>[];
      // Trigger the world phase via a full round wrap.
      var s = state;
      for (var i = 0; i < 30; i++) {
        s = completeTurn(s, Rng(s.rngSeed)).state;
      }
      expect(s.year, s.reformationYear);
      expect(s.events.any((e) => e.type == 'reformation'), isTrue);
      final protestant =
          s.dynasties.where((d) => d.religion == Religion.evangelisch).toList();
      expect(protestant, hasLength(1));
      expect(protestant.single.status, DynastyStatus.ai);
      expect(events, isEmpty);
    });

    test('Ottoman invasion creates a Muslim realm with Janitscharen', () {
      final state = freshGame();
      state.year = state.ottomanYear - 1;
      var s = state;
      for (var i = 0; i < 30; i++) {
        s = completeTurn(s, Rng(s.rngSeed)).state;
      }
      expect(s.year, s.ottomanYear);
      final muslim =
          s.dynasties.where((d) => d.religion == Religion.moslemisch).toList();
      expect(muslim, hasLength(1));
      final realm = s.realm(muslim.single.index);
      final janitscharen =
          realm.troops.where((t) => t.name == 'Die Janitscharen').toList();
      expect(janitscharen, hasLength(1));
      expect(janitscharen.single.men, 1000);
      expect(janitscharen.single.quality, TroopQuality.janitscharen);
      expect(realm.towns.first.name, endsWith('sburg'));
      expect(s.events.any((e) => e.type == 'ottomanInvasion'), isTrue);
    });
  });

  group('earthquake (§18.1)', () {
    test('never strikes before year 1010 (grace period)', () {
      for (var seed = 0; seed < 100; seed++) {
        final s = freshGame(seed: 2026).copy();
        s.year = 1009;
        final events = <GameEvent>[];
        runWorldEvents(s, Rng(seed), events);
        expect(events.where((e) => e.type == 'earthquake'), isEmpty);
      }
    });

    test('fires eventually and keeps the bookkeeping consistent', () {
      var s = freshGame(seed: 13);
      var quake = false;
      for (var round = 0; round < 60 && !quake; round++) {
        for (var i = 0; i < 30; i++) {
          s = completeTurn(s, Rng(s.rngSeed)).state;
        }
        quake = s.events.any((e) => e.type == 'earthquake');
      }
      expect(quake, isTrue, reason: '10%/round should fire within 60 rounds');
      // Bookkeeping invariants after the quake.
      for (final realm in s.realms) {
        final counted = List.filled(9, 0);
        for (var i = 0; i < s.map.terrain.length; i++) {
          if (s.map.owner[i] == realm.slot) counted[s.map.building[i]]++;
        }
        expect(realm.tileCount, counted,
            reason: 'slot ${realm.slot} tileCount after earthquake');
      }
    });
  });

  group('elimination (§19)', () {
    test('popularity crisis hands the realm to a rival branch', () {
      final state = freshGame();
      state.year = 1010;
      final dynasty = state.dynasty(1);
      final realm = state.realm(1);
      realm.popularity = 10;
      // Grow the dynasty above 3 members.
      for (var i = 0; i < 4; i++) {
        final p = Person(
            id: state.nextPersonId++,
            name: 'Mitglied$i',
            age: 20,
            dynasty: 1,
            gender: 0);
        state.persons[p.id] = p;
        dynasty.memberIds.add(p.id);
      }
      final oldRuler = realm.rulerId;
      final events = <GameEvent>[];
      runEliminationChecks(state, 1, Rng(3), events);
      expect(events.single.type, 'internalStrife');
      expect(events.single.payload['human'], isTrue,
          reason: 'the flag keys the client\'s "you lost your realm" '
              'popup (2026-07-13: the loss used to pass silently)');
      expect(realm.rulerId, isNot(oldRuler));
      expect(realm.popularity, 50);
      expect(dynasty.status, DynastyStatus.ai, reason: 'player eliminated');
    });

    test('an AI realm\'s popularity crisis is not flagged as a human loss',
        () {
      final state = freshGame();
      state.year = 1010;
      final dynasty = state.dynasty(2);
      dynasty.status = DynastyStatus.ai;
      dynasty.humanPlayer = null;
      state.realm(2).popularity = 10;
      for (var i = 0; i < 4; i++) {
        final p = Person(
            id: state.nextPersonId++,
            name: 'M$i',
            age: 20,
            dynasty: 2,
            gender: 0);
        state.persons[p.id] = p;
        dynasty.memberIds.add(p.id);
      }
      final events = <GameEvent>[];
      runEliminationChecks(state, 2, Rng(3), events);
      expect(events.single.type, 'internalStrife');
      expect(events.single.payload['human'], isFalse);
    });

    test('crisis is suppressed in the protection window', () {
      final state = freshGame();
      expect(state.year, 1000);
      final dynasty = state.dynasty(1);
      state.realm(1).popularity = 10;
      for (var i = 0; i < 4; i++) {
        final p = Person(
            id: state.nextPersonId++,
            name: 'M$i',
            age: 20,
            dynasty: 1,
            gender: 0);
        state.persons[p.id] = p;
        dynasty.memberIds.add(p.id);
      }
      final events = <GameEvent>[];
      runEliminationChecks(state, 1, Rng(3), events);
      expect(events, isEmpty);
      expect(dynasty.status, DynastyStatus.human);
    });

    test('bankruptcy seizes tiles and installs a replacement dynasty', () {
      final state = freshGame();
      state.year = 1010;
      final realm = state.realm(2);
      final oldRuler = realm.rulerId;
      realm.treasury = -12000; // Ritter limit 10,000
      // The grace period has already elapsed: this turn forecloses.
      realm.debtTurns = bankruptcyGraceTurns - 1;
      final events = <GameEvent>[];
      runEliminationChecks(state, 2, Rng(3), events);
      expect(events.any((e) => e.type == 'bankruptcy'), isTrue);
      expect(realm.rulerId, isNot(oldRuler));
      expect(realm.treasury, inInclusiveRange(500, 25000),
          reason: 'replacement treasury clamp (§5)');
      expect(state.dynasty(2).memberIds, hasLength(1));
      // 12,000 debt → 2 seizures; the starting Burg gets seized.
      expect(realm.tileCount[Building.burg], 0);
    });

    test(
        'bankruptcy seizure removes the seized town\'s garrison without '
        'double-cutting other garrisons', () {
      final state = freshGame();
      state.year = 1010;
      final realm = state.realm(2);
      // Promote the starting Dorf to a (seizable) Stadt and garrison it.
      final town = realm.towns.single;
      final index = state.map.index(town.x, town.y);
      realm.tileCount[state.map.building[index]]--;
      state.map.building[index] = Building.stadt;
      realm.tileCount[Building.stadt]++;
      town.buildingType = Building.stadt;
      town.troopCapacity = 50;
      town.garrison = 20;
      realm.troopCapacity = realm.towns.fold(0, (n, t) => n + t.troopCapacity);
      realm.troops.add(Troop(
          name: 'Garde',
          men: 20,
          troopClass: TroopClass.infanterie,
          quality: TroopQuality.regular,
          garrisonCounted: true,
          x: town.x,
          y: town.y));

      realm.treasury = -12000; // Ritter limit 10,000 → 2 seizures
      realm.debtTurns = bankruptcyGraceTurns - 1; // grace elapsed
      runEliminationChecks(state, 2, Rng(3), <GameEvent>[]);

      expect(realm.towns, isEmpty, reason: 'the Stadt was seized');
      expect(realm.armySize, 0);
      expect(realm.troops, isEmpty,
          reason: 'the garrisoned unit\'s men vanished with the town');
    });

    test('debt within the title limit is tolerated', () {
      final state = freshGame();
      state.year = 1010;
      final realm = state.realm(2);
      final ruler = realm.rulerId;
      realm.treasury = -9000;
      runEliminationChecks(state, 2, Rng(3), []);
      expect(realm.rulerId, ruler);
    });
  });

  group('long-run integration', () {
    test('100 years with everything enabled keeps core invariants', () {
      var s = freshGame(seed: 4711);
      for (var turn = 0; turn < 100 * 30; turn++) {
        s = completeTurn(s, Rng(s.rngSeed)).state;
        if (s.events.isNotEmpty && s.events.last.type == 'gameWon') break;
      }
      for (final realm in s.realms) {
        expect(realm.popularity, inInclusiveRange(0, 100));
        expect(realm.population, greaterThanOrEqualTo(0));
        final townPop = realm.towns.fold(0, (n, t) => n + t.population);
        expect(realm.population, townPop,
            reason: 'slot ${realm.slot} population sum');
        final counted = List.filled(9, 0);
        for (var i = 0; i < s.map.terrain.length; i++) {
          if (s.map.owner[i] == realm.slot) counted[s.map.building[i]]++;
        }
        expect(realm.tileCount, counted,
            reason: 'slot ${realm.slot} tileCount');
      }
      // The state must still serialize.
      final json = s.toJson();
      expect(GameState.fromJson(json).toJson(), json);
    });
  });

  group('disease mercy rule (§18.2 [DEVIATION])', () {
    test('the last living member of a dynasty always survives an outbreak', () {
      for (var seed = 0; seed < 10; seed++) {
        final state = freshGame(seed: 2026);
        state.year = 1010; // protection window over
        // Slot 1's founder stays the lone member of their dynasty; pad
        // the world above the certain-outbreak threshold (> 250 persons)
        // by enlarging the OTHER dynasties.
        final loneId = state.dynasty(1).memberIds.single;
        var id = state.nextPersonId;
        while (state.persons.length <= 260) {
          final slot = 2 + (id % 29);
          final filler = Person(
              id: id, name: 'P$id', age: 30, dynasty: slot, gender: id % 2);
          state.persons[id] = filler;
          state.dynasty(slot).memberIds.add(id);
          id++;
        }
        state.nextPersonId = id;

        final events = <GameEvent>[];
        runWorldEvents(state, Rng(seed), events);
        expect(events.any((e) => e.type == 'disease'), isTrue,
            reason: '> 250 persons → certain outbreak');
        expect(state.persons[loneId], isNotNull,
            reason: 'seed $seed killed the last member of dynasty 1');
        expect(state.persons.length, lessThan(261),
            reason: 'population control still works');
      }
    });
  });
}
