import 'dart:math' as math;

import '../rng/rng.dart';
import '../state/constants.dart';
import '../state/world_map.dart';

/// Movement-point roll — the realm's Züge for the turn (and, per unit, for
/// a war round): `max(minimum, popularity ~/ divisor) + random(6)`.
///
/// `[DEVIATION from §6.3, 2026-08-24 user request]` The original rolled
/// `titleClass + random(6)`, tying the action budget to the prestige score
/// and thus to realm size. It now rides on Beliebtheit — see
/// [movementPopularityDivisor] for the why and the calibration.
int rollMovementPoints(int popularity, Rng rng) =>
    math.max(movementPointsMinimum, popularity ~/ movementPopularityDivisor) +
    rng.nextInt(6);

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

/// The passable tile reachable from ([x],[y]) that lies nearest to
/// ([tx],[ty]) — same land graph as [warPathStep] (water blocks;
/// [allowedOwners] restricts, start excepted). Ties go to the tile
/// fewest steps away. Returns null when no reachable tile is nearer than
/// the start itself. Lets a war march approach a click it cannot reach
/// (an island, third-realm land) as far as possible instead of refusing.
(int, int)? closestReachableTile(WorldMap map, int x, int y, int tx, int ty,
    {Set<int>? allowedOwners}) {
  final start = map.index(x, y);
  final seen = List<bool>.filled(map.terrain.length, false);
  seen[start] = true;
  final queue = <int>[start];
  int distTo(int i) => (i % map.width - tx).abs() + (i ~/ map.width - ty).abs();
  var best = start;
  var bestDist = distTo(start);
  for (var head = 0; head < queue.length; head++) {
    final cur = queue[head];
    // BFS visits in step order, so a STRICT improvement keeps the
    // shallowest tile among equally near ones.
    final d = distTo(cur);
    if (d < bestDist) {
      bestDist = d;
      best = cur;
      if (d == 0) break;
    }
    for (final (nx, ny) in map.neighborsOf(cur % map.width, cur ~/ map.width)) {
      if (map.isWaterAt(nx, ny)) continue;
      final ni = map.index(nx, ny);
      if (seen[ni]) continue;
      if (allowedOwners != null && !allowedOwners.contains(map.owner[ni])) {
        continue;
      }
      seen[ni] = true;
      queue.add(ni);
    }
  }
  if (best == start) return null;
  return (best % map.width, best ~/ map.width);
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
