import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// 2026-07-14 balancing (user reports):
///  - per-turn levy limit (10% of population, min. 100) paces every
///    army buildup — the "impossibly fast" late-game AI armies were legal
///    but unbounded recruiting from a huge treasury;
///  - food: growth now plateaus at 90% of the EXPECTED yield so a real
///    harvest stock buffers bad rolls (before: population pinned to a
///    ±25%-noisy ceiling → chronic famine that field-building never cured),
///    and the labour efficiency is continuous (the old e ∈ {1, 2} rounding
///    let MORE fields halve the total yield).
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
  });

  group('per-turn levy limit (§10.2 deviation)', () {
    void arm(Realm realm, {int population = 800}) {
      realm.treasury = 100000;
      realm.towns.single.troopCapacity = 1000;
      realm.troopCapacity = 1000;
      realm.towns.single.population = population;
      realm.population = population;
    }

    test('levyLimit is 10% of the population, floored at 100', () {
      final realm = state.realm(1);
      realm.population = 5000;
      expect(levyLimit(realm), 500);
      realm.population = 300;
      expect(levyLimit(realm), 100);
    });

    test('recruiting beyond the levy throws; Söldner are exempt', () {
      arm(state.realm(1)); // population 800 → levy limit 100
      var s = applyAction(
              state,
              RecruitTroops(
                  slot: 1,
                  men: 100,
                  troopClass: TroopClass.infanterie,
                  name: 'Heer'),
              Rng(state.rngSeed))
          .state;
      expect(s.realm(1).recruitedThisTurn, 100);

      expect(
          () => applyAction(
              s,
              RecruitTroops(
                  slot: 1,
                  men: 1,
                  troopClass: TroopClass.infanterie,
                  name: 'Nachzügler'),
              Rng(s.rngSeed)),
          throwsA(isA<ActionException>()));

      // Söldner are hired abroad — no levy, only gold.
      s = applyAction(s, HireSoeldner(slot: 1, men: 200, name: 'Mietlinge'),
              Rng(s.rngSeed))
          .state;
      expect(s.realm(1).troops.last.men, 200);
      expect(s.realm(1).recruitedThisTurn, 100,
          reason: 'Söldner never count against the levy');
    });

    test('reinforcing regulars counts against the same levy', () {
      arm(state.realm(1));
      var s = applyAction(
              state,
              RecruitTroops(
                  slot: 1,
                  men: 40,
                  troopClass: TroopClass.infanterie,
                  name: 'Heer'),
              Rng(state.rngSeed))
          .state;
      s = applyAction(s, ReinforceTroop(slot: 1, unitIndex: 0, men: 60),
              Rng(s.rngSeed))
          .state;
      expect(s.realm(1).recruitedThisTurn, 100);
      expect(
          () => applyAction(s, ReinforceTroop(slot: 1, unitIndex: 0, men: 1),
              Rng(s.rngSeed)),
          throwsA(isA<ActionException>()));
    });

    test('the schwer AI buildup is paced by the levy', () {
      // Late-game shape: huge treasury and quarters. Before the levy the
      // schwer AI filled to 80% of capacity in ONE turn ("impossibly
      // fast", user report) — now one year raises at most 10% of the
      // population.
      final s = startGame(
              newGame(GameSetup(
                humans: const [],
                reformationYear: 1020,
                ottomanYear: 1040,
                warStartYear: 2000,
                aiDifficulty: AiDifficulty.schwer,
                seed: 2026,
              )),
              Rng(7))
          .state;
      final realm = s.realm(2);
      realm.treasury = 200000;
      realm.towns.single.troopCapacity = 3000;
      realm.troopCapacity = 3000;
      realm.towns.single.population = 4000;
      realm.population = 4000; // levy limit 400/turn
      final before = realm.armySize;
      final after = runAiTurn(s, 2, Rng(11)).state.realm(2);
      expect(after.armySize - before, lessThanOrEqualTo(400),
          reason: 'one turn may levy at most 10% of the population');
      expect(after.armySize - before, greaterThan(0),
          reason: 'the AI still arms, just paced');
    });

    test('the levy resets with the next turn', () {
      arm(state.realm(1));
      var s = applyAction(
              state,
              RecruitTroops(
                  slot: 1,
                  men: 100,
                  troopClass: TroopClass.infanterie,
                  name: 'Heer'),
              Rng(state.rngSeed))
          .state;
      expect(s.realm(1).recruitedThisTurn, 100);

      // Complete turns until control wraps back to slot 1: a fresh year,
      // a fresh levy.
      var guard = 0;
      do {
        s = completeTurn(s, Rng(s.rngSeed)).state;
      } while (s.currentPlayer != 1 && ++guard < 100);
      expect(s.currentPlayer, 1, reason: 'control must wrap back to slot 1');
      expect(s.realm(1).recruitedThisTurn, 0);
    });
  });

  group('food: plateau with a real stock buffer (§8 revision)', () {
    /// Puts realm 1 into a controlled farm economy: [population] people
    /// (100 of them under arms), [kornfelder]/[weiden] fields added.
    Realm farmRealm(GameState s,
        {required int population, required int kornfelder, int weiden = 2}) {
      final realm = s.realm(1);
      final town = realm.towns.single;
      town.population = population;
      realm.population = population;
      town.troopCapacity = 200;
      realm.troopCapacity = 200;
      town.garrison = 100;
      realm.armySize = 100;
      realm.troops.add(Troop(
        name: 'Heer',
        men: 100,
        troopClass: TroopClass.infanterie,
        quality: TroopQuality.regular,
        garrisonCounted: true,
        x: realm.capitalX,
        y: realm.capitalY,
      ));
      realm.tileCount[Building.kornfeld] += kornfelder;
      realm.tileCount[Building.weide] += weiden;
      realm.grainHarvest = 0;
      realm.livestockHarvest = 0;
      return realm;
    }

    test('a realm at its food plateau does not famine-trickle', () {
      final realm =
          farmRealm(state, population: 1200, kornfelder: 30, weiden: 10);
      final rng = Rng(42);
      var famineTotal = 0;
      for (var turn = 0; turn < 40; turn++) {
        final report = runFoodAndPopulation(state, realm, rng, <GameEvent>[]);
        // Give the ramp-up 8 turns to settle onto the plateau, then the
        // ±25% harvest noise must be absorbed by the stock — no more
        // "constant troop losses to Nahrungsmangel".
        if (turn >= 8) famineTotal += report.famineLoss;
      }
      expect(famineTotal, 0,
          reason: 'the stock buffer absorbs bad harvest rolls');
      expect(realm.armySize, 100, reason: 'no soldiers deserted');
      expect(realm.grainHarvest + realm.livestockHarvest, greaterThan(0),
          reason: 'a real surplus stock accumulates');
      // Spoilage: the stock never exceeds two years' worth of food.
      expect(realm.grainHarvest + realm.livestockHarvest,
          lessThanOrEqualTo(2 * realm.population));
    });

    test('building more fields raises the plateau instead of hurting', () {
      final few = state.copy();
      final many = state.copy();
      final realmFew = farmRealm(few, population: 800, kornfelder: 15);
      final realmMany = farmRealm(many, population: 800, kornfelder: 40);
      final rngFew = Rng(42);
      final rngMany = Rng(42);
      var famineTotal = 0;
      for (var turn = 0; turn < 30; turn++) {
        famineTotal +=
            runFoodAndPopulation(few, realmFew, rngFew, <GameEvent>[])
                .famineLoss;
        famineTotal +=
            runFoodAndPopulation(many, realmMany, rngMany, <GameEvent>[])
                .famineLoss;
      }
      expect(famineTotal, 0);
      expect(realmMany.population, greaterThan(realmFew.population),
          reason: 'more fields → a higher sustainable population');
    });

    test('the labour-efficiency cliff is gone: one more field never '
        'halves the yield', () {
      // 300 free workers on 20 fields sat exactly on the old e = 2/e = 1
      // rounding boundary — the 21st field used to HALVE every field's
      // output. With the continuous multiplier the yield stays put.
      final a = state.copy();
      final b = state.copy();
      final realmA = farmRealm(a, population: 400, kornfelder: 0, weiden: 0);
      final realmB = farmRealm(b, population: 400, kornfelder: 0, weiden: 0);
      realmA.tileCount[Building.kornfeld] = 20;
      realmA.tileCount[Building.weide] = 0;
      realmB.tileCount[Building.kornfeld] = 21;
      realmB.tileCount[Building.weide] = 0;
      final reportA =
          runFoodAndPopulation(a, realmA, Rng(5), <GameEvent>[]);
      final reportB =
          runFoodAndPopulation(b, realmB, Rng(5), <GameEvent>[]);
      expect(reportB.grainYield,
          greaterThanOrEqualTo((reportA.grainYield * 0.9).floor()),
          reason: 'the 21st field must not halve the harvest');
    });
  });
}
