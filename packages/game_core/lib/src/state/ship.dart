/// A colony ship on the map (§9.3, rules v9): bought at an own Hafen,
/// steered manually over water (1 Zug per tile, like the original's
/// "(S)chiff steuern"), consumed when it colonizes a free coastal tile.
///
/// Ships are hidden information like troops: only the owner sees them
/// (`visibleStateFor` redacts foreign realms' ships).
class Ship {
  Ship({required this.x, required this.y});

  factory Ship.fromJson(Map<String, dynamic> json) => Ship(
        x: json['x'] as int,
        y: json['y'] as int,
      );

  /// Position — always a water tile.
  int x;
  int y;

  Ship copy() => Ship(x: x, y: y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}
