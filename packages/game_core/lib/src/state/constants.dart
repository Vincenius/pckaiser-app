/// Shared game constants (ORIGINAL_GAME.md §1, §3, §4).
library;

/// Maximum stored length of a player-chosen name (towns, troops, children,
/// founders, save slots). The single source of truth shared by the client's
/// input fields (which block further typing at this length) and the engine
/// (which defensively clamps every stored name, so no path — online peers,
/// imported saves — can exceed it). Raised from the old hard-coded 20 so
/// longer names are allowed.
const int maxNameLength = 30;

/// Trims a user-entered name and caps it at [maxNameLength]. Returns the
/// empty string for a blank name — callers apply their own default.
String clampName(String raw) {
  final name = raw.trim();
  if (name.length <= maxNameLength) return name;
  var cut = name.substring(0, maxNameLength);
  // Never split a UTF-16 surrogate pair (e.g. an emoji on the boundary) —
  // a lone high surrogate is not a valid string and breaks JSON encoding
  // for strict non-Dart parsers.
  final last = cut.codeUnitAt(cut.length - 1);
  if (last >= 0xD800 && last <= 0xDBFF) {
    cut = cut.substring(0, cut.length - 1);
  }
  return cut;
}

/// Religions (§1).
abstract final class Religion {
  static const int katholisch = 0;
  static const int evangelisch = 1;
  static const int moslemisch = 2;
}

/// Terrain values (§3.1). Water is `2 + landNeighborMask`; all game logic
/// tests "water" as `terrain >= 2`.
abstract final class Terrain {
  static const int ebene = 0;
  static const int berg = 1;
  static const int water = 2;

  static bool isWater(int terrain) => terrain >= water;
  static bool isLand(int terrain) => terrain < water;
}

/// Building type indices on a tile (§4).
abstract final class Building {
  static const int none = 0;
  static const int kornfeld = 1;
  static const int weide = 2;
  static const int dorf = 3;
  static const int markt = 4;
  static const int stadt = 5;
  static const int burg = 6;
  static const int palast = 7;
  static const int hafen = 8;

  /// War-score / worth value per building type (§4); index = building.
  static const List<int> value = [
    0,
    100,
    150,
    1000,
    2500,
    5000,
    5000,
    10000,
    700,
  ];

  /// Build cost in Taler; `null` = cannot be built directly (Markt/Stadt
  /// grow from towns, §8.3).
  static const List<int?> cost = [
    null,
    100,
    150,
    1000,
    null,
    null,
    5000,
    10000,
    700,
  ];

  /// "(S)chiff" colony ship (§4/§9.3) — not a building on a tile: sent
  /// from a Hafen to claim a free land tile across water, consumed on use.
  static const int shipCost = 700;

  /// Seat-eligible buildings (§6.2/§17): a realm's capital must stand on
  /// a Stadt, Burg or Palast. THE one definition shared by the relocate
  /// action, the automatic re-seat, the key-point occupation test and the
  /// client's seat pickers.
  static bool isSeat(int building) =>
      building == stadt || building == burg || building == palast;

  /// Town buildings (§8.3): tiles that carry a `Town` object.
  static bool isTown(int building) =>
      building == dorf || building == markt || building == stadt;
}

/// World dimensions and slot conventions (§2, §3.1).
abstract final class World {
  static const int mapWidth = 80;
  static const int mapHeight = 44;

  /// Realm/dynasty slots are 1–30; 0 = "Niemand" (unowned/vacant sentinel).
  static const int realmCount = 30;
  static const int niemand = 0;

  static const int kurfuerstSeats = 7;
}

/// Popularity (Beliebtheit) tuning [DEVIATION from the original's §4 −70].
///
/// A religion change is a deliberate, high-stakes act, but the original's
/// flat −70 swing was brutal and opaque: a single (often accidental) tap
/// could crater a realm's mood and tip it straight into a §19.1 strife
/// collapse. We charge a smaller penalty AND floor it like every other
/// militarism cost (never below [militarismPopularityFloor]), so the people
/// can be shocked but never revolt purely because of it.
const int religionChangePopularityCost = 25;

/// Militarism popularity costs (levies, conversions) never push a realm
/// below this floor — it sits above the §19.1 strife line (20) plus the
/// ±3 harvest nudge, so routine deliberate actions alone can never tip a
/// realm into collapse. War declarations use the lower
/// [warPopularityFloor] instead.
const int militarismPopularityFloor = 25;

/// `[DESIGNED 2026-08-08, user feedback]` War weariness CEILING. The
/// declaration penalty alone had no lasting bite: the §8.4 food
/// satisfaction pulls a well-fed realm back toward 100 by up to 8 points a
/// turn, so a −5/−10 hit was healed within one or two turns and a ruler
/// who warred every single year never came near the §19.1 strife line.
/// While wars pile up (`Realm.recentWars`) the mood may no longer recover
/// past this ceiling — every war in a row lowers it by
/// [warWearinessCeilingStep], down to [warWearinessCeilingFloor]. It only
/// caps RECOVERY (the food step drifts popularity toward it), so a single
/// campaign costs little and a permanent war economy grinds the people
/// down. Only wars a realm STARTS count — being attacked never does.
const int warWearinessCeilingStep = 10;
const int warWearinessCeilingFloor = 30;

/// `[DESIGNED 2026-08-08, user feedback]` Consecutive war-free years needed
/// to forgive ONE step of war weariness (`Realm.recentWars`, counted in
/// `Realm.peaceYears`). Was one year, which let a ruler alternate war and
/// peace forever at a flat penalty; a serial warmonger must now actually
/// stand down for a while to work off the resentment.
const int wearinessDecayYears = 2;

/// `[DESIGNED 2026-07-06, user feedback]` War declarations bypass the
/// militarism floor down to this bound, BELOW the §19.1 strife line (20):
/// repeated aggression can now realistically drag a warmonger into revolt
/// (the declaration penalty also escalates per war, see `applyDeclareWar`).
/// The floor only guards against a single declaration zeroing the stat.
const int warPopularityFloor = 10;

/// §7.1 tax-rate tuning `[DESIGNED 2026-08-13, user request]`. The tax
/// rate is a percentage of the realm's base tax yield: 100 is the original
/// formula `[pop, 2×pop)` and the DEFAULT — existing games and foreign
/// realms (whose rate is hidden) all read as 100. Raising it collects
/// more Taler but costs popularity; lowering it collects less and wins
/// goodwill. The rate steps in [taxRateStep] increments and is clamped to
/// [taxRateMin]..[taxRateMax] (never below 0).
const int taxRateDefault = 100;
const int taxRateMin = 0;
const int taxRateMax = 200;
const int taxRateStep = 10;

/// The per-turn popularity reaction to a tax rate deviating from the
/// default. GOODWILL (low taxes): every [taxPopularityStep] points of rate
/// below 100 swings the mood +1. The goodwill is WITHHELD while the realm
/// is at war or war-weary (`Realm.recentWars > 0`), so a warring realm's
/// mood keeps sinking even with low taxes.
const int taxPopularityStep = 25;

/// RESENTMENT (high taxes): every [taxPopularityHighStep] points of rate
/// above 100 swings the mood −1. `[DESIGNED 2026-08-13, user request]`
/// deliberately tighter than the goodwill side so heavy taxation grinds
/// popularity down a little faster — at the extreme (−5 per turn at 200 %)
/// it still stays within a single war declaration (−5, escalating) and
/// well under the §8.4 food step cap (±8).
const int taxPopularityHighStep = 20;
