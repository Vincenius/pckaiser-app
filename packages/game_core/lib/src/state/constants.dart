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
/// above 100 swings the mood −1. `[DESIGNED 2026-08-13, user request;
/// tightened again 2026-08-13]` deliberately tighter than the goodwill
/// side so heavy taxation grinds popularity down faster. At the extreme
/// (−10 per turn at 200 %) a maximum-tax realm can no longer ride the
/// §8.4 food step (cap ±8) back to a high mood, so the rate is a real,
/// visible trade-off instead of a rounding error next to the food and
/// balance nudges.
const int taxPopularityHighStep = 10;

/// `[DESIGNED 2026-08-24, user request]` Beliebtheit as the counter-weight
/// to size. Until now popularity was a pure RISK meter: it could kill a
/// realm (§19.1 strife, peasant revolt) but being LOVED bought nothing,
/// while both the action budget and the war machine scaled with realm size.
/// The two constants below give the stat an upside that a big, war-weary
/// realm structurally cannot have — the war-weariness ceiling
/// ([warWearinessCeilingStep]) holds a serial aggressor near 30–50 while a
/// peaceful realm sits at 80–100.
///
/// COMBAT: a unit fights at `1 + (popularity − 50)/50 × bonus` — men who
/// believe in their ruler hold the line. Bonus ONLY above 50: a slump must
/// never weaken the army that has to defend the realm (that spiral —
/// unpopular → beaten → poorer → more unpopular — is exactly the runaway
/// this change fights, only pointed downward). The side HOLDING the
/// contested tile gets the larger share — the defender of the clash, the
/// one being marched upon.
/// Sized against the modifiers already in `resolveCombat` (fortification
/// +15/25 %, Schere-Stein-Papier +15 %, fortune ±25 %) so morale tilts a
/// close fight without ever eclipsing quality and terrain.
const double combatAttackPopularityBonus = 0.12;
const double combatDefencePopularityBonus = 0.20;

/// ZÜGE (§6.3 movement roll — the per-turn action budget that pays for
/// cultivating, claiming, building and steering colony ships, and per unit
/// for a war round): the roll is
/// `max([movementPointsMinimum], popularity ~/ [movementPopularityDivisor])
/// + random(6)`.
///
/// `[DEVIATION from §6.3]` The original rolled `titleClass + random(6)`,
/// and the title comes from the prestige score (population + treasury +
/// buildings) — an UNBOUNDED, size-correlated input. A Kaiser therefore
/// expanded at 8–13 tiles a turn while a Ritter crawled at 1–6: the biggest
/// realm also grew the fastest, the definition of a runaway. Popularity is
/// bounded 0–100, so the budget now has a ceiling every realm can reach and
/// a small, well-run realm keeps pace with the largest. The title keeps its
/// other duties (§19.2 bankruptcy limits, §17 elections, prestige).
///
/// The divisor is calibrated (`tool/balance_sim.dart`) so the AVERAGE roll
/// across a long game stays near the old title-driven average — the point
/// is to change WHO gets the Züge, not to hand the whole world more. It
/// lands generous exactly where the old ladder was meanest: a fresh realm
/// at the starting mood of 50 rolls 2–7 instead of a Ritter's 1–6, while
/// the ceiling a giant used to enjoy (8–13) is gone.
/// [movementPointsMinimum] is a FLOOR, not an addend: however hated a
/// ruler is, one Zug per turn always remains, so a realm in a mood crisis
/// is slowed to a crawl but never frozen out of playing at all.
const int movementPointsMinimum = 1;
const int movementPopularityDivisor = 20;

/// `[DESIGNED 2026-08-24, user request]` How many overland steps a war
/// march must SAVE before it takes a ship instead of walking: a voyage
/// ("Seetransport", §11.2) spends the unit's whole war round however short
/// the crossing, so a hop that only shaves a step or two is a waste of
/// Züge. Sized at about one round's worth of movement — the sea wins when
/// it saves at least a full round of marching. A destination with no land
/// route at all ignores this: there the ship is the only way.
///
/// Both the player's march and the AI's use it (`marchWarUnit`), so the
/// two sides pick their routes by the same yardstick.
const int warSeaRouteAdvantage = 5;
