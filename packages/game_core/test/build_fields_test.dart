import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Drag-select batch cultivation ([BuildFields]): builds Kornfeld/Weide on
/// many tiles at once, best-effort — wrong terrain and unaffordable tiles
/// are left free.
void main() {
  late GameState state;
  late Rng rng;

  setUp(() {
    state = newGame(GameSetup(
      humans: [
        HumanPlayerSetup(
            founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'Berlin'),
      ],
      reformationYear: 1020,
      ottomanYear: 1040,
      seed: 11,
    ));
    rng = Rng(state.rngSeed);
  });

  /// Reconfigures the first [n] owned tiles of slot 1 into empty tiles of
  /// [terrain] and returns their coordinates — a deterministic canvas so
  /// the batch tests don't depend on the generated map's layout.
  List<({int x, int y})> ownedEmptyTiles(int n, int terrain) {
    final map = state.map;
    final tiles = <({int x, int y})>[];
    for (var y = 0; y < map.height && tiles.length < n; y++) {
      for (var x = 0; x < map.width && tiles.length < n; x++) {
        if (map.ownerAt(x, y) != 1) continue;
        final idx = map.index(x, y);
        map.terrain[idx] = terrain;
        map.building[idx] = Building.none;
        tiles.add((x: x, y: y));
      }
    }
    // Keep tileCount[none] from going negative when the batch decrements it.
    state.realm(1).tileCount[Building.none] = 99;
    return tiles;
  }

  test('cultivates every valid tile, deducting Taler and Züge per field', () {
    final tiles = ownedEmptyTiles(4, Terrain.ebene);
    final realm = state.realm(1);
    realm.treasury = 1000;
    realm.movementPoints = 9;

    final result = applyAction(
        state, BuildFields(slot: 1, building: Building.kornfeld, tiles: tiles), rng);
    final map = result.state.map;
    for (final t in tiles) {
      expect(map.buildingAt(t.x, t.y), Building.kornfeld);
    }
    final built = result.state.realm(1);
    expect(built.treasury, 1000 - 4 * Building.cost[Building.kornfeld]!);
    expect(built.movementPoints, 9 - 4);
    expect(built.tileCount[Building.kornfeld], greaterThanOrEqualTo(4));
    expect(result.events.map((e) => e.type),
        everyElement('buildingBuilt'));
    expect(result.events, hasLength(4));
    // Purity: the input state is untouched.
    expect(state.map.buildingAt(tiles.first.x, tiles.first.y), Building.none);
  });

  test('Kornfeld leaves Berg tiles free; Weide cultivates them', () {
    final flat = ownedEmptyTiles(3, Terrain.ebene);
    // Turn the last of them into a mountain.
    final map = state.map;
    map.terrain[map.index(flat.last.x, flat.last.y)] = Terrain.berg;
    final berg = flat.last;
    final realm = state.realm(1);
    realm.treasury = 1000;
    realm.movementPoints = 9;

    final korn = applyAction(
        state, BuildFields(slot: 1, building: Building.kornfeld, tiles: flat), rng);
    // The two Ebene tiles are grain; the Berg tile is left free.
    expect(korn.state.map.buildingAt(flat[0].x, flat[0].y), Building.kornfeld);
    expect(korn.state.map.buildingAt(flat[1].x, flat[1].y), Building.kornfeld);
    expect(korn.state.map.buildingAt(berg.x, berg.y), Building.none);
    expect(korn.events, hasLength(2));

    // Weide accepts the mountain.
    final weide = applyAction(
        state, BuildFields(slot: 1, building: Building.weide, tiles: [berg]), rng);
    expect(weide.state.map.buildingAt(berg.x, berg.y), Building.weide);
  });

  test('stops at the treasury: unaffordable tiles are left free', () {
    final tiles = ownedEmptyTiles(5, Terrain.ebene);
    final realm = state.realm(1);
    // Enough for 2 Kornfelder (100 T each), not 5.
    realm.treasury = 250;
    realm.movementPoints = 9;

    final result = applyAction(
        state, BuildFields(slot: 1, building: Building.kornfeld, tiles: tiles), rng);
    final map = result.state.map;
    final builtCount =
        tiles.where((t) => map.buildingAt(t.x, t.y) == Building.kornfeld).length;
    expect(builtCount, 2, reason: '250 T buys exactly two 100 T fields');
    expect(result.state.realm(1).treasury, 50);
    expect(result.events, hasLength(2));
  });

  test('stops at the remaining movement points', () {
    final tiles = ownedEmptyTiles(5, Terrain.ebene);
    final realm = state.realm(1);
    realm.treasury = 1000;
    realm.movementPoints = 3;

    final result = applyAction(
        state, BuildFields(slot: 1, building: Building.kornfeld, tiles: tiles), rng);
    final map = result.state.map;
    final builtCount =
        tiles.where((t) => map.buildingAt(t.x, t.y) == Building.kornfeld).length;
    expect(builtCount, 3);
    expect(result.state.realm(1).movementPoints, 0);
  });

  test('throws when nothing at all can be built', () {
    final tiles = ownedEmptyTiles(3, Terrain.ebene);
    state.realm(1).treasury = 1000;
    state.realm(1).movementPoints = 0;
    expect(
      () => applyAction(
          state, BuildFields(slot: 1, building: Building.kornfeld, tiles: tiles), rng),
      throwsA(isA<ActionException>()),
      reason: 'no movement points left',
    );
  });

  test('rejects non-field buildings', () {
    final tiles = ownedEmptyTiles(1, Terrain.ebene);
    state.realm(1).treasury = 100000;
    state.realm(1).movementPoints = 9;
    expect(
      () => applyAction(
          state, BuildFields(slot: 1, building: Building.dorf, tiles: tiles), rng),
      throwsA(isA<ActionException>()),
    );
  });

  test('round-trips through JSON', () {
    final action = BuildFields(
      slot: 3,
      building: Building.weide,
      tiles: const [(x: 4, y: 5), (x: 6, y: 7)],
    );
    final decoded = PlayerAction.fromJson(action.toJson()) as BuildFields;
    expect(decoded.slot, 3);
    expect(decoded.building, Building.weide);
    expect(decoded.tiles, action.tiles);
  });

  /// Finds an owned slot-1 tile with a straight run of [n] unowned tiles
  /// leading out of the territory (each after the first not bordering
  /// slot 1 on its own), forces them to empty Ebene, and returns the run —
  /// the canvas for the claim-chain tests.
  List<({int x, int y})> unownedChain(int n) {
    final map = state.map;
    for (var y = 1; y < map.height - 1; y++) {
      for (var x = 1; x < map.width - 1; x++) {
        if (map.ownerAt(x, y) != 1) continue;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final run = <({int x, int y})>[];
          var ok = true;
          for (var k = 1; k <= n; k++) {
            final nx = x + dx * k;
            final ny = y + dy * k;
            if (!map.inBounds(nx, ny) ||
                map.ownerAt(nx, ny) != World.niemand ||
                (k > 1 && map.bordersSlot(nx, ny, 1))) {
              ok = false;
              break;
            }
            run.add((x: nx, y: ny));
          }
          if (!ok) continue;
          for (final t in run) {
            final i = map.index(t.x, t.y);
            map.terrain[i] = Terrain.ebene;
            map.building[i] = Building.none;
          }
          return run;
        }
      }
    }
    fail('the map has no straight unowned run for this seed');
  }

  group('planFieldCultivation (claim chains)', () {
    test('plans a chain into free land near-to-far and the batch builds it',
        () {
      final chain = unownedChain(3);
      final realm = state.realm(1);
      realm.treasury = 1000;
      realm.movementPoints = 9;
      final idx = [for (final t in chain) state.map.index(t.x, t.y)];
      // Selected far-first: the plan must still come back near-to-far, so
      // each tile borders (freshly claimed) own territory at its turn.
      final plan =
          planFieldCultivation(state, 1, idx.reversed, Building.kornfeld);
      expect(plan, chain);

      final result = applyAction(
          state, BuildFields(slot: 1, building: Building.kornfeld, tiles: plan), rng);
      final map = result.state.map;
      for (final t in chain) {
        expect(map.buildingAt(t.x, t.y), Building.kornfeld);
        expect(map.ownerAt(t.x, t.y), 1, reason: 'claimed on build');
      }
      expect(result.events, hasLength(3),
          reason: 'the plan is exactly what the batch builds');
    });

    test('the budget cuts the chain', () {
      final chain = unownedChain(3);
      state.realm(1).treasury = 250; // two 100 T fields
      state.realm(1).movementPoints = 9;
      final plan = planFieldCultivation(state, 1,
          [for (final t in chain) state.map.index(t.x, t.y)], Building.kornfeld);
      expect(plan, chain.sublist(0, 2));
    });

    test('a Berg mid-chain breaks the Kornfeld wave, not the Weide wave', () {
      final chain = unownedChain(3);
      final map = state.map;
      map.terrain[map.index(chain[1].x, chain[1].y)] = Terrain.berg;
      state.realm(1).treasury = 1000;
      state.realm(1).movementPoints = 9;
      final idx = [for (final t in chain) map.index(t.x, t.y)];
      expect(planFieldCultivation(state, 1, idx, Building.kornfeld), [chain[0]],
          reason: 'the Berg takes no grain — nothing behind it can claim');
      expect(planFieldCultivation(state, 1, idx, Building.weide), chain);
    });

    test('unowned tiles with no connection to the territory are left out',
        () {
      final chain = unownedChain(3);
      state.realm(1).treasury = 1000;
      state.realm(1).movementPoints = 9;
      // Only the far two selected: without the border tile nothing seeds.
      final plan = planFieldCultivation(
          state,
          1,
          [for (final t in chain.sublist(1)) state.map.index(t.x, t.y)],
          Building.kornfeld);
      expect(plan, isEmpty);
    });
  });
}
