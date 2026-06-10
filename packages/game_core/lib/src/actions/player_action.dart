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
        SellGood.kind => SellGood.fromJson(json),
        InvestShips.kind => InvestShips.fromJson(json),
        ProposeMarriage.kind => ProposeMarriage.fromJson(json),
        ResolveDecision.kind => ResolveDecision.fromJson(json),
        RecruitTroops.kind => RecruitTroops.fromJson(json),
        HireSoeldner.kind => HireSoeldner.fromJson(json),
        ReinforceTroop.kind => ReinforceTroop.fromJson(json),
        MergeTroops.kind => MergeTroops.fromJson(json),
        DisbandTroop.kind => DisbandTroop.fromJson(json),
        MoveTroop.kind => MoveTroop.fromJson(json),
        DeclareWar.kind => DeclareWar.fromJson(json),
        WarMove.kind => WarMove.fromJson(json),
        WarPlunder.kind => WarPlunder.fromJson(json),
        WarPeaceWish.kind => WarPeaceWish.fromJson(json),
        WarEndRound.kind => WarEndRound.fromJson(json),
        SettlementAnnex.kind => SettlementAnnex.fromJson(json),
        SettlementFinish.kind => SettlementFinish.fromJson(json),
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
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'x': x, 'y': y};
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
  Map<String, dynamic> toJson() =>
      {'type': kind, 'slot': slot, 'x': x, 'y': y};
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

/// Change the dynasty's religion (§4): katholisch free, evangelisch 500 T,
/// moslemisch 1,000 T; −70 popularity on every slot the ruler holds.
class ChangeReligion extends PlayerAction {
  ChangeReligion({required super.slot, required this.religion});

  factory ChangeReligion.fromJson(Map<String, dynamic> json) =>
      ChangeReligion(
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
