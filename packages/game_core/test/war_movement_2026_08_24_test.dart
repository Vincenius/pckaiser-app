import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// `2026-08-24, user report` — two complaints about war movement:
///
///  1. ordering a unit to a tile beyond the round's Züge did nothing at all
///     ("Diese Truppe kann in dieser Runde nicht weiter ziehen!") instead of
///     marching as far as it could, and the route it picked was not always
///     the best one;
///  2. AI armies never used harbors and often took poor routes.
///
/// Both now run through ONE planner (`marchWarUnit` over [warField]), so
/// these tests cover the player's march and the AI's alike.

/// A war-ready two-realm game (mirrors cleanup_2026_07_14's setUp), already
/// in the rounds phase with slot 1 attacking the AI slot 2.
GameState warAtRounds({int troopsForOne = 1, int troopsForTwo = 1}) {
  var state = startGame(
          newGame(GameSetup(
            humans: [
              HumanPlayerSetup(
                  founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'A'),
              HumanPlayerSetup(
                  founderName: 'Berta', gender: 1, countrySlot: 2, dorfName: 'B'),
            ],
            reformationYear: 1020,
            ottomanYear: 1040,
            seed: 2026,
          )),
          Rng(7))
      .state;
  state.year = 1010;
  for (final slot in [1, 2]) {
    final realm = state.realm(slot);
    realm.treasury = 10000;
    realm.towns.single.troopCapacity = 400;
    realm.troopCapacity = 400;
    final units = slot == 1 ? troopsForOne : troopsForTwo;
    for (var n = 0; n < units; n++) {
      state = applyAction(
              state,
              RecruitTroops(
                  slot: slot,
                  men: 50,
                  troopClass: TroopClass.infanterie,
                  name: 'Heer$slot$n'),
              Rng(state.rngSeed))
          .state;
    }
  }
  // A shared border, so the declaration passes §11.1.
  final map = state.map;
  outer:
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) continue;
      if (map.bordersSlot(x, y, 1)) {
        map.owner[map.index(x, y)] = 2;
        state.realm(2).tileCount[Building.none]++;
        break outer;
      }
    }
  }
  state.dynasty(2).status = DynastyStatus.ai;
  state.dynasty(2).humanPlayer = null;
  state =
      applyAction(state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
  expect(state.activeWar!.phase, WarPhase.rounds);
  return state;
}

/// Blanks the world to open water and paints a scenario into its top-left
/// corner — the generated map is no bench for route tests. Legend:
/// `.` water · `#` neutral land · `1`/`2` land of that realm ·
/// `5` a THIRD realm's land (blocks a war march) · `H`/`h` a Hafen on water
/// owned by realm 1 / realm 2.
void paint(GameState state, List<String> rows) {
  final map = state.map;
  for (var i = 0; i < map.terrain.length; i++) {
    map.terrain[i] = Terrain.water;
    map.owner[i] = World.niemand;
    map.building[i] = Building.none;
    map.troopMarker[i] = 0;
  }
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      final i = map.index(x, y);
      switch (rows[y][x]) {
        case '.':
          break;
        case '#':
          map.terrain[i] = Terrain.ebene;
        case 'H':
        case 'h':
          map.building[i] = Building.hafen;
          map.owner[i] = rows[y][x] == 'H' ? 1 : 2;
        default:
          map.terrain[i] = Terrain.ebene;
          map.owner[i] = int.parse(rows[y][x]);
      }
    }
  }
}

/// Puts [slot]'s unit [unit] on ([x],[y]) and its capital on ([cx],[cy]).
void station(GameState state, int slot, int unit, int x, int y,
    {int? cx, int? cy}) {
  final realm = state.realm(slot);
  realm.troops[unit].x = x;
  realm.troops[unit].y = y;
  if (cx != null) realm.capitalX = cx;
  if (cy != null) realm.capitalY = cy;
  state.rebuildTroopMarkers();
}

void setMoves(GameState state, int slot, int unit, int moves) {
  state.activeWar!.movesLeft[slot]![unit] = moves;
}

(int, int) at(GameState state, int slot, int unit) {
  final t = state.realm(slot).troops[unit];
  return (t.x, t.y);
}

void main() {
  group('WarField', () {
    /// A 6×2 block of land.
    WorldMap block() {
      final m = WorldMap.water(width: 6, height: 2);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 6; x++) {
          m.terrain[m.index(x, y)] = Terrain.ebene;
        }
      }
      return m;
    }

    test('answers cost, steps, path and first step from one search', () {
      final f = warField(block(), 0, 0);
      expect(f.reaches(5, 0), isTrue);
      expect(f.costTo(5, 0), 5);
      expect(f.stepsTo(5, 0), 5);
      expect(f.pathTo(5, 0)!.length, 5);
      expect(f.pathTo(5, 0)!.last, (5, 0));
      expect(f.firstStepTo(5, 0), (1, 0));
      expect(f.firstStepTo(0, 0), isNull, reason: 'already standing there');
    });

    test('water and third-realm land are not routes', () {
      final m = block();
      for (var y = 0; y < 2; y++) {
        m.owner[m.index(3, y)] = 5; // a third realm walls the block in two
      }
      final f = warField(m, 0, 0, allowedOwners: {1, 2, World.niemand});
      expect(f.reaches(2, 0), isTrue);
      expect(f.reaches(4, 0), isFalse);
      expect(f.costTo(4, 0), -1);
      expect(f.stepsTo(4, 0), -1);
    });

    test('routes AROUND an enemy stack when a near-as-short way exists', () {
      final m = block();
      final blocked = {m.index(2, 0)};
      final direct = warField(m, 0, 0);
      final around = warField(m, 0, 0, avoid: blocked);
      expect(direct.pathTo(5, 0)!.contains((2, 0)), isTrue,
          reason: 'the straight way runs over the stack');
      expect(around.pathTo(5, 0)!.contains((2, 0)), isFalse,
          reason: 'two extra steps beat walking into an unordered battle');
      expect(around.stepsTo(5, 0), 7);
    });
  });

  group('closestReachableTile', () {
    /// A ring road around a bay whose EAST leg a third realm has closed:
    /// the stub at (2,2) can then only be approached the long way round,
    /// and the tile that approaches it is six tiles from the click as the
    /// crow flies while the unit's own tile is two.
    WorldMap peninsula() {
      final m = WorldMap.water(width: 8, height: 4);
      void land(int x, int y, [int owner = World.niemand]) {
        final i = m.index(x, y);
        m.terrain[i] = Terrain.ebene;
        m.owner[i] = owner;
      }

      for (var x = 0; x < 8; x++) {
        land(x, 0); // the north road
      }
      land(7, 1);
      land(7, 2, 5); // the third realm's toll gate
      for (var x = 2; x < 8; x++) {
        land(x, 3); // the south road
      }
      land(2, 2); // the stub the click sits on
      return m;
    }

    test('measures the approach by WALKING, not as the crow flies', () {
      final m = peninsula();
      const owners = {1, 2, World.niemand};
      expect(warPathStep(m, 2, 0, 2, 2, allowedOwners: owners), isNull,
          reason: 'the toll gate really cuts the stub off');
      expect(closestReachableTile(m, 2, 0, 2, 2, allowedOwners: owners),
          equals((7, 1)),
          reason: 'the far end of the open road is where the march gets '
              'closest — every tile is further from the click by air than '
              'the unit already is, which is why the old Manhattan rule '
              'gave up and refused the order');
    });
  });

  group('warSeaEmbark', () {
    test('names the port with the shortest WALK and its walk length', () {
      // "1111H....2" — the unit's own coast holds the harbor.
      final m = WorldMap.water(width: 12, height: 2);
      void land(int x, int y, int owner) {
        final i = m.index(x, y);
        m.terrain[i] = Terrain.ebene;
        m.owner[i] = owner;
      }

      for (var x = 0; x <= 3; x++) {
        land(x, 1, 1);
      }
      m.building[m.index(4, 1)] = Building.hafen;
      m.owner[m.index(4, 1)] = 1;
      for (var x = 9; x <= 11; x++) {
        land(x, 1, 2);
      }
      final e = warSeaEmbark(m, 0, 1, 9, 1, harborOwners: {1, 2});
      expect(e, isNotNull);
      expect((e!.x, e.y), (3, 1), reason: 'the coast tile beside the Hafen');
      expect(e.walk, 3);
      // No harbor at all → no sea route.
      m.building[m.index(4, 1)] = Building.none;
      expect(warSeaEmbark(m, 0, 1, 9, 1, harborOwners: {1, 2}), isNull);
    });
  });

  group('WarMarch', () {
    test('a target beyond the round\'s Züge is marched at, not refused', () {
      final s = warAtRounds();
      paint(s, ['............', '############']);
      station(s, 1, 0, 0, 1, cx: 0, cy: 1);
      station(s, 2, 0, 11, 1, cx: 11, cy: 1);
      setMoves(s, 1, 0, 3);

      final r = applyAction(
          s, WarMarch(slot: 1, unitIndex: 0, x: 10, y: 1), Rng(s.rngSeed));

      expect(at(r.state, 1, 0), (3, 1),
          reason: 'every Zug spent closing in; the old code threw '
              '"cannot move" and applyAction discarded the whole advance');
      expect(r.state.activeWar!.movesLeft[1]![0], 0);
    });

    test('an out-of-range march keeps going where it stopped next round', () {
      var s = warAtRounds();
      paint(s, ['............', '############']);
      station(s, 1, 0, 0, 1, cx: 0, cy: 1);
      station(s, 2, 0, 11, 1, cx: 11, cy: 1);
      setMoves(s, 1, 0, 3);
      s = applyAction(
              s, WarMarch(slot: 1, unitIndex: 0, x: 10, y: 1), Rng(s.rngSeed))
          .state;
      setMoves(s, 1, 0, 4);
      s = applyAction(
              s, WarMarch(slot: 1, unitIndex: 0, x: 10, y: 1), Rng(s.rngSeed))
          .state;
      expect(at(s, 1, 0), (7, 1));
    });

    test('marches around an enemy stack it was not ordered to attack', () {
      final s = warAtRounds();
      paint(s, ['############', '############']);
      station(s, 1, 0, 0, 1, cx: 0, cy: 1);
      station(s, 2, 0, 3, 1, cx: 11, cy: 0);
      setMoves(s, 1, 0, 10);

      final r = applyAction(
          s, WarMarch(slot: 1, unitIndex: 0, x: 6, y: 1), Rng(s.rngSeed));

      expect(at(r.state, 1, 0), (6, 1));
      expect(r.state.realm(2).troops, hasLength(1),
          reason: 'the detour avoided the battle entirely');
      expect(r.events.where((e) => e.type == 'battle'), isEmpty);
    });

    test('takes a ship when the land road is much longer than the crossing',
        () {
      final s = warAtRounds();
      paint(s, [
        '############',
        '1111H....222',
      ]);
      station(s, 1, 0, 3, 1, cx: 0, cy: 1);
      station(s, 2, 0, 11, 1, cx: 11, cy: 1);
      setMoves(s, 1, 0, 4); // the 8-step road around is out of reach

      final r = applyAction(
          s, WarMarch(slot: 1, unitIndex: 0, x: 9, y: 1), Rng(s.rngSeed));

      expect(at(r.state, 1, 0), (9, 1),
          reason: 'embarked at its own coast and landed across the water');
      expect(r.state.activeWar!.movesLeft[1]![0], 0,
          reason: 'a voyage spends the whole round');
    });

    test('walks when the land road still fits into the round', () {
      final s = warAtRounds();
      paint(s, [
        '############',
        '1111H....222',
      ]);
      station(s, 1, 0, 3, 1, cx: 0, cy: 1);
      station(s, 2, 0, 11, 1, cx: 11, cy: 1);
      setMoves(s, 1, 0, 9); // the road is 8 steps — no reason to burn a round

      final r = applyAction(
          s, WarMarch(slot: 1, unitIndex: 0, x: 9, y: 1), Rng(s.rngSeed));

      expect(at(r.state, 1, 0), (9, 1));
      expect(r.state.activeWar!.movesLeft[1]![0], 1,
          reason: 'it marched: a voyage would have zeroed the round');
    });

    test('ordering a land unit onto open water is refused, not wandered at',
        () {
      final s = warAtRounds();
      paint(s, ['............', '####........']);
      station(s, 1, 0, 0, 1, cx: 0, cy: 1);
      station(s, 2, 0, 3, 1, cx: 3, cy: 1);
      setMoves(s, 1, 0, 6);
      expect(
          () => applyAction(
              s, WarMarch(slot: 1, unitIndex: 0, x: 8, y: 0), Rng(s.rngSeed)),
          throwsA(isA<ActionException>()));
      expect(at(s, 1, 0), (0, 1));
    });
  });

  group('AI war movement', () {
    test('an AI army crosses the water through a harbor', () {
      final s = warAtRounds(troopsForOne: 2);
      paint(s, [
        '............',
        '111H....2222',
      ]);
      station(s, 1, 0, 0, 1, cx: 0, cy: 1); // stays home as the guard
      station(s, 1, 1, 2, 1); // the expedition, standing at its own port
      station(s, 2, 0, 8, 1, cx: 11, cy: 1);
      s.dynasty(1).status = DynastyStatus.ai;
      s.dynasty(1).humanPlayer = null;
      setMoves(s, 1, 0, 6);
      setMoves(s, 1, 1, 6);

      final events = <GameEvent>[];
      runAiWarMovement(s, 1, Rng(s.rngSeed), events);

      expect(at(s, 1, 1), (11, 1),
          reason: 'shipped onto the enemy seat — before this the AI had no '
              'notion of harbors and sat on its own coast all war');
      expect(at(s, 1, 0), (0, 1), reason: 'the home guard holds the seat');
    });

    test('an AI defender picks the intruder it can actually march to', () {
      final s = warAtRounds(troopsForOne: 2, troopsForTwo: 2);
      // Slot 2's realm is a horseshoe whose two arms meet only at the FAR
      // right. Intruder A stands right across the gap — 2 tiles by air, 12
      // on foot, and the road to it runs east. Intruder B is 4 tiles west
      // along the defender's own arm.
      paint(s, [
        '22222222222.',
        '..........2.',
        '22222222222.',
      ]);
      station(s, 2, 0, 0, 0, cx: 0, cy: 0); // the home guard on the seat
      station(s, 2, 1, 5, 2);
      station(s, 1, 0, 5, 0, cx: 10, cy: 0); // across the gap
      station(s, 1, 1, 1, 2); // up the defender's own road
      setMoves(s, 2, 0, 3);
      setMoves(s, 2, 1, 3);

      final events = <GameEvent>[];
      runAiWarMovement(s, 2, Rng(s.rngSeed), events);

      expect(at(s, 2, 1), (2, 2),
          reason: 'it set off west at the intruder it can actually reach; '
              'the old air-distance pick chased the one across the gap and '
              'marched east, the long way round the horseshoe');
    });
  });
}
