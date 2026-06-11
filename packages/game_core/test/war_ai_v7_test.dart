/// Rules v7 tests: the drilling action ("Truppe ausbilden", +1 quality
/// for 5 T/man) and the war AI defender that fights back.
library;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  late GameState state;

  setUp(() {
    state = startGame(
        newGame(GameSetup(
          humans: [
            HumanPlayerSetup(
                founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'A'),
            HumanPlayerSetup(
                founderName: 'Berta', gender: 1, countrySlot: 2, dorfName: 'B'),
          ],
          reformationYear: 1020,
          ottomanYear: 1040,
          seed: 2026,
        )),
        Rng(7)).state;
    state.year = 1010;
    state.dynasty(2).status = DynastyStatus.ai;
    state.dynasty(2).humanPlayer = null;
    for (final slot in [1, 2]) {
      final realm = state.realm(slot);
      realm.treasury = 10000;
      realm.towns.single.troopCapacity = 200;
      realm.troopCapacity = 200;
      state = applyAction(
          state,
          RecruitTroops(
              slot: slot,
              men: 50,
              troopClass: TroopClass.infanterie,
              name: 'Heer$slot'),
          Rng(state.rngSeed)).state;
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

  group('DrillTroop (rules v7)', () {
    test('+1 quality for 5 T/man, repeatable within a turn since v8', () {
      final before = state.realm(1).treasury;
      var s = applyAction(
              state, DrillTroop(slot: 1, unitIndex: 0), Rng(state.rngSeed))
          .state;
      final troop = s.realm(1).troops.single;
      expect(troop.quality, TroopQuality.regular + 1);
      expect(troop.troopClass, TroopClass.infanterie, reason: 'no class change');
      expect(s.realm(1).treasury, before - 5 * 50);
      expect(troop.drilledThisTurn, isTrue);

      // v7 pinned the drill to once per unit per turn; v8 lifted it.
      final v7 = GameState.fromJson(s.toJson()..['rulesVersion'] = 7);
      expect(
        () => applyAction(v7, DrillTroop(slot: 1, unitIndex: 0), Rng(1)),
        throwsA(isA<ActionException>()),
        reason: 'v7: once per unit per turn',
      );
      s = applyAction(s, DrillTroop(slot: 1, unitIndex: 0), Rng(1)).state;
      expect(s.realm(1).troops.single.quality, TroopQuality.regular + 2,
          reason: 'v8: no per-turn limit');
    });

    test('drilling raises combat strength', () {
      final undrilled = troopStrength(state.realm(1).troops.single);
      final s = applyAction(
              state, DrillTroop(slot: 1, unitIndex: 0), Rng(state.rngSeed))
          .state;
      expect(troopStrength(s.realm(1).troops.single), greaterThan(undrilled));
    });

    test('rejects Söldner, the quality cap, at-war and pre-v7 games', () {
      var s = applyAction(
              state, HireSoeldner(slot: 1, men: 10, name: 'Mietlinge'),
              Rng(state.rngSeed))
          .state;
      expect(
        () => applyAction(s, DrillTroop(slot: 1, unitIndex: 1), Rng(1)),
        throwsA(isA<ActionException>()),
        reason: 'Söldner cannot drill',
      );

      state.realm(1).troops.single.quality = Troop.drillCap;
      expect(
        () => applyAction(state, DrillTroop(slot: 1, unitIndex: 0), Rng(1)),
        throwsA(isA<ActionException>()),
        reason: 'quality cap reached',
      );
      state.realm(1).troops.single.quality = TroopQuality.regular;

      s = applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
              Rng(state.rngSeed))
          .state;
      expect(
        () => applyAction(s, DrillTroop(slot: 1, unitIndex: 0), Rng(1)),
        throwsA(isA<ActionException>()),
        reason: 'not while at war',
      );

      final old = GameState.fromJson(state.toJson()..['rulesVersion'] = 6);
      expect(
        () => applyAction(old, DrillTroop(slot: 1, unitIndex: 0), Rng(1)),
        throwsA(isA<ActionException>()),
        reason: 'pre-v7 games play without drilling',
      );
    });

    test('a drilled unit can still be retrained to another class', () {
      var s = applyAction(
              state, DrillTroop(slot: 1, unitIndex: 0), Rng(state.rngSeed))
          .state;
      s = applyAction(
              s,
              TrainTroop(
                  slot: 1,
                  unitIndex: 0,
                  troopClass: TroopClass.kavallerie),
              Rng(1))
          .state;
      final troop = s.realm(1).troops.single;
      expect(troop.troopClass, TroopClass.kavallerie);
      expect(troop.quality, TroopQuality.regular + 1,
          reason: 'drilled quality survives the retrain');
    });

    test('drill flag and quality round-trip through JSON', () {
      final s = applyAction(
              state, DrillTroop(slot: 1, unitIndex: 0), Rng(state.rngSeed))
          .state;
      final loaded = GameState.fromJson(s.toJson());
      expect(loaded.realm(1).troops.single.quality, TroopQuality.regular + 1);
      expect(loaded.realm(1).troops.single.drilledThisTurn, isTrue);
      // Old saves without the field default to false.
      final json = s.toJson();
      for (final t
          in ((json['realms'] as List)[0] as Map)['troops'] as List) {
        (t as Map).remove('drilledThisTurn');
      }
      expect(GameState.fromJson(json).realm(1).troops.single.drilledThisTurn,
          isFalse);
    });
  });

  group('war AI defender (rules v7)', () {
    int distanceToCapital(Troop t, Realm target) =>
        (t.x - target.capitalX).abs() + (t.y - target.capitalY).abs();

    test('counter-marches on the enemy capital once the attacker army is '
        'wiped out', () {
      state = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      // The human attacker's army is annihilated.
      state.realm(1).troops.clear();
      state.activeWar!.movesLeft[1] = [];

      final defender = state.realm(2);
      final before = distanceToCapital(defender.troops.single, state.realm(1));
      final events = <GameEvent>[];
      runAiWarMovement(state, 2, Rng(99), events);

      if (state.activeWar == null) {
        // Marched all the way: ruler captured.
        expect(events.any((e) => e.type == 'rulerCaptured'), isTrue);
      } else {
        final after =
            distanceToCapital(defender.troops.single, state.realm(1));
        expect(after, lessThan(before),
            reason: 'the defender must advance on the enemy capital');
      }
    });

    test('intercepts an intruder standing on own territory', () {
      state = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      // Teleport the attacker onto a defender-owned tile (test shortcut).
      final map = state.map;
      final intruder = state.realm(1).troops.single;
      outer:
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) == 2 && map.isLandAt(x, y)) {
            intruder.x = x;
            intruder.y = y;
            break outer;
          }
        }
      }

      final defender = state.realm(2).troops.single;
      final before = (defender.x - intruder.x).abs() +
          (defender.y - intruder.y).abs();
      final events = <GameEvent>[];
      runAiWarMovement(state, 2, Rng(99), events);

      final fought = events.any((e) => e.type == 'battle');
      if (!fought) {
        final troops = state.realm(2).troops;
        expect(troops, isNotEmpty);
        final after = (troops.first.x - intruder.x).abs() +
            (troops.first.y - intruder.y).abs();
        expect(after, lessThan(before),
            reason: 'the defender must close in on the intruder');
      }
    });

    test('pre-v7 defenders keep the original stay-home behavior', () {
      final old = GameState.fromJson(state.toJson()..['rulesVersion'] = 6);
      var s = applyAction(
              old, DeclareWar(slot: 1, targetSlot: 2), Rng(old.rngSeed))
          .state;
      s.realm(1).troops.clear();
      s.activeWar!.movesLeft[1] = [];

      final positions = [
        for (final t in s.realm(2).troops) (t.x, t.y),
      ];
      runAiWarMovement(s, 2, Rng(99), <GameEvent>[]);
      expect([for (final t in s.realm(2).troops) (t.x, t.y)], positions,
          reason: 'old games: the defender never leaves home');
    });
  });
}
