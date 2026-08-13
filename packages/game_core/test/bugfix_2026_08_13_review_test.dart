import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Regressions from the v0.2.6 review (2026-08-13):
///  - a voluntary tile handover is a cause of LAND LOSS and must vacate a
///    realm it leaves landless, exactly like a conquest,
///  - the tax rate is a PLAYER policy: a realm in AI hands always plays the
///    original formula, so an inherited setting can never strand it,
///  - a malformed `slots` payload in a `warPlan` answer must not crash the
///    engine (`List.cast` is lazy — the entries are filtered instead).
void main() {
  GameState twoHumans() {
    final state = startGame(
      newGame(GameSetup(
        humans: [
          HumanPlayerSetup(
              founderName: 'Otto', gender: 0, countrySlot: 1, dorfName: 'A'),
          HumanPlayerSetup(
              founderName: 'Ida', gender: 1, countrySlot: 2, dorfName: 'B'),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 2026,
      )),
      Rng(7),
    ).state;
    state.year = 1010;
    return state;
  }

  group('TransferTile land loss', () {
    test('handing away the LAST field vacates the giver', () {
      var state = twoHumans();
      final map = state.map;
      final giver = state.realm(1);
      // A lost seat: the capital tile already belongs to slot 2, so the
      // "not the capital" gate protects nothing and every remaining tile
      // of slot 1 is transferable.
      final capital = map.index(giver.capitalX, giver.capitalY);
      final building = map.building[capital];
      map.owner[capital] = 2;
      giver.tileCount[building]--;
      state.realm(2).tileCount[building]++;
      final town = giver.towns.removeAt(0);
      giver.population -= town.population;
      giver.troopCapacity -= town.troopCapacity;
      state.realm(2).towns.add(town);
      state.realm(2).population += town.population;
      state.realm(2).troopCapacity += town.troopCapacity;

      var guard = 0;
      while (guard++ < 500) {
        final m = state.map;
        (int, int)? next;
        for (var y = 0; y < m.height && next == null; y++) {
          for (var x = 0; x < m.width; x++) {
            if (m.ownerAt(x, y) == 1) {
              next = (x, y);
              break;
            }
          }
        }
        if (next == null) break;
        state = applyAction(
          state,
          TransferTile(slot: 1, targetSlot: 2, x: next.$1, y: next.$2),
          Rng(3),
        ).state;
      }

      expect(state.realm(1).tileCount.fold(0, (a, b) => a + b), 0);
      expect(state.realm(1).isVacant, isTrue,
          reason: 'a landless realm must be vacated, never left as a zombie '
              'ruler that blocks checkWinCondition forever');
    });

    test('a normal handover leaves the giver alone', () {
      final state = twoHumans();
      final map = state.map;
      final giver = state.realm(1);
      (int, int)? tile;
      for (var y = 0; y < map.height && tile == null; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) == 1 &&
              !(x == giver.capitalX && y == giver.capitalY)) {
            tile = (x, y);
            break;
          }
        }
      }
      final next = applyAction(
        state,
        TransferTile(slot: 1, targetSlot: 2, x: tile!.$1, y: tile.$2),
        Rng(3),
      ).state;
      expect(next.realm(1).isVacant, isFalse);
      expect(next.events.any((e) => e.type == 'realmOverrun'), isFalse);
    });
  });

  group('tax rate in AI hands', () {
    test('an AI turn resets an inherited rate to the original formula', () {
      final state = twoHumans();
      final ai = state.realms.firstWhere((r) =>
          !r.isVacant && state.dynasty(r.slot).status == DynastyStatus.ai);
      ai.taxRate = taxRateMax;
      final next = runAiTurn(state, ai.slot, Rng(5)).state;
      expect(next.realm(ai.slot).taxRate, taxRateDefault);
    });

    test('a replacement dynasty starts on the default rate', () {
      final state = twoHumans();
      final slot = state.realms
          .firstWhere((r) =>
              !r.isVacant && state.dynasty(r.slot).status == DynastyStatus.ai)
          .slot;
      state.realm(slot).taxRate = taxRateMin;
      foundReplacementDynasty(state, slot, Rng(3), <GameEvent>[]);
      expect(state.realm(slot).taxRate, taxRateDefault);
    });
  });

  group('war-plan payload hardening', () {
    test('a non-integer start slot is dropped, not thrown on', () {
      final state = twoHumans();
      for (final slot in [1, 2]) {
        final realm = state.realm(slot);
        realm.troops.add(Troop(
          name: 'Heer$slot',
          men: 100,
          troopClass: TroopClass.infanterie,
          quality: TroopQuality.regular,
          garrisonCounted: false,
          x: realm.capitalX,
          y: realm.capitalY,
        ));
      }
      final war = startWar(state, 1, 2, Rng(1));
      final plan = state.pendingDecisions
          .singleWhere((d) => d.type == 'warPlan' && d.decidingSlot == 1);
      applyActionInPlace(
        state,
        ResolveDecision(slot: 1, decisionId: plan.id, choice: {
          'auto': false,
          'slots': <dynamic>['tomorrow', 2000, null],
        }),
        Rng(1),
      );
      expect(war.planSlots[1], [2000],
          reason: 'garbage entries are filtered; the engine must not throw '
              'on a lazily cast list');
    });
  });
}
