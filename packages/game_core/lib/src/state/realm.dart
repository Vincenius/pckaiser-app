import 'intel_report.dart';
import 'ship.dart';
import 'town.dart';
import 'troop.dart';

/// A player slot / realm (ORIGINAL_GAME.md §2). 30 fixed slots, indices
/// 1–30, never compacted; 0 = "Niemand".
class Realm {
  Realm({
    required this.slot,
    this.titleClass = 0,
    this.capitalX = 0,
    this.capitalY = 0,
    this.cursorX = 0,
    this.cursorY = 0,
    this.population = 0,
    this.troopCapacity = 0,
    this.armySize = 0,
    List<int>? tileCount,
    this.grainHarvest = 0,
    this.livestockHarvest = 0,
    this.treasury = 0,
    this.guardLevel = 0,
    this.popularity = 50,
    this.movementPoints = 0,
    this.lastTax = 0,
    this.lastTribute = 0,
    this.soldGrainThisTurn = false,
    this.soldCattleThisTurn = false,
    this.investedThisTurn = false,
    this.proposedMarriageThisTurn = false,
    this.warThisYear = false,
    this.rulerId,
    List<Troop>? troops,
    List<Town>? towns,
    List<Ship>? ships,
    List<IntelReport>? intelReports,
  })  : tileCount = tileCount ?? List.filled(9, 0),
        troops = troops ?? [],
        towns = towns ?? [],
        ships = ships ?? [],
        intelReports = intelReports ?? [];

  factory Realm.fromJson(Map<String, dynamic> json) => Realm(
        slot: json['slot'] as int,
        titleClass: json['titleClass'] as int? ?? 0,
        capitalX: json['capitalX'] as int? ?? 0,
        capitalY: json['capitalY'] as int? ?? 0,
        cursorX: json['cursorX'] as int? ?? 0,
        cursorY: json['cursorY'] as int? ?? 0,
        population: json['population'] as int? ?? 0,
        troopCapacity: json['troopCapacity'] as int? ?? 0,
        armySize: json['armySize'] as int? ?? 0,
        tileCount: (json['tileCount'] as List?)?.cast<int>(),
        grainHarvest: json['grainHarvest'] as int? ?? 0,
        livestockHarvest: json['livestockHarvest'] as int? ?? 0,
        treasury: json['treasury'] as int? ?? 0,
        guardLevel: json['guardLevel'] as int? ?? 0,
        popularity: json['popularity'] as int? ?? 50,
        movementPoints: json['movementPoints'] as int? ?? 0,
        lastTax: json['lastTax'] as int? ?? 0,
        lastTribute: json['lastTribute'] as int? ?? 0,
        soldGrainThisTurn: json['soldGrainThisTurn'] as bool? ?? false,
        soldCattleThisTurn: json['soldCattleThisTurn'] as bool? ?? false,
        investedThisTurn: json['investedThisTurn'] as bool? ?? false,
        proposedMarriageThisTurn:
            json['proposedMarriageThisTurn'] as bool? ?? false,
        warThisYear: json['warThisYear'] as bool? ?? false,
        rulerId: json['rulerId'] as int?,
        troops: (json['troops'] as List?)
            ?.map((t) => Troop.fromJson((t as Map).cast<String, dynamic>()))
            .toList(),
        towns: (json['towns'] as List?)
            ?.map((t) => Town.fromJson((t as Map).cast<String, dynamic>()))
            .toList(),
        // Additive field (rules v9) — older saves have no ships.
        ships: (json['ships'] as List?)
            ?.map((s) => Ship.fromJson((s as Map).cast<String, dynamic>()))
            .toList(),
        intelReports: (json['intelReports'] as List?)
            ?.map((r) =>
                IntelReport.fromJson((r as Map).cast<String, dynamic>()))
            .toList(),
      );

  /// Slot index 1–30.
  final int slot;

  /// 1–12 male, 13–24 female title ladder (§16).
  int titleClass;

  int capitalX;
  int capitalY;
  int cursorX;
  int cursorY;

  /// Σ of this realm's towns' populations (kept in sync).
  int population;

  /// Σ of this realm's towns' capacities.
  int troopCapacity;

  /// Σ of this realm's towns' garrisons.
  int armySize;

  /// Owned-tile counters per building type, indexed 1–8; index 0 counts
  /// owned tiles without a building (claimed but empty).
  final List<int> tileCount;

  /// This turn's sellable yields (§8.1).
  int grainHarvest;
  int livestockHarvest;

  /// Can go negative — debt (§19).
  int treasury;

  /// "Verstärken" stat, capped at 50 (§13).
  int guardLevel;

  /// Popularity a.k.a. "weight" — ONE field, init 50, clamped 0–100,
  /// displayed up to 150 (§8.4).
  int popularity;

  /// Re-rolled per turn by title class (§6.3).
  int movementPoints;

  int lastTax;
  int lastTribute;

  // Per-turn action flags (§2). One sell per good per turn (§9.1); one
  // marriage proposal per turn (modern UX rule).
  bool soldGrainThisTurn;
  bool soldCattleThisTurn;
  bool investedThisTurn;
  bool proposedMarriageThisTurn;
  bool warThisYear;

  /// Ruler person id; null = slot vacant. The same person can rule several
  /// slots (ruler aliasing, §19).
  int? rulerId;

  final List<Troop> troops;
  final List<Town> towns;

  /// Colony ships at sea (rules v9). Hidden information like [troops].
  final List<Ship> ships;

  /// Espionage results owned by this realm — private, hidden-information
  /// state (ARCHITECTURE.md).
  final List<IntelReport> intelReports;

  bool get isVacant => rulerId == null;

  Realm copy() => Realm(
        slot: slot,
        titleClass: titleClass,
        capitalX: capitalX,
        capitalY: capitalY,
        cursorX: cursorX,
        cursorY: cursorY,
        population: population,
        troopCapacity: troopCapacity,
        armySize: armySize,
        tileCount: List.of(tileCount),
        grainHarvest: grainHarvest,
        livestockHarvest: livestockHarvest,
        treasury: treasury,
        guardLevel: guardLevel,
        popularity: popularity,
        movementPoints: movementPoints,
        lastTax: lastTax,
        lastTribute: lastTribute,
        soldGrainThisTurn: soldGrainThisTurn,
        soldCattleThisTurn: soldCattleThisTurn,
        investedThisTurn: investedThisTurn,
        proposedMarriageThisTurn: proposedMarriageThisTurn,
        warThisYear: warThisYear,
        rulerId: rulerId,
        troops: [for (final t in troops) t.copy()],
        towns: [for (final t in towns) t.copy()],
        ships: [for (final s in ships) s.copy()],
        intelReports: [for (final r in intelReports) r.copy()],
      );

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'titleClass': titleClass,
        'capitalX': capitalX,
        'capitalY': capitalY,
        'cursorX': cursorX,
        'cursorY': cursorY,
        'population': population,
        'troopCapacity': troopCapacity,
        'armySize': armySize,
        'tileCount': tileCount,
        'grainHarvest': grainHarvest,
        'livestockHarvest': livestockHarvest,
        'treasury': treasury,
        'guardLevel': guardLevel,
        'popularity': popularity,
        'movementPoints': movementPoints,
        'lastTax': lastTax,
        'lastTribute': lastTribute,
        'soldGrainThisTurn': soldGrainThisTurn,
        'soldCattleThisTurn': soldCattleThisTurn,
        'investedThisTurn': investedThisTurn,
        'proposedMarriageThisTurn': proposedMarriageThisTurn,
        'warThisYear': warThisYear,
        'rulerId': rulerId,
        'troops': [for (final t in troops) t.toJson()],
        'towns': [for (final t in towns) t.toJson()],
        'ships': [for (final s in ships) s.toJson()],
        'intelReports': [for (final r in intelReports) r.toJson()],
      };
}
