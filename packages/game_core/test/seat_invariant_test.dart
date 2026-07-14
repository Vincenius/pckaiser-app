import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Seat invariant: a realm that still owns land ALWAYS has a valid seat.
/// Without one the capital-occupation victory can never fire and the map
/// draws no seat flag — the reported "enemy seat missing, war unwinnable"
/// bug. Covered here:
///  - the no-Burg fallback (re-seat onto ANY owned tile, even for humans),
///  - the forced repair at war start and every war-round end,
///  - the immediate re-seat when the settlement annexes the loser's capital.
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
    state.dynasty(2).status = DynastyStatus.ai;
    state.dynasty(2).humanPlayer = null;
  });

  /// Strips [slot] of every Stadt/Burg/Palast tile (hands them to nobody)
  /// and invalidates the seat, leaving only non-eligible land.
  void loseAllSeatTiles(int slot) {
    final map = state.map;
    for (var i = 0; i < map.terrain.length; i++) {
      if (map.owner[i] != slot) continue;
      final b = map.building[i];
      if (b == Building.stadt || b == Building.burg || b == Building.palast) {
        map.owner[i] = World.niemand;
      }
    }
  }

  group('no-Burg fallback seat', () {
    test('an AI realm with no eligible building re-seats onto any own tile',
        () {
      loseAllSeatTiles(2);
      final events = <GameEvent>[];
      reseatLostCapitals(state, Rng(1), events);

      final realm = state.realm(2);
      expect(state.map.ownerAt(realm.capitalX, realm.capitalY), 2,
          reason: 'the seat must land on own territory');
      expect(events.any((e) => e.type == 'capitalReseated'), isTrue);
    });

    test('a human realm with no eligible building re-seats automatically too',
        () {
      loseAllSeatTiles(1);
      final events = <GameEvent>[];
      reseatLostCapitals(state, Rng(1), events);

      final realm = state.realm(1);
      expect(state.map.ownerAt(realm.capitalX, realm.capitalY), 1,
          reason: 'nothing to choose from — the seat is placed automatically');
      expect(
          state.pendingDecisions
              .any((d) => d.type == 'relocateCapital' && d.decidingSlot == 1),
          isFalse,
          reason: 'no decision without an eligible Stadt/Burg/Palast');
    });

    test('the fallback picks the highest-value owned tile', () {
      loseAllSeatTiles(2);
      final events = <GameEvent>[];
      reseatLostCapitals(state, Rng(1), events);

      final realm = state.realm(2);
      final map = state.map;
      final seatValue =
          Building.value[map.buildingAt(realm.capitalX, realm.capitalY)];
      for (var i = 0; i < map.terrain.length; i++) {
        if (map.owner[i] != 2) continue;
        expect(
            seatValue, greaterThanOrEqualTo(Building.value[map.building[i]]));
      }
    });
  });

  group('war seat repair', () {
    test('startWar repairs a stale seat on both sides, even for a human', () {
      final map = state.map;
      final realm = state.realm(1); // human attacker with a lost seat
      map.owner[map.index(realm.capitalX, realm.capitalY)] = World.niemand;

      final events = <GameEvent>[];
      startWar(state, 1, 2, Rng(1), events: events);

      expect(map.ownerAt(realm.capitalX, realm.capitalY), 1,
          reason: 'a war must start with two capturable seats');
      expect(events.any((e) => e.type == 'capitalReseated'), isTrue);
    });

    test('startWar clears a pending relocateCapital decision it supersedes',
        () {
      final map = state.map;
      final realm = state.realm(1);
      map.owner[map.index(realm.capitalX, realm.capitalY)] = World.niemand;
      // An eligible Stadt, so the peacetime flow prompts instead of moving.
      outer:
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) == World.niemand && !map.isWaterAt(x, y)) {
            map.owner[map.index(x, y)] = 1;
            map.building[map.index(x, y)] = Building.stadt;
            break outer;
          }
        }
      }
      // The peacetime flow already prompted the human to pick a seat.
      reseatLostCapitals(state, Rng(1), <GameEvent>[]);
      expect(state.pendingDecisions.any((d) => d.type == 'relocateCapital'),
          isTrue);

      startWar(state, 2, 1, Rng(1), events: <GameEvent>[]);

      expect(map.ownerAt(realm.capitalX, realm.capitalY), 1);
      expect(state.pendingDecisions.any((d) => d.type == 'relocateCapital'),
          isFalse,
          reason: 'the forced re-seat resolved the prompt');
    });

    // (The old "endWarRound repairs a stale mid-war seat" test is gone with
    // the per-round repair itself: startWar establishes the seat invariant
    // and no mid-war action can strip a seat tile — transfers only happen
    // at settlement, plunder never touches Stadt/Burg/Palast ownership.)

    test('the settlement re-seats a loser whose capital was annexed', () {
      final war = startWar(state, 1, 2, Rng(1));
      war.phase = WarPhase.settlement;
      war.winnerSlot = 1;
      war.remainingClaim = 0;
      final loser = state.realm(2);
      final events = <GameEvent>[];
      transferTile(state, loser.capitalX, loser.capitalY, 1, events);

      finishSettlement(state, Rng(1), events);

      expect(state.map.ownerAt(loser.capitalX, loser.capitalY), 2,
          reason: 'an AI loser re-seats immediately, not at the year start');
      expect(events.any((e) => e.type == 'capitalReseated'), isTrue);
    });

    test('a human loser is prompted right at the settlement', () {
      final war = startWar(state, 2, 1, Rng(1));
      war.phase = WarPhase.settlement;
      war.winnerSlot = 2;
      war.remainingClaim = 0;
      final loser = state.realm(1); // human
      final map = state.map;
      // Keep an eligible Stadt so there is a real choice to prompt for.
      outer:
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) == World.niemand && !map.isWaterAt(x, y)) {
            map.owner[map.index(x, y)] = 1;
            map.building[map.index(x, y)] = Building.stadt;
            break outer;
          }
        }
      }
      final events = <GameEvent>[];
      transferTile(state, loser.capitalX, loser.capitalY, 2, events);

      finishSettlement(state, Rng(1), events);

      expect(
          state.pendingDecisions
              .any((d) => d.type == 'relocateCapital' && d.decidingSlot == 1),
          isTrue,
          reason: 'the human picks the new seat, immediately after the war');
    });
  });
}
