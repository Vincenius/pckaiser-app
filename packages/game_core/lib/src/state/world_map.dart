import 'constants.dart';

/// The tile map (ORIGINAL_GAME.md §3.1) — 80×44 in the original; smaller
/// map sizes shrink the grid (see `MapSize`).
///
/// Stored as four parallel flat lists indexed `y * width + x` — compact in
/// JSON and cheap to copy.
class WorldMap {
  WorldMap({
    required this.terrain,
    required this.owner,
    required this.building,
    required this.troopMarker,
    List<int>? devastatedUntil,
    this.width = World.mapWidth,
    this.height = World.mapHeight,
  })  : devastatedUntil =
            devastatedUntil ?? List.filled(terrain.length, 0, growable: false),
        assert(terrain.length == width * height),
        assert(owner.length == terrain.length),
        assert(building.length == terrain.length),
        assert(troopMarker.length == terrain.length);

  /// All tiles open water (terrain 2), unowned, no building.
  factory WorldMap.water(
      {int width = World.mapWidth, int height = World.mapHeight}) {
    final size = width * height;
    return WorldMap(
      width: width,
      height: height,
      terrain: List.filled(size, Terrain.water, growable: false),
      owner: List.filled(size, World.niemand, growable: false),
      building: List.filled(size, Building.none, growable: false),
      troopMarker: List.filled(size, 0, growable: false),
    );
  }

  // `cast<int>()` returns a write-through VIEW over the decoded JSON list,
  // not a copy. These four lists are mutated in place all over the engine
  // (`map.building[i] = …`, `troopMarker.fillRange(…)`), so a bare cast
  // would let those writes leak back into the source JSON document — and vice
  // versa. Materialize fresh lists so a loaded map owns its storage, matching
  // the `copy()` contract and the class doc ("cheap to copy").
  factory WorldMap.fromJson(Map<String, dynamic> json) => WorldMap(
        terrain: (json['terrain'] as List).cast<int>().toList(),
        owner: (json['owner'] as List).cast<int>().toList(),
        building: (json['building'] as List).cast<int>().toList(),
        troopMarker: (json['troopMarker'] as List).cast<int>().toList(),
        // Additive field (2026-07-19) — older saves have no devastation.
        devastatedUntil:
            (json['devastatedUntil'] as List?)?.cast<int>().toList(),
        // Additive fields (2026-07-21, map sizes) — older saves are always
        // the original 80×44 world.
        width: json['width'] as int? ?? World.mapWidth,
        height: json['height'] as int? ?? World.mapHeight,
      );

  final List<int> terrain;
  final List<int> owner;
  final List<int> building;
  final List<int> troopMarker;

  /// Per tile: the YEAR a war-plundered field recovers (0 = intact). A
  /// Kornfeld/Weide with `devastatedUntil[i] > year` lies fallow — it
  /// yields nothing but keeps its owner and building (user rule
  /// 2026-07-19: plunder devastates fields instead of erasing them, so
  /// wars no longer shrink the world permanently).
  final List<int> devastatedUntil;

  /// Whether the field at ([x],[y]) currently lies devastated in [year].
  bool isDevastatedAt(int x, int y, int year) =>
      devastatedUntil[index(x, y)] > year;

  /// Grid dimensions — fixed per game at setup (see `MapSize`).
  final int width;
  final int height;

  bool inBounds(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;

  int index(int x, int y) => y * width + x;

  int terrainAt(int x, int y) => terrain[index(x, y)];
  int ownerAt(int x, int y) => owner[index(x, y)];
  int buildingAt(int x, int y) => building[index(x, y)];

  bool isWaterAt(int x, int y) => Terrain.isWater(terrainAt(x, y));
  bool isLandAt(int x, int y) => Terrain.isLand(terrainAt(x, y));

  /// The four orthogonal step offsets — THE definition of adjacency
  /// (movement, claims, borders, war marches all use it).
  static const List<(int, int)> orthogonalSteps = [
    (-1, 0),
    (1, 0),
    (0, 1),
    (0, -1),
  ];

  /// In-bounds orthogonal neighbor coordinates of ([x],[y]).
  Iterable<(int, int)> neighborsOf(int x, int y) sync* {
    for (final (dx, dy) in orthogonalSteps) {
      if (inBounds(x + dx, y + dy)) yield (x + dx, y + dy);
    }
  }

  /// Whether any orthogonal neighbor of ([x],[y]) is owned by [slot] —
  /// the shared border test (tile claims, settlement annexes, hafen
  /// anchoring, AI expansion).
  bool bordersSlot(int x, int y, int slot) {
    for (final (nx, ny) in neighborsOf(x, y)) {
      if (ownerAt(nx, ny) == slot) return true;
    }
    return false;
  }

  /// Like [bordersSlot], but only [slot]'s LAND tiles count — an own Hafen
  /// on a water tile must not anchor further coastal builds.
  bool bordersSlotLand(int x, int y, int slot) {
    for (final (nx, ny) in neighborsOf(x, y)) {
      if (ownerAt(nx, ny) == slot && isLandAt(nx, ny)) return true;
    }
    return false;
  }

  /// All realm slots whose territory orthogonally touches [slot]'s — wars
  /// may only be declared across a shared border.
  Set<int> realmNeighbors(int slot) {
    final neighbors = <int>{};
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (ownerAt(x, y) != slot) continue;
        for (final (nx, ny) in neighborsOf(x, y)) {
          final other = ownerAt(nx, ny);
          if (other != slot && other != World.niemand) neighbors.add(other);
        }
      }
    }
    return neighbors;
  }

  /// True if a troop at land tile ([fromX],[fromY]) can be transported by sea
  /// to land tile ([toX],[toY]) using [slot]'s harbors: requires an own harbor
  /// water tile adjacent to the troop's position and a connected water path
  /// (via any sea tiles) to a water tile adjacent to the target.
  /// [harborOwners] widens whose harbors may serve as the embark point —
  /// at war, troops may also use the ENEMY's harbors (user rule 2026-07-19).
  bool canNavalTransport(int slot, int fromX, int fromY, int toX, int toY,
      {Set<int>? harborOwners}) {
    final owners = harborOwners ?? {slot};
    if (!inBounds(toX, toY) || !isLandAt(toX, toY)) return false;
    final visited = List<bool>.filled(terrain.length, false);
    final queue = <int>[];
    for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
      final hx = fromX + dx;
      final hy = fromY + dy;
      if (!inBounds(hx, hy)) continue;
      final hi = index(hx, hy);
      if (owners.contains(owner[hi]) &&
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

  /// The land tile next to one of [slot]'s harbors, sea-connected to the
  /// coastal target ([toX],[toY]), that is closest (Manhattan) to
  /// ([fromX],[fromY]) — i.e. the tile a unit must reach to embark for that
  /// destination. Null when no harbor of [slot] connects to the target.
  /// Drives the client's "tap a sea-separated tile → march to the harbor,
  /// then ship across" routing; [canNavalTransport] from the returned tile
  /// to the target is guaranteed true. [harborOwners] widens the usable
  /// harbors like in [canNavalTransport] (enemy harbors at war).
  (int, int)? navalEmbarkTile(int slot, int fromX, int fromY, int toX, int toY,
      {Set<int>? harborOwners}) {
    final owners = harborOwners ?? {slot};
    if (!inBounds(toX, toY) || !isLandAt(toX, toY)) return null;
    (int, int)? best;
    var bestDist = 1 << 30;
    for (var i = 0; i < terrain.length; i++) {
      if (!owners.contains(owner[i]) ||
          building[i] != Building.hafen ||
          !Terrain.isWater(terrain[i])) {
        continue;
      }
      final hx = i % width;
      final hy = i ~/ width;
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        final lx = hx + dx;
        final ly = hy + dy;
        if (!inBounds(lx, ly) || !isLandAt(lx, ly)) continue;
        if (!canNavalTransport(slot, lx, ly, toX, toY,
            harborOwners: owners)) {
          continue;
        }
        final dist = (lx - fromX).abs() + (ly - fromY).abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = (lx, ly);
        }
      }
    }
    return best;
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
        width: width,
        height: height,
        terrain: List.of(terrain, growable: false),
        owner: List.of(owner, growable: false),
        building: List.of(building, growable: false),
        troopMarker: List.of(troopMarker, growable: false),
        devastatedUntil: List.of(devastatedUntil, growable: false),
      );

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'terrain': terrain,
        'owner': owner,
        'building': building,
        'troopMarker': troopMarker,
        'devastatedUntil': devastatedUntil,
      };
}
