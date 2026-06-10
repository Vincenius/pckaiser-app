import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  late GameState state;
  late Rng rng;

  /// Finds an unowned land tile adjacent to slot 1's territory.
  (int, int) claimableTile() {
    final map = state.map;
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) {
          continue;
        }
        for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
          if (map.inBounds(x + dx, y + dy) &&
              map.ownerAt(x + dx, y + dy) == 1) {
            return (x, y);
          }
        }
      }
    }
    fail('no claimable tile for slot 1');
  }

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
    state.realm(1).movementPoints = 5;
    rng = Rng(state.rngSeed);
  });

  group('ClaimTile', () {
    test('claims an adjacent unowned land tile for 1 movement point', () {
      final (x, y) = claimableTile();
      final result =
          applyAction(state, ClaimTile(slot: 1, x: x, y: y), rng);
      final realm = result.state.realm(1);
      expect(result.state.map.ownerAt(x, y), 1);
      expect(realm.movementPoints, 4);
      expect(realm.tileCount[Building.none], 1);
      expect(result.events.single.type, 'tileClaimed');
      // Input state untouched (purity).
      expect(state.map.ownerAt(x, y), World.niemand);
      expect(state.realm(1).movementPoints, 5);
    });

    test('rejects non-adjacent, owned, or water tiles and 0 MP', () {
      final (x, y) = claimableTile();
      final realm1 = state.realm(1);
      expect(
        () => applyAction(state,
            ClaimTile(slot: 1, x: realm1.capitalX, y: realm1.capitalY), rng),
        throwsA(isA<ActionException>()),
        reason: 'already owned',
      );
      // A far-away corner is not adjacent (and may be water — either way
      // it must fail).
      expect(
        () => applyAction(state, ClaimTile(slot: 2, x: x, y: y), rng),
        throwsA(isA<ActionException>()),
        reason: 'not adjacent to slot 2',
      );
      state.realm(1).movementPoints = 0;
      expect(
        () => applyAction(state, ClaimTile(slot: 1, x: x, y: y), rng),
        throwsA(isA<ActionException>()),
        reason: 'no movement points',
      );
    });
  });

  group('Build', () {
    test('builds a Kornfeld on owned Ebene, paying cost and 1 MP', () {
      final (x, y) = claimableTile();
      var s = applyAction(state, ClaimTile(slot: 1, x: x, y: y), rng).state;
      // Force terrain so the build rule is deterministic in this test.
      s.map.terrain[s.map.index(x, y)] = Terrain.ebene;
      final kornfelderBefore = s.realm(1).tileCount[Building.kornfeld];
      final result = applyAction(
          s, Build(slot: 1, x: x, y: y, building: Building.kornfeld), rng);
      final realm = result.state.realm(1);
      expect(result.state.map.buildingAt(x, y), Building.kornfeld);
      expect(realm.treasury, 1000 - 100);
      expect(realm.movementPoints, 3);
      expect(realm.tileCount[Building.kornfeld], kornfelderBefore + 1);
      expect(realm.tileCount[Building.none], 0);
    });

    test('rejects Kornfeld on Berg and Weide on Ebene', () {
      final (x, y) = claimableTile();
      final s = applyAction(state, ClaimTile(slot: 1, x: x, y: y), rng).state;
      s.map.terrain[s.map.index(x, y)] = Terrain.berg;
      expect(
        () => applyAction(
            s, Build(slot: 1, x: x, y: y, building: Building.kornfeld), rng),
        throwsA(isA<ActionException>()),
      );
      s.map.terrain[s.map.index(x, y)] = Terrain.ebene;
      expect(
        () => applyAction(
            s, Build(slot: 1, x: x, y: y, building: Building.weide), rng),
        throwsA(isA<ActionException>()),
      );
    });

    test('founding a Dorf creates a named town and updates aggregates', () {
      final (x, y) = claimableTile();
      final s = applyAction(state, ClaimTile(slot: 1, x: x, y: y), rng).state;
      final popBefore = s.realm(1).population;
      final result = applyAction(
          s,
          Build(slot: 1, x: x, y: y, building: Building.dorf,
              townName: 'Neustadt'),
          rng);
      final realm = result.state.realm(1);
      expect(realm.towns, hasLength(2));
      final town = realm.towns.last;
      expect(town.name, 'Neustadt');
      expect(town.population, inInclusiveRange(75, 124));
      expect(realm.population, popBefore + town.population);
      expect(realm.troopCapacity, 50);
      expect(realm.treasury, 0, reason: '1000 T Dorf cost');
      expect(result.events.map((e) => e.type),
          ['buildingBuilt', 'townFounded']);
    });

    test('rejects a Dorf without a name, Markt/Stadt, and unaffordable builds',
        () {
      final (x, y) = claimableTile();
      final s = applyAction(state, ClaimTile(slot: 1, x: x, y: y), rng).state;
      expect(
        () => applyAction(
            s, Build(slot: 1, x: x, y: y, building: Building.dorf), rng),
        throwsA(isA<ActionException>()),
        reason: 'Dorf needs a name',
      );
      expect(
        () => applyAction(
            s, Build(slot: 1, x: x, y: y, building: Building.markt), rng),
        throwsA(isA<ActionException>()),
        reason: 'Markt only grows from a Dorf',
      );
      expect(
        () => applyAction(
            s, Build(slot: 1, x: x, y: y, building: Building.palast), rng),
        throwsA(isA<ActionException>()),
        reason: '10000 T Palast with 1000 T treasury',
      );
    });
  });

  group('Demolish', () {
    test('clears a field for 100 T but never a town', () {
      final realm = state.realm(1);
      final map = state.map;
      // Find a cross arm with a Kornfeld/Weide/Hafen.
      var fx = -1, fy = -1;
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        final b = map.buildingAt(realm.capitalX + dx, realm.capitalY + dy);
        if (b == Building.kornfeld || b == Building.weide || b == Building.hafen) {
          fx = realm.capitalX + dx;
          fy = realm.capitalY + dy;
          break;
        }
      }
      if (fx >= 0) {
        final before = map.buildingAt(fx, fy);
        final countBefore = realm.tileCount[before];
        final result =
            applyAction(state, Demolish(slot: 1, x: fx, y: fy), rng);
        expect(result.state.map.buildingAt(fx, fy), Building.none);
        expect(result.state.realm(1).treasury, 900);
        expect(result.state.realm(1).tileCount[before], countBefore - 1);
        expect(result.state.realm(1).tileCount[Building.none], 1);
      }
      final town = realm.towns.single;
      expect(
        () => applyAction(state, Demolish(slot: 1, x: town.x, y: town.y), rng),
        throwsA(isA<ActionException>()),
      );
    });
  });

  group('ChangeReligion', () {
    test('is gated by the Reformation and Ottoman years (§15.2)', () {
      expect(
        () => applyAction(state,
            ChangeReligion(slot: 1, religion: Religion.evangelisch), rng),
        throwsA(isA<ActionException>()),
        reason: 'year 999 < Reformation 1020',
      );
      state.year = 1021;
      final result = applyAction(state,
          ChangeReligion(slot: 1, religion: Religion.evangelisch), rng);
      expect(result.state.dynasty(1).religion, Religion.evangelisch);
      expect(result.state.realm(1).treasury, 500, reason: '500 T cost');
      expect(result.state.realm(1).popularity, 0,
          reason: '50 − 70 clamped to 0');
      expect(
        () => applyAction(result.state,
            ChangeReligion(slot: 1, religion: Religion.moslemisch), rng),
        throwsA(isA<ActionException>()),
        reason: 'year 1021 < Ottoman year 1040',
      );
    });

    test('conversion to Islam costs the Kurfürst seat and resets the title',
        () {
      state.year = 1041;
      final rulerId = state.realm(1).rulerId!;
      state.kurfuerstenIds.add(rulerId);
      state.realm(1).treasury = 5000;
      state.realm(1).titleClass = 15; // Gräfin
      final result = applyAction(
          state, ChangeReligion(slot: 1, religion: Religion.moslemisch), rng);
      expect(result.state.dynasty(1).religion, Religion.moslemisch);
      expect(result.state.kurfuerstenIds, isNot(contains(rulerId)));
      expect(result.state.realm(1).titleClass, 21,
          reason: 'Scheichin (9 + 12)');
      expect(result.state.realm(1).treasury, 4000);
    });
  });

  group('wire format', () {
    test('actions round-trip through JSON', () {
      final actions = <PlayerAction>[
        ClaimTile(slot: 1, x: 2, y: 3),
        Build(slot: 4, x: 5, y: 6, building: Building.dorf, townName: 'Zell'),
        Demolish(slot: 7, x: 8, y: 9),
        ChangeReligion(slot: 10, religion: Religion.moslemisch),
      ];
      for (final action in actions) {
        final decoded = PlayerAction.fromJson(action.toJson());
        expect(decoded.toJson(), action.toJson());
      }
    });
  });
}
