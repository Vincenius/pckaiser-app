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

    test('rejects Kornfeld on Berg; Weide builds on Ebene and Berg', () {
      final (x, y) = claimableTile();
      final s = applyAction(state, ClaimTile(slot: 1, x: x, y: y), rng).state;
      s.map.terrain[s.map.index(x, y)] = Terrain.berg;
      expect(
        () => applyAction(
            s, Build(slot: 1, x: x, y: y, building: Building.kornfeld), rng),
        throwsA(isA<ActionException>()),
      );
      // [DEVIATION] Weide is allowed on Ebene too.
      s.map.terrain[s.map.index(x, y)] = Terrain.ebene;
      final result = applyAction(
          s, Build(slot: 1, x: x, y: y, building: Building.weide), rng);
      expect(result.state.map.buildingAt(x, y), Building.weide);
    });

    test('building on unowned adjacent land claims the tile in one step', () {
      final (x, y) = claimableTile();
      state.map.terrain[state.map.index(x, y)] = Terrain.ebene;
      final result = applyAction(
          state, Build(slot: 1, x: x, y: y, building: Building.kornfeld), rng);
      final realm = result.state.realm(1);
      expect(result.state.map.ownerAt(x, y), 1);
      expect(result.state.map.buildingAt(x, y), Building.kornfeld);
      expect(realm.movementPoints, 4, reason: 'claim+build = 1 MP');
      expect(realm.treasury, 1000 - 100);
      expect(realm.tileCount[Building.none], 0);
      expect(realm.tileCount[Building.kornfeld],
          state.realm(1).tileCount[Building.kornfeld] + 1);
    });

    test('still rejects building on unowned land away from own territory',
        () {
      final map = state.map;
      int fx = -1, fy = -1;
      for (var y = 0; y < map.height && fx < 0; y++) {
        for (var x = 0; x < map.width && fx < 0; x++) {
          if (!map.isLandAt(x, y) || map.ownerAt(x, y) != World.niemand) {
            continue;
          }
          var nearOwn = false;
          for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
            if (map.inBounds(x + dx, y + dy) &&
                map.ownerAt(x + dx, y + dy) == 1) {
              nearOwn = true;
            }
          }
          if (!nearOwn) {
            fx = x;
            fy = y;
          }
        }
      }
      expect(fx, greaterThanOrEqualTo(0));
      state.map.terrain[state.map.index(fx, fy)] = Terrain.ebene;
      expect(
        () => applyAction(state,
            Build(slot: 1, x: fx, y: fy, building: Building.kornfeld), rng),
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

    test('builds a Hafen on unowned coastal water, taking ownership', () {
      // Find an unowned water tile orthogonally adjacent to slot 1's land.
      final map = state.map;
      var found = (-1, -1);
      outer:
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (!map.isWaterAt(x, y) ||
              map.ownerAt(x, y) != World.niemand) {
            continue;
          }
          for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
            if (map.inBounds(x + dx, y + dy) &&
                map.ownerAt(x + dx, y + dy) == 1) {
              found = (x, y);
              break outer;
            }
          }
        }
      }
      if (found == (-1, -1)) {
        return; // landlocked start for this seed — nothing to test
      }
      final (x, y) = found;
      final hafenBefore = state.realm(1).tileCount[Building.hafen];
      final result = applyAction(
          state,
          Build(slot: 1, x: x, y: y, building: Building.hafen),
          rng);
      final realm = result.state.realm(1);
      expect(result.state.map.ownerAt(x, y), 1,
          reason: 'the build takes ownership of the coastal water');
      expect(result.state.map.buildingAt(x, y), Building.hafen);
      expect(realm.tileCount[Building.hafen], hafenBefore + 1);
      expect(realm.tileCount[Building.none], 0,
          reason: 'no owned-empty counter is consumed');
      expect(realm.treasury, 1000 - 700);
    });

    test('rejects a Hafen on water without an adjacent own tile', () {
      // The far corner is practically never adjacent to slot 1's cross.
      final map = state.map;
      var corner = (-1, -1);
      outer:
      for (var y = map.height - 1; y >= 0; y--) {
        for (var x = map.width - 1; x >= 0; x--) {
          if (map.isWaterAt(x, y) &&
              map.ownerAt(x, y) == World.niemand &&
              ![for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)])
                if (map.inBounds(x + dx, y + dy)) map.ownerAt(x + dx, y + dy)]
                  .contains(1)) {
            corner = (x, y);
            break outer;
          }
        }
      }
      expect(corner, isNot((-1, -1)));
      expect(
        () => applyAction(
            state,
            Build(slot: 1, x: corner.$1, y: corner.$2,
                building: Building.hafen),
            rng),
        throwsA(isA<ActionException>()),
      );
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

  group('ProposeMarriage', () {
    test('only one proposal per turn', () {
      // An eligible pair: opposite gender, both 20, different dynasties,
      // both Catholic at game start.
      state.persons[9001] =
          Person(id: 9001, name: 'Hans', age: 20, dynasty: 1, gender: 0);
      state.persons[9002] =
          Person(id: 9002, name: 'Ute', age: 20, dynasty: 2, gender: 1);
      final result = applyAction(state,
          ProposeMarriage(slot: 1, proposerId: 9001, targetId: 9002), rng);
      expect(result.state.realm(1).proposedMarriageThisTurn, isTrue);
      expect(
        () => applyAction(result.state,
            ProposeMarriage(slot: 1, proposerId: 9001, targetId: 9002), rng),
        throwsA(isA<ActionException>()),
      );
    });
  });

  group('RecruitTroops placement', () {
    test('stations the new unit on the chosen own tile', () {
      final realm = state.realm(1);
      realm.treasury = 5000;
      realm.towns.single.troopCapacity = 100;
      realm.troopCapacity = 100;
      final town = realm.towns.single;
      final result = applyAction(
          state,
          RecruitTroops(
              slot: 1,
              men: 10,
              troopClass: TroopClass.infanterie,
              name: 'Wache',
              x: town.x,
              y: town.y),
          rng);
      final troop = result.state.realm(1).troops.single;
      expect((troop.x, troop.y), (town.x, town.y));
      expect(
          result.state.map.troopMarker[
              result.state.map.index(town.x, town.y)],
          1);
    });

    test('rejects stationing outside own territory', () {
      final realm = state.realm(1);
      realm.treasury = 5000;
      realm.towns.single.troopCapacity = 100;
      realm.troopCapacity = 100;
      final (x, y) = claimableTile(); // unowned land
      expect(
          () => applyAction(
              state,
              RecruitTroops(
                  slot: 1,
                  men: 10,
                  troopClass: TroopClass.infanterie,
                  name: 'Wache',
                  x: x,
                  y: y),
              rng),
          throwsA(isA<ActionException>()));
    });
  });

  group('MarryCommoner', () {
    test('always accepted; the commoner spouse joins the dynasty', () {
      state.persons[9001] =
          Person(id: 9001, name: 'Hans', age: 20, dynasty: 1, gender: 0);
      state.dynasty(1).memberIds.add(9001);
      for (var seed = 0; seed < 40; seed++) {
        final result = applyAction(
            state, MarryCommoner(slot: 1, personId: 9001), Rng(seed));
        expect(result.state.realm(1).proposedMarriageThisTurn, isTrue);
        final hans = result.state.persons[9001]!;
        expect(hans.spouseId, isNotNull,
            reason: 'a commoner never declines');
        final spouse = result.state.persons[hans.spouseId!]!;
        expect(spouse.dynasty, 1);
        expect(spouse.gender, 1, reason: 'opposite gender');
        expect((spouse.age - 20).abs(), lessThan(10));
        expect(spouse.age, greaterThanOrEqualTo(14));
        expect(result.state.dynasty(1).memberIds, contains(spouse.id));
        expect(result.events.any((e) => e.type == 'wedding'), isTrue);
      }
    });

    test('shares the one-proposal-per-turn gate and rejects the married',
        () {
      state.persons[9001] =
          Person(id: 9001, name: 'Hans', age: 20, dynasty: 1, gender: 0);
      state.realm(1).proposedMarriageThisTurn = true;
      expect(
          () => applyAction(
              state, MarryCommoner(slot: 1, personId: 9001), Rng(1)),
          throwsA(isA<ActionException>()));
      state.realm(1).proposedMarriageThisTurn = false;
      state.persons[9001]!.spouseId = 1;
      expect(
          () => applyAction(
              state, MarryCommoner(slot: 1, personId: 9001), Rng(1)),
          throwsA(isA<ActionException>()));
    });
  });

  group('SendMoney', () {
    test('transfers Taler to another realm', () {
      state.realm(1).treasury = 1000;
      final before = state.realm(2).treasury;
      final result =
          applyAction(state, SendMoney(slot: 1, targetSlot: 2, amount: 300), rng);
      expect(result.state.realm(1).treasury, 700);
      expect(result.state.realm(2).treasury, before + 300);
      expect(result.events.single.type, 'moneySent');
      // Hidden information: only the participants may see the transfer.
      expect(result.events.single.visibleTo(1), isTrue);
      expect(result.events.single.visibleTo(2), isTrue);
      expect(result.events.single.visibleTo(3), isFalse);
    });

    test('rejects self, vacant target, zero amount and missing funds', () {
      state.realm(1).treasury = 100;
      expect(() => applyAction(state, SendMoney(slot: 1, targetSlot: 1, amount: 10), rng),
          throwsA(isA<ActionException>()));
      expect(() => applyAction(state, SendMoney(slot: 1, targetSlot: 2, amount: 0), rng),
          throwsA(isA<ActionException>()));
      expect(() => applyAction(state, SendMoney(slot: 1, targetSlot: 2, amount: 101), rng),
          throwsA(isA<ActionException>()));
    });
  });

  group('RelocateCapital', () {
    test('relocates a lost capital onto an own Stadt for 5000 T', () {
      final realm = state.realm(1);
      final map = state.map;
      // Lose the capital tile, then build up a Stadt elsewhere.
      map.owner[map.index(realm.capitalX, realm.capitalY)] = World.niemand;
      final (x, y) = claimableTile();
      map.owner[map.index(x, y)] = 1;
      map.building[map.index(x, y)] = Building.stadt;
      realm.treasury = 6000;

      final result =
          applyAction(state, RelocateCapital(slot: 1, x: x, y: y), rng);
      expect(result.state.realm(1).capitalX, x);
      expect(result.state.realm(1).capitalY, y);
      expect(result.state.realm(1).treasury, 1000);
      expect(result.events.single.type, 'capitalRelocated');
    });

    test('rejects while the capital is still held', () {
      final realm = state.realm(1);
      realm.treasury = 6000;
      expect(
          () => applyAction(state,
              RelocateCapital(slot: 1, x: realm.capitalX, y: realm.capitalY), rng),
          throwsA(isA<ActionException>()));
    });
  });

  group('wire format', () {
    test('actions round-trip through JSON', () {
      final actions = <PlayerAction>[
        ClaimTile(slot: 1, x: 2, y: 3),
        Build(slot: 4, x: 5, y: 6, building: Building.dorf, townName: 'Zell'),
        Demolish(slot: 7, x: 8, y: 9),
        ChangeReligion(slot: 10, religion: Religion.moslemisch),
        SendMoney(slot: 1, targetSlot: 2, amount: 500),
        RelocateCapital(slot: 3, x: 4, y: 5),
        MarryCommoner(slot: 6, personId: 7),
      ];
      for (final action in actions) {
        final decoded = PlayerAction.fromJson(action.toJson());
        expect(decoded.toJson(), action.toJson());
      }
    });
  });
}
