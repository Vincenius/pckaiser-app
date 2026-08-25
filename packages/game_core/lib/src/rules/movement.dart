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

/// A single-source route search over the war-march land graph, computed
/// once and then queried — `[DESIGNED 2026-08-24, user request]` THE
/// pathfinder behind every march (player tap, AI unit, approach retarget,
/// harbor routing). One search answers "can I get there", "how far is it",
/// "which way do I step" and "what is the whole path", so a planner and
/// the step it plans can never disagree.
///
/// Costs are not plain step counts: a tile in [warPathAvoid] costs
/// [warPathAvoidPenalty] extra, which leaves the route the SAME length
/// while steering it around an enemy stack that is not the destination —
/// a march ordered to a far tile no longer walks into an unrelated battle
/// when an equally short way around exists.
class WarField {
  WarField._(this.map, this.start, this._cost, this._prev);

  final WorldMap map;

  /// Flat index of the tile the search started from.
  final int start;

  final List<int> _cost;
  final List<int> _prev;

  bool _valid(int x, int y) => map.inBounds(x, y) && _cost[map.index(x, y)] >= 0;

  /// Whether a march can reach ([x],[y]) at all.
  bool reaches(int x, int y) => _valid(x, y);

  /// Route cost to ([x],[y]) (steps plus avoidance penalties), or -1.
  int costTo(int x, int y) => map.inBounds(x, y) ? _cost[map.index(x, y)] : -1;

  /// Number of MOVES (one Zug each) the route to ([x],[y]) spends, or -1 —
  /// the penalties in [costTo] are a routing preference, not a toll.
  int stepsTo(int x, int y) {
    if (!_valid(x, y)) return -1;
    var steps = 0;
    var cur = map.index(x, y);
    while (cur != start) {
      cur = _prev[cur];
      steps++;
    }
    return steps;
  }

  /// The whole route to ([x],[y]) as tile coordinates, start EXCLUDED
  /// (empty when the target is the start itself), or null when unreachable.
  List<(int, int)>? pathTo(int x, int y) {
    if (!_valid(x, y)) return null;
    final path = <(int, int)>[];
    var cur = map.index(x, y);
    while (cur != start) {
      path.add((cur % map.width, cur ~/ map.width));
      cur = _prev[cur];
    }
    return path.reversed.toList();
  }

  /// First step (dx, dy) of the route to ([x],[y]); null when the target is
  /// the start itself or unreachable.
  (int, int)? firstStepTo(int x, int y) {
    if (!_valid(x, y)) return null;
    var cur = map.index(x, y);
    if (cur == start) return null;
    while (_prev[cur] != start) {
      cur = _prev[cur];
    }
    return (cur % map.width - start % map.width,
        cur ~/ map.width - start ~/ map.width);
  }
}

/// Extra route cost for crossing a tile in `avoid` — see [WarField]. Big
/// enough that a march prefers any detour of equal length, small enough
/// that it never walks a genuinely longer way around.
const int warPathAvoidPenalty = 4;

/// Searches the war-march land graph from ([x],[y]).
///
/// Water blocks (embarking is a [warSeaEmbark] voyage, not a step). When
/// [allowedOwners] is non-null only tiles whose owner is in the set are
/// traversed, the start excepted — the §11.2 war-march passability rule
/// (own, enemy and neutral land; third realms block). [avoid] holds flat
/// tile indices the route should route around when it can (enemy stacks).
WarField warField(WorldMap map, int x, int y,
    {Set<int>? allowedOwners, Set<int>? avoid}) {
  final size = map.terrain.length;
  final cost = List<int>.filled(size, -1);
  final prev = List<int>.filled(size, -1);
  final start = map.index(x, y);
  cost[start] = 0;
  prev[start] = start;
  // Dijkstra over a tiny cost range (1 or 1 + penalty): bucket the frontier
  // by cost instead of paying for a heap. Buckets are visited in order, so
  // the first pop of a tile is its cheapest route.
  final buckets = <int, List<int>>{
    0: [start]
  };
  for (var c = 0; buckets.isNotEmpty; c++) {
    final bucket = buckets.remove(c);
    if (bucket == null) continue;
    for (final cur in bucket) {
      if (cost[cur] != c) continue; // stale entry from a costlier route
      final cx = cur % map.width;
      final cy = cur ~/ map.width;
      for (final (nx, ny) in map.neighborsOf(cx, cy)) {
        if (map.isWaterAt(nx, ny)) continue;
        final ni = map.index(nx, ny);
        if (allowedOwners != null && !allowedOwners.contains(map.owner[ni])) {
          continue;
        }
        final next = c + 1 + (avoid != null && avoid.contains(ni)
            ? warPathAvoidPenalty
            : 0);
        if (cost[ni] != -1 && cost[ni] <= next) continue;
        cost[ni] = next;
        prev[ni] = cur;
        (buckets[next] ??= <int>[]).add(ni);
      }
    }
  }
  return WarField._(map, start, cost, prev);
}

/// First step (dx, dy) of a shortest LAND path from ([x],[y]) to
/// ([tx],[ty]); null when the target is the start itself or unreachable
/// over land. If [allowedOwners] is non-null, only tiles whose owner is in
/// the set (plus the start tile) are traversed — the war-march passability
/// rule (own, enemy and neutral land; third realms block). Shared by the
/// AI war movement and the WarMarch action, so both march by the same map.
///
/// A convenience over [warField]; callers that need more than one answer
/// should build the field once and query it.
(int, int)? warPathStep(WorldMap map, int x, int y, int tx, int ty,
        {Set<int>? allowedOwners}) =>
    warField(map, x, y, allowedOwners: allowedOwners).firstStepTo(tx, ty);

/// The passable tile reachable from ([x],[y]) that lies nearest to
/// ([tx],[ty]) — same land graph as [warPathStep] (water blocks;
/// [allowedOwners] restricts, start excepted). Returns null when no
/// reachable tile is nearer than the start itself. Lets a war march
/// approach a click it cannot reach (an island, third-realm land) as far
/// as possible instead of refusing.
///
/// "Nearest" is measured by WALKING (a second search rooted at the click,
/// ownership ignored — a third realm's fields still show which way the
/// click lies), not as the crow flies. `[FIXED 2026-08-24]` The old
/// Manhattan yardstick sent a unit to the wrong shore of a bay: the tile
/// with the smallest air distance to a click across the water can be many
/// tiles of coastline away from the one that actually approaches it. Only
/// when the click has no land connection at all (a true island) does the
/// air distance decide, as the tie-break between equally cut-off tiles.
(int, int)? closestReachableTile(WorldMap map, int x, int y, int tx, int ty,
    {Set<int>? allowedOwners}) {
  final reach = warField(map, x, y, allowedOwners: allowedOwners);
  final toGoal = warField(map, tx, ty);
  // Tiles with no land connection to the click rank behind every tile that
  // has one, ordered among themselves by air distance.
  const cutOff = 1 << 20;
  int remaining(int i) {
    final walk = toGoal.costTo(i % map.width, i ~/ map.width);
    if (walk >= 0) return walk;
    return cutOff + (i % map.width - tx).abs() + (i ~/ map.width - ty).abs();
  }

  final start = map.index(x, y);
  var best = start;
  var bestRemaining = remaining(start);
  var bestCost = 0;
  for (var i = 0; i < map.terrain.length; i++) {
    final cost = reach.costTo(i % map.width, i ~/ map.width);
    if (cost < 0) continue;
    final rest = remaining(i);
    if (rest > bestRemaining || (rest == bestRemaining && cost >= bestCost)) {
      continue;
    }
    best = i;
    bestRemaining = rest;
    bestCost = cost;
  }
  if (best == start) return null;
  return (best % map.width, best ~/ map.width);
}

/// A planned sea leg for a war march: the LAND tile the unit embarks from
/// and the overland walk that reaches it (0 = it is already standing
/// there). See [warSeaEmbark].
typedef SeaEmbark = ({int x, int y, int walk});

/// Where a unit at ([fromX],[fromY]) must stand to be shipped to the land
/// tile ([tx],[ty]), and how far it has to walk to get there — null when no
/// usable harbor connects to the destination.
///
/// `[DESIGNED 2026-08-24, user request]` THE harbor planner, shared by the
/// player's march and the AI's (which used to ignore harbors entirely and
/// left island wars unfought). It mirrors [WorldMap.canNavalTransport]
/// exactly, but finds every usable port in ONE sea search instead of
/// re-running that check per harbor: the water body touching the
/// destination is flooded once, and every [harborOwners] Hafen inside it
/// can serve. Among their coast tiles the one with the shortest war-march
/// walk wins — [WorldMap.navalEmbarkTile] compared as the crow flies and
/// so could name a port on the far side of a mountain-locked coast.
SeaEmbark? warSeaEmbark(WorldMap map, int fromX, int fromY, int tx, int ty,
    {required Set<int> harborOwners,
    Set<int>? allowedOwners,
    WarField? field}) {
  if (!map.inBounds(tx, ty) || !map.isLandAt(tx, ty)) return null;
  // Flood the water body that touches the destination.
  final atSea = List<bool>.filled(map.terrain.length, false);
  final queue = <int>[];
  for (final (nx, ny) in map.neighborsOf(tx, ty)) {
    if (!map.isWaterAt(nx, ny)) continue;
    final ni = map.index(nx, ny);
    if (atSea[ni]) continue;
    atSea[ni] = true;
    queue.add(ni);
  }
  for (var head = 0; head < queue.length; head++) {
    final cur = queue[head];
    for (final (nx, ny) in map.neighborsOf(cur % map.width, cur ~/ map.width)) {
      if (!map.isWaterAt(nx, ny)) continue;
      final ni = map.index(nx, ny);
      if (atSea[ni]) continue;
      atSea[ni] = true;
      queue.add(ni);
    }
  }
  final walkable =
      field ?? warField(map, fromX, fromY, allowedOwners: allowedOwners);
  SeaEmbark? best;
  for (var i = 0; i < map.terrain.length; i++) {
    if (!atSea[i] ||
        map.building[i] != Building.hafen ||
        !harborOwners.contains(map.owner[i])) {
      continue;
    }
    for (final (lx, ly) in map.neighborsOf(i % map.width, i ~/ map.width)) {
      if (!map.isLandAt(lx, ly)) continue;
      final walk = walkable.stepsTo(lx, ly);
      if (walk < 0) continue;
      if (best == null || walk < best.walk) best = (x: lx, y: ly, walk: walk);
    }
  }
  return best;
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
