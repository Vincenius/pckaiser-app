import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  group('generateMap', () {
    test('is deterministic for the same seed', () {
      final a = generateMap(Rng(2026));
      final b = generateMap(Rng(2026));
      expect(a.terrain, b.terrain);
    });

    test('produces only valid terrain values (0–17)', () {
      final map = generateMap(Rng(1));
      for (final t in map.terrain) {
        expect(t, inInclusiveRange(0, 17));
      }
    });

    test('starts unowned, unbuilt, unmarked', () {
      final map = generateMap(Rng(1));
      expect(map.owner, everyElement(World.niemand));
      expect(map.building, everyElement(Building.none));
      expect(map.troopMarker, everyElement(0));
    });

    test('every water tile encodes its land-neighbor mask (§3.1)', () {
      final map = generateMap(Rng(7));
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.isLandAt(x, y)) continue;
          expect(
            map.terrainAt(x, y),
            Terrain.water + landNeighborMask(map, x, y),
            reason: 'shoreline mismatch at ($x, $y)',
          );
        }
      }
    });

    test('land fraction is plausible across seeds', () {
      // 100 patches of ~8×7 minus 25 lakes on an 80×44 grid — the land share
      // should be substantial but never total.
      for (final seed in [1, 42, 999, 123456, 0xDEADBEEF]) {
        final map = generateMap(Rng(seed));
        final land = map.terrain.where(Terrain.isLand).length;
        final fraction = land / map.terrain.length;
        expect(fraction, greaterThan(0.30), reason: 'seed $seed too watery');
        expect(fraction, lessThan(0.95), reason: 'seed $seed too dry');
      }
    });

    test('mountains are a minority of land (p = 1/7 per §3.2)', () {
      final map = generateMap(Rng(3));
      final land = map.terrain.where(Terrain.isLand).length;
      final berg = map.terrain.where((t) => t == Terrain.berg).length;
      expect(berg / land, lessThan(0.30));
      expect(berg, greaterThan(0));
    });

    test('default size is gross and matches an explicit gross', () {
      final implicit = generateMap(Rng(2026));
      final explicit = generateMap(Rng(2026), size: MapSize.gross);
      expect(implicit.width, 80);
      expect(implicit.height, 44);
      expect(implicit.terrain, explicit.terrain);
    });

    for (final size in MapSize.values) {
      test('${size.name} maps have the right grid and plausible land', () {
        for (final seed in [1, 42, 2026]) {
          final map = generateMap(Rng(seed), size: size);
          expect(map.width, size.width);
          expect(map.height, size.height);
          expect(map.terrain, hasLength(size.width * size.height));
          // Patch/lake counts are scaled by area, so the land share stays
          // in the same band on every size.
          final land = map.terrain.where(Terrain.isLand).length;
          final fraction = land / map.terrain.length;
          expect(fraction, greaterThan(0.30),
              reason: '${size.name} seed $seed too watery');
          expect(fraction, lessThan(0.95),
              reason: '${size.name} seed $seed too dry');
          // Shoreline pass holds on every grid.
          for (var y = 0; y < map.height; y++) {
            for (var x = 0; x < map.width; x++) {
              if (map.isLandAt(x, y)) continue;
              expect(map.terrainAt(x, y),
                  Terrain.water + landNeighborMask(map, x, y),
                  reason: '${size.name} shoreline mismatch at ($x, $y)');
            }
          }
        }
      });
    }
  });
}
