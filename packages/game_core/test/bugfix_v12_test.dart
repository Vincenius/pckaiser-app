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
                founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'A'),
            HumanPlayerSetup(
                founderName: 'Berta', gender: 1, countrySlot: 2, dorfName: 'B'),
          ],
          reformationYear: 1020,
          ottomanYear: 1040,
          seed: 2026,
        )),
        Rng(7)).state;
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
          Rng(state.rngSeed)).state;
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

  /// Declares war (slot 1 → slot 2) and parks slot 1's unit on slot 2's
  /// capital; the defender's unit is moved aside first.
  GameState marchOntoCapital(GameState from) {
    var s = applyAction(from, DeclareWar(slot: 1, targetSlot: 2),
            Rng(from.rngSeed))
        .state;
    final enemy = s.realm(2);
    enemy.troops.single.x = enemy.towns.single.x;
    enemy.troops.single.y = enemy.towns.single.y;
    final troop = s.realm(1).troops.single;
    troop.x = enemy.capitalX - 1;
    troop.y = enemy.capitalY;
    s.activeWar!.movesLeft[1]![0] = 5;
    return applyAction(
            s, WarMove(slot: 1, unitIndex: 0, dx: 1, dy: 0), Rng(s.rngSeed))
        .state;
  }

  group('settlement claim cap (rules v12)', () {
    test('a capital capture claim is capped at half the loser territory '
        'value', () {
      var s = marchOntoCapital(state);
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      final loserValueBefore = territoryValue(s, 2);
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;

      expect(s.activeWar!.phase, WarPhase.settlement);
      expect(s.activeWar!.winnerSlot, 1);
      expect(s.activeWar!.remainingClaim,
          lessThanOrEqualTo(loserValueBefore ~/ 2),
          reason: 'one lost war may cost at most half the realm');
      expect(s.activeWar!.remainingClaim, greaterThan(0));
    });

    test('under v11 rules the same capture is uncapped', () {
      final pinned =
          GameState.fromJson(state.toJson()..['rulesVersion'] = 11);
      var s = marchOntoCapital(pinned);
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      final loserValue = territoryValue(s, 2);
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;

      expect(s.activeWar!.phase, WarPhase.settlement);
      expect(s.activeWar!.remainingClaim, greaterThan(loserValue ~/ 2),
          reason: 'pre-v12 the war score dwarfed the loser territory');
    });

    test('a winter score victory is capped the same way', () {
      var s = applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
              Rng(state.rngSeed))
          .state;
      final enemyTown = s.realm(2).towns.single;
      final troop = s.realm(1).troops.single;
      troop.x = enemyTown.x;
      troop.y = enemyTown.y;
      final loserValueBefore = territoryValue(s, 2);
      s.activeWar!.round = 21;
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;

      expect(s.activeWar!.phase, WarPhase.settlement);
      expect(s.activeWar!.remainingClaim,
          lessThanOrEqualTo(loserValueBefore ~/ 2));
    });

    test('the cap leaves the loser the last tile: annexing everything is '
        'impossible', () {
      // A loser realm with a single 100-point tile: cap = 50 < 100, so
      // the tile can never be afforded in the settlement.
      var s = marchOntoCapital(state);
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      // Strip slot 2 down to one bare tile before the capture resolves.
      final map = s.map;
      final loser = s.realm(2);
      var kept = false;
      for (var i = 0; i < map.terrain.length; i++) {
        if (map.owner[i] != 2) continue;
        final isCapital =
            i == map.index(loser.capitalX, loser.capitalY);
        if (!kept && !isCapital && map.building[i] == Building.none) {
          kept = true;
          continue;
        }
        if (isCapital) continue; // capital stays for the capture check
        loser.tileCount[map.building[i]]--;
        map.owner[i] = World.niemand;
      }
      expect(kept, isTrue);
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;

      expect(s.activeWar!.phase, WarPhase.settlement);
      // Loser value: capital (5000) + bare tile (100) → cap 2550 < 5000:
      // the capital itself stays out of reach too.
      expect(s.activeWar!.remainingClaim,
          lessThan(settlementTileValue(s, Building.burg)));
    });
  });

  group('realmOverrun event', () {
    test('finishing a settlement against a landless loser reports the '
        'total loss', () {
      var s = marchOntoCapital(state);
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
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
      final result =
          applyAction(s, SettlementFinish(slot: 1), Rng(s.rngSeed));

      expect(result.events.any((e) => e.type == 'realmOverrun'), isTrue);
      expect(
          result.events
              .firstWhere((e) => e.type == 'realmOverrun')
              .slot,
          2);
    });

    test('a loser with land left does not trigger the event', () {
      var s = marchOntoCapital(state);
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      final result =
          applyAction(s, SettlementFinish(slot: 1), Rng(s.rngSeed));
      expect(result.events.any((e) => e.type == 'realmOverrun'), isFalse);
    });
  });

  group('humansDefeated stop', () {
    test('advanceUntilHuman ends the game when no human seat remains',
        () {
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
          result.state.events.any((e) => e.type == 'humansDefeated'),
          isFalse);
      expect(
          result.state.dynasty(result.state.currentPlayer).status,
          DynastyStatus.human);
    });
  });
}
