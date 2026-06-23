/// Shared game constants (ORIGINAL_GAME.md §1, §3, §4).
library;

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

/// Militarism popularity costs (levies, wars, conversions) never push a
/// realm below this floor — it sits above the §19.1 strife line (20) plus
/// the ±3 harvest nudge, so deliberate actions alone can never tip a realm
/// into collapse.
const int militarismPopularityFloor = 25;
