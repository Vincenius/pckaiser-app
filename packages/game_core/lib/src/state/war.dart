/// Phases of an active war (§11.2): the war-round loop, then possibly the
/// claim-settlement screen of a limited victory.
enum WarPhase { rounds, settlement }

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
    this.attackerPlunderedThisRound = false,
    this.defenderPlunderedThisRound = false,
    Map<int, List<UnitSnapshot>>? snapshots,
    Map<int, List<int>>? movesLeft,
    this.winnerSlot,
    this.remainingClaim = 0,
  })  : snapshots = snapshots ?? {},
        movesLeft = movesLeft ?? {};

  factory ActiveWar.fromJson(Map<String, dynamic> json) => ActiveWar(
        attackerSlot: json['attackerSlot'] as int,
        defenderSlot: json['defenderSlot'] as int,
        round: json['round'] as int? ?? 0,
        phase: WarPhase.values.byName(json['phase'] as String? ?? 'rounds'),
        attackerWantsPeace: json['attackerWantsPeace'] as bool? ?? false,
        defenderWantsPeace: json['defenderWantsPeace'] as bool? ?? false,
        attackerPlunderedThisRound:
            json['attackerPlunderedThisRound'] as bool? ?? false,
        defenderPlunderedThisRound:
            json['defenderPlunderedThisRound'] as bool? ?? false,
        snapshots: {
          for (final e in ((json['snapshots'] as Map?) ?? {}).entries)
            int.parse(e.key as String): [
              for (final s in e.value as List)
                UnitSnapshot.fromJson((s as Map).cast<String, dynamic>()),
            ],
        },
        movesLeft: {
          for (final e in ((json['movesLeft'] as Map?) ?? {}).entries)
            int.parse(e.key as String): (e.value as List).cast<int>(),
        },
        winnerSlot: json['winnerSlot'] as int?,
        remainingClaim: json['remainingClaim'] as int? ?? 0,
      );

  final int attackerSlot;
  final int defenderSlot;

  /// War-round counter; winter forces the end above 20 (§11.2).
  int round;

  WarPhase phase;

  bool attackerWantsPeace;
  bool defenderWantsPeace;
  bool attackerPlunderedThisRound;
  bool defenderPlunderedThisRound;

  /// Pre-war unit positions per slot, parallel to the troop list at
  /// declaration (units are pruned to non-empty first).
  final Map<int, List<UnitSnapshot>> snapshots;

  /// Remaining moves this war round, per slot, parallel to the troop list.
  final Map<int, List<int>> movesLeft;

  /// Set in the settlement phase (§11.2 claim settlement).
  int? winnerSlot;
  int remainingClaim;

  bool isParticipant(int slot) =>
      slot == attackerSlot || slot == defenderSlot;

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

  bool plunderedThisRound(int slot) => slot == attackerSlot
      ? attackerPlunderedThisRound
      : defenderPlunderedThisRound;

  void setPlunderedThisRound(int slot, bool value) {
    if (slot == attackerSlot) {
      attackerPlunderedThisRound = value;
    } else {
      defenderPlunderedThisRound = value;
    }
  }

  ActiveWar copy() => ActiveWar(
        attackerSlot: attackerSlot,
        defenderSlot: defenderSlot,
        round: round,
        phase: phase,
        attackerWantsPeace: attackerWantsPeace,
        defenderWantsPeace: defenderWantsPeace,
        attackerPlunderedThisRound: attackerPlunderedThisRound,
        defenderPlunderedThisRound: defenderPlunderedThisRound,
        snapshots: {
          for (final e in snapshots.entries) e.key: List.of(e.value),
        },
        movesLeft: {
          for (final e in movesLeft.entries) e.key: List.of(e.value),
        },
        winnerSlot: winnerSlot,
        remainingClaim: remainingClaim,
      );

  Map<String, dynamic> toJson() => {
        'attackerSlot': attackerSlot,
        'defenderSlot': defenderSlot,
        'round': round,
        'phase': phase.name,
        'attackerWantsPeace': attackerWantsPeace,
        'defenderWantsPeace': defenderWantsPeace,
        'attackerPlunderedThisRound': attackerPlunderedThisRound,
        'defenderPlunderedThisRound': defenderPlunderedThisRound,
        'snapshots': {
          for (final e in snapshots.entries)
            '${e.key}': [for (final s in e.value) s.toJson()],
        },
        'movesLeft': {
          for (final e in movesLeft.entries) '${e.key}': e.value,
        },
        'winnerSlot': winnerSlot,
        'remainingClaim': remainingClaim,
      };
}
