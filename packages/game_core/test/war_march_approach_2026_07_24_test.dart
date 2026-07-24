import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// 2026-07-24: a war march to an unreachable LAND click no longer rejects —
/// the unit approaches as far as possible (retarget to the reachable tile
/// nearest the click). Water clicks keep the old manual-steering fallback.

/// Mirrors the cleanup_2026_07_14 setUp: human slot 1 next to slot 2, both
/// with a 50-man infantry unit.
GameState warReadyGame() {
  var state = startGame(
          newGame(GameSetup(
            humans: [
              HumanPlayerSetup(
                  founderName: 'Anna',
                  gender: 1,
                  countrySlot: 1,
                  dorfName: 'A'),
              HumanPlayerSetup(
                  founderName: 'Berta',
                  gender: 1,
                  countrySlot: 2,
                  dorfName: 'B'),
            ],
            reformationYear: 1020,
            ottomanYear: 1040,
            seed: 2026,
          )),
          Rng(7))
      .state;
  state.year = 1010;
  for (final slot in [1, 2]) {
    final realm = state.realm(slot);
    realm.treasury = 10000;
    realm.towns.single.troopCapacity = 200;
    realm.troopCapacity = 200;
    state = applyAction(
            state,
            RecruitTroops(
                slot: slot,
                men: 50,
                troopClass: TroopClass.infanterie,
                name: 'Heer$slot'),
            Rng(state.rngSeed))
        .state;
  }
  final map = state.map;
  outer:
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) continue;
      if (map.bordersSlot(x, y, 1)) {
        map.owner[map.index(x, y)] = 2;
        state.realm(2).tileCount[Building.none]++;
        break outer;
      }
    }
  }
  return state;
}

void main() {
  test('closestReachableTile stops at the near shore of a water gap', () {
    // A 7×3 water map with a single land row at y=1, cut at x=3:
    // L L L ~ L L L — from (0,1) the far side is unreachable.
    final map = WorldMap.water(width: 7, height: 3);
    for (final x in [0, 1, 2, 4, 5, 6]) {
      map.terrain[map.index(x, 1)] = Terrain.ebene;
    }
    expect(warPathStep(map, 0, 1, 6, 1), isNull,
        reason: 'the gap really severs the strip');
    expect(closestReachableTile(map, 0, 1, 6, 1), equals((2, 1)),
        reason: 'nearest reachable tile to the far end is the near shore');
    // Already standing as close as the land allows → nothing better.
    expect(closestReachableTile(map, 2, 1, 6, 1), isNull);
  });

  test('closestReachableTile honors allowedOwners like the war march', () {
    // Solid land row, but tiles x ≥ 3 belong to a third realm (slot 5).
    final map = WorldMap.water(width: 7, height: 3);
    for (var x = 0; x < 7; x++) {
      map.terrain[map.index(x, 1)] = Terrain.ebene;
      if (x >= 3) map.owner[map.index(x, 1)] = 5;
    }
    final owners = {1, 2, World.niemand};
    expect(warPathStep(map, 0, 1, 6, 1, allowedOwners: owners), isNull);
    expect(closestReachableTile(map, 0, 1, 6, 1, allowedOwners: owners),
        equals((2, 1)),
        reason: 'the march may only close up to the third realm\'s border');
  });

  test('WarMarch to an unreachable island tile approaches instead of '
      'rejecting', () {
    var s = warReadyGame();
    s.dynasty(2).status = DynastyStatus.ai;
    s.dynasty(2).humanPlayer = null;
    s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
        .state;
    expect(s.activeWar!.phase, WarPhase.rounds);

    final map = s.map;
    final unit = s.realm(1).troops.first;
    final enemy = s.realm(2);

    // Turn an interior enemy tile into an island: all four neighbors become
    // open water, so no land path can ever reach it.
    var ix = -1, iy = -1;
    outer:
    for (var y = 1; y < map.height - 1; y++) {
      for (var x = 1; x < map.width - 1; x++) {
        if (map.ownerAt(x, y) != 2 || map.isWaterAt(x, y)) continue;
        if (x == enemy.capitalX && y == enemy.capitalY) continue;
        if ((x - unit.x).abs() + (y - unit.y).abs() < 3) continue;
        if (enemy.troops.any((t) => t.x == x && t.y == y)) continue;
        ix = x;
        iy = y;
        break outer;
      }
    }
    expect(ix, greaterThanOrEqualTo(0), reason: 'found a tile to islandify');
    for (final (nx, ny) in map.neighborsOf(ix, iy)) {
      final ni = map.index(nx, ny);
      map.terrain[ni] = Terrain.water;
      map.owner[ni] = World.niemand;
      map.building[ni] = Building.none;
      map.troopMarker[ni] = 0;
    }
    expect(warPathStep(map, unit.x, unit.y, ix, iy), isNull,
        reason: 'the island really is unreachable over land');

    final before = (unit.x - ix).abs() + (unit.y - iy).abs();
    final result = applyAction(
        s, WarMarch(slot: 1, unitIndex: 0, x: ix, y: iy), Rng(s.rngSeed));

    final after = result.state.realm(1).troops.first;
    final remaining = (after.x - ix).abs() + (after.y - iy).abs();
    expect(remaining, lessThan(before),
        reason: 'instead of "impassable" the unit marches as close to the '
            'island as the land allows');
  });
}
