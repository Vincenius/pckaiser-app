import 'constants.dart';

/// The 80×44 tile map (ORIGINAL_GAME.md §3.1).
///
/// Stored as four parallel flat lists indexed `y * width + x` — compact in
/// JSON and cheap to copy.
class WorldMap {
  WorldMap({
    required this.terrain,
    required this.owner,
    required this.building,
    required this.troopMarker,
  })  : assert(terrain.length == World.mapWidth * World.mapHeight),
        assert(owner.length == terrain.length),
        assert(building.length == terrain.length),
        assert(troopMarker.length == terrain.length);

  /// All tiles open water (terrain 2), unowned, no building.
  factory WorldMap.water() {
    const size = World.mapWidth * World.mapHeight;
    return WorldMap(
      terrain: List.filled(size, Terrain.water, growable: false),
      owner: List.filled(size, World.niemand, growable: false),
      building: List.filled(size, Building.none, growable: false),
      troopMarker: List.filled(size, 0, growable: false),
    );
  }

  factory WorldMap.fromJson(Map<String, dynamic> json) => WorldMap(
        terrain: (json['terrain'] as List).cast<int>(),
        owner: (json['owner'] as List).cast<int>(),
        building: (json['building'] as List).cast<int>(),
        troopMarker: (json['troopMarker'] as List).cast<int>(),
      );

  final List<int> terrain;
  final List<int> owner;
  final List<int> building;
  final List<int> troopMarker;

  int get width => World.mapWidth;
  int get height => World.mapHeight;

  bool inBounds(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;

  int index(int x, int y) => y * width + x;

  int terrainAt(int x, int y) => terrain[index(x, y)];
  int ownerAt(int x, int y) => owner[index(x, y)];
  int buildingAt(int x, int y) => building[index(x, y)];

  bool isWaterAt(int x, int y) => Terrain.isWater(terrainAt(x, y));
  bool isLandAt(int x, int y) => Terrain.isLand(terrainAt(x, y));

  /// All realm slots whose territory orthogonally touches [slot]'s — wars
  /// may only be declared across a shared border.
  Set<int> realmNeighbors(int slot) {
    final neighbors = <int>{};
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (ownerAt(x, y) != slot) continue;
        for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
          if (!inBounds(x + dx, y + dy)) continue;
          final other = ownerAt(x + dx, y + dy);
          if (other != slot && other != World.niemand) neighbors.add(other);
        }
      }
    }
    return neighbors;
  }

  WorldMap copy() => WorldMap(
        terrain: List.of(terrain, growable: false),
        owner: List.of(owner, growable: false),
        building: List.of(building, growable: false),
        troopMarker: List.of(troopMarker, growable: false),
      );

  Map<String, dynamic> toJson() => {
        'terrain': terrain,
        'owner': owner,
        'building': building,
        'troopMarker': troopMarker,
      };
}
