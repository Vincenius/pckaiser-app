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

/// `[DESIGNED]` How a unit behaves when its side's war round is fought on
/// AUTOPILOT — the online war clock running out on an idle human, or a
/// player who left the match. (When the human fights the round live in the
/// war panel they move every unit by hand; the stance is ignored.)
///
///  - [holdPosition] (default): the unit walks back to its pre-war position
///    and defends the base. It only marches on the enemy capital once the
///    enemy has no troops left.
///  - [attack]: the unit advances on the enemy capital straight away.
abstract final class TroopStance {
  static const int holdPosition = 0;
  static const int attack = 1;
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
    this.stance = TroopStance.holdPosition,
    this.plunderedThisRound = false,
  });

  factory Troop.fromJson(Map<String, dynamic> json) => Troop(
        name: json['name'] as String,
        men: json['men'] as int,
        troopClass: json['troopClass'] as int,
        quality: json['quality'] as int,
        garrisonCounted: json['garrisonCounted'] as bool,
        x: json['x'] as int,
        y: json['y'] as int,
        // Additive field — units from older saves default to holding their
        // position (defending the base).
        stance: json['stance'] as int? ?? TroopStance.holdPosition,
        // Additive field — units from older saves have not plundered yet.
        plunderedThisRound: json['plunderedThisRound'] as bool? ?? false,
      );

  String name;
  int men;

  /// Mutable: "Truppe umrüsten" retrains the class.
  int troopClass;

  /// Mutable: drilling ("ausbilden", proc_00A316) raises it by 1 per
  /// drill, capped at [drillCap].
  int quality;

  /// Quality ceiling for drilled regulars. `[DESIGNED]` raised to 99:
  /// costs scale with level (`5 × men × quality`), so high levels are
  /// expensive to reach; reinforcing new recruits dilutes quality back down.
  static const int drillCap = 99;

  /// False for Söldner — they never count against garrison capacity (§10.2).
  final bool garrisonCounted;

  int x;
  int y;

  /// Autopilot behaviour for an unattended war round (see [TroopStance]).
  /// Mutable: set per unit via the "Verhalten im Krieg" toggle.
  int stance;

  /// §11.5: each army plunders once per war round. Cleared at war start
  /// and on every round advance.
  bool plunderedThisRound;

  Troop copy() => Troop(
        name: name,
        men: men,
        troopClass: troopClass,
        quality: quality,
        garrisonCounted: garrisonCounted,
        x: x,
        y: y,
        stance: stance,
        plunderedThisRound: plunderedThisRound,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'men': men,
        'troopClass': troopClass,
        'quality': quality,
        'garrisonCounted': garrisonCounted,
        'x': x,
        'y': y,
        'stance': stance,
        'plunderedThisRound': plunderedThisRound,
      };
}
