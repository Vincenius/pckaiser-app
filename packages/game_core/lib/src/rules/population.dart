import 'dart:math' as math;

import '../rng/rng.dart';
import '../state/constants.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/realm.dart';
import '../state/town.dart';

/// What the food/population upkeep did this turn (§8) — feeds the §21.1
/// status report.
class FoodReport {
  int grainYield = 0;
  int livestockYield = 0;
  int surplusPercent = 0;
  int populationDelta = 0;
  int famineLoss = 0;
}

/// Food production, growth, famine, town transitions and the popularity
/// updates (ORIGINAL_GAME.md §8), in the §6.1/§8.4 order. Mutates [realm]
/// in place; emits town-transition events into [events].
FoodReport runFoodAndPopulation(
    GameState state, Realm realm, Rng rng, List<GameEvent> events) {
  final report = FoodReport();

  // §8.2: a (near-)dead realm skips the whole block.
  if (realm.population <= 1) {
    realm.population = 0;
    for (final town in realm.towns) {
      town.population = 0;
    }
    realm.popularity = 50;
    _runTownTransitions(state, realm, events);
    return report;
  }

  // §8.1 Food production.
  final fields =
      realm.tileCount[Building.kornfeld] + realm.tileCount[Building.weide];
  if (fields > 0) {
    final efficiency =
        ((realm.population - realm.armySize) / fields / 10).clamp(0.5, 2.0);
    final e = efficiency.round(); // ∈ {1, 2}
    report.grainYield =
        e * (rng.nextInt(15) + 20) * realm.tileCount[Building.kornfeld];
    report.livestockYield =
        e * (rng.nextInt(10) + 20) * realm.tileCount[Building.weide];
    realm.grainHarvest += report.grainYield;
    realm.livestockHarvest += report.livestockYield;
  }

  // §8.2 Surplus percent, clamped FIRST.
  final stock = realm.grainHarvest + realm.livestockHarvest;
  report.surplusPercent =
      ((stock - realm.population) * 100 ~/ realm.population).clamp(-30, 15);
  final s = report.surplusPercent;

  // §8.4 update 1 — food satisfaction, right after S is computed.
  final oldStat = realm.popularity;
  realm.popularity = math.min(
    (oldStat * (100 + s) / 82).round(),
    (oldStat * 1.05).round(),
  );

  // §8.2 Growth.
  var g = s == 0 ? 0 : s.sign * (rng.nextInt(s.abs()) + 1);
  g = math.min(g, 10); // global +10%/turn cap (DS:[2])

  var totalDelta = 0;
  for (final town in realm.towns) {
    final delta = (town.population * g / 82).round();
    town.population += delta;
    totalDelta += delta;
    // Capacity follows population at ¼ rate; loss capped at −capacity
    // (Pascal div truncates toward zero, as ~/ does).
    town.troopCapacity = math.max(0, town.troopCapacity + delta ~/ 4);
  }
  realm.population += totalDelta;
  realm.troopCapacity = realm.towns.fold(0, (sum, t) => sum + t.troopCapacity);
  report.populationDelta = totalDelta;

  // §8.2 Famine: soldiers desert/die.
  if (totalDelta < 0) {
    report.famineLoss = math.min((-totalDelta) ~/ 4, realm.armySize);
    removeArmyMen(realm, report.famineLoss);
  }

  // §8.3 Town transitions.
  _runTownTransitions(state, realm, events);

  // §8.4 update 2 — balance nudge, after town growth & famine.
  final grain = realm.grainHarvest;
  final livestock = realm.livestockHarvest;
  final balanced = grain <= 2 * livestock && livestock <= 2 * grain;
  realm.popularity += (balanced ? 1 : -1) * (rng.nextInt(3) + 1);
  realm.popularity = realm.popularity.clamp(0, 100);

  // Consumption [INTERPRETATION]: each inhabitant eats 1 food per turn
  // (§8.1). The spec implies it through S = stock − population but never
  // states the stock write-back; we consume grain first, then livestock,
  // so the sale screen's "Überschuß" shows what is genuinely left over.
  var toEat = realm.population;
  final grainEaten = math.min(realm.grainHarvest, toEat);
  realm.grainHarvest -= grainEaten;
  toEat -= grainEaten;
  realm.livestockHarvest = math.max(0, realm.livestockHarvest - toEat);

  return report;
}

/// §8.3 town transitions: Marktrecht at 500, Stadtrecht at 1000, death
/// below 5 inhabitants (tile reverts to Kornfeld/Weide by terrain).
void _runTownTransitions(GameState state, Realm realm, List<GameEvent> events) {
  final map = state.map;
  for (var i = realm.towns.length - 1; i >= 0; i--) {
    final town = realm.towns[i];

    if (town.population >= 500 && town.buildingType < Building.markt) {
      _setTownBuilding(state, realm, town, Building.markt);
      events.add(GameEvent(
        year: state.year,
        slot: realm.slot,
        type: 'townPromoted',
        visibility: EventVisibility.public,
        payload: {'name': town.name, 'building': Building.markt},
      ));
    }
    if (town.population >= 1000 && town.buildingType < Building.stadt) {
      _setTownBuilding(state, realm, town, Building.stadt);
      events.add(GameEvent(
        year: state.year,
        slot: realm.slot,
        type: 'townPromoted',
        visibility: EventVisibility.public,
        payload: {'name': town.name, 'building': Building.stadt},
      ));
    }

    if (town.population < 5) {
      // Garrison soldiers are removed from the army; the tile reverts.
      realm.armySize = math.max(0, realm.armySize - town.garrison);
      cutGarrisonTroops(realm, town.garrison);
      realm.population -= math.max(0, town.population);
      realm.troopCapacity -= town.troopCapacity;
      final index = map.index(town.x, town.y);
      final reverted = map.terrain[index] == Terrain.berg
          ? Building.weide
          : Building.kornfeld;
      realm.tileCount[town.buildingType]--;
      realm.tileCount[reverted]++;
      map.building[index] = reverted;
      realm.towns.removeAt(i);
      events.add(GameEvent(
        year: state.year,
        slot: realm.slot,
        type: 'townDied',
        visibility: EventVisibility.public,
        payload: {'name': town.name, 'x': town.x, 'y': town.y},
      ));
    }
  }
}

void _setTownBuilding(GameState state, Realm realm, Town town, int building) {
  realm.tileCount[town.buildingType]--;
  realm.tileCount[building]++;
  town.buildingType = building;
  state.map.building[state.map.index(town.x, town.y)] = building;
}

/// Removes [count] garrisoned men from the realm: town garrisons,
/// garrison-counted troop units and `armySize` all shrink together;
/// emptied units are deleted (§8.2, §10.2).
void removeArmyMen(Realm realm, int count) {
  if (count <= 0) return;
  realm.armySize = math.max(0, realm.armySize - count);

  var left = count;
  for (final town in realm.towns) {
    if (left == 0) break;
    final cut = math.min(town.garrison, left);
    town.garrison -= cut;
    left -= cut;
  }

  left = count;
  for (var i = realm.troops.length - 1; i >= 0; i--) {
    if (left == 0) break;
    final troop = realm.troops[i];
    if (!troop.garrisonCounted) continue;
    final cut = math.min(troop.men, left);
    troop.men -= cut;
    left -= cut;
    if (troop.men == 0) realm.troops.removeAt(i);
  }
}

/// §8.3 normalization pass (every round, world phase): clamp every town to
/// `capacity ≤ population` and `garrison ≤ capacity`; excess garrison men
/// are removed from the army.
void normalizeTowns(GameState state) {
  for (final realm in state.realms) {
    for (final town in realm.towns) {
      if (town.troopCapacity > town.population) {
        realm.troopCapacity -= town.troopCapacity - town.population;
        town.troopCapacity = town.population;
      }
      if (town.garrison > town.troopCapacity) {
        final excess = town.garrison - town.troopCapacity;
        town.garrison = town.troopCapacity;
        realm.armySize = math.max(0, realm.armySize - excess);
        cutGarrisonTroops(realm, excess);
      }
    }
  }
}

/// Cuts [count] men from garrison-counted troop units only (the garrisons
/// have already been adjusted by the caller — e.g. the town holding them
/// was destroyed, seized or conquered).
void cutGarrisonTroops(Realm realm, int count) {
  var left = count;
  for (var i = realm.troops.length - 1; i >= 0 && left > 0; i--) {
    final troop = realm.troops[i];
    if (!troop.garrisonCounted) continue;
    final cut = math.min(troop.men, left);
    troop.men -= cut;
    left -= cut;
    if (troop.men == 0) realm.troops.removeAt(i);
  }
}
