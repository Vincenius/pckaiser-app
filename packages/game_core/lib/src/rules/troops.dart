import 'dart:math' as math;

import '../rng/rng.dart';
import '../state/realm.dart';
import '../state/troop.dart';

/// Per-man combat power (§10.1): `(3 × class + quality) / 10`.
double powerPerMan(Troop troop) => (3 * troop.troopClass + troop.quality) / 10;

/// A unit's total combat strength.
double troopStrength(Troop troop) => troop.men * powerPerMan(troop);

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
  realm.armySize += assigned;
}

/// Removes a disbanded/destroyed garrison-counted unit's men from the
/// town garrisons and `armySize` (§10.2 bookkeeping).
void releaseGarrison(Realm realm, int men) {
  realm.armySize = math.max(0, realm.armySize - men);
  var left = men;
  for (final town in realm.towns) {
    if (left == 0) break;
    final cut = math.min(town.garrison, left);
    town.garrison -= cut;
    left -= cut;
  }
}
