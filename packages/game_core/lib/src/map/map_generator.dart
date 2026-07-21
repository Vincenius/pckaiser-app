import '../rng/rng.dart';
import '../state/constants.dart';
import '../state/map_size.dart';
import '../state/world_map.dart';

/// Procedural map generation (ORIGINAL_GAME.md §3.2). Every game world is
/// random — there is no fixed scenario map.
///
/// The algorithm and its RNG call order follow the original exactly:
/// land patches, then lakes, then the shoreline pass. On [MapSize.gross]
/// (the default) the output is bit-identical to the pre-map-size generator;
/// smaller sizes shrink the grid and scale the patch/lake counts by area.
WorldMap generateMap(Rng rng, {MapSize size = MapSize.gross}) {
  final map = WorldMap.water(width: size.width, height: size.height);
  // The original spawns patches in [0, 70) × [0, 34) on the 80×44 grid —
  // a 10-tile margin that keeps every patch (≤ 7 tiles tall/wide) in
  // bounds. The same margin generalizes to the smaller grids.
  final spawnW = size.width - 10;
  final spawnH = size.height - 10;

  // Land patches (original: 100): 8 rows × ~6–8 cols, terrain Ebene p=6/7,
  // Berg p=1/7.
  for (var patch = 0; patch < size.landPatches; patch++) {
    final x0 = rng.nextInt(spawnW);
    final y0 = rng.nextInt(spawnH);
    for (var y = y0; y <= y0 + 7; y++) {
      final xStart = x0 + rng.nextInt(2);
      final xEnd = x0 + 5 + rng.nextInt(2);
      for (var x = xStart; x <= xEnd; x++) {
        map.terrain[map.index(x, y)] = rng.nextInt(7) ~/ 6;
      }
    }
  }

  // Lakes (original: 25): small rectangles set back to water.
  for (var lake = 0; lake < size.lakes; lake++) {
    final x0 = rng.nextInt(spawnW);
    final y0 = rng.nextInt(spawnH);
    final yEnd = y0 + 2 + rng.nextInt(3);
    final xStart = x0 + rng.nextInt(2);
    final xEnd = x0 + 2 + rng.nextInt(3);
    for (var y = y0; y <= yEnd; y++) {
      for (var x = xStart; x <= xEnd; x++) {
        map.terrain[map.index(x, y)] = Terrain.water;
      }
    }
  }

  applyShorelinePass(map);
  return map;
}

/// Shoreline pass (§3.1, §3.2 step 4): every water tile gets
/// `terrain = 2 + landNeighborMask`. The 4-bit mask encodes which orthogonal
/// neighbors are land: bit3 = +X, bit2 = −X, bit1 = −Y, bit0 = +Y.
/// Out-of-bounds neighbors count as water. Order-independent because only
/// water values (≥ 2) change.
void applyShorelinePass(WorldMap map) {
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.isLandAt(x, y)) continue;
      map.terrain[map.index(x, y)] =
          Terrain.water + landNeighborMask(map, x, y);
    }
  }
}

/// 4-bit land-neighbor mask for the tile at (x, y) — see [applyShorelinePass].
int landNeighborMask(WorldMap map, int x, int y) {
  bool land(int nx, int ny) => map.inBounds(nx, ny) && map.isLandAt(nx, ny);
  return (land(x + 1, y) ? 8 : 0) |
      (land(x - 1, y) ? 4 : 0) |
      (land(x, y - 1) ? 2 : 0) |
      (land(x, y + 1) ? 1 : 0);
}
