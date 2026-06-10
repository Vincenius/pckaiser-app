import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

GameSetup sampleSetup({int seed = 2026}) => GameSetup(
      humans: [
        HumanPlayerSetup(
          founderName: 'Vincent',
          gender: 0,
          countrySlot: 10, // Österreich
          dorfName: 'Wien',
        ),
        HumanPlayerSetup(
          founderName: 'Klara',
          gender: 1,
          countrySlot: 3, // Bayern
          dorfName: 'München',
        ),
      ],
      reformationYear: 1020,
      ottomanYear: 1040,
      seed: seed,
    );

void main() {
  group('newGame', () {
    test('setup invariants hold for every realm across seeds (golden)', () {
      for (final seed in [1, 2026, 77777]) {
        final state = newGame(sampleSetup(seed: seed));

        expect(state.year, 999);
        expect(state.realms, hasLength(30));
        expect(state.dynasties, hasLength(30));
        expect(state.persons, hasLength(30));

        for (var slot = 1; slot <= 30; slot++) {
          final realm = state.realm(slot);
          final dynasty = state.dynasty(slot);
          final founder = state.person(realm.rulerId)!;

          // Founding values (§5).
          expect(realm.treasury, 1000);
          expect(realm.popularity, 50);
          expect(realm.armySize, 0);
          expect(realm.troops, isEmpty);
          expect(founder.age, inInclusiveRange(17, 21));
          expect(founder.dynasty, slot);
          expect(dynasty.memberIds, [founder.id]);
          expect(dynasty.religion, Religion.katholisch);
          expect(realm.titleClass, founder.isMale ? 1 : 13);

          // Starting cross: capital Burg + exactly one Dorf town.
          final map = state.map;
          expect(map.ownerAt(realm.capitalX, realm.capitalY), slot);
          expect(
              map.buildingAt(realm.capitalX, realm.capitalY), Building.burg);
          expect(realm.towns, hasLength(1));
          final town = realm.towns.single;
          expect(town.population, inInclusiveRange(75, 124));
          expect(town.troopCapacity, 25);
          expect(town.garrison, 0);
          expect(map.buildingAt(town.x, town.y), Building.dorf);
          expect(map.ownerAt(town.x, town.y), slot);

          // Aggregates stay in sync (§2).
          expect(realm.population, town.population);
          expect(realm.troopCapacity, 25);

          // tileCount matches the map exactly.
          final counted = List.filled(9, 0);
          var owned = 0;
          for (var i = 0; i < map.terrain.length; i++) {
            if (map.owner[i] == slot) {
              owned++;
              counted[map.building[i]]++;
            }
          }
          expect(owned, 5, reason: 'slot $slot must own its 5-tile cross');
          expect(realm.tileCount, counted);
          expect(realm.tileCount[Building.burg], 1);
          expect(realm.tileCount[Building.dorf], 1);
        }

        // Crosses never overlap: total owned tiles = 30 × 5.
        final ownedTotal =
            state.map.owner.where((o) => o != World.niemand).length;
        expect(ownedTotal, 150);
      }
    });

    test('no starting position sits on a small island', () {
      // Land-component size at each capital via flood fill: every realm
      // must start on a landmass of ≥ 50 tiles (or the map's largest).
      for (final seed in [1, 2026, 77777, 424242]) {
        final state = newGame(sampleSetup(seed: seed));
        final map = state.map;
        final componentOf = List<int>.filled(map.terrain.length, -1);
        final sizes = <int>[];
        for (var start = 0; start < map.terrain.length; start++) {
          if (componentOf[start] != -1 ||
              !Terrain.isLand(map.terrain[start])) {
            continue;
          }
          final id = sizes.length;
          var count = 0;
          final stack = [start];
          componentOf[start] = id;
          while (stack.isNotEmpty) {
            final index = stack.removeLast();
            count++;
            final x = index % map.width;
            final y = index ~/ map.width;
            for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
              if (!map.inBounds(x + dx, y + dy)) continue;
              final ni = map.index(x + dx, y + dy);
              if (componentOf[ni] == -1 && Terrain.isLand(map.terrain[ni])) {
                componentOf[ni] = id;
                stack.add(ni);
              }
            }
          }
          sizes.add(count);
        }
        final largest = sizes.reduce((a, b) => a > b ? a : b);
        final threshold = largest < 50 ? largest : 50;
        for (final realm in state.realms) {
          final component =
              componentOf[map.index(realm.capitalX, realm.capitalY)];
          expect(sizes[component], greaterThanOrEqualTo(threshold),
              reason: 'slot ${realm.slot} (seed $seed) starts on an island');
        }
      }
    });

    test('humans sit on their chosen slots, the rest is AI', () {
      final state = newGame(sampleSetup());

      expect(state.dynasty(10).status, DynastyStatus.human);
      expect(state.dynasty(10).humanPlayer, 0);
      expect(state.person(state.realm(10).rulerId)!.name, 'Vincent');
      expect(state.realm(10).towns.single.name, 'Wien');

      expect(state.dynasty(3).status, DynastyStatus.human);
      expect(state.dynasty(3).humanPlayer, 1);
      expect(state.realm(3).titleClass, 13, reason: 'female founder');

      final aiCount = state.dynasties
          .where((d) => d.status == DynastyStatus.ai)
          .length;
      expect(aiCount, 28);
      // AI realms get the suggested city name for their country (§22.4).
      expect(state.dynasty(1).status, DynastyStatus.ai);
      expect(state.realm(1).towns.single.name, 'Berlin');
    });

    test('is fully deterministic for the same seed', () {
      final a = newGame(sampleSetup());
      final b = newGame(sampleSetup());
      expect(a.toJson(), b.toJson());
    });

    test('rejects setup years before 1011 (§5) and bad slots', () {
      expect(
        () => GameSetup(
          humans: [
            HumanPlayerSetup(
                founderName: 'X', gender: 0, countrySlot: 1, dorfName: 'D'),
          ],
          reformationYear: 1010,
          ottomanYear: 1040,
          seed: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => newGame(GameSetup(
          humans: [
            HumanPlayerSetup(
                founderName: 'X', gender: 0, countrySlot: 31, dorfName: 'D'),
          ],
          reformationYear: 1020,
          ottomanYear: 1040,
          seed: 1,
        )),
        throwsArgumentError,
      );
    });
  });
}
