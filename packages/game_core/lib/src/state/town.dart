/// A town object — Dorf, Markt or Stadt (ORIGINAL_GAME.md §2, §8.3).
class Town {
  Town({
    required this.name,
    required this.population,
    required this.troopCapacity,
    required this.garrison,
    required this.buildingType,
    required this.x,
    required this.y,
  });

  factory Town.fromJson(Map<String, dynamic> json) => Town(
        name: json['name'] as String,
        population: json['population'] as int,
        troopCapacity: json['troopCapacity'] as int,
        garrison: json['garrison'] as int,
        buildingType: json['buildingType'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
      );

  String name;
  int population;
  int troopCapacity;
  int garrison;

  /// 3 = Dorf, 4 = Markt, 5 = Stadt (§4).
  int buildingType;

  final int x;
  final int y;

  Town copy() => Town(
        name: name,
        population: population,
        troopCapacity: troopCapacity,
        garrison: garrison,
        buildingType: buildingType,
        x: x,
        y: y,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'population': population,
        'troopCapacity': troopCapacity,
        'garrison': garrison,
        'buildingType': buildingType,
        'x': x,
        'y': y,
      };
}
