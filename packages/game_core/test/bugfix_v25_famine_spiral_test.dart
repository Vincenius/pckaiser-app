import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Regression for the offline report: a large, steadily-growing realm
/// starved "out of nowhere", lost ~a third of its population and thousands
/// of troops per turn to desertion, then was conquered by an AI WITHOUT a
/// fought battle. Three guards now break that cascade:
///  - famine growth is floored so one bad harvest can't erase a third of the
///    realm ([famineGrowthFloor]);
///  - desertion is capped and a home guard always survives
///    ([famineDesertionCapPercent], [famineArmyFloor]) — so a starving realm
///    is never left defenceless and a war is always fought, not walked over.
GameState _game() => startGame(
      newGame(GameSetup(
        humans: [
          HumanPlayerSetup(
              founderName: 'Ruth', gender: 1, countrySlot: 1, dorfName: 'Burg'),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 2026,
      )),
      Rng(7),
    ).state;

/// Turns [realm] into a big realm whose few fields cannot feed it, so
/// [runFoodAndPopulation] is guaranteed to hit famine. The single town is a
/// Stadt (top tier) with plenty of headroom so no town promotion/death path
/// touches the map during the test.
void _starve(Realm realm, {required int population, required int army}) {
  final town = realm.towns.single;
  town.buildingType = Building.stadt;
  town.population = population;
  town.troopCapacity = population;
  town.garrison = army;
  realm.population = population;
  realm.troopCapacity = population;
  for (var i = 0; i < realm.tileCount.length; i++) {
    realm.tileCount[i] = 0;
  }
  realm.tileCount[Building.stadt] = 1;
  realm.tileCount[Building.kornfeld] = 10; // far too few for the population
  realm.grainHarvest = 0;
  realm.livestockHarvest = 0;
  realm.troops
    ..clear()
    ..add(Troop(
      name: 'Heer',
      men: army,
      troopClass: TroopClass.infanterie,
      quality: TroopQuality.regular,
      garrisonCounted: true,
      x: realm.capitalX,
      y: realm.capitalY,
    ));
}

void main() {
  group('famine no longer spirals into an unrecoverable collapse', () {
    test('a single famine turn never erases more than ~12% of the population',
        () {
      final state = _game();
      final realm = state.realm(1);
      _starve(realm, population: 20000, army: 0);

      runFoodAndPopulation(state, realm, Rng(1), <GameEvent>[]);

      expect(realm.population, lessThan(20000), reason: 'famine did strike');
      // Floor is -10 growth → pop × -10/82 ≈ -12.2%. Well short of the old
      // ~-37% cliff. Allow a little slack for rounding.
      expect(realm.population, greaterThan((20000 * 0.86).round()),
          reason: 'the loss must be gradual and recoverable, not a cliff');
    });

    test('desertion is capped and never drops the army below the home guard',
        () {
      final state = _game();
      final realm = state.realm(1);
      _starve(realm, population: 20000, army: 4000);

      runFoodAndPopulation(state, realm, Rng(1), <GameEvent>[]);

      expect(realm.armySize, greaterThan(0), reason: 'never a total wipe');
      // At most a quarter deserts in one turn.
      expect(realm.armySize, greaterThanOrEqualTo(3000));
      expect(realm.armySize, greaterThanOrEqualTo(famineArmyFloor));
    });

    test('a small army under the home-guard floor does not desert at all', () {
      final state = _game();
      final realm = state.realm(1);
      _starve(realm, population: 20000, army: famineArmyFloor - 10);

      runFoodAndPopulation(state, realm, Rng(1), <GameEvent>[]);

      expect(realm.armySize, famineArmyFloor - 10,
          reason: 'the last home guard is protected from famine');
    });
  });

  group('growth is coupled to the food ceiling (no overshoot)', () {
    // A realm with [kornfeld] fields, a single Stadt of [population], and a
    // huge harvest STOCK — the stock alone would drive the surplus positive
    // and grow the population well past what the fields can feed.
    void setup(Realm realm, {required int population, required int kornfeld}) {
      final town = realm.towns.single;
      town.buildingType = Building.stadt;
      town.population = population;
      town.troopCapacity = population;
      town.garrison = 0;
      realm.population = population;
      realm.troopCapacity = population;
      realm.troops.clear();
      for (var i = 0; i < realm.tileCount.length; i++) {
        realm.tileCount[i] = 0;
      }
      realm.tileCount[Building.stadt] = 1;
      realm.tileCount[Building.kornfeld] = kornfeld;
      realm.grainHarvest = 1000000; // a big buffer that would fuel overshoot
      realm.livestockHarvest = 0;
    }

    test('a huge harvest stock cannot grow population past the food ceiling',
        () {
      final state = _game();
      final realm = state.realm(1);
      // Only 5 fields (feed ≲ 340) for a 5000-strong population: the fields
      // are already far short, but the huge STOCK keeps the surplus positive.
      // Pre-coupling this fuelled a +10% overshoot (≈ +610) straight into the
      // next turn's famine; now growth is held at 0 because the fields can't
      // feed a single extra mouth.
      setup(realm, population: 5000, kornfeld: 5);

      final report = runFoodAndPopulation(state, realm, Rng(3), <GameEvent>[]);
      final foodCeiling = report.grainYield + report.livestockYield;

      expect(foodCeiling, lessThan(5000), reason: 'fields cannot feed the pop');
      expect(realm.population, 5000,
          reason: 'over the ceiling: growth is held, not overshooting');
    });

    test('a realm well below its food ceiling still grows normally', () {
      final state = _game();
      final realm = state.realm(1);
      // 40 fields feed ~2000; a population of 200 is far below the ceiling, so
      // the cap must not bite — normal (up to +10%) growth applies.
      setup(realm, population: 200, kornfeld: 40);

      runFoodAndPopulation(state, realm, Rng(3), <GameEvent>[]);

      expect(realm.population, greaterThan(200),
          reason: 'plenty of food headroom — growth is unhindered');
    });
  });
}
