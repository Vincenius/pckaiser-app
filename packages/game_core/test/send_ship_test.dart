/// Tests for the "(S)chiff" colony ship (rules v6–v8): send a ship from
/// an own Hafen to claim a free land tile across water (ORIGINAL_GAME.md
/// §9.3, manual + proc_005D2B). Rules v9 replaced this tap-target voyage
/// with manually steered ships (see manual_ship_test.dart) — the states
/// here are pinned to v8.
library;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  late GameState state;
  late Rng rng;

  // The test paints a fixed maritime scenario into the bottom-left corner
  // of the generated map (rows 38–43 are stamped over):
  //
  //   (2,40) own land   (3,40) own Hafen   (4..8,40) open water
  //   (9,40) free island tile — reachable target
  //   (12..14,39..41) land block; its center (13,40) is land-locked —
  //   no water tile borders it, so no ship can ever reach it.
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
    realm.movementPoints = 5;
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
    // SendShip lives in rules v6–v8 only (v9 = manual ships).
    state = GameState.fromJson(state.toJson()..['rulesVersion'] = 8);
    paintScenario();
    rng = Rng(state.rngSeed);
  });

  group('SendShip', () {
    test('colonizes a reachable free land tile for 700 T + 1 MP', () {
      final result = applyAction(state, SendShip(slot: 1, x: 9, y: 40), rng);
      final realm = result.state.realm(1);
      expect(result.state.map.ownerAt(9, 40), 1);
      expect(result.state.map.buildingAt(9, 40), Building.none);
      expect(realm.treasury, 2000 - 700);
      expect(realm.movementPoints, 4);
      expect(realm.tileCount[Building.none], 1);
      expect(result.events.single.type, 'shipColonized');
      // Input state untouched (purity).
      expect(state.map.ownerAt(9, 40), World.niemand);
      expect(state.realm(1).treasury, 2000);
    });

    test('a Dorf can then be founded on the colonized tile', () {
      var next = applyAction(state, SendShip(slot: 1, x: 9, y: 40), rng).state;
      next = applyAction(
        next,
        Build(
            slot: 1, x: 9, y: 40, building: Building.dorf, townName: 'Atoll'),
        rng,
      ).state;
      expect(next.map.buildingAt(9, 40), Building.dorf);
      expect(next.realm(1).towns.any((t) => t.name == 'Atoll'), isTrue);
    });

    test('rejects water, owned and sea-unreachable targets', () {
      expect(
        () => applyAction(state, SendShip(slot: 1, x: 5, y: 40), rng),
        throwsA(isA<ActionException>()),
        reason: 'water tile',
      );
      state.map.owner[state.map.index(9, 40)] = 2;
      expect(
        () => applyAction(state, SendShip(slot: 1, x: 9, y: 40), rng),
        throwsA(isA<ActionException>()),
        reason: 'already owned',
      );
      expect(
        () => applyAction(state, SendShip(slot: 1, x: 13, y: 40), rng),
        throwsA(isA<ActionException>()),
        reason: 'land-locked — no bordering water',
      );
    });

    test('requires an own Hafen, funds and a movement point', () {
      final realm = state.realm(1);

      realm.treasury = 699;
      expect(
        () => applyAction(state, SendShip(slot: 1, x: 9, y: 40), rng),
        throwsA(isA<ActionException>()),
        reason: 'cannot afford the ship',
      );
      realm.treasury = 2000;

      realm.movementPoints = 0;
      expect(
        () => applyAction(state, SendShip(slot: 1, x: 9, y: 40), rng),
        throwsA(isA<ActionException>()),
        reason: 'no movement points',
      );
      realm.movementPoints = 5;

      state.map.building[state.map.index(3, 40)] = Building.none;
      realm.tileCount[Building.hafen]--;
      expect(
        () => applyAction(state, SendShip(slot: 1, x: 9, y: 40), rng),
        throwsA(isA<ActionException>()),
        reason: 'no harbor to sail from',
      );
    });

    test('pre-v6 games keep playing without the colony ship', () {
      final old = GameState.fromJson(state.toJson()..['rulesVersion'] = 5);
      expect(
        () => applyAction(old, SendShip(slot: 1, x: 9, y: 40), rng),
        throwsA(isA<ActionException>()),
      );
    });

    test('v9 retires SendShip in favor of manually steered ships', () {
      final v9 = GameState.fromJson(state.toJson()..['rulesVersion'] = 9);
      expect(
        () => applyAction(v9, SendShip(slot: 1, x: 9, y: 40), rng),
        throwsA(isA<ActionException>()),
      );
    });

    test('round-trips through JSON', () {
      final action = SendShip(slot: 1, x: 9, y: 40);
      final decoded = PlayerAction.fromJson(action.toJson()) as SendShip;
      expect(decoded.slot, 1);
      expect(decoded.x, 9);
      expect(decoded.y, 40);
    });
  });
}
