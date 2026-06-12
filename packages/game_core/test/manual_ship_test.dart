/// Tests for the manually steered colony ships (rules v9): BuyShip at an
/// own Hafen, MoveShip over water at 1 Zug per tile, ColonizeShip founds
/// a named Dorf on a free land tile next to the ship.
library;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  late GameState state;
  late Rng rng;

  // Same maritime scenario as send_ship_test.dart, stamped into the
  // bottom-left corner of the generated map:
  //
  //   (2,40) own land   (3,40) own Hafen   (4..8,40) open water
  //   (9,40) free island tile — colonizable from a ship at (8,40)
  //   (12..14,39..41) land block; its center (13,40) is land-locked.
  void paintScenario() {
    final map = state.map;
    for (var y = 38; y <= 43; y++) {
      for (var x = 0; x <= 16; x++) {
        final i = map.index(x, y);
        map.terrain[i] = Terrain.water;
        map.owner[i] = World.niemand;
        map.building[i] = Building.none;
      }
    }
    void land(int x, int y, {int owner = World.niemand}) {
      map.terrain[map.index(x, y)] = Terrain.ebene;
      map.owner[map.index(x, y)] = owner;
    }

    land(2, 40, owner: 1);
    map.owner[map.index(3, 40)] = 1; // Hafen on coastal water
    map.building[map.index(3, 40)] = Building.hafen;
    land(9, 40); // reachable island
    for (var y = 39; y <= 41; y++) {
      for (var x = 12; x <= 14; x++) {
        land(x, y); // land-locked block around (13,40)
      }
    }

    final realm = state.realm(1);
    realm.tileCount[Building.hafen]++;
    realm.movementPoints = 8;
    realm.treasury = 2000;
  }

  setUp(() {
    state = newGame(GameSetup(
      humans: [
        HumanPlayerSetup(
            founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'Kiel'),
      ],
      reformationYear: 1020,
      ottomanYear: 1040,
      seed: 11,
    ));
    paintScenario();
    rng = Rng(state.rngSeed);
  });

  group('BuyShip', () {
    test('spawns a ship on the own Hafen for 700 T + 1 Zug', () {
      final result = applyAction(state, BuyShip(slot: 1, x: 3, y: 40), rng);
      final realm = result.state.realm(1);
      expect(realm.ships, hasLength(1));
      expect((realm.ships.single.x, realm.ships.single.y), (3, 40));
      expect(realm.treasury, 2000 - 700);
      expect(realm.movementPoints, 7);
      expect(result.events.single.type, 'shipBought');
      // Input state untouched (purity).
      expect(state.realm(1).ships, isEmpty);
    });

    test('requires an own Hafen tile, funds and a Zug', () {
      expect(
        () => applyAction(state, BuyShip(slot: 1, x: 5, y: 40), rng),
        throwsA(isA<ActionException>()),
        reason: 'open water is not a harbor',
      );
      state.realm(1).treasury = 699;
      expect(
        () => applyAction(state, BuyShip(slot: 1, x: 3, y: 40), rng),
        throwsA(isA<ActionException>()),
        reason: 'cannot afford the ship',
      );
      state.realm(1).treasury = 2000;
      state.realm(1).movementPoints = 0;
      expect(
        () => applyAction(state, BuyShip(slot: 1, x: 3, y: 40), rng),
        throwsA(isA<ActionException>()),
        reason: 'no Züge left',
      );
    });
  });

  group('MoveShip', () {
    late GameState withShip;

    setUp(() {
      withShip = applyAction(state, BuyShip(slot: 1, x: 3, y: 40), rng).state;
    });

    test('sails the shortest water route at 1 Zug per tile', () {
      final result = applyAction(
          withShip, MoveShip(slot: 1, shipIndex: 0, x: 8, y: 40), rng);
      final realm = result.state.realm(1);
      expect((realm.ships.single.x, realm.ships.single.y), (8, 40));
      // (3,40) → (8,40) is 5 water tiles; 7 Züge were left after buying.
      expect(realm.movementPoints, 7 - 5);
    });

    test('rejects land targets, unreachable water and over-long voyages', () {
      expect(
        () => applyAction(
            withShip, MoveShip(slot: 1, shipIndex: 0, x: 9, y: 40), rng),
        throwsA(isA<ActionException>()),
        reason: 'the island itself is land',
      );
      withShip.realm(1).movementPoints = 2;
      expect(
        () => applyAction(
            withShip, MoveShip(slot: 1, shipIndex: 0, x: 8, y: 40), rng),
        throwsA(isA<ActionException>()),
        reason: '5-tile voyage with 2 Züge left',
      );
      expect(
        () => applyAction(
            withShip, MoveShip(slot: 1, shipIndex: 0, x: 3, y: 40), rng),
        throwsA(isA<ActionException>()),
        reason: 'already there',
      );
    });
  });

  group('ColonizeShip', () {
    late GameState atIsland;

    setUp(() {
      var s = applyAction(state, BuyShip(slot: 1, x: 3, y: 40), rng).state;
      s = applyAction(
              s, MoveShip(slot: 1, shipIndex: 0, x: 8, y: 40), Rng(s.rngSeed))
          .state;
      atIsland = s;
    });

    test(
        'founds a named Dorf on the adjacent free tile, consuming the '
        'ship', () {
      final result = applyAction(
          atIsland,
          ColonizeShip(slot: 1, shipIndex: 0, x: 9, y: 40, townName: 'Atoll'),
          Rng(atIsland.rngSeed));
      final s = result.state;
      final realm = s.realm(1);
      expect(s.map.ownerAt(9, 40), 1);
      expect(s.map.buildingAt(9, 40), Building.dorf);
      expect(realm.ships, isEmpty, reason: 'the ship is consumed');
      expect(realm.tileCount[Building.dorf], 2); // start Dorf + colony
      final colony = realm.towns.firstWhere((t) => t.name == 'Atoll');
      expect(colony.population, inInclusiveRange(75, 124));
      expect(colony.troopCapacity, 25);
      expect(result.events.map((e) => e.type),
          containsAll(['shipColonized', 'townFounded']));
      // No Taler beyond the ship; one Zug for the landing.
      expect(realm.treasury, 2000 - 700);
      expect(realm.movementPoints, 8 - 1 - 5 - 1);
    });

    test('rejects distant, owned and water tiles and empty names', () {
      expect(
        () => applyAction(
            atIsland,
            ColonizeShip(slot: 1, shipIndex: 0, x: 13, y: 40, townName: 'Fern'),
            rng),
        throwsA(isA<ActionException>()),
        reason: 'not adjacent to the ship',
      );
      expect(
        () => applyAction(
            atIsland,
            ColonizeShip(slot: 1, shipIndex: 0, x: 7, y: 40, townName: 'Nass'),
            rng),
        throwsA(isA<ActionException>()),
        reason: 'water cannot be colonized',
      );
      expect(
        () => applyAction(
            atIsland,
            ColonizeShip(slot: 1, shipIndex: 0, x: 9, y: 40, townName: ' '),
            rng),
        throwsA(isA<ActionException>()),
        reason: 'the Dorf needs a name',
      );
      atIsland.map.owner[atIsland.map.index(9, 40)] = 2;
      expect(
        () => applyAction(
            atIsland,
            ColonizeShip(slot: 1, shipIndex: 0, x: 9, y: 40, townName: 'Fremd'),
            rng),
        throwsA(isA<ActionException>()),
        reason: 'already owned',
      );
    });
  });

  test('ships round-trip through JSON; old saves default to none', () {
    final s = applyAction(state, BuyShip(slot: 1, x: 3, y: 40), rng).state;
    final loaded = GameState.fromJson(s.toJson());
    expect(loaded.realm(1).ships, hasLength(1));
    expect((loaded.realm(1).ships.single.x, loaded.realm(1).ships.single.y),
        (3, 40));

    final json = s.toJson();
    for (final r in json['realms'] as List) {
      (r as Map).remove('ships');
    }
    expect(GameState.fromJson(json).realm(1).ships, isEmpty);
  });

  test('foreign ships are hidden information', () {
    final s = applyAction(state, BuyShip(slot: 1, x: 3, y: 40), rng).state;
    expect(visibleStateFor(s, 1).realm(1).ships, hasLength(1));
    expect(visibleStateFor(s, 2).realm(1).ships, isEmpty);
  });

  test('the three actions round-trip through JSON', () {
    final buy = PlayerAction.fromJson(BuyShip(slot: 1, x: 3, y: 40).toJson())
        as BuyShip;
    expect((buy.slot, buy.x, buy.y), (1, 3, 40));
    final move = PlayerAction.fromJson(
        MoveShip(slot: 1, shipIndex: 2, x: 8, y: 40).toJson()) as MoveShip;
    expect((move.shipIndex, move.x, move.y), (2, 8, 40));
    final colonize = PlayerAction.fromJson(
        ColonizeShip(slot: 1, shipIndex: 0, x: 9, y: 40, townName: 'A')
            .toJson()) as ColonizeShip;
    expect((colonize.shipIndex, colonize.x, colonize.y, colonize.townName),
        (0, 9, 40, 'A'));
  });
}
