import 'intel_report.dart';
import 'pending_ship_return.dart';
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
    this.colorArgb,
    this.population = 0,
    this.troopCapacity = 0,
    List<int>? tileCount,
    this.grainHarvest = 0,
    this.livestockHarvest = 0,
    this.treasury = 0,
    this.debtTurns = 0,
    this.guardLevel = 0,
    this.popularity = 50,
    this.movementPoints = 0,
    this.lastTax = 0,
    this.lastTribute = 0,
    this.soldGrainThisTurn = false,
    this.soldCattleThisTurn = false,
    this.investedThisTurn = false,
    this.recruitedThisTurn = 0,
    List<int>? proposedThisTurnIds,
    List<int>? assassinatedThisTurnSlots,
    this.warThisYear = false,
    this.recentWars = 0,
    this.lastWarYear = 0,
    this.peaceYears = 0,
    Map<int, int>? truceUntilYear,
    this.rulerId,
    List<Troop>? troops,
    List<Town>? towns,
    List<Ship>? ships,
    List<PendingShipReturn>? pendingShipReturns,
    List<IntelReport>? intelReports,
  })  : tileCount = tileCount ?? List.filled(9, 0),
        truceUntilYear = truceUntilYear ?? {},
        proposedThisTurnIds = proposedThisTurnIds ?? [],
        assassinatedThisTurnSlots = assassinatedThisTurnSlots ?? [],
        troops = troops ?? [],
        towns = towns ?? [],
        ships = ships ?? [],
        pendingShipReturns = pendingShipReturns ?? [],
        intelReports = intelReports ?? [];

  factory Realm.fromJson(Map<String, dynamic> json) => Realm(
        slot: json['slot'] as int,
        titleClass: json['titleClass'] as int? ?? 0,
        capitalX: json['capitalX'] as int? ?? 0,
        capitalY: json['capitalY'] as int? ?? 0,
        cursorX: json['cursorX'] as int? ?? 0,
        cursorY: json['cursorY'] as int? ?? 0,
        // Additive field — older saves keep the slot-derived default color.
        colorArgb: json['colorArgb'] as int?,
        population: json['population'] as int? ?? 0,
        troopCapacity: json['troopCapacity'] as int? ?? 0,
        // 'armySize' in the document is ignored: the army is DERIVED from
        // the troop list (see the getter), so a stored value can never
        // contradict the units again.
        // `.toList()` detaches from the decoded JSON: tileCount is index-
        // mutated in place (`tileCount[building]++`), so a bare cast view
        // would write back into the source document. (copy() already copies.)
        tileCount: (json['tileCount'] as List?)?.cast<int>().toList(),
        grainHarvest: json['grainHarvest'] as int? ?? 0,
        livestockHarvest: json['livestockHarvest'] as int? ?? 0,
        treasury: json['treasury'] as int? ?? 0,
        // Additive field — older saves start the debt clock at zero.
        debtTurns: json['debtTurns'] as int? ?? 0,
        guardLevel: json['guardLevel'] as int? ?? 0,
        popularity: json['popularity'] as int? ?? 50,
        movementPoints: json['movementPoints'] as int? ?? 0,
        lastTax: json['lastTax'] as int? ?? 0,
        lastTribute: json['lastTribute'] as int? ?? 0,
        soldGrainThisTurn: json['soldGrainThisTurn'] as bool? ?? false,
        soldCattleThisTurn: json['soldCattleThisTurn'] as bool? ?? false,
        investedThisTurn: json['investedThisTurn'] as bool? ?? false,
        // Additive field — older mid-turn saves start with a fresh levy.
        recruitedThisTurn: json['recruitedThisTurn'] as int? ?? 0,
        // Replaces the pre-2026-07-10 realm-wide bool
        // `proposedMarriageThisTurn` (the limit is per PERSON now); the
        // legacy key is simply ignored — worst case an old mid-turn save
        // allows one extra proposal once.
        proposedThisTurnIds:
            (json['proposedThisTurnIds'] as List?)?.cast<int>().toList(),
        // Additive field — an old mid-turn save allows one extra
        // assassination against an already-targeted realm once.
        assassinatedThisTurnSlots: (json['assassinatedThisTurnSlots'] as List?)
            ?.cast<int>()
            .toList(),
        warThisYear: json['warThisYear'] as bool? ?? false,
        // Additive field — older saves carry no war-weariness yet.
        recentWars: json['recentWars'] as int? ?? 0,
        // Additive fields — older saves know no war recovery and no truce
        // (year 0 is before any game year, so nothing is blocked on load).
        lastWarYear: json['lastWarYear'] as int? ?? 0,
        peaceYears: json['peaceYears'] as int? ?? 0,
        truceUntilYear: {
          for (final e in ((json['truceUntilYear'] as Map?) ?? {}).entries)
            int.parse(e.key as String): e.value as int,
        },
        rulerId: json['rulerId'] as int?,
        troops: (json['troops'] as List?)
            ?.map((t) => Troop.fromJson((t as Map).cast<String, dynamic>()))
            .toList(),
        towns: (json['towns'] as List?)
            ?.map((t) => Town.fromJson((t as Map).cast<String, dynamic>()))
            .toList(),
        // Additive field — older saves have no ships.
        ships: (json['ships'] as List?)
            ?.map((s) => Ship.fromJson((s as Map).cast<String, dynamic>()))
            .toList(),
        // Additive field — older saves have no in-flight trade voyages.
        pendingShipReturns: (json['pendingShipReturns'] as List?)
            ?.map((r) =>
                PendingShipReturn.fromJson((r as Map).cast<String, dynamic>()))
            .toList(),
        intelReports: (json['intelReports'] as List?)
            ?.map(
                (r) => IntelReport.fromJson((r as Map).cast<String, dynamic>()))
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

  /// Player-chosen map color (ARGB), picked at game setup; null = the
  /// client derives a default color from the slot index. Pure display
  /// data — no rule ever reads it.
  int? colorArgb;

  /// Σ of this realm's towns' populations (kept in sync).
  int population;

  /// Σ of this realm's towns' capacities.
  int troopCapacity;

  /// The standing regular army: Σ men of the garrison-counted units.
  /// DERIVED from the troop list — it can never drift from the units, so
  /// no mutation site has to hand-sync it and no sweep has to repair it.
  /// (The per-town `garrison` fields track where those men are QUARTERED
  /// and sum to the same number; `quarterRecruits`/`releaseGarrison` and
  /// friends keep them aligned.) Söldner are not garrison-counted; their
  /// wages run via their own head count (see runEconomy).
  int get armySize {
    var sum = 0;
    for (final troop in troops) {
      if (troop.garrisonCounted) sum += troop.men;
    }
    return sum;
  }

  /// Owned-tile counters per building type, indexed 1–8; index 0 counts
  /// owned tiles without a building (claimed but empty).
  final List<int> tileCount;

  /// This turn's sellable yields (§8.1).
  int grainHarvest;
  int livestockHarvest;

  /// Can go negative — debt (§19).
  int treasury;

  /// Consecutive end-of-turns the treasury has stayed below the §19.2
  /// bankruptcy limit. The creditor only forecloses once it reaches
  /// [bankruptcyGraceTurns] — until then the realm has time to recover.
  /// Reset to 0 the moment the debt climbs back above the limit.
  int debtTurns;

  /// "Verstärken" stat, capped at 50 (§13).
  int guardLevel;

  /// Popularity a.k.a. "weight" — ONE field, init 50, clamped 0–100,
  /// displayed up to 150 (§8.4).
  int popularity;

  /// Re-rolled per turn by title class (§6.3).
  int movementPoints;

  int lastTax;
  int lastTribute;

  // Per-turn action flags (§2). One sell per good per turn (§9.1).
  bool soldGrainThisTurn;
  bool soldCattleThisTurn;
  bool investedThisTurn;
  bool warThisYear;

  /// Regulars levied this turn, counted against the per-turn levy limit
  /// (see `levyLimit` in rules/troops.dart). Reset with the other
  /// per-turn flags; Söldner are exempt.
  int recruitedThisTurn;

  /// Dynasty members who already made a royal marriage proposal this turn
  /// (modern UX rule: one proposal per PERSON per turn — the original had
  /// no cap at all, §14.1). Cleared with the other per-turn flags.
  final List<int> proposedThisTurnIds;

  /// Realms this realm already sent assassins at THIS turn (§13.3
  /// `[DESIGNED]`): one attempt per target realm per round, so splitting a
  /// squad into several orders can no longer beat the
  /// [maxAgentsPerMission] cap. Cleared with the other per-turn flags.
  final List<int> assassinatedThisTurnSlots;

  /// War weariness: wars this realm STARTED without a peace year in
  /// between. Escalates the declaration's popularity penalty
  /// (−5 × (recentWars + 1), see applyDeclareWar) and decays by one per
  /// war-free year (turn pipeline year start).
  int recentWars;

  /// `[DESIGNED 2026-08-08, user feedback]` The year this realm last ENTERED
  /// a war — as aggressor or as defender. Not a rule of its own: the AI
  /// leaves a realm that fought last year or this year alone
  /// (`_pickWarTarget`), so a beaten-down realm gets a breather instead of
  /// being the whole neighbourhood's preferred prey year after year (the AI
  /// picks the WEAKEST neighbour, which is a self-reinforcing loop without
  /// this). A boxed-in ("desperate") AI still ignores it. 0 = never at war.
  int lastWarYear;

  /// `[DESIGNED 2026-08-08, user feedback]` Truce per opponent slot: the
  /// LAST year (inclusive) in which this realm may not declare war on that
  /// slot. Written symmetrically for both combatants when a war ends
  /// ([truceYears]) and enforced in `declareWarBlocker` for humans and AI
  /// alike, so the same pair cannot grind each other down year after year.
  /// Entries simply expire by year — a stale one from a vacated (and later
  /// re-founded) slot can block nothing for long.
  final Map<int, int> truceUntilYear;

  /// Consecutive war-free years since the last one that forgave a step of
  /// [recentWars] — the counter behind [wearinessDecayYears]. Reset to 0 by
  /// any year the realm saw a war (defending included) and by each step it
  /// pays for. Bookkeeping only; no rule reads it directly.
  int peaceYears;

  /// Ruler person id; null = slot vacant. The same person can rule several
  /// slots (ruler aliasing, §19).
  int? rulerId;

  final List<Troop> troops;
  final List<Town> towns;

  /// Colony ships at sea. Hidden information like [troops].
  final List<Ship> ships;

  /// Trade-ship voyages still at sea (§9.2). Sent during a turn, each
  /// resolves at the start of this realm's next turn — hidden information
  /// like [ships].
  final List<PendingShipReturn> pendingShipReturns;

  /// Espionage results owned by this realm — private, hidden-information
  /// state (ARCHITECTURE.md).
  final List<IntelReport> intelReports;

  bool get isVacant => rulerId == null;

  /// The town on tile ([x],[y]), or null. A Dorf/Markt/Stadt tile owned by
  /// this realm always has a matching town object — callers that looked
  /// the tile's building up first may `assert` on null to surface a
  /// map/town desync in debug and tests instead of silently skipping.
  Town? townAt(int x, int y) {
    for (final town in towns) {
      if (town.x == x && town.y == y) return town;
    }
    return null;
  }

  Realm copy() => Realm(
        slot: slot,
        titleClass: titleClass,
        capitalX: capitalX,
        capitalY: capitalY,
        cursorX: cursorX,
        cursorY: cursorY,
        colorArgb: colorArgb,
        population: population,
        troopCapacity: troopCapacity,
        tileCount: List.of(tileCount),
        grainHarvest: grainHarvest,
        livestockHarvest: livestockHarvest,
        treasury: treasury,
        debtTurns: debtTurns,
        guardLevel: guardLevel,
        popularity: popularity,
        movementPoints: movementPoints,
        lastTax: lastTax,
        lastTribute: lastTribute,
        soldGrainThisTurn: soldGrainThisTurn,
        soldCattleThisTurn: soldCattleThisTurn,
        investedThisTurn: investedThisTurn,
        recruitedThisTurn: recruitedThisTurn,
        proposedThisTurnIds: List.of(proposedThisTurnIds),
        assassinatedThisTurnSlots: List.of(assassinatedThisTurnSlots),
        warThisYear: warThisYear,
        recentWars: recentWars,
        lastWarYear: lastWarYear,
        peaceYears: peaceYears,
        truceUntilYear: Map.of(truceUntilYear),
        rulerId: rulerId,
        troops: [for (final t in troops) t.copy()],
        towns: [for (final t in towns) t.copy()],
        ships: [for (final s in ships) s.copy()],
        pendingShipReturns: [for (final r in pendingShipReturns) r.copy()],
        intelReports: [for (final r in intelReports) r.copy()],
      );

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'titleClass': titleClass,
        'capitalX': capitalX,
        'capitalY': capitalY,
        'cursorX': cursorX,
        'cursorY': cursorY,
        'colorArgb': colorArgb,
        'population': population,
        'troopCapacity': troopCapacity,
        // Derived, but still written so older builds reading this save
        // (additive-JSON rule) keep a correct value.
        'armySize': armySize,
        'tileCount': tileCount,
        'grainHarvest': grainHarvest,
        'livestockHarvest': livestockHarvest,
        'treasury': treasury,
        'debtTurns': debtTurns,
        'guardLevel': guardLevel,
        'popularity': popularity,
        'movementPoints': movementPoints,
        'lastTax': lastTax,
        'lastTribute': lastTribute,
        'soldGrainThisTurn': soldGrainThisTurn,
        'soldCattleThisTurn': soldCattleThisTurn,
        'investedThisTurn': investedThisTurn,
        'recruitedThisTurn': recruitedThisTurn,
        'proposedThisTurnIds': proposedThisTurnIds,
        'assassinatedThisTurnSlots': assassinatedThisTurnSlots,
        'warThisYear': warThisYear,
        'recentWars': recentWars,
        'lastWarYear': lastWarYear,
        'peaceYears': peaceYears,
        'truceUntilYear': {
          for (final e in truceUntilYear.entries) '${e.key}': e.value,
        },
        'rulerId': rulerId,
        'troops': [for (final t in troops) t.toJson()],
        'towns': [for (final t in towns) t.toJson()],
        'ships': [for (final s in ships) s.toJson()],
        'pendingShipReturns': [for (final r in pendingShipReturns) r.toJson()],
        'intelReports': [for (final r in intelReports) r.toJson()],
      };
}
