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
          expect(map.buildingAt(realm.capitalX, realm.capitalY), Building.burg);
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
          if (componentOf[start] != -1 || !Terrain.isLand(map.terrain[start])) {
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

      final aiCount =
          state.dynasties.where((d) => d.status == DynastyStatus.ai).length;
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

    test('draws "Zufällig" countries from the seed, empty Dorf falls back',
        () {
      GameSetup randomSetup(int seed) => GameSetup(
            humans: [
              HumanPlayerSetup(
                  founderName: 'Anna',
                  gender: 1,
                  countrySlot: null, // Zufällig
                  dorfName: ''),
              HumanPlayerSetup(
                  founderName: 'Berta',
                  gender: 1,
                  countrySlot: 3,
                  dorfName: 'München'),
              HumanPlayerSetup(
                  founderName: 'Carla',
                  gender: 1,
                  countrySlot: null, // Zufällig
                  dorfName: 'Eigenhausen'),
            ],
            reformationYear: 1020,
            ottomanYear: 1040,
            seed: seed,
          );

      final state = newGame(randomSetup(2026));
      final humanSlots = <int, int>{
        for (final d in state.dynasties)
          if (d.humanPlayer != null) d.humanPlayer!: d.index,
      };
      // All three seated, on three distinct valid slots; the fixed pick
      // is honored and never handed to a random player.
      expect(humanSlots, hasLength(3));
      expect(humanSlots[1], 3);
      expect(humanSlots.values.toSet(), hasLength(3));
      for (final slot in humanSlots.values) {
        expect(slot, inInclusiveRange(1, 30));
      }
      // Empty Dorf → the drawn realm's historical village; a typed name
      // survives the draw.
      expect(state.realm(humanSlots[0]!).towns.single.name,
          cityNames[humanSlots[0]! - 1]);
      expect(state.realm(humanSlots[2]!).towns.single.name, 'Eigenhausen');

      // The draw is part of the seed: same seed → same slots.
      final again = newGame(randomSetup(2026));
      expect(again.toJson(), state.toJson());
    });

    for (final size in [MapSize.klein, MapSize.mittel]) {
      test('${size.name} maps build a smaller world with fewer realms', () {
        final state = newGame(GameSetup(
          humans: [
            HumanPlayerSetup(
                founderName: 'Vincent',
                gender: 0,
                countrySlot: size.defaultRealmCount, // highest slot in play
                dorfName: 'Wien'),
          ],
          reformationYear: 1020,
          ottomanYear: 1040,
          mapSize: size,
          seed: 2026,
        ));
        expect(state.map.width, size.width);
        expect(state.map.height, size.height);
        expect(state.realmCount, size.defaultRealmCount);
        expect(state.realms, hasLength(size.defaultRealmCount));
        expect(state.dynasties, hasLength(size.defaultRealmCount));
        // Every realm owns its full 5-tile cross, none overlap.
        final ownedTotal =
            state.map.owner.where((o) => o != World.niemand).length;
        expect(ownedTotal, size.defaultRealmCount * 5);
        // The world survives a JSON roundtrip with its size intact.
        final loaded = GameState.fromJson(state.toJson());
        expect(loaded.map.width, size.width);
        expect(loaded.map.height, size.height);
        expect(loaded.realmCount, size.defaultRealmCount);
        expect(loaded.toJson(), state.toJson());
      });
    }

    test('an explicit realm count within the size range is honored', () {
      final state = newGame(GameSetup(
        humans: [],
        reformationYear: 1020,
        ottomanYear: 1040,
        mapSize: MapSize.klein,
        realmCount: 8,
        seed: 7,
      ));
      expect(state.realmCount, 8);
    });

    test('rejects realm counts outside the size range and too many humans',
        () {
      GameSetup make({int? realmCount, int humanCount = 0}) => GameSetup(
            humans: [
              for (var i = 0; i < humanCount; i++)
                HumanPlayerSetup(
                    founderName: 'H$i',
                    gender: 0,
                    countrySlot: null,
                    dorfName: 'D$i'),
            ],
            reformationYear: 1020,
            ottomanYear: 1040,
            mapSize: MapSize.klein,
            realmCount: realmCount,
            seed: 1,
          );
      expect(() => make(realmCount: 5), throwsArgumentError);
      expect(() => make(realmCount: 17), throwsArgumentError);
      // 7 humans don't fit into 6 realms.
      expect(() => make(realmCount: 6, humanCount: 7), throwsArgumentError);
      expect(make(realmCount: 6, humanCount: 6), isA<GameSetup>());
    });

    test('rejects a chosen country beyond the realms in play', () {
      expect(
        () => newGame(GameSetup(
          humans: [
            HumanPlayerSetup(
                founderName: 'X', gender: 0, countrySlot: 13, dorfName: 'D'),
          ],
          reformationYear: 1020,
          ottomanYear: 1040,
          mapSize: MapSize.klein, // 12 realms by default
          seed: 1,
        )),
        throwsArgumentError,
      );
    });

    test('maps without width/height in JSON load as the original 80×44', () {
      final json = newGame(sampleSetup()).map.toJson()
        ..remove('width')
        ..remove('height');
      final map = WorldMap.fromJson(json);
      expect(map.width, 80);
      expect(map.height, 44);
    });

    test('a chosen realm color lands on the Realm and survives JSON '
        '(2026-07-27)', () {
      final state = newGame(GameSetup(
        humans: [
          HumanPlayerSetup(
              founderName: 'X',
              gender: 0,
              countrySlot: 3,
              dorfName: 'D',
              color: 0xFFD32F2F),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 1,
      ));
      expect(state.realm(3).colorArgb, 0xFFD32F2F);
      expect(state.realm(1).colorArgb, isNull,
          reason: 'AI realms keep the slot-derived default');
      final loaded = GameState.fromJson(state.toJson());
      expect(loaded.realm(3).colorArgb, 0xFFD32F2F);
      expect(loaded.realm(3).copy().colorArgb, 0xFFD32F2F);
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
