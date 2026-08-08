import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Rules v12 round: the settlement claim cap (half the loser's territory
/// value), the `realmOverrun` total-loss event, and the `humansDefeated`
/// stop in `advanceUntilHuman`.
void main() {
  late GameState state;

  setUp(() {
    state = startGame(
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
    state.year = 1010;
    // Human-vs-human wars are blocked in V1: slot 2 plays AI-controlled.
    state.dynasty(2).status = DynastyStatus.ai;
    state.dynasty(2).humanPlayer = null;
    for (final slot in [1, 2]) {
      final realm = state.realm(slot);
      realm.treasury = 10000;
      realm.towns.single.troopCapacity = 200;
      realm.troopCapacity = 200;
      state = applyAction(
              state,
              RecruitTroops(
                  slot: slot,
                  men: 50,
                  troopClass: TroopClass.infanterie,
                  name: 'Heer$slot'),
              Rng(state.rngSeed))
          .state;
    }
    // Wars need a shared border: hand slot 2 a land tile next to slot 1.
    final map = state.map;
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
            state.realm(2).tileCount[Building.none]++;
            break outer;
          }
        }
      }
    }
    expect(state.map.realmNeighbors(1), contains(2));
  });

  /// Total settlement value of [slot]'s territory under [s]'s rules.
  int territoryValue(GameState s, int slot) {
    var total = 0;
    for (var i = 0; i < s.map.terrain.length; i++) {
      if (s.map.owner[i] == slot) {
        total += settlementTileValue(s, s.map.building[i]);
      }
    }
    return total;
  }

  /// Declares war (slot 1 → slot 2) and reaches the claim settlement via
  /// the WINTER score victory: slot 1's unit occupies slot 2's town when
  /// the forced end arrives. (Capital capture no longer opens a
  /// settlement — since 2026-07-10 it takes over the whole realm, §11.2.)
  GameState winterSettlement(GameState from) {
    var s =
        applyAction(from, DeclareWar(slot: 1, targetSlot: 2), Rng(from.rngSeed))
            .state;
    final enemyTown = s.realm(2).towns.single;
    final troop = s.realm(1).troops.single;
    troop.x = enemyTown.x;
    troop.y = enemyTown.y;
    s.activeWar!.round = 21;
    return applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
  }

  group(
      'settlement claim cap (rules v12; share rolled '
      '$warClaimShareMin–$warClaimShareMax % since v3)', () {
    test('a winter score victory is capped the same way', () {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      final enemyTown = s.realm(2).towns.single;
      final troop = s.realm(1).troops.single;
      troop.x = enemyTown.x;
      troop.y = enemyTown.y;
      // 2026-07-19: the score is occupation-based (tile values + won
      // battles), so a lone occupied Dorf no longer dwarfs the loser's
      // territory. Pump the score over the cap via battle wins to test
      // that the anti-swallow cap still binds.
      s.activeWar!.attackerBattlesWon = 100; // +25,000 score
      final loserValueBefore = territoryValue(s, 2);
      s.activeWar!.round = 21;
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;

      expect(s.activeWar!.phase, WarPhase.settlement);
      expect(s.activeWar!.remainingClaim,
          lessThanOrEqualTo(loserValueBefore * warClaimShareMax ~/ 100));
      expect(s.activeWar!.remainingClaim,
          greaterThanOrEqualTo(loserValueBefore * warClaimShareMin ~/ 100),
          reason: 'the rolled share never falls below the band minimum');
    });

    test('2026-07-19: a claim below the cap is the earned score itself', () {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      final enemyTown = s.realm(2).towns.single;
      final troop = s.realm(1).troops.single;
      troop.x = enemyTown.x;
      troop.y = enemyTown.y;
      final score = warScore(s, 1);
      expect(score, Building.value[s.map.buildingAt(enemyTown.x, enemyTown.y)],
          reason: 'occupation-based score: the occupied tile\'s worth');
      s.activeWar!.round = 21;
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;

      expect(s.activeWar!.phase, WarPhase.settlement);
      expect(s.activeWar!.remainingClaim, score,
          reason: 'you get what you hold — no strength multiplier');
    });
  });

  group('realmOverrun event', () {
    test(
        'finishing a settlement against a landless loser reports the '
        'total loss', () {
      var s = winterSettlement(state);
      expect(s.activeWar!.phase, WarPhase.settlement);

      // The loser loses its remaining land out-of-band (plunder razes
      // tiles to nobody during the war): the finish must report it.
      final map = s.map;
      final loser = s.realm(2);
      for (var i = 0; i < map.terrain.length; i++) {
        if (map.owner[i] != 2) continue;
        loser.tileCount[map.building[i]]--;
        map.owner[i] = World.niemand;
      }
      final result = applyAction(s, SettlementFinish(slot: 1), Rng(s.rngSeed));

      expect(result.events.any((e) => e.type == 'realmOverrun'), isTrue);
      expect(result.events.firstWhere((e) => e.type == 'realmOverrun').slot, 2);
    });

    test('a loser with land left does not trigger the event', () {
      final s = winterSettlement(state);
      final result = applyAction(s, SettlementFinish(slot: 1), Rng(s.rngSeed));
      expect(result.events.any((e) => e.type == 'realmOverrun'), isFalse);
    });
  });

  group('realmOverrun vacates the loser (zombie-realm bug fix)', () {
    test(
        'a total-conquest settlement vacates the loser so it leaves the '
        'turn order and cannot inherit the human slot', () {
      // Win the war (enter settlement phase).
      var s = winterSettlement(state);
      expect(s.activeWar!.phase, WarPhase.settlement);

      // Strip all loser tiles out-of-band (simulates a large-claim total
      // conquest: the settlement claim covers every tile the loser owns).
      final map = s.map;
      final loser = s.realm(2);
      for (var i = 0; i < map.terrain.length; i++) {
        if (map.owner[i] != 2) continue;
        loser.tileCount[map.building[i]]--;
        map.owner[i] = World.niemand;
      }
      s = applyAction(s, SettlementFinish(slot: 1), Rng(s.rngSeed)).state;

      // Loser must be vacant — not a zombie with 0 tiles.
      expect(s.realm(2).isVacant, isTrue,
          reason:
              'a realm that lost every tile must become vacant immediately');

      // Vacate all AI slots (3–30) so slot 1 is the sole living ruler:
      // this simulates the win-condition scenario without running a full game.
      for (var slot = 3; slot <= 30; slot++) {
        s.realm(slot).rulerId = null;
      }
      final result = completeTurn(s, Rng(s.rngSeed));
      expect(result.events.any((e) => e.type == 'gameWon'), isTrue);
      expect(result.events.firstWhere((e) => e.type == 'gameWon').slot, 1,
          reason: 'the human wins — not the zombie slot');
    });
  });

  group('humansDefeated stop', () {
    test('advanceUntilHuman ends the game when no human seat remains', () {
      // Both human dynasties fall to AI control (strife/capture path).
      for (final slot in [1, 2]) {
        state.dynasty(slot).status = DynastyStatus.ai;
        state.dynasty(slot).humanPlayer = null;
      }
      final yearBefore = state.year;
      final result = advanceUntilHuman(state, Rng(state.rngSeed));

      expect(result.state.events.last.type, 'humansDefeated');
      expect(result.events.any((e) => e.type == 'humansDefeated'), isTrue);
      expect(result.state.year, yearBefore,
          reason: 'the game must stop immediately, not simulate the '
              'AI-only world for centuries');
    });

    test('a surviving human seat keeps the game running', () {
      final result = advanceUntilHuman(state, Rng(state.rngSeed));
      expect(
          result.state.events.any((e) => e.type == 'humansDefeated'), isFalse);
      expect(result.state.dynasty(result.state.currentPlayer).status,
          DynastyStatus.human);
    });
  });
}
