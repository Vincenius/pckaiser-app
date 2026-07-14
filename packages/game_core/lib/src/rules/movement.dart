import '../rng/rng.dart';
import '../state/world_map.dart';
import 'titles.dart' show christianEquivalentClass;

/// Christian-equivalent class for the movement roll (§6.3) — the shared
/// ladder mapping from rules/titles.dart.
int movementClassEquivalent(int titleClass) =>
    christianEquivalentClass(titleClass);

/// Movement-point roll (ORIGINAL_GAME.md §6.3):
/// `points = classEquivalent + random(6)`.
int rollMovementPoints(int titleClass, Rng rng) =>
    movementClassEquivalent(titleClass) + rng.nextInt(6);

/// First step (dx, dy) of a shortest LAND path from ([x],[y]) to
/// ([tx],[ty]); null when the target is the start itself or unreachable
/// over land. If [allowedOwners] is non-null, only tiles whose owner is in
/// the set (plus the start tile) are traversed — the war-march passability
/// rule (own, enemy and neutral land; third realms block). Shared by the
/// AI war movement and the WarMarch action, so both march by the same map.
(int, int)? warPathStep(WorldMap map, int x, int y, int tx, int ty,
    {Set<int>? allowedOwners}) {
  final start = map.index(x, y);
  final goal = map.index(tx, ty);
  if (start == goal) return null;
  final prev = List<int>.filled(map.terrain.length, -1);
  prev[start] = start;
  final queue = <int>[start];
  for (var head = 0; head < queue.length; head++) {
    final cur = queue[head];
    if (cur == goal) break;
    final cx = cur % map.width;
    final cy = cur ~/ map.width;
    for (final (nx, ny) in map.neighborsOf(cx, cy)) {
      if (map.isWaterAt(nx, ny)) continue;
      final ni = map.index(nx, ny);
      if (prev[ni] != -1) continue;
      if (allowedOwners != null && !allowedOwners.contains(map.owner[ni])) {
        continue;
      }
      prev[ni] = cur;
      queue.add(ni);
    }
  }
  if (prev[goal] == -1) return null; // unreachable (island capital etc.)
  var cur = goal;
  while (prev[cur] != start) {
    cur = prev[cur];
  }
  return (cur % map.width - x, cur ~/ map.width - y);
}

/// Greedy fallback step toward ([tx],[ty]) when no full path exists
/// ([warPathStep] returned null): the direct axes first, then any
/// passable detour. Keeps a unit inching toward a coastal target the BFS
/// cannot fully reach.
(int, int)? greedyStepToward(WorldMap map, int x, int y, int tx, int ty,
    {Set<int>? allowedOwners}) {
  final candidates = <(int, int)>[];
  if (tx > x) candidates.add((1, 0));
  if (tx < x) candidates.add((-1, 0));
  if (ty > y) candidates.add((0, 1));
  if (ty < y) candidates.add((0, -1));
  // Detours when the direct axes are blocked by water.
  candidates.addAll(const [(0, 1), (0, -1), (1, 0), (-1, 0)]);
  for (final (dx, dy) in candidates) {
    final nx = x + dx;
    final ny = y + dy;
    if (!map.inBounds(nx, ny) || map.isWaterAt(nx, ny)) continue;
    if (allowedOwners != null &&
        !allowedOwners.contains(map.owner[map.index(nx, ny)])) {
      continue;
    }
    return (dx, dy);
  }
  return null;
}
