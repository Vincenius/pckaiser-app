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
}
