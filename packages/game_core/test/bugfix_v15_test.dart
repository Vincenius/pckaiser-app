import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Rules v4: war armies may march across neutral land; a realm that loses
/// its capital takes a new seat (AI automatically, humans by decision);
/// "Sitz verlegen" is allowed any time; and `humansDefeated` carries the
/// real cause. (15th bugfix iteration — the file counter is just a label;
/// rules are not versioned, every game plays the latest.)
void main() {
  late GameState state;

  setUp(() {
    state = startGame(
            newGame(GameSetup(
              humans: [
                HumanPlayerSetup(
                    founderName: 'Anna',
                    gender: 1,
                    countrySlot: 1,
                    dorfName: 'A'),
                HumanPlayerSetup(
                    founderName: 'Berta',
                    gender: 1,
                    countrySlot: 2,
                    dorfName: 'B'),
              ],
              reformationYear: 1020,
              ottomanYear: 1040,
              seed: 2026,
            )),
            Rng(7))
        .state;
    state.year = 1010;
    state.dynasty(2).status = DynastyStatus.ai;
    state.dynasty(2).humanPlayer = null;
    for (final slot in [1, 2]) {
      final realm = state.realm(slot);
      realm.treasury = 50000;
      realm.towns.single.troopCapacity = 1000;
      realm.troopCapacity = 1000;
      state = applyAction(
              state,
              RecruitTroops(
                  slot: slot,
                  men: 50,
                  troopClass: TroopClass.infanterie,
                  name: 'Heer$slot'),
              Rng(state.rngSeed))
          .state;
    }
    // Wars need a shared border: hand slot 2 a land tile next to slot 1.
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
  });

  group('war march across neutral land (rules v4)', () {
    test('a unit may step onto a neutral, unowned land tile', () {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      final map = s.map;
      final troop = s.realm(1).troops.single;
      // Find a neutral land tile orthogonally adjacent to the unit; carve
      // one if necessary so the test is deterministic.
      late int nx, ny, dx, dy;
      var found = false;
      for (final (cdx, cdy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final tx = troop.x + cdx;
        final ty = troop.y + cdy;
        if (map.inBounds(tx, ty) && !map.isWaterAt(tx, ty)) {
          map.owner[map.index(tx, ty)] = World.niemand;
          nx = tx;
          ny = ty;
          dx = cdx;
          dy = cdy;
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: 'a land neighbour must exist');
      expect(map.ownerAt(nx, ny), World.niemand);
      s.activeWar!.movesLeft[1]![0] = 5;

      s = applyAction(
              s, WarMove(slot: 1, unitIndex: 0, dx: dx, dy: dy), Rng(s.rngSeed))
          .state;

      expect(s.realm(1).troops.single.x, nx);
      expect(s.realm(1).troops.single.y, ny);
    });

    test('marching through a THIRD realm is still forbidden', () {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      final map = s.map;
      final troop = s.realm(1).troops.single;
      for (final (cdx, cdy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final tx = troop.x + cdx;
        final ty = troop.y + cdy;
        if (map.inBounds(tx, ty) && !map.isWaterAt(tx, ty)) {
          map.owner[map.index(tx, ty)] = 5; // an uninvolved realm
          s.activeWar!.movesLeft[1]![0] = 5;
          expect(
              () => applyAction(
                  s,
                  WarMove(slot: 1, unitIndex: 0, dx: cdx, dy: cdy),
                  Rng(s.rngSeed)),
              throwsA(isA<ActionException>()));
          return;
        }
      }
      fail('no land neighbour to test against');
    });
  });

  group('lost capital re-seating (rules v4)', () {
    test('an AI realm auto-reseats onto its best-value tile', () {
      final realm = state.realm(2);
      final map = state.map;
      // Lose the capital tile; place two eligible tiles of different value.
      map.owner[map.index(realm.capitalX, realm.capitalY)] = World.niemand;
      final spots = <(int, int)>[];
      for (var y = 0; y < map.height && spots.length < 2; y++) {
        for (var x = 0; x < map.width && spots.length < 2; x++) {
          if (map.ownerAt(x, y) == World.niemand && !map.isWaterAt(x, y)) {
            spots.add((x, y));
          }
        }
      }
      // A Burg (value 5) beats a Stadt-less... use Stadt vs Palast.
      map.owner[map.index(spots[0].$1, spots[0].$2)] = 2;
      map.building[map.index(spots[0].$1, spots[0].$2)] = Building.burg;
      map.owner[map.index(spots[1].$1, spots[1].$2)] = 2;
      map.building[map.index(spots[1].$1, spots[1].$2)] = Building.palast;
      final palastValue = Building.value[Building.palast];
      final burgValue = Building.value[Building.burg];
      expect(palastValue, greaterThan(burgValue));

      final events = <GameEvent>[];
      reseatLostCapitals(state, Rng(1), events);

      expect(map.buildingAt(state.realm(2).capitalX, state.realm(2).capitalY),
          Building.palast,
          reason: 'AI picks the highest-value eligible tile');
      expect(events.any((e) => e.type == 'capitalReseated'), isTrue);
    });

    test('a human realm gets a relocateCapital decision, not an auto-move', () {
      final realm = state.realm(1); // slot 1 stays human
      final map = state.map;
      final oldX = realm.capitalX;
      final oldY = realm.capitalY;
      map.owner[map.index(oldX, oldY)] = World.niemand;
      // The realm still holds another seat-eligible tile to move to.
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) == World.niemand && !map.isWaterAt(x, y)) {
            map.owner[map.index(x, y)] = 1;
            map.building[map.index(x, y)] = Building.stadt;
            y = map.height;
            break;
          }
        }
      }

      final events = <GameEvent>[];
      reseatLostCapitals(state, Rng(1), events);

      expect(state.realm(1).capitalX, oldX,
          reason: 'the human seat is not moved automatically');
      expect(
          state.pendingDecisions
              .any((d) => d.type == 'relocateCapital' && d.decidingSlot == 1),
          isTrue);
      expect(events.any((e) => e.type == 'capitalLost'), isTrue);
    });

    test('resolving the decision re-seats for free onto the chosen tile', () {
      final realm = state.realm(1);
      final map = state.map;
      map.owner[map.index(realm.capitalX, realm.capitalY)] = World.niemand;
      // An own Stadt to choose.
      (int, int)? target;
      for (var y = 0; y < map.height && target == null; y++) {
        for (var x = 0; x < map.width && target == null; x++) {
          if (map.ownerAt(x, y) == World.niemand && !map.isWaterAt(x, y)) {
            map.owner[map.index(x, y)] = 1;
            map.building[map.index(x, y)] = Building.stadt;
            target = (x, y);
          }
        }
      }
      var s = state;
      final events = <GameEvent>[];
      reseatLostCapitals(s, Rng(1), events);
      final decision =
          s.pendingDecisions.firstWhere((d) => d.type == 'relocateCapital');
      final treasuryBefore = s.realm(1).treasury;

      s = applyAction(
              s,
              ResolveDecision(
                slot: 1,
                decisionId: decision.id,
                choice: {'x': target!.$1, 'y': target.$2},
              ),
              Rng(s.rngSeed))
          .state;

      expect(s.realm(1).capitalX, target.$1);
      expect(s.realm(1).capitalY, target.$2);
      expect(s.realm(1).treasury, treasuryBefore,
          reason: 'forced re-seat is free');
      expect(
          s.pendingDecisions.any((d) => d.type == 'relocateCapital'), isFalse);
    });
  });

  group('humansDefeated reason (rules v4)', () {
    test('an internal-strife elimination is reported as the cause', () {
      // Single human (slot 1; slot 2 is AI from setUp). Drive slot 1 into a
      // popularity collapse with rival branches so §19.1 strife flips it to
      // AI during its end-of-turn — the defeat reason must then name strife.
      final realm = state.realm(1);
      realm.popularity = 10;
      // §19.1 needs > 3 dynasty members with at least one non-ruler rival.
      for (var i = 0; i < 4; i++) {
        final p = Person(
            id: 5000 + i, name: 'Zweig$i', gender: 0, age: 30, dynasty: 1);
        state.persons[p.id] = p;
        state.dynasty(1).memberIds.add(p.id);
      }

      final completed = completeTurn(state, Rng(1));
      expect(completed.state.dynasty(1).status, DynastyStatus.ai,
          reason: 'precondition: strife dethroned the human');

      final result = advanceUntilHuman(completed.state, Rng(1));
      final defeat =
          result.events.firstWhere((e) => e.type == 'humansDefeated');
      expect(defeat.payload['reason'], 'internalStrife');
    });
  });

  group('bankruptcy grace period (rules v4)', () {
    test('deep debt only warns until the grace period elapses', () {
      final realm = state.realm(1);
      realm.popularity = 50; // keep §19.1 strife out of the picture
      // Far below the class-1 limit (10000 T) so the foreclosure clock runs.
      realm.treasury = -20000;

      // The first turns below the limit only warn — no seizure yet.
      for (var turn = 1; turn < bankruptcyGraceTurns; turn++) {
        final events = <GameEvent>[];
        runEliminationChecks(state, 1, Rng(1), events);
        expect(events.any((e) => e.type == 'debtWarning'), isTrue,
            reason: 'turn $turn should warn');
        expect(events.any((e) => e.type == 'bankruptcy'), isFalse,
            reason: 'turn $turn must not foreclose yet');
        expect(state.realm(1).debtTurns, turn);
        // Still solvent in title terms — the dynasty was not replaced.
        expect(state.dynasty(1).status, DynastyStatus.human);
      }

      // The grace-th consecutive deep-debt turn forecloses.
      final events = <GameEvent>[];
      runEliminationChecks(state, 1, Rng(1), events);
      expect(events.any((e) => e.type == 'bankruptcy'), isTrue);
    });

    test('recovering above the limit resets the debt clock', () {
      final realm = state.realm(1);
      realm.popularity = 50;
      realm.treasury = -20000;

      var events = <GameEvent>[];
      runEliminationChecks(state, 1, Rng(1), events);
      expect(state.realm(1).debtTurns, 1);

      // Climb back above the limit: the clock resets, no bankruptcy.
      state.realm(1).treasury = 500;
      events = <GameEvent>[];
      runEliminationChecks(state, 1, Rng(1), events);
      expect(state.realm(1).debtTurns, 0);
      expect(events.any((e) => e.type == 'bankruptcy'), isFalse);
      expect(events.any((e) => e.type == 'debtWarning'), isFalse);
    });
  });
}
