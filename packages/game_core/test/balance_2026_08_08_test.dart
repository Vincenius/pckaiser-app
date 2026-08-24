import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Balance round 2026-08-08 (user report): wars were relentless and
/// internally free — a ruler could war every single year without ever
/// facing the unrest the original punished them with, and games were
/// decided around year 1020, before any §18 world event happened.
/// Covered here:
///  - the AI's post-war recovery grace (a realm that just fought is left
///    alone for a year, so the same victim is not everyone's prey),
///  - the war-weariness recovery CEILING and its slower decay,
///  - the peasant revolt for a house with no pretender,
///  - the world-size-scaled §18.2 outbreak threshold.
/// The freed defender war slot and the pair truce are pinned in war_test.
void main() {
  group('AI recovery grace (war target pick)', () {
    /// An all-AI world where slot 1 is fully primed to declare war on its
    /// single neighbour: past the war gate, content, two armies.
    GameState warEagerGame() {
      final state = startGame(
              newGame(GameSetup(
                humans: [],
                reformationYear: 1020,
                ottomanYear: 1040,
                warStartYear: 2000, // no spontaneous war before we set the year
                seed: 9,
              )),
              Rng(9))
          .state;
      state.year = 2001;
      final realm = state.realm(1);
      realm.popularity = 100;
      realm.recentWars = 0;
      _makeNeighbor(state, 1);
      realm.troops.clear();
      for (var i = 0; i < 2; i++) {
        realm.troops.add(Troop(
          name: 'Heer $i',
          men: 100,
          troopClass: TroopClass.infanterie,
          quality: TroopQuality.regular,
          garrisonCounted: true,
          x: realm.capitalX,
          y: realm.capitalY,
        ));
      }
      state.rebuildTroopMarkers();
      return state;
    }

    int soleNeighborOf(GameState state) =>
        state.map.realmNeighbors(1).single;

    test('a neighbour that was attacked this year or last year is spared', () {
      for (final lastDefended in [2001, 2000]) {
        final state = warEagerGame();
        state.realm(soleNeighborOf(state)).lastDefendedYear = lastDefended;
        for (var seed = 0; seed < 200; seed++) {
          final result = runAiTurn(state, 1, Rng(seed));
          expect(result.events.where((e) => e.type == 'warDeclared'), isEmpty,
              reason: 'the only neighbour was last attacked in $lastDefended '
                  'and must be left to recover (seed $seed)');
        }
      }
    });

    test('the same neighbour is fair game once its grace year has passed', () {
      // Positive control: proves the silence above is the grace, not a
      // blocker, mood or dice artefact. The AI's spontaneous war roll is
      // ~1/60 per seed (warChance × the 1-in-3 gate), so the seed budget
      // has to be wide enough that an unlucky RNG stretch cannot fail the
      // test — any change that shifts the RNG stream would otherwise flake
      // it (as the 2026-08-24 movement-roll change did at 200 seeds).
      final state = warEagerGame();
      state.realm(soleNeighborOf(state)).lastDefendedYear = 1999;
      var declared = false;
      for (var seed = 0; seed < 3000 && !declared; seed++) {
        final result = runAiTurn(state, 1, Rng(seed));
        declared = result.events.any((e) => e.type == 'warDeclared');
      }
      expect(declared, isTrue);
    });

    test('a neighbour that STARTED its recent war earns no grace', () {
      // `[FIX 2026-08-08 review]` The grace protects victims, not
      // aggressors: were it keyed on `lastWarYear` (stamped on both
      // sides), declaring a cheap war every other year would have bought
      // permanent immunity from AI attack.
      final state = warEagerGame();
      final neighbor = state.realm(soleNeighborOf(state));
      neighbor.lastWarYear = 2001; // it declared a war this year …
      neighbor.lastDefendedYear = 0; // … but was never itself attacked
      var declared = false;
      for (var seed = 0; seed < 3000 && !declared; seed++) {
        final result = runAiTurn(state, 1, Rng(seed));
        declared = result.events.any((e) => e.type == 'warDeclared');
      }
      expect(declared, isTrue,
          reason: 'an aggressor stays a legitimate target');
    });
  });

  group('war weariness has lasting bite', () {
    /// A well-fed all-AI realm (fat stores → the §8.4 food target is the
    /// full 100) whose mood sits at 90.
    (GameState, Realm) contentRealm({required int recentWars}) {
      final state = startGame(
              newGame(GameSetup(
                humans: const [],
                reformationYear: 1020,
                ottomanYear: 1040,
                seed: 11,
              )),
              Rng(11))
          .state;
      final realm = state.realm(1);
      realm.grainHarvest = realm.population * 2; // surplus at the +15 cap
      realm.popularity = 90;
      realm.recentWars = recentWars;
      return (state, realm);
    }

    test('the ceiling drops one step per war in a row, down to the floor', () {
      expect(warWearinessCeiling(Realm(slot: 1, recentWars: 0)), 100);
      expect(warWearinessCeiling(Realm(slot: 1, recentWars: 3)), 70);
      expect(warWearinessCeiling(Realm(slot: 1, recentWars: 99)),
          warWearinessCeilingFloor,
          reason: 'never below the floor');
    });

    test('a full granary no longer buys back a warmonger\'s popularity', () {
      final (state, realm) = contentRealm(recentWars: 3); // ceiling 70
      runFoodAndPopulation(state, realm, Rng(1), []);
      expect(realm.popularity, lessThan(90),
          reason: 'the mood drifts DOWN toward the ceiling …');
      expect(realm.popularity, greaterThanOrEqualTo(warWearinessCeiling(realm)),
          reason: '… in bounded steps, never a jarring clamp');
    });

    test('the same realm at peace climbs as before (control)', () {
      final (state, realm) = contentRealm(recentWars: 0);
      runFoodAndPopulation(state, realm, Rng(1), []);
      expect(realm.popularity, greaterThan(90));
    });

    test('weariness needs wearinessDecayYears of peace per step', () {
      var state = startGame(
              newGame(GameSetup(
                humans: const [],
                reformationYear: 1020,
                ottomanYear: 1040,
                seed: 12,
              )),
              Rng(12))
          .state;
      state.realm(1).recentWars = 2;
      // `startGame` already ran one round start, which banked a peace year —
      // start the count from a clean slate so this tests the RULE.
      state.realm(1).peaceYears = 0;
      final start = state.year;
      // One quiet year is no longer enough …
      state = _advanceYears(state, 1);
      expect(state.realm(1).recentWars, 2);
      // … two forgive exactly one step …
      state = _advanceYears(state, 1);
      expect(state.realm(1).recentWars, 1);
      // … and the counter starts over for the next one.
      state = _advanceYears(state, 1);
      expect(state.realm(1).recentWars, 1);
      state = _advanceYears(state, 1);
      expect(state.realm(1).recentWars, 0);
      expect(state.year, start + 4);
    });

    test('a year with a war resets the peace counter', () {
      var state = startGame(
              newGame(GameSetup(
                humans: const [],
                reformationYear: 1020,
                ottomanYear: 1040,
                seed: 13,
              )),
              Rng(13))
          .state;
      state.realm(1).recentWars = 1;
      state.realm(1).peaceYears = 0;
      state.realm(1).lastWarYear = state.year; // a war this year
      state = _advanceYears(state, 1);
      expect(state.realm(1).peaceYears, 0,
          reason: 'the year of the war banks nothing');
      state = _advanceYears(state, 1);
      expect(state.realm(1).recentWars, 1,
          reason: 'one quiet year after the war is not enough');
      state = _advanceYears(state, 1);
      expect(state.realm(1).recentWars, 0, reason: 'the second one pays it off');
    });
  });

  group('peasant revolt (house without a pretender)', () {
    GameState revoltReadyGame() {
      var state = startGame(
              newGame(GameSetup(
                humans: const [],
                reformationYear: 1020,
                ottomanYear: 1040,
                seed: 14,
              )),
              Rng(14))
          .state;
      state.year = 1015; // past the protect-new-players window
      final realm = state.realm(1);
      realm.treasury = 10000;
      realm.towns.single.troopCapacity = 200;
      realm.troopCapacity = 200;
      state = applyAction(
              state,
              RecruitTroops(
                  slot: 1,
                  men: 100,
                  troopClass: TroopClass.infanterie,
                  name: 'Heer'),
              Rng(state.rngSeed))
          .state;
      state.realm(1).treasury = 1000;
      state.realm(1).popularity = 10; // below the §19.1 strife line
      return state;
    }

    test('breaks out, costs men, people and money, then burns itself out', () {
      final state = revoltReadyGame();
      final realm = state.realm(1);
      expect(state.dynasty(1).memberIds.length, lessThanOrEqualTo(3),
          reason: 'no rival branch — the §19.1 coup cannot fire');
      final armyBefore = realm.armySize;
      final peopleBefore = realm.population;
      final rulerBefore = realm.rulerId;

      final events = <GameEvent>[];
      runEliminationChecks(state, 1, Rng(3), events);

      final revolt = events.singleWhere((e) => e.type == 'peasantRevolt');
      expect(revolt.payload['men'],
          armyBefore * peasantRevoltDesertionPercent ~/ 100);
      expect(realm.armySize, lessThan(armyBefore));
      expect(realm.population, lessThan(peopleBefore));
      expect(realm.treasury, 1000 - 1000 * peasantRevoltTreasuryLossPercent ~/ 100);
      expect(realm.popularity, peasantRevoltVentedPopularity,
          reason: 'vented above the strife line — recurring, not a spiral');
      expect(realm.rulerId, rulerBefore,
          reason: 'a revolt never takes the realm away — that stays the '
              'pretender\'s privilege (§19.1)');
    });

    test('a realm already in debt is not handed money by the mob', () {
      final state = revoltReadyGame();
      state.realm(1).treasury = -500;
      runEliminationChecks(state, 1, Rng(3), <GameEvent>[]);
      expect(state.realm(1).treasury, -500);
    });

    test('with a pretender the §19.1 coup fires instead', () {
      final state = revoltReadyGame();
      for (var i = 0; i < 4; i++) {
        final person = Person(
          id: state.nextPersonId++,
          name: 'Rivale $i',
          age: 30,
          dynasty: 1,
          gender: 0,
        );
        state.persons[person.id] = person;
        state.dynasty(1).memberIds.add(person.id);
      }
      final events = <GameEvent>[];
      runEliminationChecks(state, 1, Rng(3), events);
      expect(events.any((e) => e.type == 'internalStrife'), isTrue);
      expect(events.any((e) => e.type == 'peasantRevolt'), isFalse);
      expect(state.realm(1).recentWars, 0,
          reason: 'the pretender does not inherit the deposed ruler\'s wars');
    });
  });

  group('truce bookkeeping survives the wire', () {
    test('the per-opponent map round-trips and copies deeply', () {
      final state = startGame(
              newGame(GameSetup(
                humans: const [],
                reformationYear: 1020,
                ottomanYear: 1040,
                seed: 3,
              )),
              Rng(3))
          .state;
      state.realm(1).truceUntilYear[2] = 1016;
      state.realm(1).lastWarYear = 1015;
      state.realm(1).lastDefendedYear = 1014;

      // JSON keys are strings — the map must come back keyed by int.
      final loaded = GameState.fromJson(state.toJson());
      expect(loaded.realm(1).truceUntilYear[2], 1016);
      expect(loaded.realm(1).lastWarYear, 1015);
      expect(loaded.realm(1).lastDefendedYear, 1014);

      final copy = state.copy();
      copy.realm(1).truceUntilYear[2] = 1099;
      expect(state.realm(1).truceUntilYear[2], 1016,
          reason: 'the copy must not alias the original\'s truce map');
    });
  });

  group('§18.2 outbreak threshold scales with the world', () {
    GameState worldWith(int realms) => startGame(
            newGame(GameSetup(
              humans: const [],
              reformationYear: 1020,
              ottomanYear: 1040,
              realmCount: realms,
              mapSize: realms <= 16 ? MapSize.klein : MapSize.gross,
              seed: 4,
            )),
            Rng(4))
        .state;

    test('a full 30-realm world keeps the original 150 persons', () {
      expect(diseaseThreshold(worldWith(30)), 150);
    });

    test('a klein world scales down instead of never falling ill', () {
      final state = worldWith(12);
      expect(diseaseThreshold(state), 60,
          reason: '5 per realm, floored at 60 — the flat 150 assumed a full '
              '30-realm world and no small map ever reached it');
    });

    test('vacated realms lower it, but never below the floor', () {
      final state = worldWith(30);
      for (final realm in state.realms.skip(2)) {
        realm.rulerId = null;
      }
      expect(diseaseThreshold(state), 60);
    });
  });
}

/// Cycles turns until [years] year rollovers have happened. Nobody acts —
/// the point is the `_startRound` bookkeeping (weariness decay).
GameState _advanceYears(GameState state, int years) {
  var current = state;
  final target = current.year + years;
  var safety = 0;
  while (current.year < target && safety++ < 40 * (years + 1)) {
    current = completeTurn(current, Rng(current.rngSeed)).state;
  }
  expect(current.year, target, reason: 'the year must actually roll over');
  return current;
}

/// Gives another living realm one tile orthogonally touching [slot]'s
/// territory, so the war target pick has a neighbour.
void _makeNeighbor(GameState state, int slot) {
  if (state.map.realmNeighbors(slot).isNotEmpty) return;
  final map = state.map;
  final other =
      state.realms.firstWhere((r) => r.slot != slot && !r.isVacant).slot;
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) {
        continue;
      }
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        if (map.inBounds(x + dx, y + dy) &&
            map.ownerAt(x + dx, y + dy) == slot) {
          map.owner[map.index(x, y)] = other;
          state.realm(other).tileCount[Building.none]++;
          return;
        }
      }
    }
  }
  fail('no free tile bordering slot $slot');
}
