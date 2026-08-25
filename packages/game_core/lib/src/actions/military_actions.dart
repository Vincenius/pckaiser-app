part of 'player_action.dart';

/// Recruit a new regular unit (§10.2): 5 T/man + class surcharge; men are
/// quartered in towns against free capacity. The unit is stationed at
/// ([x], [y]) when given (must be own territory), else at the capital.
class RecruitTroops extends PlayerAction {
  RecruitTroops({
    required super.slot,
    required this.men,
    required this.troopClass,
    required this.name,
    this.x,
    this.y,
  });

  factory RecruitTroops.fromJson(Map<String, dynamic> json) => RecruitTroops(
        slot: json['slot'] as int,
        men: json['men'] as int,
        troopClass: json['troopClass'] as int,
        name: json['name'] as String,
        x: json['x'] as int?,
        y: json['y'] as int?,
      );

  static const kind = 'recruitTroops';

  final int men;
  final int troopClass;
  final String name;
  final int? x;
  final int? y;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'men': men,
        'troopClass': troopClass,
        'name': name,
        'x': x,
        'y': y,
      };
}

/// Hire Söldner (§10.2): 50 T/man, not garrison-counted, ongoing wages.
/// Stationed at ([x], [y]) when given (own territory), else the capital.
class HireSoeldner extends PlayerAction {
  HireSoeldner({
    required super.slot,
    required this.men,
    required this.name,
    this.x,
    this.y,
  });

  factory HireSoeldner.fromJson(Map<String, dynamic> json) => HireSoeldner(
        slot: json['slot'] as int,
        men: json['men'] as int,
        name: json['name'] as String,
        x: json['x'] as int?,
        y: json['y'] as int?,
      );

  static const kind = 'hireSoeldner';

  final int men;
  final String name;
  final int? x;
  final int? y;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'men': men, 'name': name, 'x': x, 'y': y};
}

/// "Truppe verstärken" — add men to an existing unit (§10.2).
class ReinforceTroop extends PlayerAction {
  ReinforceTroop(
      {required super.slot, required this.unitIndex, required this.men});

  factory ReinforceTroop.fromJson(Map<String, dynamic> json) => ReinforceTroop(
        slot: json['slot'] as int,
        unitIndex: json['unitIndex'] as int,
        men: json['men'] as int,
      );

  static const kind = 'reinforceTroop';

  final int unitIndex;
  final int men;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'unitIndex': unitIndex, 'men': men};
}

/// "Truppe ausbilden" — drill (§10.2, the traced original
/// `proc_00A316`): +1 quality for 5 T/man, no class change. Repeatable
/// within a turn like the original, regulars only, capped at
/// [Troop.drillCap].
class DrillTroop extends PlayerAction {
  DrillTroop({required super.slot, required this.unitIndex});

  factory DrillTroop.fromJson(Map<String, dynamic> json) => DrillTroop(
        slot: json['slot'] as int,
        unitIndex: json['unitIndex'] as int,
      );

  static const kind = 'drillTroop';

  final int unitIndex;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'unitIndex': unitIndex};
}

/// "Truppe umrüsten": retrain a regular unit to a new
/// class for 5 T/man plus the class surcharge (Kav +500, Art +1,000).
class TrainTroop extends PlayerAction {
  TrainTroop({
    required super.slot,
    required this.unitIndex,
    required this.troopClass,
  });

  factory TrainTroop.fromJson(Map<String, dynamic> json) => TrainTroop(
        slot: json['slot'] as int,
        unitIndex: json['unitIndex'] as int,
        troopClass: json['troopClass'] as int,
      );

  static const kind = 'trainTroop';

  final int unitIndex;
  final int troopClass;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'unitIndex': unitIndex,
        'troopClass': troopClass,
      };
}

/// Rename a unit (free; forbidden at war — war snapshots match by name).
class RenameTroop extends PlayerAction {
  RenameTroop({
    required super.slot,
    required this.unitIndex,
    required this.name,
  });

  factory RenameTroop.fromJson(Map<String, dynamic> json) => RenameTroop(
        slot: json['slot'] as int,
        unitIndex: json['unitIndex'] as int,
        name: json['name'] as String,
      );

  static const kind = 'renameTroop';

  final int unitIndex;
  final String name;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'unitIndex': unitIndex,
        'name': name,
      };
}

/// "Verhalten im Krieg" — set a unit's autopilot war stance (see
/// [TroopStance]). Free, and allowed during a war too: it only flips a flag
/// the unattended round-resolution reads, never the troop list or moves.
class SetTroopStance extends PlayerAction {
  SetTroopStance({
    required super.slot,
    required this.unitIndex,
    required this.stance,
  });

  factory SetTroopStance.fromJson(Map<String, dynamic> json) => SetTroopStance(
        slot: json['slot'] as int,
        unitIndex: json['unitIndex'] as int,
        stance: json['stance'] as int,
      );

  static const kind = 'setTroopStance';

  final int unitIndex;
  final int stance;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'unitIndex': unitIndex, 'stance': stance};
}

/// "Truppen vereinigen" — merge unit [fromIndex] into [toIndex] (§10.2).
class MergeTroops extends PlayerAction {
  MergeTroops(
      {required super.slot, required this.fromIndex, required this.toIndex});

  factory MergeTroops.fromJson(Map<String, dynamic> json) => MergeTroops(
        slot: json['slot'] as int,
        fromIndex: json['fromIndex'] as int,
        toIndex: json['toIndex'] as int,
      );

  static const kind = 'mergeTroops';

  final int fromIndex;
  final int toIndex;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'fromIndex': fromIndex,
        'toIndex': toIndex,
      };
}

/// "Truppe auflösen" — disband a unit (§10.2).
class DisbandTroop extends PlayerAction {
  DisbandTroop({required super.slot, required this.unitIndex});

  factory DisbandTroop.fromJson(Map<String, dynamic> json) => DisbandTroop(
        slot: json['slot'] as int,
        unitIndex: json['unitIndex'] as int,
      );

  static const kind = 'disbandTroop';

  final int unitIndex;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'unitIndex': unitIndex};
}

/// "Truppenstandort" — reposition a unit on own territory (1 movement
/// point, §10.2).
class MoveTroop extends PlayerAction {
  MoveTroop({
    required super.slot,
    required this.unitIndex,
    required this.x,
    required this.y,
  });

  factory MoveTroop.fromJson(Map<String, dynamic> json) => MoveTroop(
        slot: json['slot'] as int,
        unitIndex: json['unitIndex'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  static const kind = 'moveTroop';

  final int unitIndex;
  final int x;
  final int y;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'unitIndex': unitIndex,
        'x': x,
        'y': y,
      };
}

/// Transfer a whole troop unit to another living realm. The recipient gets
/// the unit at the beginning of their next turn and may then position it.
class TransferTroop extends PlayerAction {
  TransferTroop(
      {required super.slot, required this.unitIndex, required this.targetSlot});

  factory TransferTroop.fromJson(Map<String, dynamic> json) => TransferTroop(
        slot: json['slot'] as int,
        unitIndex: json['unitIndex'] as int,
        targetSlot: json['targetSlot'] as int,
      );

  static const kind = 'transferTroop';
  final int unitIndex;
  final int targetSlot;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'unitIndex': unitIndex,
        'targetSlot': targetSlot,
      };
}

/// "(K)rieg erklären" (§11.1): year ≥ 1010, once per year, needs troops.
class DeclareWar extends PlayerAction {
  DeclareWar({required super.slot, required this.targetSlot});

  factory DeclareWar.fromJson(Map<String, dynamic> json) => DeclareWar(
        slot: json['slot'] as int,
        targetSlot: json['targetSlot'] as int,
      );

  static const kind = 'declareWar';

  final int targetSlot;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'targetSlot': targetSlot};
}

/// One-tile war-round move (§11.2); meeting an enemy unit fights (§11.3),
/// reaching the enemy capital captures the ruler.
class WarMove extends PlayerAction {
  WarMove({
    required super.slot,
    required this.unitIndex,
    required this.dx,
    required this.dy,
  });

  factory WarMove.fromJson(Map<String, dynamic> json) => WarMove(
        slot: json['slot'] as int,
        unitIndex: json['unitIndex'] as int,
        dx: json['dx'] as int,
        dy: json['dy'] as int,
      );

  static const kind = 'warMove';

  final int unitIndex;

  /// One orthogonal step: (dx, dy) ∈ {(±1,0),(0,±1)}.
  final int dx;
  final int dy;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'unitIndex': unitIndex,
        'dx': dx,
        'dy': dy,
      };
}

/// March a unit toward a target tile over several war-round steps in ONE
/// action: the engine walks the §11.2 shortest passable land path step by
/// step (each step with the full [WarMove] semantics — combat, capture
/// arming) until the unit arrives, runs out of moves, is held by a
/// defender, or is destroyed. Replaces the client-side step loop, whose
/// name-and-position identity tracking was the workaround for units having
/// had no stable identity inside the engine.
class WarMarch extends PlayerAction {
  WarMarch({
    required super.slot,
    required this.unitIndex,
    required this.x,
    required this.y,
  });

  factory WarMarch.fromJson(Map<String, dynamic> json) => WarMarch(
        slot: json['slot'] as int,
        unitIndex: json['unitIndex'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  static const kind = 'warMarch';

  final int unitIndex;

  /// Target tile; the march stops early when the path is exhausted.
  final int x;
  final int y;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'unitIndex': unitIndex,
        'x': x,
        'y': y,
      };
}

/// "Plündern" during a war round (§11.5) — once per side per round.
class WarPlunder extends PlayerAction {
  WarPlunder({required super.slot, required this.x, required this.y});

  factory WarPlunder.fromJson(Map<String, dynamic> json) => WarPlunder(
        slot: json['slot'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  static const kind = 'warPlunder';

  final int x;
  final int y;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {'type': kind, 'slot': slot, 'x': x, 'y': y};
}

/// "Will `<Land>` ein Ende des Krieges ?" — set this side's peace wish
/// for the current round (§11.2).
class WarPeaceWish extends PlayerAction {
  WarPeaceWish({required super.slot, required this.wantsPeace});

  factory WarPeaceWish.fromJson(Map<String, dynamic> json) => WarPeaceWish(
        slot: json['slot'] as int,
        wantsPeace: json['wantsPeace'] as bool,
      );

  static const kind = 'warPeaceWish';

  final bool wantsPeace;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'wantsPeace': wantsPeace};
}

/// Ends the current war round: termination checks run, then the next
/// round's movement allowances are rolled (§11.2).
class WarEndRound extends PlayerAction {
  WarEndRound({required super.slot});

  factory WarEndRound.fromJson(Map<String, dynamic> json) =>
      WarEndRound(slot: json['slot'] as int);

  static const kind = 'warEndRound';

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {'type': kind, 'slot': slot};
}

/// `[DESIGNED 2026-08-09, user request]` REVISES this side's war-start plan
/// during the preparation window: live command vs. stance autopilot
/// ([auto]), and the proposed duel start times ([slots], epoch ms UTC on
/// full hours). Same payload as the `warPlan` decision answer — but usable
/// as often as the player likes for as long as the preparation runs, so a
/// commander can switch to manual control before the duel begins and two
/// sides that found no common time can widen their offers until they do.
///
/// Allowed OUT OF TURN for both combatants (like [SetTroopStance] in the
/// preparation window): the defender is never the awaited player there.
class WarPrepPlan extends PlayerAction {
  WarPrepPlan({required super.slot, required this.auto, this.slots});

  factory WarPrepPlan.fromJson(Map<String, dynamic> json) => WarPrepPlan(
        slot: json['slot'] as int,
        auto: json['auto'] as bool,
        // EAGER element cast (`[for … as int]`, not `cast<int>()`): a lazy
        // cast view defers the type error to the first walk of the list —
        // far outside this parse, where the server's "bad request" guard no
        // longer covers it. Parsing here turns a malformed payload into the
        // 400 it is.
        slots: (json['slots'] as List?)?.map((v) => v as int).toList(),
      );

  static const kind = 'warPrepPlan';

  /// True hands THIS war to the stance autopilot, false commands it live.
  final bool auto;

  /// The side's full list of acceptable start instants (epoch ms UTC);
  /// null leaves the stored proposal untouched, an EMPTY list withdraws it.
  /// Ignored for `auto` (a delegated side never schedules).
  final List<int>? slots;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'auto': auto,
        if (slots != null) 'slots': slots,
      };
}

/// `[DESIGNED 2026-08-24, user request]` Takes manual command back from the
/// no-show autopilot (`war.autoSlots`) while the war ROUNDS are already
/// running: a side that never acted before its first round clock expired is
/// handed to the stance autopilot for the rest of the war
/// (ARCHITECTURE.md "war clock") — this reverses exactly that handover, for
/// this one side, at any point the player wants. The ONE direction allowed
/// mid-war: unlike [WarPrepPlan] (preparation-only, both directions), a live
/// side can never delegate itself back to the autopilot through this action.
class ResumeWarCommand extends PlayerAction {
  ResumeWarCommand({required super.slot});

  factory ResumeWarCommand.fromJson(Map<String, dynamic> json) =>
      ResumeWarCommand(slot: json['slot'] as int);

  static const kind = 'resumeWarCommand';

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {'type': kind, 'slot': slot};
}

/// Naval transport during war: moves a unit from a land tile adjacent to an
/// own harbor to any sea-reachable land tile, using all remaining moves.
class WarNavalTransport extends PlayerAction {
  WarNavalTransport({
    required super.slot,
    required this.unitIndex,
    required this.x,
    required this.y,
  });

  factory WarNavalTransport.fromJson(Map<String, dynamic> json) =>
      WarNavalTransport(
        slot: json['slot'] as int,
        unitIndex: json['unitIndex'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  static const kind = 'warNavalTransport';

  final int unitIndex;
  final int x;
  final int y;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'unitIndex': unitIndex,
        'x': x,
        'y': y,
      };
}

/// Claim settlement: annex one loser tile at its building value (§11.2).
class SettlementAnnex extends PlayerAction {
  SettlementAnnex({required super.slot, required this.x, required this.y});

  factory SettlementAnnex.fromJson(Map<String, dynamic> json) =>
      SettlementAnnex(
        slot: json['slot'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  static const kind = 'settlementAnnex';

  final int x;
  final int y;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {'type': kind, 'slot': slot, 'x': x, 'y': y};
}

/// Claim settlement: annex SEVERAL loser tiles in one submission, in tap
/// order, atomically (any invalid tile rejects the whole batch). The
/// online client buffers its per-tile taps locally and flushes them as one
/// of these with the settlement finish — one round-trip instead of one per
/// tile.
class SettlementAnnexMany extends PlayerAction {
  SettlementAnnexMany({required super.slot, required this.tiles});

  factory SettlementAnnexMany.fromJson(Map<String, dynamic> json) =>
      SettlementAnnexMany(
        slot: json['slot'] as int,
        tiles: [
          for (final t in json['tiles'] as List)
            (
              x: (t as Map)['x'] as int,
              y: t['y'] as int,
            ),
        ],
      );

  static const kind = 'settlementAnnexMany';

  final List<({int x, int y})> tiles;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'tiles': [
          for (final t in tiles) {'x': t.x, 'y': t.y},
        ],
      };
}

/// Claim settlement: annex EVERY affordable loser tile
/// bordering the own land in one stroke, then finish the settlement
/// (rest in Taler). Offered by the client as "Ganzes Land übernehmen"
/// when the claim covers the loser's whole territory.
class SettlementTakeAll extends PlayerAction {
  SettlementTakeAll({required super.slot});

  factory SettlementTakeAll.fromJson(Map<String, dynamic> json) =>
      SettlementTakeAll(slot: json['slot'] as int);

  static const kind = 'settlementTakeAll';

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {'type': kind, 'slot': slot};
}

/// Claim settlement: press `F` (fertig) — unspent claim pays out 1:1 in
/// Taler from the loser's treasury (§11.2).
class SettlementFinish extends PlayerAction {
  SettlementFinish({required super.slot});

  factory SettlementFinish.fromJson(Map<String, dynamic> json) =>
      SettlementFinish(slot: json['slot'] as int);

  static const kind = 'settlementFinish';

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {'type': kind, 'slot': slot};
}

/// The two intel mission kinds (§13).
enum SpyKind { economy, military }

/// Intel mission (§13.1/§13.2): 1–30 agents at 200 T each.
class SpyMission extends PlayerAction {
  SpyMission({
    required super.slot,
    required this.targetSlot,
    required this.agents,
    required this.spyKind,
  });

  factory SpyMission.fromJson(Map<String, dynamic> json) => SpyMission(
        slot: json['slot'] as int,
        targetSlot: json['targetSlot'] as int,
        agents: json['agents'] as int,
        spyKind: SpyKind.values.byName(json['spyKind'] as String),
      );

  static const kind = 'spyMission';

  final int targetSlot;
  final int agents;
  final SpyKind spyKind;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'targetSlot': targetSlot,
        'agents': agents,
        'spyKind': spyKind.name,
      };
}

/// "(A)nschlag verüben" (§13.3): 1–30 agents at 250 T each; queued,
/// resolved in the event phase.
class OrderAssassination extends PlayerAction {
  OrderAssassination({
    required super.slot,
    required this.targetSlot,
    required this.agents,
  });

  factory OrderAssassination.fromJson(Map<String, dynamic> json) =>
      OrderAssassination(
        slot: json['slot'] as int,
        targetSlot: json['targetSlot'] as int,
        agents: json['agents'] as int,
      );

  static const kind = 'orderAssassination';

  final int targetSlot;
  final int agents;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'targetSlot': targetSlot,
        'agents': agents,
      };
}

/// "(v)erstärken" / dismiss guards (§13): hire at 100 T per guard
/// (cap 50); dismissing is free.
class AdjustGuards extends PlayerAction {
  AdjustGuards({required super.slot, required this.delta});

  factory AdjustGuards.fromJson(Map<String, dynamic> json) => AdjustGuards(
        slot: json['slot'] as int,
        delta: json['delta'] as int,
      );

  static const kind = 'adjustGuards';

  final int delta;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {'type': kind, 'slot': slot, 'delta': delta};
}
