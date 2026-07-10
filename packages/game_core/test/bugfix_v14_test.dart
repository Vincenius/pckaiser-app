import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Rules v14 round: debt-free conquest shares, the `SettlementTakeAll`
/// shortcut, the espionage rebalance (success scales with agents), spied
/// unit positions in intel reports — and a verification of the
/// assassination → extinction → inheritance chain.
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
    // Human-vs-human wars are blocked in V1: slot 2 plays AI-controlled.
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
    expect(state.map.realmNeighbors(1), contains(2));
  });

  /// First slot-2 tile bordering slot 1 (the bridge tile from setUp).
  (int, int) bridgeTile(GameState s) {
    final map = s.map;
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != 2) continue;
        for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
          if (map.inBounds(x + dx, y + dy) &&
              map.ownerAt(x + dx, y + dy) == 1) {
            return (x, y);
          }
        }
      }
    }
    fail('no slot-2 tile borders slot 1');
  }

  group('debt-free conquest (rules v14)', () {
    test('conquering a tile of an indebted realm transfers no treasury', () {
      final (x, y) = bridgeTile(state);
      // Give the tile a treasury-sharing building (Dorf, t1 = 2).
      state.map.building[state.map.index(x, y)] = Building.dorf;
      state.realm(2).tileCount[Building.none]--;
      state.realm(2).tileCount[Building.dorf]++;
      state.realm(2).treasury = -8000;
      state.realm(1).treasury = 1000;

      transferTile(state, x, y, 1, []);

      expect(state.realm(1).treasury, 1000,
          reason: 'the winner must never inherit debt');
      expect(state.realm(2).treasury, -8000,
          reason: 'conquest must not relieve the loser of debt either');
      expect(state.map.ownerAt(x, y), 1);
    });
  });

  group('SettlementTakeAll (rules v14)', () {
    /// Declares war (slot 1 → slot 2) and reaches the claim settlement via
    /// the WINTER score victory (capital capture no longer opens a
    /// settlement — since 2026-07-10 it takes the whole realm, §11.2).
    GameState winterSettlement(GameState from) {
      var s = applyAction(
              from, DeclareWar(slot: 1, targetSlot: 2), Rng(from.rngSeed))
          .state;
      final enemyTown = s.realm(2).towns.single;
      final troop = s.realm(1).troops.single;
      troop.x = enemyTown.x;
      troop.y = enemyTown.y;
      s.activeWar!.round = 21;
      return applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
    }

    test('annexes every affordable bordering tile and ends the war', () {
      var s = winterSettlement(state);
      expect(s.activeWar!.phase, WarPhase.settlement);
      final (bx, by) = bridgeTile(s);
      // Grow a small annexable cluster around the bridge tile.
      final map = s.map;
      final cluster = <(int, int)>[(bx, by)];
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        final x = bx + dx;
        final y = by + dy;
        if (map.inBounds(x, y) &&
            map.ownerAt(x, y) == World.niemand &&
            !map.isWaterAt(x, y)) {
          map.owner[map.index(x, y)] = 2;
          s.realm(2).tileCount[Building.none]++;
          cluster.add((x, y));
        }
      }
      expect(cluster.length, greaterThan(1));
      s.activeWar!.remainingClaim = 1000000; // covers everything

      s = applyAction(s, SettlementTakeAll(slot: 1), Rng(s.rngSeed)).state;

      expect(s.activeWar, isNull, reason: 'take-all finishes the war');
      for (final (x, y) in cluster) {
        expect(s.map.ownerAt(x, y), 1,
            reason: 'every reachable loser tile was annexed');
      }
      // The greedy sweep is complete: no loser tile borders slot 1 land.
      for (var y = 0; y < s.map.height; y++) {
        for (var x = 0; x < s.map.width; x++) {
          if (s.map.ownerAt(x, y) != 2) continue;
          for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
            if (s.map.inBounds(x + dx, y + dy)) {
              expect(s.map.ownerAt(x + dx, y + dy), isNot(1));
            }
          }
        }
      }
    });

    test('only the settlement winner may take all', () {
      final s = winterSettlement(state);
      expect(s.activeWar!.phase, WarPhase.settlement);
      expect(() => applyAction(s, SettlementTakeAll(slot: 2), Rng(s.rngSeed)),
          throwsA(isA<ActionException>()));
    });
  });

  group('espionage rebalance', () {
    int successes(int agents, int guards, int trials) {
      var count = 0;
      for (var i = 0; i < trials; i++) {
        final s = GameState.fromJson(state.toJson());
        s.realm(2).guardLevel = guards;
        final events = runMilitaryMission(
            s, s.realm(1), s.realm(2), agents, Rng(1000 + i));
        if (events.any((e) => e.type == 'intelGathered')) count++;
      }
      return count;
    }

    test('military intel with a full mission usually succeeds', () {
      // 30 agents vs a fully guarded target (the rich-AI case that used
      // to fail ~90% of the time before the rebalance).
      final full = successes(30, 50, 100);
      expect(full, greaterThan(60),
          reason: 'a 6000 T mission should usually succeed');
    });

    test('few agents stay risky', () {
      final few = successes(3, 30, 100);
      expect(few, lessThan(70),
          reason: 'a token mission must not be a sure thing');
    });

    test('a successful military report carries unit positions', () {
      var report = <String, int>{};
      for (var i = 0; i < 50 && report.isEmpty; i++) {
        final s = GameState.fromJson(state.toJson());
        final events =
            runMilitaryMission(s, s.realm(1), s.realm(2), 30, Rng(2000 + i));
        if (events.any((e) => e.type == 'intelGathered')) {
          report = s.realm(1).intelReports.last.values;
        }
      }
      expect(report, isNotEmpty);
      final troop = state.realm(2).troops.single;
      expect(report['unitCount'], 1);
      expect(report['unit0X'], troop.x);
      expect(report['unit0Y'], troop.y);
      expect(report['unit0Class'], troop.troopClass);
    });
  });

  group('assassination → extinction → inheritance', () {
    test('with an heir, the realm stays in the family', () {
      final ruler = state.person(state.realm(2).rulerId)!;
      // Give the ruler a child in the same dynasty.
      final child = Person(
        id: 9999,
        name: 'Erbin',
        gender: 1,
        age: 10,
        dynasty: 2,
      );
      state.persons[child.id] = child;
      state.dynasty(2).memberIds.add(child.id);
      ruler.childrenIds.add(child.id);

      final events = <GameEvent>[];
      handleDeath(state, ruler, Rng(1), events);

      expect(state.realm(2).rulerId, child.id);
      expect(events.any((e) => e.type == 'succession'), isTrue);
    });

    test('a wiped-out royal house passes to a random living ruler', () {
      final ruler = state.person(state.realm(2).rulerId)!;
      expect(state.dynasty(2).memberIds, [ruler.id],
          reason: 'precondition: the founder is the sole member');

      final events = <GameEvent>[];
      handleDeath(state, ruler, Rng(1), events);

      expect(events.any((e) => e.type == 'dynastyExtinct'), isTrue);
      final inheritor = state.realm(2).rulerId;
      expect(inheritor, isNotNull,
          reason: 'the realm is inherited, never left vacant');
      expect(state.persons[inheritor], isNotNull);
      expect(state.persons[inheritor]!.dynasty, isNot(2));
      // Control follows the new ruler (alignSlotControl).
      expect(state.dynasty(2).status,
          state.dynasty(state.persons[inheritor]!.dynasty).status);
    });
  });
}
