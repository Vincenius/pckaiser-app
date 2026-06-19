import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// v5: war naval transport is a usable amphibious move — embark next to an
/// own Hafen, ship to any sea-connected coast (own/enemy/neutral), fighting
/// defenders on a contested landing.
void main() {
  group('WorldMap naval geometry', () {
    void set(WorldMap m, int x, int y, int terrain, int owner, int building) {
      final i = m.index(x, y);
      m.terrain[i] = terrain;
      m.owner[i] = owner;
      m.building[i] = building;
    }

    // land(5,5,own) — Hafen(6,5,own,water) — sea(7,5) — land(8,5,enemy)
    WorldMap coast() {
      final m = WorldMap.water();
      set(m, 5, 5, Terrain.ebene, 1, Building.none);
      set(m, 6, 5, Terrain.water, 1, Building.hafen);
      set(m, 8, 5, Terrain.ebene, 2, Building.none);
      return m;
    }

    test('canNavalTransport: own harbor + sea path to a coastal target', () {
      final m = coast();
      expect(m.canNavalTransport(1, 5, 5, 8, 5), isTrue);
    });

    test('canNavalTransport: the harbor (a water tile) is not a destination',
        () {
      final m = coast();
      expect(m.canNavalTransport(1, 5, 5, 6, 5), isFalse);
    });

    test('canNavalTransport: needs an OWN harbor adjacent to the unit', () {
      final m = coast();
      m.owner[m.index(6, 5)] = 2; // harbor now belongs to the enemy
      expect(m.canNavalTransport(1, 5, 5, 8, 5), isFalse);
    });

    test('navalEmbarkTile: nearest harbor-coast that reaches the target', () {
      final m = coast();
      expect(m.navalEmbarkTile(1, 5, 5, 8, 5), (5, 5));
      expect(m.navalEmbarkTile(1, 0, 5, 8, 5), (5, 5)); // route from afar
    });

    test('navalEmbarkTile: null when no own harbor connects', () {
      final m = WorldMap.water();
      set(m, 8, 5, Terrain.ebene, 2, Building.none); // target, but no harbor
      expect(m.navalEmbarkTile(1, 5, 5, 8, 5), isNull);
    });
  });

  group('applyWarNavalTransport (amphibious)', () {
    late GameState war;

    void paintCoast(GameState s, int targetOwner) {
      final m = s.map;
      void set(int x, int y, int terrain, int owner, int building) {
        final i = m.index(x, y);
        m.terrain[i] = terrain;
        m.owner[i] = owner;
        m.building[i] = building;
      }

      for (var x = 18; x <= 25; x++) {
        for (var y = 19; y <= 21; y++) {
          set(x, y, Terrain.ebene, World.niemand, Building.none);
        }
      }
      set(20, 20, Terrain.ebene, 1, Building.none); // embark coast (own)
      set(21, 20, Terrain.water, 1, Building.hafen); // own harbor
      set(22, 20, Terrain.water, World.niemand, Building.none); // sea
      set(23, 20, Terrain.ebene, targetOwner, Building.none); // landing tile
    }

    setUp(() {
      var s = startGame(
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
      s.year = 1010;
      s.dynasty(2).status = DynastyStatus.ai;
      s.dynasty(2).humanPlayer = null;
      for (final slot in [1, 2]) {
        s.realm(slot).treasury = 10000;
        s.realm(slot).towns.single.troopCapacity = 200;
        s.realm(slot).troopCapacity = 200;
        s = applyAction(
                s,
                RecruitTroops(
                    slot: slot,
                    men: 50,
                    troopClass: TroopClass.infanterie,
                    name: 'Heer$slot'),
                Rng(s.rngSeed))
            .state;
      }
      // Shared border so the war can be declared.
      final map = s.map;
      outer:
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) {
            continue;
          }
          for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
            if (map.inBounds(x + dx, y + dy) &&
                map.ownerAt(x + dx, y + dy) == 1) {
              map.owner[map.index(x, y)] = 2;
              break outer;
            }
          }
        }
      }
      war = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
    });

    test('ships a unit onto an undefended enemy coast (invasion)', () {
      paintCoast(war, 2);
      final troop = war.realm(1).troops.single;
      troop.x = 20;
      troop.y = 20;
      war.activeWar!.movesLeft[1]![0] = 5;

      final result = applyAction(
          war, WarNavalTransport(slot: 1, unitIndex: 0, x: 23, y: 20),
          Rng(war.rngSeed));
      final moved = result.state.realm(1).troops.single;
      expect((moved.x, moved.y), (23, 20), reason: 'landed on enemy coast');
      expect(result.state.activeWar!.movesLeft[1]![0], 0,
          reason: 'the voyage spends the round');
    });

    test('ships a unit onto own coast', () {
      paintCoast(war, 1);
      final troop = war.realm(1).troops.single;
      troop.x = 20;
      troop.y = 20;
      war.activeWar!.movesLeft[1]![0] = 5;

      final moved = applyAction(
              war, WarNavalTransport(slot: 1, unitIndex: 0, x: 23, y: 20),
              Rng(war.rngSeed))
          .state
          .realm(1)
          .troops
          .single;
      expect((moved.x, moved.y), (23, 20));
    });

    test('a contested landing fights the defenders', () {
      paintCoast(war, 2);
      final attacker = war.realm(1).troops.single;
      attacker.x = 20;
      attacker.y = 20;
      // Defender sits on the landing tile.
      final defender = war.realm(2).troops.single;
      defender.x = 23;
      defender.y = 20;
      war.activeWar!.movesLeft[1]![0] = 5;

      final result = applyAction(
          war, WarNavalTransport(slot: 1, unitIndex: 0, x: 23, y: 20),
          Rng(war.rngSeed));
      expect(result.events.any((e) => e.type == 'battle'), isTrue,
          reason: 'an opposed landing resolves combat');
    });

    test('rejects landing on a third realm\'s coast', () {
      paintCoast(war, 3); // neither own (1) nor the war enemy (2)
      final troop = war.realm(1).troops.single;
      troop.x = 20;
      troop.y = 20;
      war.activeWar!.movesLeft[1]![0] = 5;

      expect(
        () => applyAction(
            war, WarNavalTransport(slot: 1, unitIndex: 0, x: 23, y: 20),
            Rng(war.rngSeed)),
        throwsA(isA<ActionException>()),
      );
    });

    test('manual steering: embark at own harbor, sail, disembark on coast',
        () {
      paintCoast(war, 2);
      final troop = war.realm(1).troops.single;
      troop.x = 20;
      troop.y = 20;
      war.activeWar!.movesLeft[1]![0] = 5;

      var s = war;
      // Step east onto the own Hafen (embark).
      s = applyAction(s, WarMove(slot: 1, unitIndex: 0, dx: 1, dy: 0),
              Rng(s.rngSeed))
          .state;
      expect((s.realm(1).troops.single.x, s.realm(1).troops.single.y),
          (21, 20));
      // Sail one open-water tile.
      s = applyAction(s, WarMove(slot: 1, unitIndex: 0, dx: 1, dy: 0),
              Rng(s.rngSeed))
          .state;
      expect((s.realm(1).troops.single.x, s.realm(1).troops.single.y),
          (22, 20));
      // Disembark onto the enemy coast.
      s = applyAction(s, WarMove(slot: 1, unitIndex: 0, dx: 1, dy: 0),
              Rng(s.rngSeed))
          .state;
      expect((s.realm(1).troops.single.x, s.realm(1).troops.single.y),
          (23, 20));
    });

    test('manual steering: cannot enter open water except via an own harbor',
        () {
      paintCoast(war, 2);
      // Open the southern neighbour as plain sea (no harbor).
      final m = war.map;
      m.terrain[m.index(20, 21)] = Terrain.water;
      m.owner[m.index(20, 21)] = World.niemand;
      m.building[m.index(20, 21)] = Building.none;
      final troop = war.realm(1).troops.single;
      troop.x = 20;
      troop.y = 20;
      war.activeWar!.movesLeft[1]![0] = 5;

      expect(
        () => applyAction(
            war, WarMove(slot: 1, unitIndex: 0, dx: 0, dy: 1), Rng(war.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'stepping onto non-harbor sea from land is refused',
      );
    });
  });
}
