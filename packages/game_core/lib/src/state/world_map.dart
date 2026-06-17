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

  /// True if the land tile [x],[y] touches water reachable from one of
  /// [slot]'s harbors — the colony ship's sea route (§9.3): BFS over
  /// water tiles seeded with every own Hafen.
  bool shipReachable(int slot, int x, int y) {
    final visited = List<bool>.filled(terrain.length, false);
    final queue = <int>[];
    for (var i = 0; i < terrain.length; i++) {
      if (owner[i] == slot &&
          building[i] == Building.hafen &&
          Terrain.isWater(terrain[i])) {
        visited[i] = true;
        queue.add(i);
      }
    }
    final target = index(x, y);
    for (var head = 0; head < queue.length; head++) {
      final tx = queue[head] % width;
      final ty = queue[head] ~/ width;
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        final nx = tx + dx;
        final ny = ty + dy;
        if (!inBounds(nx, ny)) continue;
        final ni = index(nx, ny);
        if (ni == target) return true;
        if (visited[ni] || !Terrain.isWater(terrain[ni])) continue;
        visited[ni] = true;
        queue.add(ni);
      }
    }
    return false;
  }

  /// True if a troop at land tile ([fromX],[fromY]) can be transported by sea
  /// to land tile ([toX],[toY]) using [slot]'s harbors: requires an own harbor
  /// water tile adjacent to the troop's position and a connected water path
  /// (via any sea tiles) to a water tile adjacent to the target.
  bool canNavalTransport(int slot, int fromX, int fromY, int toX, int toY) {
    if (!inBounds(toX, toY) || !isLandAt(toX, toY)) return false;
    final visited = List<bool>.filled(terrain.length, false);
    final queue = <int>[];
    for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
      final hx = fromX + dx;
      final hy = fromY + dy;
      if (!inBounds(hx, hy)) continue;
      final hi = index(hx, hy);
      if (owner[hi] == slot &&
          building[hi] == Building.hafen &&
          Terrain.isWater(terrain[hi]) &&
          !visited[hi]) {
        visited[hi] = true;
        queue.add(hi);
      }
    }
    if (queue.isEmpty) return false;
    for (var head = 0; head < queue.length; head++) {
      final cx = queue[head] % width;
      final cy = queue[head] ~/ width;
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (!inBounds(nx, ny)) continue;
        if (nx == toX && ny == toY) return true;
        final ni = index(nx, ny);
        if (visited[ni] || !Terrain.isWater(terrain[ni])) continue;
        visited[ni] = true;
        queue.add(ni);
      }
    }
    return false;
  }

  /// Length of the shortest all-water path from ([fromX],[fromY]) to
  /// ([toX],[toY]) in orthogonal steps, or -1 when unreachable. Both ends
  /// must be water tiles. Used by the manual ship voyage:
  /// every water tile sailed costs 1 Zug, like the original's
  /// "(S)chiff steuern".
  int waterPathLength(int fromX, int fromY, int toX, int toY) {
    if (!inBounds(fromX, fromY) ||
        !inBounds(toX, toY) ||
        !isWaterAt(fromX, fromY) ||
        !isWaterAt(toX, toY)) {
      return -1;
    }
    final start = index(fromX, fromY);
    final goal = index(toX, toY);
    if (start == goal) return 0;
    final dist = List<int>.filled(terrain.length, -1);
    dist[start] = 0;
    final queue = <int>[start];
    for (var head = 0; head < queue.length; head++) {
      final cur = queue[head];
      final cx = cur % width;
      final cy = cur ~/ width;
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (!inBounds(nx, ny)) continue;
        final ni = index(nx, ny);
        if (dist[ni] != -1 || !Terrain.isWater(terrain[ni])) continue;
        dist[ni] = dist[cur] + 1;
        if (ni == goal) return dist[ni];
        queue.add(ni);
      }
    }
    return -1;
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
