/// Troop unit classes (ORIGINAL_GAME.md §2, §10.1).
abstract final class TroopClass {
  static const int infanterie = 0;
  static const int kavallerie = 1;
  static const int artillerie = 2;
}

/// Troop quality values (§2): 1 = regular, 3 = Söldner, 50 = Janitscharen.
/// The reworked §18.4 event (deviation 2026-07-28) spawns its Janissary
/// guard at [janitscharenGuard] instead of the original's near-unbeatable
/// 50 — [janitscharen] stays for combat math and for old saves that still
/// carry the original troop.
abstract final class TroopQuality {
  static const int regular = 1;
  static const int soeldner = 3;
  static const int janitscharen = 50;
  static const int janitscharenGuard = 10;
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
    this.id = 0,
    this.stance = TroopStance.holdPosition,
    this.plunderedThisRound = false,
    this.janissary = false,
  });

  factory Troop.fromJson(Map<String, dynamic> json) => Troop(
        name: json['name'] as String,
        men: json['men'] as int,
        troopClass: json['troopClass'] as int,
        quality: json['quality'] as int,
        garrisonCounted: json['garrisonCounted'] as bool,
        x: json['x'] as int,
        y: json['y'] as int,
        // Additive field — units from older saves get an id assigned on
        // load (GameState.fromJson).
        id: json['id'] as int? ?? 0,
        // Additive field — units from older saves default to holding their
        // position (defending the base).
        stance: json['stance'] as int? ?? TroopStance.holdPosition,
        // Additive field — units from older saves have not plundered yet.
        plunderedThisRound: json['plunderedThisRound'] as bool? ?? false,
        // Additive field — only the §18.4 Ottoman guard carries it. Old
        // saves' original 1,000-man Janitscharen deliberately stay false:
        // whoever holds them keeps them, we only stop NEW ones migrating.
        janissary: json['janissary'] as bool? ?? false,
      );

  /// Stable unit identity, unique within one game (assigned from
  /// `GameState.nextUnitId` at creation; older saves get ids on load).
  /// 0 = unassigned — the war snapshot pairing then falls back to the
  /// legacy name matching (hand-built test units, pre-id snapshots).
  int id;

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

  /// §18.4 rework (deviation 2026-07-28): the Ottoman guard serves the
  /// house it was installed for — `disbandJanissaries` removes flagged
  /// units whenever their realm passes to another house (inheritance,
  /// merge/transfer, replacement dynasty), so no player ever "suddenly
  /// owns" them.
  final bool janissary;

  Troop copy() => Troop(
        name: name,
        men: men,
        troopClass: troopClass,
        quality: quality,
        garrisonCounted: garrisonCounted,
        x: x,
        y: y,
        id: id,
        stance: stance,
        plunderedThisRound: plunderedThisRound,
        janissary: janissary,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'men': men,
        'troopClass': troopClass,
        'quality': quality,
        'garrisonCounted': garrisonCounted,
        'x': x,
        'y': y,
        'id': id,
        'stance': stance,
        'plunderedThisRound': plunderedThisRound,
        'janissary': janissary,
      };
}
