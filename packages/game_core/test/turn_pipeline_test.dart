import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

GameState freshGame({int seed = 2026}) => newGame(GameSetup(
      humans: [
        HumanPlayerSetup(
            founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'Berlin'),
      ],
      reformationYear: 1020,
      ottomanYear: 1040,
      seed: seed,
    ));

/// Asserts the §8 bookkeeping invariants the original re-asserts each turn.
void expectInvariants(GameState state) {
  for (final realm in state.realms) {
    final townPop = realm.towns.fold(0, (s, t) => s + t.population);
    final townCap = realm.towns.fold(0, (s, t) => s + t.troopCapacity);
    final townGarrison = realm.towns.fold(0, (s, t) => s + t.garrison);
    expect(realm.population, townPop, reason: 'slot ${realm.slot} pop sum');
    expect(realm.troopCapacity, townCap,
        reason: 'slot ${realm.slot} capacity sum');
    expect(realm.armySize, townGarrison,
        reason: 'slot ${realm.slot} garrison sum');
    expect(realm.popularity, inInclusiveRange(0, 100));
    expect(realm.grainHarvest, greaterThanOrEqualTo(0));
    expect(realm.livestockHarvest, greaterThanOrEqualTo(0));

    final counted = List.filled(9, 0);
    final map = state.map;
    for (var i = 0; i < map.terrain.length; i++) {
      if (map.owner[i] == realm.slot) counted[map.building[i]]++;
    }
    expect(realm.tileCount, counted,
        reason: 'slot ${realm.slot} tileCount vs map');
  }
}

void main() {
  group('startGame', () {
    test('rolls into year 1000 with prices and first upkeep', () {
      final result = startGame(freshGame(), Rng(1));
      final state = result.state;
      expect(state.year, 1000);
      expect(state.currentPlayer, 1);
      expect(state.grainPrice, inInclusiveRange(1.0, 2.0));
      expect(state.cattlePrice, inInclusiveRange(1.5, 2.5));

      final realm = state.realm(1);
      // Movement roll for Burgherrin (class 13 → equivalent 1): [1, 6].
      expect(realm.movementPoints, inInclusiveRange(1, 6));
      expect(state.kaiserPot, greaterThan(0), reason: 'tribute was paid');

      final upkeep = result.events.where((e) => e.type == 'turnUpkeep').single;
      expect(upkeep.slot, 1);
      // Treasury follows exactly from the upkeep report.
      expect(
          realm.treasury,
          1000 +
              (upkeep.payload['tax'] as int) -
              (upkeep.payload['tribute'] as int) +
              (upkeep.payload['harborIncome'] as int) -
              (upkeep.payload['wages'] as int));
      expect(upkeep.payload['tax'],
          inInclusiveRange(realm.population, 2 * realm.population * 2));
      expectInvariants(state);
    });

    test('rejects a state that is not fresh', () {
      final started = startGame(freshGame(), Rng(1)).state;
      expect(() => startGame(started, Rng(1)), throwsStateError);
    });
  });

  group('completeTurn', () {
    test('advances slots and rolls the year on wrap', () {
      var state = startGame(freshGame(), Rng(1)).state;
      final grainPriceBefore = state.grainPrice;
      for (var i = 0; i < 29; i++) {
        state = completeTurn(state, Rng(state.rngSeed)).state;
        expect(state.year, 1000);
      }
      expect(state.currentPlayer, 30);
      state = completeTurn(state, Rng(state.rngSeed)).state;
      expect(state.currentPlayer, 1);
      expect(state.year, 1001, reason: 'wrap increments the year');
      // 11 possible price values each — a same-value re-roll is possible
      // but the seed used here produces a change.
      expect(state.grainPrice, isNot(grainPriceBefore));
    });

    test('skips vacant slots', () {
      var state = startGame(freshGame(), Rng(1)).state;
      state.realm(2).rulerId = null;
      state.realm(3).rulerId = null;
      state = completeTurn(state, Rng(state.rngSeed)).state;
      expect(state.currentPlayer, 4);
    });

    test('emits gameWon when one ruler holds everything', () {
      var state = startGame(freshGame(), Rng(1)).state;
      final ruler = state.realm(1).rulerId;
      for (final realm in state.realms) {
        if (realm.slot != 1) realm.rulerId = null;
      }
      expect(checkWinCondition(state), 1);
      final result = completeTurn(state, Rng(state.rngSeed));
      expect(result.events.single.type, 'gameWon');
      expect(result.events.single.slot, 1);
      expect(result.state.realm(1).rulerId, ruler);
    });

    test('ruler aliasing across slots also wins (§19.3)', () {
      final state = startGame(freshGame(), Rng(1)).state;
      final ruler = state.realm(1).rulerId;
      for (final realm in state.realms) {
        realm.rulerId = ruler; // one person rules all 30 slots
      }
      expect(checkWinCondition(state), 1);
    });

    test('50-year smoke run keeps all invariants', () {
      var state = startGame(freshGame(), Rng(99)).state;
      for (var turn = 0; turn < 50 * 30; turn++) {
        state = completeTurn(state, Rng(state.rngSeed)).state;
      }
      expect(state.year, 1050);
      expectInvariants(state);
      // Fed realms grow: total population should have risen from ~100/realm.
      final total = state.realms.fold(0, (s, r) => s + r.population);
      expect(total, greaterThan(30 * 100));
    });
  });

  group('economy (§7)', () {
    test('tribute goes to the kaiser pot; the Kaiser collects it', () {
      var state = startGame(freshGame(), Rng(7)).state;
      final pot = state.kaiserPot;
      expect(pot, greaterThan(0));

      // Crown slot 2's ruler: on their upkeep they collect the whole pot
      // and pay no tribute.
      state.kaiserId = state.realm(2).rulerId;
      final before = state.realm(2).treasury;
      state = completeTurn(state, Rng(state.rngSeed)).state;
      final upkeep = state.events.reversed
          .firstWhere((e) => e.type == 'turnUpkeep' && e.slot == 2);
      expect(upkeep.payload['potCollected'], pot);
      expect(upkeep.payload['tribute'], 0);
      expect(
          state.realm(2).treasury,
          before +
              pot +
              (upkeep.payload['tax'] as int) +
              (upkeep.payload['harborIncome'] as int) -
              (upkeep.payload['wages'] as int));
    });

    test('wages cost 0.5 T per man', () {
      final state = startGame(freshGame(), Rng(7)).state;
      final realm = state.realm(2);
      realm.armySize = 100;
      realm.towns.single.garrison = 100;
      realm.towns.single.troopCapacity = 100;
      realm.grainHarvest = 10000; // well fed — no famine desertion
      final result = completeTurn(state, Rng(state.rngSeed));
      final upkeep = result.events
          .firstWhere((e) => e.type == 'turnUpkeep' && e.slot == 2);
      expect(upkeep.payload['wages'], 50);
    });
  });

  group('food & popularity (§8)', () {
    test('surplus percent is clamped to [−30, +15]', () {
      var state = startGame(freshGame(), Rng(3)).state;
      // Slot 2: huge stock → S must clamp at +15.
      state.realm(2).grainHarvest = 1000000;
      state = completeTurn(state, Rng(state.rngSeed)).state;
      final upkeep = state.events.reversed
          .firstWhere((e) => e.type == 'turnUpkeep' && e.slot == 2);
      expect(upkeep.payload['surplusPercent'], 15);

      // Slot 3: no food at all → S clamps at −30.
      state.realm(3).grainHarvest = 0;
      state.realm(3).livestockHarvest = 0;
      state.realm(3).tileCount[Building.kornfeld] = 0;
      state.realm(3).tileCount[Building.weide] = 0;
      state = completeTurn(state, Rng(state.rngSeed)).state;
      final upkeep3 = state.events.reversed
          .firstWhere((e) => e.type == 'turnUpkeep' && e.slot == 3);
      expect(upkeep3.payload['surplusPercent'], -30);
    });

    test('a starving realm loses popularity, a fed one gains ≤ 5% + 3', () {
      final state = startGame(freshGame(), Rng(3)).state;
      final fed = state.realm(2)..grainHarvest = 100000;
      final starving = state.realm(3)
        ..grainHarvest = 0
        ..livestockHarvest = 0
        ..tileCount[Building.kornfeld] = 0
        ..tileCount[Building.weide] = 0;
      // Keep tileCount/map consistent for the starving realm.
      final map = state.map;
      for (var i = 0; i < map.terrain.length; i++) {
        if (map.owner[i] == 3 &&
            (map.building[i] == Building.kornfeld ||
                map.building[i] == Building.weide)) {
          map.building[i] = Building.none;
          starving.tileCount[Building.none]++;
        }
      }
      final popBefore = {2: fed.popularity, 3: starving.popularity};

      var s = completeTurn(state, Rng(state.rngSeed)).state; // slot 2
      s = completeTurn(s, Rng(s.rngSeed)).state; // slot 3

      expect(s.realm(2).popularity,
          inInclusiveRange(popBefore[2]!, (popBefore[2]! * 1.05).round() + 3));
      expect(s.realm(2).popularity, greaterThan(popBefore[2]!));
      expect(s.realm(3).popularity, lessThan(popBefore[3]!));
    });

    test('towns get Marktrecht at 500 and Stadtrecht at 1000', () {
      final state = startGame(freshGame(), Rng(5)).state;
      final town2 = state.realm(2).towns.single;
      final town3 = state.realm(3).towns.single;
      state.realm(2).population += 600 - town2.population;
      town2.population = 600;
      state.realm(3).population += 1500 - town3.population;
      town3.population = 1500;
      // Keep both realms fed so growth cannot shrink them below the
      // promotion thresholds before the transition check runs.
      state.realm(2).grainHarvest = 10000;
      state.realm(3).grainHarvest = 10000;

      var s = completeTurn(state, Rng(state.rngSeed)).state; // slot 2
      s = completeTurn(s, Rng(s.rngSeed)).state; // slot 3

      expect(s.realm(2).towns.single.buildingType, Building.markt);
      expect(s.realm(2).tileCount[Building.markt], 1);
      expect(s.realm(2).tileCount[Building.dorf], 0);
      expect(s.realm(3).towns.single.buildingType, Building.stadt,
          reason: 'Dorf double-promotes through Markt to Stadt');
      expect(s.events.where((e) => e.type == 'townPromoted' && e.slot == 3),
          hasLength(2));
      expectInvariants(s);
    });

    test('a town below 5 inhabitants dies and the tile reverts', () {
      final state = startGame(freshGame(), Rng(5)).state;
      final realm = state.realm(2);
      final town = realm.towns.single;
      realm.population += 1 - town.population;
      town.population = 1; // population ≤ 1 → block skipped, town pop → 0
      final s = completeTurn(state, Rng(state.rngSeed)).state;
      expect(s.realm(2).towns, isEmpty);
      expect(s.realm(2).population, 0);
      expect(s.events.where((e) => e.type == 'townDied'), hasLength(1));
      expect(s.realm(2).tileCount[Building.dorf], 0);
      expectInvariants(s);
    });
  });

  group('game end', () {
    test('total extinction ends the game in a draw instead of crashing', () {
      final state = startGame(freshGame(), Rng(11)).state;
      for (final realm in state.realms) {
        realm.rulerId = null;
      }
      final result = completeTurn(state, Rng(state.rngSeed));
      expect(result.events.any((e) => e.type == 'gameDraw'), isTrue);
      // A dead world stays inert on further calls.
      final again = completeTurn(result.state, Rng(result.state.rngSeed));
      expect(again.events.any((e) => e.type == 'gameDraw'), isTrue);
    });
  });

  group('market actions (§9)', () {
    test('sells once per good per turn at the global price', () {
      final state = startGame(freshGame(), Rng(11)).state;
      final realm = state.realm(1);
      realm.grainHarvest = 500;
      state.grainPrice = 2.0;
      final result = applyAction(
          state,
          SellGood(slot: 1, good: MarketGood.grain, amount: 100),
          Rng(state.rngSeed));
      expect(result.state.realm(1).grainHarvest, 400);
      expect(result.state.realm(1).treasury, realm.treasury + 200);
      expect(
        () => applyAction(
            result.state,
            SellGood(slot: 1, good: MarketGood.grain, amount: 1),
            Rng(result.state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'Du hast diese Runde schon verkauft !!!',
      );
      // Cattle is a separate flag.
      result.state.realm(1).livestockHarvest = 10;
      final cattle = applyAction(
          result.state,
          SellGood(slot: 1, good: MarketGood.cattle, amount: 10),
          Rng(result.state.rngSeed));
      expect(cattle.state.realm(1).livestockHarvest, 0);
    });

    test('rejects overselling, zero and negative amounts', () {
      final state = startGame(freshGame(), Rng(11)).state;
      state.realm(1).grainHarvest = 50;
      // 0 must throw too: it would burn the once-per-turn flag for nothing.
      for (final amount in [-1, 0, 51]) {
        expect(
          () => applyAction(
              state,
              SellGood(slot: 1, good: MarketGood.grain, amount: amount),
              Rng(state.rngSeed)),
          throwsA(isA<ActionException>()),
        );
      }
    });

    test('ship investment is capped, once per turn, outcome bounded', () {
      final state = startGame(freshGame(), Rng(11)).state;
      final realm = state.realm(1);
      realm.tileCount[Building.hafen] = 2; // cap 1200
      realm.treasury = 1000;
      expect(
        () => applyAction(
            state, InvestShips(slot: 1, amount: 1201), Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'over the 600 × harbors cap',
      );
      expect(
        () => applyAction(
            state, InvestShips(slot: 1, amount: 1001), Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'more than the treasury',
      );
      final result = applyAction(
          state, InvestShips(slot: 1, amount: 500), Rng(state.rngSeed));
      final invested = result.state.realm(1);
      // Stake leaves the treasury now; the haul lands next turn.
      expect(invested.treasury, 500, reason: 'stake deducted immediately');
      expect(invested.pendingShipReturns, hasLength(1));
      final voyage = invested.pendingShipReturns.single;
      expect(voyage.invested, 500);
      // Returned ∈ [0, 2×amount].
      expect(voyage.returned, inInclusiveRange(0, 1000));
      expect(voyage.returnYear, result.state.year + 1);
      expect(
        () => applyAction(result.state, InvestShips(slot: 1, amount: 100),
            Rng(result.state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'once per turn',
      );
    });

    test('trade ships return at the start of the next round', () {
      final state = startGame(freshGame(), Rng(11)).state;
      final realm = state.realm(1);
      realm.tileCount[Building.hafen] = 1;
      realm.treasury = 600;
      final sent = applyAction(
          state, InvestShips(slot: 1, amount: 600), Rng(state.rngSeed)).state;
      final voyage = sent.realm(1).pendingShipReturns.single;
      expect(sent.events.last.type, 'shipsSent', reason: 'departure notice');

      // Advance the pipeline until slot 1 begins its next turn (the voyage
      // resolves there).
      var s = sent;
      for (var i = 0; i < 200 && s.realm(1).pendingShipReturns.isNotEmpty; i++) {
        s = completeTurn(s, Rng(s.rngSeed)).state;
      }

      expect(s.realm(1).pendingShipReturns, isEmpty, reason: 'voyage resolved');
      expect(s.year, 1001, reason: 'returned the following round');
      final notice = s.events.lastWhere(
          (e) => e.type == 'shipsReturned' && e.slot == 1,
          orElse: () => throw StateError('no return notice posted'));
      expect(notice.payload['returned'], voyage.returned,
          reason: 'notice reports the haul rolled at departure');
    });
  });

  group('movement (§6.3)', () {
    test('rolls classEquivalent + random(6) for every ladder', () {
      const expected = {
        1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, // Christian
        9: 1, 10: 3, 11: 6, 12: 8, // Muslim equivalents
      };
      final rng = Rng(42);
      for (final entry in expected.entries) {
        for (var i = 0; i < 50; i++) {
          expect(rollMovementPoints(entry.key, rng),
              inInclusiveRange(entry.value, entry.value + 5));
          // Female form: same roll range.
          expect(rollMovementPoints(entry.key + 12, rng),
              inInclusiveRange(entry.value, entry.value + 5));
        }
      }
    });
  });

  group('event log cap', () {
    test('completeTurn prunes the oldest events past maxRetainedEvents', () {
      var state = startGame(freshGame(), Rng(1)).state;
      // Inflate the log well past the cap with marker events.
      for (var i = 0; i < maxRetainedEvents + 250; i++) {
        state.events.add(GameEvent(
          year: state.year,
          slot: 0,
          type: 'filler$i',
          visibility: EventVisibility.public,
        ));
      }
      final before = state.events.length;
      final result = completeTurn(state, Rng(state.rngSeed));
      final s = result.state;
      expect(s.events.length, maxRetainedEvents);
      expect(s.prunedEventCount,
          before + result.events.length - maxRetainedEvents);
      // The newest events (this turn's) survive; the oldest are gone.
      expect(s.events.last.type, result.events.last.type);
      expect(s.events.any((e) => e.type == 'filler0'), isFalse);
      // The cap survives the save round-trip.
      final json = s.toJson();
      expect(GameState.fromJson(json).prunedEventCount, s.prunedEventCount);
    });
  });

  group('protect-new-players rule', () {
    test('is active in years 1000–1009 only', () {
      final state = startGame(freshGame(), Rng(1)).state;
      expect(state.year, 1000);
      expect(newPlayerProtectionActive(state), isTrue);
      state.year = 1009;
      expect(newPlayerProtectionActive(state), isTrue);
      state.year = 1010;
      expect(newPlayerProtectionActive(state), isFalse);
      expect(firstWarYear, 1010);
    });
  });
}
