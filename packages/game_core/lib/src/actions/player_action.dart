/// Player action types (ARCHITECTURE.md `actions/`). Actions are the only
/// way state changes: serialized over the wire in online mode, applied
/// locally in hot-seat mode — both through `applyAction`.
library;

part 'military_actions.dart';

/// Thrown when an action fails validation. The message is player-facing.
class ActionException implements Exception {
  ActionException(this.message);

  final String message;

  @override
  String toString() => 'ActionException: $message';
}

sealed class PlayerAction {
  PlayerAction({required this.slot});

  /// Decodes any action from its wire form.
  factory PlayerAction.fromJson(Map<String, dynamic> json) =>
      switch (json['type'] as String) {
        ClaimTile.kind => ClaimTile.fromJson(json),
        Build.kind => Build.fromJson(json),
        Demolish.kind => Demolish.fromJson(json),
        ChangeReligion.kind => ChangeReligion.fromJson(json),
        CollectTribute.kind => CollectTribute.fromJson(json),
        SellGood.kind => SellGood.fromJson(json),
        InvestShips.kind => InvestShips.fromJson(json),
        SendMoney.kind => SendMoney.fromJson(json),
        RelocateCapital.kind => RelocateCapital.fromJson(json),
        ProposeMarriage.kind => ProposeMarriage.fromJson(json),
        MarryCommoner.kind => MarryCommoner.fromJson(json),
        ResolveDecision.kind => ResolveDecision.fromJson(json),
        MergeRealms.kind => MergeRealms.fromJson(json),
        TransferRealm.kind => TransferRealm.fromJson(json),
        RecruitTroops.kind => RecruitTroops.fromJson(json),
        HireSoeldner.kind => HireSoeldner.fromJson(json),
        ReinforceTroop.kind => ReinforceTroop.fromJson(json),
        TrainTroop.kind => TrainTroop.fromJson(json),
        DrillTroop.kind => DrillTroop.fromJson(json),
        RenameTroop.kind => RenameTroop.fromJson(json),
        SetTroopStance.kind => SetTroopStance.fromJson(json),
        MergeTroops.kind => MergeTroops.fromJson(json),
        DisbandTroop.kind => DisbandTroop.fromJson(json),
        MoveTroop.kind => MoveTroop.fromJson(json),
        DeclareWar.kind => DeclareWar.fromJson(json),
        WarMove.kind => WarMove.fromJson(json),
        WarMarch.kind => WarMarch.fromJson(json),
        WarPlunder.kind => WarPlunder.fromJson(json),
        WarPeaceWish.kind => WarPeaceWish.fromJson(json),
        WarEndRound.kind => WarEndRound.fromJson(json),
        WarNavalTransport.kind => WarNavalTransport.fromJson(json),
        SettlementAnnex.kind => SettlementAnnex.fromJson(json),
        SettlementAnnexMany.kind => SettlementAnnexMany.fromJson(json),
        SettlementTakeAll.kind => SettlementTakeAll.fromJson(json),
        SettlementFinish.kind => SettlementFinish.fromJson(json),
        BuyShip.kind => BuyShip.fromJson(json),
        MoveShip.kind => MoveShip.fromJson(json),
        ColonizeShip.kind => ColonizeShip.fromJson(json),
        SpyMission.kind => SpyMission.fromJson(json),
        OrderAssassination.kind => OrderAssassination.fromJson(json),
        AdjustGuards.kind => AdjustGuards.fromJson(json),
        final t => throw ArgumentError('unknown action type: $t'),
      };

  /// Acting realm slot (1–30).
  final int slot;

  String get type;

  Map<String, dynamic> toJson();
}

/// Claim an adjacent unowned land tile — 1 movement point (§4).
class ClaimTile extends PlayerAction {
  ClaimTile({required super.slot, required this.x, required this.y});

  factory ClaimTile.fromJson(Map<String, dynamic> json) => ClaimTile(
        slot: json['slot'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  static const kind = 'claimTile';

  final int x;
  final int y;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {'type': kind, 'slot': slot, 'x': x, 'y': y};
}

/// Build on an owned tile — 1 movement point + the building's cost (§4).
/// Founding a Dorf carries the town name the player typed.
class Build extends PlayerAction {
  Build({
    required super.slot,
    required this.x,
    required this.y,
    required this.building,
    this.townName,
  });

  factory Build.fromJson(Map<String, dynamic> json) => Build(
        slot: json['slot'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
        building: json['building'] as int,
        townName: json['townName'] as String?,
      );

  static const kind = 'build';

  final int x;
  final int y;

  /// Building index (§4). Markt/Stadt are rejected — they only grow.
  final int building;

  final String? townName;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'x': x,
        'y': y,
        'building': building,
        'townName': townName,
      };
}

/// "(A)breißen" — clear the building on an owned tile, 100 T (§4).
class Demolish extends PlayerAction {
  Demolish({required super.slot, required this.x, required this.y});

  factory Demolish.fromJson(Map<String, dynamic> json) => Demolish(
        slot: json['slot'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  static const kind = 'demolish';

  final int x;
  final int y;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {'type': kind, 'slot': slot, 'x': x, 'y': y};
}

/// Menu action "H(e)irat vorschlagen" (§14.1): propose a marriage between
/// one of your dynasty members and a candidate. An AI-controlled target
/// rolls 25% immediately; a human target gets a pending decision.
class ProposeMarriage extends PlayerAction {
  ProposeMarriage({
    required super.slot,
    required this.proposerId,
    required this.targetId,
  });

  factory ProposeMarriage.fromJson(Map<String, dynamic> json) =>
      ProposeMarriage(
        slot: json['slot'] as int,
        proposerId: json['proposerId'] as int,
        targetId: json['targetId'] as int,
      );

  static const kind = 'proposeMarriage';

  final int proposerId;
  final int targetId;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'proposerId': proposerId,
        'targetId': targetId,
      };
}

/// "(B)ürgerlich heiraten" (§14.1): marry one of your dynasty members to
/// a commoner. [DEVIATION] Always accepted (original: 25% roll); the new
/// spouse joins the dynasty so the annual birth loop applies.
class MarryCommoner extends PlayerAction {
  MarryCommoner({required super.slot, required this.personId});

  factory MarryCommoner.fromJson(Map<String, dynamic> json) => MarryCommoner(
        slot: json['slot'] as int,
        personId: json['personId'] as int,
      );

  static const kind = 'marryCommoner';

  final int personId;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'personId': personId};
}

/// Resolves a [PendingDecision] addressed to this slot (ARCHITECTURE.md):
/// marriage consent, heir choice, child naming, election bribes and
/// elector votes all arrive through this one action.
class ResolveDecision extends PlayerAction {
  ResolveDecision({
    required super.slot,
    required this.decisionId,
    this.choice = const {},
  });

  factory ResolveDecision.fromJson(Map<String, dynamic> json) =>
      ResolveDecision(
        slot: json['slot'] as int,
        decisionId: json['decisionId'] as String,
        choice: (json['choice'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  static const kind = 'resolveDecision';

  final String decisionId;
  final Map<String, dynamic> choice;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'decisionId': decisionId,
        'choice': choice,
      };
}

/// "Reiche zusammenlegen" (§6.2): merge another slot you rule into this
/// one. Free; the source must own ≥ 1 tile.
class MergeRealms extends PlayerAction {
  MergeRealms({required super.slot, required this.sourceSlot});

  factory MergeRealms.fromJson(Map<String, dynamic> json) => MergeRealms(
        slot: json['slot'] as int,
        sourceSlot: json['sourceSlot'] as int,
      );

  static const kind = 'mergeRealms';

  final int sourceSlot;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'sourceSlot': sourceSlot};
}

/// "Reich übertragen" [DESIGNED, deviation]: voluntarily hand this whole
/// realm — land, towns, troops, ships, treasury and the dynasty's court —
/// to a FOREIGN ruler. The target absorbs everything ([transferRealm]);
/// the acting seat is vacated, ending the player's part in the game unless
/// they control another realm.
class TransferRealm extends PlayerAction {
  TransferRealm({required super.slot, required this.targetSlot});

  factory TransferRealm.fromJson(Map<String, dynamic> json) => TransferRealm(
        slot: json['slot'] as int,
        targetSlot: json['targetSlot'] as int,
      );

  static const kind = 'transferRealm';

  final int targetSlot;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'targetSlot': targetSlot};
}

/// Buy a colony ship at an own Hafen: 700 T + 1 Zug, the ship
/// spawns on the harbor's water tile and is steered manually afterwards.
class BuyShip extends PlayerAction {
  BuyShip({required super.slot, required this.x, required this.y});

  factory BuyShip.fromJson(Map<String, dynamic> json) => BuyShip(
        slot: json['slot'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  static const kind = 'buyShip';

  /// The own Hafen tile the ship is bought at.
  final int x;
  final int y;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {'type': kind, 'slot': slot, 'x': x, 'y': y};
}

/// Sail a ship to a water tile: the player picks the target,
/// the ship takes the shortest all-water route — 1 Zug per water tile,
/// like the original's "(S)chiff steuern". Long voyages span turns.
class MoveShip extends PlayerAction {
  MoveShip({
    required super.slot,
    required this.shipIndex,
    required this.x,
    required this.y,
  });

  factory MoveShip.fromJson(Map<String, dynamic> json) => MoveShip(
        slot: json['slot'] as int,
        shipIndex: json['shipIndex'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  static const kind = 'moveShip';

  /// Index into the realm's ship list.
  final int shipIndex;

  /// Target water tile.
  final int x;
  final int y;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'shipIndex': shipIndex, 'x': x, 'y': y};
}

/// Colonize a free land tile next to the ship: the ship is
/// consumed (its settlers stay) and a named Dorf is founded on the tile.
class ColonizeShip extends PlayerAction {
  ColonizeShip({
    required super.slot,
    required this.shipIndex,
    required this.x,
    required this.y,
    required this.townName,
  });

  factory ColonizeShip.fromJson(Map<String, dynamic> json) => ColonizeShip(
        slot: json['slot'] as int,
        shipIndex: json['shipIndex'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
        townName: json['townName'] as String,
      );

  static const kind = 'colonizeShip';

  /// Index into the realm's ship list.
  final int shipIndex;

  /// Free land tile orthogonally adjacent to the ship.
  final int x;
  final int y;

  /// Name of the founded Dorf.
  final String townName;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'shipIndex': shipIndex,
        'x': x,
        'y': y,
        'townName': townName,
      };
}

/// The two market goods (§9.1).
enum MarketGood { grain, cattle }

/// Sell grain or cattle at the global market price — once per good per
/// turn (§9.1).
class SellGood extends PlayerAction {
  SellGood({required super.slot, required this.good, required this.amount});

  factory SellGood.fromJson(Map<String, dynamic> json) => SellGood(
        slot: json['slot'] as int,
        good: MarketGood.values.byName(json['good'] as String),
        amount: json['amount'] as int,
      );

  static const kind = 'sellGood';

  final MarketGood good;
  final int amount;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'good': good.name, 'amount': amount};
}

/// Trade-ship investment — once per turn, 50/50 gamble, capped at
/// 600 T × harbors (§9.2).
class InvestShips extends PlayerAction {
  InvestShips({required super.slot, required this.amount});

  factory InvestShips.fromJson(Map<String, dynamic> json) => InvestShips(
        slot: json['slot'] as int,
        amount: json['amount'] as int,
      );

  static const kind = 'investShips';

  final int amount;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'amount': amount};
}

/// Handel-menu "Geld schicken" (§6.2): transfer Taler to another realm
/// (diplomacy, election bribes). No gate beyond a sufficient treasury.
class SendMoney extends PlayerAction {
  SendMoney({
    required super.slot,
    required this.targetSlot,
    required this.amount,
  });

  factory SendMoney.fromJson(Map<String, dynamic> json) => SendMoney(
        slot: json['slot'] as int,
        targetSlot: json['targetSlot'] as int,
        amount: json['amount'] as int,
      );

  static const kind = 'sendMoney';

  final int targetSlot;
  final int amount;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {
        'type': kind,
        'slot': slot,
        'targetSlot': targetSlot,
        'amount': amount,
      };
}

/// "Sitz verlegen" (§6.2): relocate a lost/unset capital onto an own tile
/// with Stadt/Burg/Palast — costs 5,000 T.
class RelocateCapital extends PlayerAction {
  RelocateCapital({required super.slot, required this.x, required this.y});

  factory RelocateCapital.fromJson(Map<String, dynamic> json) =>
      RelocateCapital(
        slot: json['slot'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  static const kind = 'relocateCapital';

  final int x;
  final int y;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {'type': kind, 'slot': slot, 'x': x, 'y': y};
}

/// "Staatskasse plündern" (§17.5): the Kaiser/Sultan collects the
/// accumulated tribute pot into their treasury — a deliberate action, not
/// an automatic payout `[DESIGNED 2026-07-06, user request]`. Free (no
/// Zug); AI office holders trigger it at turn start.
class CollectTribute extends PlayerAction {
  CollectTribute({required super.slot});

  factory CollectTribute.fromJson(Map<String, dynamic> json) =>
      CollectTribute(slot: json['slot'] as int);

  static const kind = 'collectTribute';

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() => {'type': kind, 'slot': slot};
}

/// Change the dynasty's religion (§4): katholisch free, evangelisch 500 T,
/// moslemisch 1,000 T; a floored popularity hit
/// ([religionChangePopularityCost]) on every slot the ruler holds.
class ChangeReligion extends PlayerAction {
  ChangeReligion({required super.slot, required this.religion});

  factory ChangeReligion.fromJson(Map<String, dynamic> json) => ChangeReligion(
        slot: json['slot'] as int,
        religion: json['religion'] as int,
      );

  static const kind = 'changeReligion';

  final int religion;

  @override
  String get type => kind;

  @override
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'religion': religion};
}
