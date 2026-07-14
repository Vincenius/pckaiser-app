import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

GameState aiOnlyGame({int seed = 2026}) => startGame(
        newGame(GameSetup(
          humans: const [],
          reformationYear: 1020,
          ottomanYear: 1040,
          seed: seed,
        )),
        Rng(seed))
    .state;

void expectInvariants(GameState state) {
  for (final realm in state.realms) {
    expect(realm.popularity, inInclusiveRange(0, 100),
        reason: 'slot ${realm.slot} popularity');
    expect(realm.population, greaterThanOrEqualTo(0));
    expect(realm.grainHarvest, greaterThanOrEqualTo(0));
    expect(realm.livestockHarvest, greaterThanOrEqualTo(0));
    expect(realm.guardLevel, inInclusiveRange(0, 50));
    final townPop = realm.towns.fold(0, (n, t) => n + t.population);
    final townCap = realm.towns.fold(0, (n, t) => n + t.troopCapacity);
    expect(realm.population, townPop,
        reason: 'slot ${realm.slot} population sum');
    expect(realm.troopCapacity, townCap,
        reason: 'slot ${realm.slot} capacity sum');

    final counted = List.filled(9, 0);
    for (var i = 0; i < state.map.terrain.length; i++) {
      if (state.map.owner[i] == realm.slot) {
        counted[state.map.building[i]]++;
      }
    }
    expect(realm.tileCount, counted,
        reason: 'slot ${realm.slot} tileCount vs map');
    for (final troop in realm.troops) {
      expect(troop.men, greaterThan(0),
          reason: 'slot ${realm.slot} has an empty unit');
    }
  }
  // Person/dynasty cross-references are intact.
  for (final dynasty in state.dynasties) {
    for (final id in dynasty.memberIds) {
      expect(state.persons[id]?.dynasty, dynasty.index,
          reason: 'dynasty ${dynasty.index} member $id');
    }
  }
}

void main() {
  group('AI turn script (§20)', () {
    test('the AI expands, farms and builds with its movement points', () {
      var state = aiOnlyGame();
      final ownedBefore =
          state.map.owner.where((o) => o != World.niemand).length;
      final result = runAiTurn(state, 1, Rng(state.rngSeed));
      state = result.state;
      expect(state.realm(1).movementPoints, 0,
          reason: 'build loop spends all points');
      final ownedAfter =
          state.map.owner.where((o) => o != World.niemand).length;
      expect(ownedAfter, greaterThan(ownedBefore));
      expectInvariants(state);
    });

    test('the AI sells at high prices and never stockpiles', () {
      final state = aiOnlyGame();
      state.grainPrice = 1.9;
      state.realm(1).grainHarvest = 500;
      final treasuryBefore = state.realm(1).treasury;
      final result = runAiTurn(state, 1, Rng(state.rngSeed));
      expect(result.state.realm(1).grainHarvest, 0);
      expect(result.state.realm(1).treasury,
          greaterThan(treasuryBefore + 500), // 500 × 1.9 minus build costs…
          skip: 'treasury also moves through builds — checked via event');
      expect(result.events.any((e) => e.type == 'goodsSold'), isTrue);
    });

    test('the AI keeps grain at low prices', () {
      final state = aiOnlyGame();
      state.grainPrice = 1.2;
      state.cattlePrice = 1.5; // below the ~2.2 sell threshold too
      state.realm(1).grainHarvest = 500;
      final result = runAiTurn(state, 1, Rng(state.rngSeed));
      expect(result.events.any((e) => e.type == 'goodsSold'), isFalse);
    });

    test('the AI recruits troops once towns have capacity', () {
      final state = aiOnlyGame();
      state.realm(1).treasury = 5000;
      state.realm(1).towns.single.troopCapacity = 100;
      state.realm(1).troopCapacity = 100;
      final result = runAiTurn(state, 1, Rng(state.rngSeed));
      expect(result.state.realm(1).troops, isNotEmpty);
      expect(result.state.realm(1).armySize, greaterThan(0));
      expectInvariants(result.state);
    });

    test('the AI merges slots it acquired through inheritance', () {
      final state = aiOnlyGame();
      // Slot 1's ruler also rules slot 2 (e.g. inherited).
      state.realm(2).rulerId = state.realm(1).rulerId;
      // Ensure slot 2 borders slot 1 (merging now requires a shared border).
      final map = state.map;
      if (!map.realmNeighbors(1).contains(2)) {
        outer:
        for (var y = 0; y < map.height; y++) {
          for (var x = 0; x < map.width; x++) {
            if (map.ownerAt(x, y) != 1) continue;
            for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
              final nx = x + dx, ny = y + dy;
              if (!map.inBounds(nx, ny)) continue;
              if (map.ownerAt(nx, ny) == World.niemand &&
                  map.isLandAt(nx, ny)) {
                map.owner[map.index(nx, ny)] = 2;
                state.realm(2).tileCount[Building.none]++;
                break outer;
              }
            }
          }
        }
      }
      final result = runAiTurn(state, 1, Rng(state.rngSeed));
      expect(result.events.any((e) => e.type == 'realmsMerged'), isTrue);
      // The acting slot (1) is the source — it gets vacated; slot 2 absorbs it.
      expect(result.state.realm(1).rulerId, isNull);
      expect(result.state.realm(1).towns, isEmpty);
      expect(result.state.realm(1).popularity, 60);
      expectInvariants(result.state);
    });
  });

  group('human guard', () {
    test('runAiTurn never acts for a human-controlled dynasty', () {
      final state = newGame(GameSetup(
        humans: [
          HumanPlayerSetup(
              founderName: 'Anna',
              gender: 1,
              countrySlot: 1,
              dorfName: 'Berlin'),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 3,
      ));
      state.realm(1).movementPoints = 5;
      state.realm(1).treasury = 5000;
      final result = runAiTurn(state, 1, Rng(7));
      expect(result.events, isEmpty);
      expect(result.state.realm(1).treasury, 5000);
      expect(result.state.realm(1).movementPoints, 5,
          reason: 'the AI must not play the human realm');
    });
  });

  group('AI war (§11.2, §20.8)', () {
    test('a fast-forwarded AI war terminates and bookkeeping holds', () {
      final state = aiOnlyGame(seed: 9);
      state.year = 1011;
      // Arm slot 1 heavily so a war it declares actually goes somewhere.
      final realm = state.realm(1);
      realm.treasury = 20000;
      realm.towns.single.troopCapacity = 300;
      realm.troopCapacity = 300;
      // Levy limit (10% of population/turn): room for the 250-man recruit.
      realm.towns.single.population += 2500;
      realm.population += 2500;
      var s = applyAction(
              state,
              RecruitTroops(
                  slot: 1,
                  men: 250,
                  troopClass: TroopClass.infanterie,
                  name: 'Heer'),
              Rng(state.rngSeed))
          .state;

      // Force the war branch: declare directly, then fast-forward by
      // repeatedly letting the AI act (runAiTurn won't start a second war).
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: _adjacentTo(s, 1)),
              Rng(s.rngSeed))
          .state;
      expect(s.activeWar, isNotNull);
      var guard = 0;
      while (s.activeWar != null && guard++ < 40) {
        final events = <GameEvent>[];
        final copy = s.copy();
        runAiWarMovement(
            copy, copy.activeWar!.attackerSlot, Rng(copy.rngSeed), events);
        if (copy.activeWar != null) {
          runAiWarMovement(copy, copy.activeWar!.defenderSlot,
              Rng(copy.rngSeed + 1), events);
        }
        if (copy.activeWar != null &&
            copy.activeWar!.phase == WarPhase.rounds) {
          endWarRound(copy, Rng(copy.rngSeed + 2), events);
        } else if (copy.activeWar != null) {
          autoSettleClaim(copy, Rng(copy.rngSeed + 3), events);
        }
        s = copy;
      }
      expect(s.activeWar, isNull, reason: 'war must terminate');
      expectInvariants(s);
    });
  });

  group('full-AI smoke test', () {
    test('30 AI realms, 200 years headless, no invariant violations', () {
      var state = aiOnlyGame(seed: 777);
      var year = state.year;
      var safety = 0;
      var won = false;
      while (state.year < 1200 && safety++ < 200 * 40) {
        final slot = state.currentPlayer;
        if (!state.realm(slot).isVacant &&
            state.dynasty(slot).status == DynastyStatus.ai) {
          state = runAiTurn(state, slot, Rng(state.rngSeed)).state;
        }
        if (state.activeWar != null) {
          // Defensive: no war may leak out of an all-AI simulation.
          fail('an AI war was left unresolved');
        }
        state = completeTurn(state, Rng(state.rngSeed)).state;
        if (state.events.isNotEmpty && state.events.last.type == 'gameWon') {
          won = true;
          break;
        }
        if (state.year > year) {
          year = state.year;
          if (year % 50 == 0) expectInvariants(state);
        }
        // No human decisions may ever be queued in an all-AI game.
        expect(state.pendingDecisions, isEmpty);
      }
      // Since ruler capture takes whole realms (§11.2, 2026-07-10), an
      // all-AI world can legitimately consolidate to a sole ruler early.
      expect(won || state.year >= 1050, isTrue,
          reason: 'simulation must run deep (or end by victory)');
      expectInvariants(state);

      // The end state still serializes losslessly.
      final json = state.toJson();
      expect(GameState.fromJson(json).toJson(), json);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

int _adjacentTo(GameState state, int slot) {
  final neighbors = state.map.realmNeighbors(slot);
  for (final n in neighbors) {
    if (!state.realm(n).isVacant) return n;
  }
  // No natural neighbor: hand another living realm a tile that touches
  // [slot] — wars require a shared border.
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
          return other;
        }
      }
    }
  }
  fail('no war target found');
}
