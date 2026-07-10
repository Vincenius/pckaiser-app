/// Phases of an active war (§11.2): for a human-vs-human war a preparation
/// window first (both sides choose live control vs autopilot and review
/// stances — user-designed mechanic, 2026-07-06), then the war-round loop,
/// then possibly the claim-settlement screen of a limited victory.
enum WarPhase { preparation, rounds, settlement }

/// A unit's snapshotted pre-war position (§11.1) — used by the AI peace
/// test and the post-war troop return.
class UnitSnapshot {
  UnitSnapshot({required this.name, required this.x, required this.y});

  factory UnitSnapshot.fromJson(Map<String, dynamic> json) => UnitSnapshot(
        name: json['name'] as String,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  final String name;
  final int x;
  final int y;

  Map<String, dynamic> toJson() => {'name': name, 'x': x, 'y': y};
}

/// State of an ongoing war (§11). Lives in the game state so both sides
/// (hot-seat or online) act on it through actions across war rounds.
class ActiveWar {
  ActiveWar({
    required this.attackerSlot,
    required this.defenderSlot,
    this.round = 0,
    this.phase = WarPhase.rounds,
    this.attackerWantsPeace = false,
    this.defenderWantsPeace = false,
    Map<int, List<UnitSnapshot>>? snapshots,
    Map<int, List<int>>? movesLeft,
    this.winnerSlot,
    this.remainingClaim = 0,
    this.heldCapitalSlot,
    this.actingSlot,
    this.attackerMenLost = 0,
    this.defenderMenLost = 0,
    this.battles = 0,
    this.attackerLoot = 0,
    this.defenderLoot = 0,
    this.attackerTilesTaken = 0,
    this.defenderTilesTaken = 0,
    Set<int>? autoSlots,
    Map<int, List<int>>? planSlots,
    this.scheduledStartMs,
    Set<int>? actedSlots,
  })  : snapshots = snapshots ?? {},
        movesLeft = movesLeft ?? {},
        autoSlots = autoSlots ?? {},
        planSlots = planSlots ?? {},
        actedSlots = actedSlots ?? {};

  factory ActiveWar.fromJson(Map<String, dynamic> json) => ActiveWar(
        attackerSlot: json['attackerSlot'] as int,
        defenderSlot: json['defenderSlot'] as int,
        round: json['round'] as int? ?? 0,
        phase: WarPhase.values.byName(json['phase'] as String? ?? 'rounds'),
        attackerWantsPeace: json['attackerWantsPeace'] as bool? ?? false,
        defenderWantsPeace: json['defenderWantsPeace'] as bool? ?? false,
        // The pre-2026-07-10 per-SIDE plunder flags
        // (attacker/defenderPlunderedThisRound) are ignored: plunder is
        // per ARMY now (Troop.plunderedThisRound).
        snapshots: {
          for (final e in ((json['snapshots'] as Map?) ?? {}).entries)
            int.parse(e.key as String): [
              for (final s in e.value as List)
                UnitSnapshot.fromJson((s as Map).cast<String, dynamic>()),
            ],
        },
        movesLeft: {
          // toList(): `cast` alone aliases the source lists (toJson emits
          // the live lists) — a clone's war round would drain the
          // original's move budgets.
          for (final e in ((json['movesLeft'] as Map?) ?? {}).entries)
            int.parse(e.key as String): (e.value as List).cast<int>().toList(),
        },
        winnerSlot: json['winnerSlot'] as int?,
        remainingClaim: json['remainingClaim'] as int? ?? 0,
        // Additive field — older saves have no armed capture.
        heldCapitalSlot: json['heldCapitalSlot'] as int?,
        // Additive field — pre-HvH saves derive the acting side from the
        // dynasty statuses (warActingSlot falls back to the first human).
        actingSlot: json['actingSlot'] as int?,
        // Additive fields — older saves start their war tally at zero.
        attackerMenLost: json['attackerMenLost'] as int? ?? 0,
        defenderMenLost: json['defenderMenLost'] as int? ?? 0,
        battles: json['battles'] as int? ?? 0,
        attackerLoot: json['attackerLoot'] as int? ?? 0,
        defenderLoot: json['defenderLoot'] as int? ?? 0,
        attackerTilesTaken: json['attackerTilesTaken'] as int? ?? 0,
        defenderTilesTaken: json['defenderTilesTaken'] as int? ?? 0,
        // Additive field — older saves have no delegated war sides.
        autoSlots: (json['autoSlots'] as List?)?.cast<int>().toSet(),
        // Additive fields — pre-scheduling saves have no start proposals.
        planSlots: {
          for (final e in ((json['planSlots'] as Map?) ?? {}).entries)
            int.parse(e.key as String): (e.value as List).cast<int>().toList(),
        },
        scheduledStartMs: json['scheduledStartMs'] as int?,
        actedSlots: (json['actedSlots'] as List?)?.cast<int>().toSet(),
      );

  final int attackerSlot;
  final int defenderSlot;

  /// War-round counter; winter forces the end above 20 (§11.2).
  int round;

  WarPhase phase;

  bool attackerWantsPeace;
  bool defenderWantsPeace;

  /// Pre-war unit positions per slot, parallel to the troop list at
  /// declaration (units are pruned to non-empty first).
  final Map<int, List<UnitSnapshot>> snapshots;

  /// Remaining moves this war round, per slot, parallel to the troop list.
  final Map<int, List<int>> movesLeft;

  /// Set in the settlement phase (§11.2 claim settlement).
  int? winnerSlot;
  int remainingClaim;

  /// The side that occupied the enemy capital at the previous
  /// round end ("armed" capture). Holding it at the NEXT round end too —
  /// through the opponent's full response round — resolves the capture;
  /// null when nobody holds it.
  int? heldCapitalSlot;

  /// The side whose interactive war input is awaited right now. Attacker
  /// first each round; in a human-vs-human war the attacker's round end
  /// HANDS OVER to the defender instead of advancing the round (see
  /// `endWarRoundFor`). Null when no human fights — AI sides never await
  /// input. Read through `warActingSlot`, which also covers pre-HvH saves.
  int? actingSlot;

  /// Cumulative war tally for the end-of-war overview: men lost per side,
  /// battle count, plunder loot and conquered tiles per side. Incremented
  /// in `resolveCombat`/`plunderTile`/`conquerTile`; copied into the
  /// war-ending event's `summary` payload before the war state is cleared.
  int attackerMenLost;
  int defenderMenLost;
  int battles;
  int attackerLoot;
  int defenderLoot;
  int attackerTilesTaken;
  int defenderTilesTaken;

  /// Human war sides who handed THIS war to the computer (`warDefense`
  /// decision): their rounds are played by the stance autopilot like an
  /// AI side's, and their input is never awaited. Cleared with the war.
  final Set<int> autoSlots;

  /// Proposed duel start times per LIVE side (`warPlan` answer, online
  /// scheduling): epoch milliseconds UTC on full hours; the sentinel 0
  /// means "as soon as both have answered". Used only during the
  /// preparation phase of a both-live war.
  final Map<int, List<int>> planSlots;

  /// The agreed duel start (earliest common `planSlots` entry) once every
  /// side has answered: epoch milliseconds UTC, 0 = immediately. Null =
  /// no overlap (or no proposals) — the online fallback deadline (half
  /// the turn timer) governs the start, exactly as before scheduling.
  int? scheduledStartMs;

  /// War sides that have given at least one interactive input during the
  /// ROUNDS phase (set by the server). A side whose round clock expires
  /// while it never acted at all is handed to the stance autopilot for
  /// the rest of the war (online no-show rule) instead of idling through
  /// every round one short clock at a time.
  final Set<int> actedSlots;

  /// The tally as a war-ending event payload fragment.
  Map<String, dynamic> summary() => {
        'attackerSlot': attackerSlot,
        'defenderSlot': defenderSlot,
        'rounds': round + 1,
        'battles': battles,
        'attackerMenLost': attackerMenLost,
        'defenderMenLost': defenderMenLost,
        'attackerLoot': attackerLoot,
        'defenderLoot': defenderLoot,
        'attackerTilesTaken': attackerTilesTaken,
        'defenderTilesTaken': defenderTilesTaken,
      };

  bool isParticipant(int slot) => slot == attackerSlot || slot == defenderSlot;

  int opponentOf(int slot) =>
      slot == attackerSlot ? defenderSlot : attackerSlot;

  bool wantsPeace(int slot) =>
      slot == attackerSlot ? attackerWantsPeace : defenderWantsPeace;

  void setWantsPeace(int slot, bool value) {
    if (slot == attackerSlot) {
      attackerWantsPeace = value;
    } else {
      defenderWantsPeace = value;
    }
  }

  ActiveWar copy() => ActiveWar(
        attackerSlot: attackerSlot,
        defenderSlot: defenderSlot,
        round: round,
        phase: phase,
        attackerWantsPeace: attackerWantsPeace,
        defenderWantsPeace: defenderWantsPeace,
        snapshots: {
          for (final e in snapshots.entries) e.key: List.of(e.value),
        },
        movesLeft: {
          for (final e in movesLeft.entries) e.key: List.of(e.value),
        },
        winnerSlot: winnerSlot,
        remainingClaim: remainingClaim,
        heldCapitalSlot: heldCapitalSlot,
        actingSlot: actingSlot,
        attackerMenLost: attackerMenLost,
        defenderMenLost: defenderMenLost,
        battles: battles,
        attackerLoot: attackerLoot,
        defenderLoot: defenderLoot,
        attackerTilesTaken: attackerTilesTaken,
        defenderTilesTaken: defenderTilesTaken,
        autoSlots: Set.of(autoSlots),
        planSlots: {
          for (final e in planSlots.entries) e.key: List.of(e.value),
        },
        scheduledStartMs: scheduledStartMs,
        actedSlots: Set.of(actedSlots),
      );

  Map<String, dynamic> toJson() => {
        'attackerSlot': attackerSlot,
        'defenderSlot': defenderSlot,
        'round': round,
        'phase': phase.name,
        'attackerWantsPeace': attackerWantsPeace,
        'defenderWantsPeace': defenderWantsPeace,
        'snapshots': {
          for (final e in snapshots.entries)
            '${e.key}': [for (final s in e.value) s.toJson()],
        },
        'movesLeft': {
          for (final e in movesLeft.entries) '${e.key}': e.value,
        },
        'winnerSlot': winnerSlot,
        'remainingClaim': remainingClaim,
        'heldCapitalSlot': heldCapitalSlot,
        'actingSlot': actingSlot,
        'attackerMenLost': attackerMenLost,
        'defenderMenLost': defenderMenLost,
        'battles': battles,
        'attackerLoot': attackerLoot,
        'defenderLoot': defenderLoot,
        'attackerTilesTaken': attackerTilesTaken,
        'defenderTilesTaken': defenderTilesTaken,
        'autoSlots': autoSlots.toList(),
        'planSlots': {
          for (final e in planSlots.entries) '${e.key}': e.value,
        },
        'scheduledStartMs': scheduledStartMs,
        'actedSlots': actedSlots.toList(),
      };
}
