/// Troop unit classes (ORIGINAL_GAME.md §2, §10.1).
abstract final class TroopClass {
  static const int infanterie = 0;
  static const int kavallerie = 1;
  static const int artillerie = 2;
}

/// Troop quality values (§2): 1 = regular, 3 = Söldner, 50 = Janitscharen.
abstract final class TroopQuality {
  static const int regular = 1;
  static const int soeldner = 3;
  static const int janitscharen = 50;
}

/// A troop unit (ORIGINAL_GAME.md §2, §10).
class Troop {
  Troop({
    required this.name,
    required this.men,
    required this.troopClass,
    required this.quality,
    required this.garrisonCounted,
    required this.x,
    required this.y,
  });

  factory Troop.fromJson(Map<String, dynamic> json) => Troop(
        name: json['name'] as String,
        men: json['men'] as int,
        troopClass: json['troopClass'] as int,
        quality: json['quality'] as int,
        garrisonCounted: json['garrisonCounted'] as bool,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  String name;
  int men;
  final int troopClass;
  final int quality;

  /// False for Söldner — they never count against garrison capacity (§10.2).
  final bool garrisonCounted;

  int x;
  int y;

  Troop copy() => Troop(
        name: name,
        men: men,
        troopClass: troopClass,
        quality: quality,
        garrisonCounted: garrisonCounted,
        x: x,
        y: y,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'men': men,
        'troopClass': troopClass,
        'quality': quality,
        'garrisonCounted': garrisonCounted,
        'x': x,
        'y': y,
      };
}
