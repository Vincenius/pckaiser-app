import 'dart:math' as math;

import '../rng/rng.dart';
import '../state/realm.dart';
import '../state/troop.dart';

/// Per-man combat power (§10.1) for a class/quality pair: `(3 × class +
/// quality) / 10`. The ONE formula behind [powerPerMan]/[troopStrength]
/// and every client-side strength preview (recruit/retrain sheets).
double powerPerManOf(int troopClass, int quality) =>
    (3 * troopClass + quality) / 10;

/// Per-man combat power of an existing unit (§10.1).
double powerPerMan(Troop troop) =>
    powerPerManOf(troop.troopClass, troop.quality);

/// A unit's total combat strength.
double troopStrength(Troop troop) => troop.men * powerPerMan(troop);

/// Rounded strength of a hypothetical unit — the preview the recruit and
/// retrain sheets show before the unit exists.
int previewTroopStrength(int men, int troopClass, int quality) =>
    (men * powerPerManOf(troopClass, quality)).round();

/// Price of one regular recruit (§10.1) — the base of the recruit,
/// reinforce, retrain and drill costs.
const int recruitCostPerMan = 5;

/// Price of one Söldner (§10.3): hired abroad at 10× the levy price,
/// exempt from quarters and the levy limit.
const int soeldnerCostPerMan = 50;

/// Cost of raising [men] fresh regulars of [troopClass] (§10.1).
int recruitCost(int men, int troopClass) =>
    recruitCostPerMan * men + classSurcharge(troopClass);

/// Cost of hiring [men] Söldner (§10.3).
int soeldnerCost(int men) => soeldnerCostPerMan * men;

/// Cost of reinforcing [troop] with [men]: levy price for regulars,
/// Söldner price for a mercenary unit (identified by NOT being
/// garrison-counted — never by quality, which a drilled regular shares).
int reinforceCost(Troop troop, int men) =>
    troop.garrisonCounted ? recruitCostPerMan * men : soeldnerCostPerMan * men;

/// Cost of one drill step for [troop] (§10.2 `[DESIGNED]`): scales with
/// the current level — `5 × men × quality`.
int drillCost(Troop troop) => recruitCostPerMan * troop.men * troop.quality;

/// Cost of retraining [troop] to [troopClass]: 5 T/man plus the class
/// surcharge.
int retrainCost(Troop troop, int troopClass) =>
    recruitCostPerMan * troop.men + classSurcharge(troopClass);

/// Whether two units may be merged (§10.2 bookkeeping): class, quality AND
/// garrison accounting must match — quality alone cannot tell a twice-
/// drilled regular (quartered, wage via armySize) from a Söldner
/// (quality 3, unquartered, wage via soeldnerMen); absorbing one into the
/// other corrupts the garrison and wage bookkeeping for good. The ONE
/// predicate shared by the action gate and the client's merge picker.
bool canMergeTroops(Troop a, Troop b) =>
    a.troopClass == b.troopClass &&
    a.quality == b.quality &&
    a.garrisonCounted == b.garrisonCounted;

/// `[DESIGNED 2026-07-14, user report]` Per-turn levy limit for REGULAR
/// recruits: at most 10% of the population (min. 100 men) can be levied
/// per year — men come from the people, not from thin air. The original
/// had no per-turn cap, so a gold-rich late-game realm (human or AI —
/// especially the schwer AI's planned recruiting) could raise thousands
/// of men in a single turn, which read as cheating and made war losses
/// meaningless. Söldner are exempt: hired abroad, at 10× the price.
int levyLimit(Realm realm) => math.max(100, realm.population ~/ 10);

/// Regulars this year's levy still allows — the ONE definition shared by
/// the action gate, the AI's pacing and the client's sliders/labels.
int levyLeft(Realm realm) =>
    math.max(0, levyLimit(realm) - realm.recruitedThisTurn);

/// One-time surcharge on creating a regular unit of this class (§10.1):
/// Kavallerie +500, Artillerie +1,000.
int classSurcharge(int troopClass) => switch (troopClass) {
      TroopClass.kavallerie => 500,
      TroopClass.artillerie => 1000,
      _ => 0,
    };

/// §10.2: quarter [men] recruits across the realm's towns proportionally
/// to free capacity (capacity − garrison), leftovers one by one to random
/// towns. Caller must have checked `armySize + men ≤ troopCapacity`.
void quarterRecruits(Realm realm, int men, Rng rng) {
  final free = [
    for (final town in realm.towns)
      math.max(0, town.troopCapacity - town.garrison),
  ];
  final totalFree = free.fold(0, (a, b) => a + b);
  if (totalFree <= 0 || men <= 0) return;

  var assigned = 0;
  for (var i = 0; i < realm.towns.length; i++) {
    final share = men * free[i] ~/ totalFree;
    realm.towns[i].garrison += share;
    assigned += share;
  }
  // Leftovers one-by-one to random towns with free capacity.
  var guard = 0;
  while (assigned < men && guard++ < 10000) {
    final i = rng.nextInt(realm.towns.length);
    final town = realm.towns[i];
    if (town.garrison < town.troopCapacity) {
      town.garrison++;
      assigned++;
    }
  }
}

/// Removes a disbanded/destroyed garrison-counted unit's men from the
/// town garrisons (§10.2 bookkeeping; `armySize` is derived from the
/// units themselves).
void releaseGarrison(Realm realm, int men) {
  var left = men;
  for (final town in realm.towns) {
    if (left == 0) break;
    final cut = math.min(town.garrison, left);
    town.garrison -= cut;
    left -= cut;
  }
}
