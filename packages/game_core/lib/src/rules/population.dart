import 'dart:math' as math;

import '../rng/rng.dart';
import '../state/constants.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/realm.dart';
import '../state/town.dart';

/// Largest popularity change the §8.4 food-satisfaction step may apply in a
/// single turn (before the ±3 balance nudge), keeping the mood legible — no
/// surprise swings — and well under the "lose >30 at once" threshold players
/// complained about. [DESIGNED.]
const int foodSatisfactionStepCap = 8;

/// `[DESIGNED]` Famine floor: the worst single-turn growth §8.2 may apply.
/// The original clamped the surplus percent to −30 and then rolled a growth
/// ∈ [−30, −1], so one bad harvest could erase a THIRD of the realm in a
/// single turn (`pop × −30/82 ≈ −37 %`) — an unrecoverable cliff that wiped
/// large realms "out of nowhere". We floor the famine growth so a starving
/// realm shrinks GRADUALLY (≈ −12 %/turn worst case), giving several clearly
/// warned turns to build fields before real damage — recovery stays possible.
/// (The surplus percent itself is still clamped to −30 for the §8.4
/// popularity update, so the mood still reflects a full-blown famine.)
const int famineGrowthFloor = -10;

/// `[DESIGNED]` Famine thins the army but never annihilates it in one turn:
/// at most this share of the standing army may desert to hunger per turn.
const int famineDesertionCapPercent = 25;

/// `[DESIGNED]` … and a small home guard always survives a famine, so a
/// starving realm is never left utterly defenceless. Players kept losing
/// their whole realm without a battle: famine wiped the army, then any AI
/// walked onto the undefended capital. A guaranteed remnant means a war is
/// always FOUGHT, never a walkover.
const int famineArmyFloor = 100;

/// §8.1 harvest rolls: `base + rng.nextInt(span)` per field, × efficiency
/// (grain 20–34 per Kornfeld, livestock 20–29 per Weide). The means below
/// are DERIVED from these so the growth ceiling can never silently desync
/// from a retuned roll.
const int grainYieldBase = 20;
const int grainYieldSpan = 15;
const int livestockYieldBase = 20;
const int livestockYieldSpan = 10;
const double grainYieldMean = grainYieldBase + (grainYieldSpan - 1) / 2;
const double livestockYieldMean =
    livestockYieldBase + (livestockYieldSpan - 1) / 2;

/// `[DESIGNED 2026-07-14]` Growth plateaus at this share of the EXPECTED
/// yield — the remaining margin accumulates as the harvest stock that
/// buffers bad rolls (the famine-trickle fix, see the growth block).
const double foodCeilingMargin = 0.9;

/// `[DESIGNED 2026-07-14]` Spoilage: the stores keep at most this many
/// years' worth of food (1 food per inhabitant per year).
const int storeCapYears = 2;

/// What the food/population upkeep did this turn (§8) — feeds the §21.1
/// status report.
class FoodReport {
  int grainYield = 0;
  int livestockYield = 0;
  int surplusPercent = 0;
  int populationDelta = 0;
  int famineLoss = 0;
}

/// `[DESIGNED 2026-08-08, user feedback]` The highest popularity a realm's
/// mood may RECOVER to while its wars pile up — 100 minus one
/// [warWearinessCeilingStep] per war started without the peace years to
/// work it off, never below [warWearinessCeilingFloor]. See those constants
/// for the why. Read by the §8.4 food-satisfaction step and the balance
/// nudge (the only two places popularity climbs on its own).
int warWearinessCeiling(Realm realm) => math.max(
    warWearinessCeilingFloor, 100 - warWearinessCeilingStep * realm.recentWars);

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

  // §8.1 Food production. [DEVIATION 2026-07-14, user report] The original
  // rounded the labour efficiency to a whole factor (e ∈ {1, 2}), so
  // crossing the (pop − army) = 15 × fields boundary — by building MORE
  // fields, or by recruiting — HALVED every field's output in one step:
  // exactly the "I keep building fields and it gets worse" trap. The
  // multiplier is continuous now; extra fields and levies dilute the
  // workforce smoothly instead of cliffing.
  // War-devastated fields (2026-07-19) lie fallow: they keep owner and
  // building — titles, settlement values and the map are untouched — but
  // yield nothing until they recover (`WorldMap.devastatedUntil`).
  var devastatedGrain = 0;
  var devastatedLivestock = 0;
  final map = state.map;
  for (var i = 0; i < map.terrain.length; i++) {
    // Cheapest reject first: almost every tile is intact (0 = never
    // devastated), so this one comparison skips the owner/building reads
    // for the whole map in the common no-recent-war case.
    if (map.devastatedUntil[i] <= state.year) continue;
    if (map.owner[i] != realm.slot) continue;
    if (map.building[i] == Building.kornfeld) devastatedGrain++;
    if (map.building[i] == Building.weide) devastatedLivestock++;
  }
  final grainFields = realm.tileCount[Building.kornfeld] - devastatedGrain;
  final livestockFields =
      realm.tileCount[Building.weide] - devastatedLivestock;

  final fields = grainFields + livestockFields;
  var efficiency = 0.0;
  if (fields > 0) {
    efficiency =
        ((realm.population - realm.armySize) / fields / 10).clamp(0.5, 2.0);
    report.grainYield = (efficiency *
            (rng.nextInt(grainYieldSpan) + grainYieldBase) *
            grainFields)
        .round();
    report.livestockYield = (efficiency *
            (rng.nextInt(livestockYieldSpan) + livestockYieldBase) *
            livestockFields)
        .round();
    realm.grainHarvest += report.grainYield;
    realm.livestockHarvest += report.livestockYield;
  }

  // §8.2 Surplus percent, clamped FIRST.
  final stock = realm.grainHarvest + realm.livestockHarvest;
  report.surplusPercent =
      ((stock - realm.population) * 100 ~/ realm.population).clamp(-30, 15);
  final s = report.surplusPercent;

  // §8.4 update 1 — food satisfaction, right after S is computed.
  // [DEVIATION] The original's purely multiplicative step
  // (oldStat * (100 + s) / 82) let a low realm crawl back at ~1 point per
  // turn while a well-fed one ballooned, and it was hard to reason about.
  // We instead nudge popularity toward a food-driven target with a small,
  // bounded, symmetric step: a content realm settles around 50, a fed one
  // climbs and a starving one falls — recovery from a slump is fair and a
  // single harvest never swings the mood violently.
  final oldStat = realm.popularity;
  // Target ∈ [0, 100]: 50 at break-even, → 100 at the +15 surplus cap,
  // → 0 at the −30 famine floor …
  final fed = s >= 0 ? 50 + s * 50 ~/ 15 : 50 + s * 50 ~/ 30;
  // … capped by war weariness: full bellies cannot buy back the goodwill a
  // ruler spends on campaign after campaign. A realm already ABOVE the
  // ceiling drifts down to it through this very step (bounded, a few
  // points a turn) instead of being clamped in one jarring drop.
  final target = math.min(fed, warWearinessCeiling(realm));
  final gap = target - oldStat;
  var step = (gap / 4).round();
  if (step == 0 && gap != 0) step = gap.sign; // always close the last point
  step = step.clamp(-foodSatisfactionStepCap, foodSatisfactionStepCap);
  realm.popularity = (oldStat + step).clamp(0, 100);

  // §8.2 Growth. Floored on the famine side so a single bad harvest can
  // never erase a third of the realm (see [famineGrowthFloor]); the +10%/turn
  // growth cap (DS:[2]) is unchanged.
  var g = s == 0 ? 0 : s.sign * (rng.nextInt(s.abs()) + 1);
  g = g.clamp(famineGrowthFloor, 10);

  // `[DESIGNED]` Couple growth to the food ceiling. Population lives in towns
  // and grows up to +10 %/turn (thousands of people at scale), but each field
  // feeds only ~50 and the player can build just a handful of fields per turn
  // — so a large realm's population inevitably OVERSHOT what its farms (even a
  // fully-built territory) could feed, then crashed into famine "out of
  // nowhere". [REVISED 2026-07-14, user report] Capping growth at THIS turn's
  // rolled yield pinned the population to the top of a ±25 %-noisy ceiling:
  // every low harvest roll dipped below break-even → chronic famine trickle
  // that building more fields could never cure (growth immediately consumed
  // the new headroom). The ceiling is now 90 % of the EXPECTED yield (mean
  // rolls: 27/Kornfeld, 24.5/Weide, × efficiency) — the ~10 % average surplus
  // accumulates as a real harvest STOCK that absorbs bad rolls, so famine is
  // left to real causes: lost fields (war, quake), an army starving its own
  // farms, or selling the food your people needed to eat. Famine shrink
  // (g < 0) is untouched — it still corrects any existing excess.
  if (g > 0) {
    // Devastated fields feed nobody — the ceiling uses the WORKING fields.
    final expectedYield = efficiency *
        (grainYieldMean * grainFields + livestockYieldMean * livestockFields);
    // Also never past what is actually ON HAND this turn (the stock,
    // fresh yield included): with empty stores and a bad roll the
    // population holds instead of growing into next year's famine — the
    // buffer model only protects once a buffer exists.
    final foodCeiling =
        math.min((expectedYield * foodCeilingMargin).floor(), stock);
    final room = foodCeiling - realm.population;
    if (room <= 0) {
      g = 0; // already at or over what the fields can feed — hold steady
    } else {
      // Largest whole-percent growth that keeps population ≤ the food ceiling
      // (delta ≈ population × g / 82, so g ≤ room × 82 / population).
      final maxG = room * 82 ~/ realm.population;
      if (maxG < g) g = maxG;
    }
  }

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

  // §8.2 Famine: soldiers desert/die — but capped, and never below the
  // home-guard floor, so a starving realm keeps a defensive core (a war is
  // always fought, never a walkover). See [famineDesertionCapPercent] /
  // [famineArmyFloor].
  if (totalDelta < 0 && realm.armySize > 0) {
    final raw = (-totalDelta) ~/ 4;
    final fractionCap =
        (realm.armySize * famineDesertionCapPercent / 100).round();
    final aboveGuard = math.max(0, realm.armySize - famineArmyFloor);
    report.famineLoss = math.min(raw, math.min(fractionCap, aboveGuard));
    if (report.famineLoss > 0) removeArmyMen(realm, report.famineLoss);
  }

  // §8.3 Town transitions.
  _runTownTransitions(state, realm, events);

  // §8.4 update 2 — balance nudge, after town growth & famine.
  final grain = realm.grainHarvest;
  final livestock = realm.livestockHarvest;
  final balanced = grain <= 2 * livestock && livestock <= 2 * grain;
  final beforeNudge = realm.popularity;
  realm.popularity += (balanced ? 1 : -1) * (rng.nextInt(3) + 1);
  realm.popularity = realm.popularity.clamp(0, 100);
  // The nudge must not lift a war-weary realm past its ceiling either. A
  // realm already above the ceiling simply keeps what it had (the food step
  // above walks it down); the negative nudge always applies.
  realm.popularity = math.min(
      realm.popularity, math.max(warWearinessCeiling(realm), beforeNudge));

  // Consumption [INTERPRETATION]: each inhabitant eats 1 food per turn
  // (§8.1). The spec implies it through S = stock − population but never
  // states the stock write-back; we consume grain first, then livestock,
  // so the sale screen's "Überschuß" shows what is genuinely left over.
  var toEat = realm.population;
  final grainEaten = math.min(realm.grainHarvest, toEat);
  realm.grainHarvest -= grainEaten;
  toEat -= grainEaten;
  realm.livestockHarvest = math.max(0, realm.livestockHarvest - toEat);

  // [DESIGNED 2026-07-14] Spoilage: the stores keep at most
  // [storeCapYears] years' worth of food. The stock is the famine buffer
  // the growth margin above builds up — without a cap it would accumulate
  // without bound and turn into an infinite grain-gold printer at the
  // market. Windfalls beyond the cap (war loot, a realm merge) survive
  // until this realm's NEXT upkeep — sell them the turn they arrive.
  final maxStore = storeCapYears * realm.population;
  final stored = realm.grainHarvest + realm.livestockHarvest;
  if (stored > maxStore) {
    realm.grainHarvest = realm.grainHarvest * maxStore ~/ stored;
    realm.livestockHarvest = realm.livestockHarvest * maxStore ~/ stored;
  }

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

/// Removes [count] garrisoned men from the realm: town garrisons and
/// garrison-counted troop units shrink together (`armySize` is derived
/// from the units); emptied units are deleted (§8.2, §10.2).
void removeArmyMen(Realm realm, int count) {
  if (count <= 0) return;
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
