import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

GameState freshGame({int seed = 2026, int reformation = 1020, int ottoman = 1040}) =>
    startGame(
        newGame(GameSetup(
          humans: [
            HumanPlayerSetup(
                founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'A'),
          ],
          reformationYear: reformation,
          ottomanYear: ottoman,
          seed: seed,
        )),
        Rng(seed)).state;

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
      final protestant = s.dynasties
          .where((d) => d.religion == Religion.evangelisch)
          .toList();
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
      final muslim = s.dynasties
          .where((d) => d.religion == Religion.moslemisch)
          .toList();
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
    test('never strikes before year 1005 (grace period)', () {
      for (var seed = 0; seed < 100; seed++) {
        final s = freshGame(seed: 2026).copy();
        s.year = 1004;
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
      expect(realm.rulerId, isNot(oldRuler));
      expect(realm.popularity, 50);
      expect(dynasty.status, DynastyStatus.ai, reason: 'player eliminated');
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
}
