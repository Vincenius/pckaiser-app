/// Player action types (ARCHITECTURE.md `actions/`). Actions are the only
/// way state changes: serialized over the wire in online mode, applied
/// locally in hot-seat mode — both through `applyAction`.
library;

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
