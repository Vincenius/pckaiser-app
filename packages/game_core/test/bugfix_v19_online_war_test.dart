import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Online-war fixes (19th bugfix iteration — the file counter is just a
/// label; rules are not versioned, every game plays the latest):
///   * war never drives a treasury negative — a loser pays at most what it
///     owns (settlement claim cash and tile-conquest treasury shares are
///     both capped), so a beaten player can't end up deep in the red and
///     soft-locked out of paying for anything afterwards;
///   * an election bribe prompt is answerable with zero even when the
///     finalist's treasury is negative (the post-war reparations case),
///     instead of rejecting the empty submission and trapping the player;
///   * a war side with no troops left has its round auto-skipped so a
///     defenceless seat never stalls the war (covered in war_test.dart).
void main() {
  GameState twoHumans() => startGame(
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
        Rng(7),
      ).state;

  group('war never drives a treasury negative', () {
    test('a settlement claim larger than the loser purse pays only the purse',
        () {
      final state = twoHumans();
      final war = startWar(state, 1, 2, Rng(state.rngSeed));
      // Slot 1 wins with an open claim far above slot 2's small treasury.
      war.phase = WarPhase.settlement;
      war.winnerSlot = 1;
      war.remainingClaim = 50000;
      state.realm(2).treasury = 800;
      state.realm(1).treasury = 0;

      final events = <GameEvent>[];
      finishSettlement(state, events);

      expect(state.realm(2).treasury, 0,
          reason: 'the loser pays everything it has, never more');
      expect(state.realm(1).treasury, 800,
          reason: 'the winner receives only what the loser could pay');
      final paid =
          events.firstWhere((e) => e.type == 'claimPaidOut').payload['amount'];
      expect(paid, 800, reason: 'the event reports the actual amount paid');
    });

    test('an already-bankrupt loser pays nothing (stays at its debt)', () {
      final state = twoHumans();
      final war = startWar(state, 1, 2, Rng(state.rngSeed));
      war.phase = WarPhase.settlement;
      war.winnerSlot = 1;
      war.remainingClaim = 9000;
      state.realm(2).treasury = -500; // already in the red
      state.realm(1).treasury = 100;

      finishSettlement(state, <GameEvent>[]);

      expect(state.realm(2).treasury, -500, reason: 'no money to take');
      expect(state.realm(1).treasury, 100, reason: 'winner gains nothing');
    });

    test('a conquered high-value capital tile cannot overdraw the treasury',
        () {
      final state = twoHumans();
      final loser = state.realm(2);
      // Make the capital the only treasury-bearing tile, so the doubled
      // capital share (factor 2) would compute more than the whole purse.
      loser.treasury = 100;
      final events = <GameEvent>[];
      transferTile(state, loser.capitalX, loser.capitalY, 1, events);

      expect(loser.treasury, greaterThanOrEqualTo(0),
          reason: 'a capital capture never leaves the loser in debt');
    });
  });

  group('election bribe with an empty / negative treasury', () {
    test('a broke finalist can confirm with no gift and the election proceeds',
        () {
      // Same setup as the working offices_test bribe case (single human,
      // König title → guaranteed finalist), then a negative treasury.
      final state = startGame(
              newGame(GameSetup(
                humans: [
                  HumanPlayerSetup(
                      founderName: 'Mensch',
                      gender: 0,
                      countrySlot: 1,
                      dorfName: 'Stadt'),
                ],
                reformationYear: 1020,
                ottomanYear: 1040,
                seed: 2026,
              )),
              Rng(1))
          .state;
      state.year = 1010;
      state.realm(1).titleClass = 8; // König → guaranteed finalist
      refillKurfuersten(state, Rng(3), []);
      final events = <GameEvent>[];
      maybeStartElection(state, Office.kaiser, Rng(3), events);
      advanceElection(state, Rng(3), events);

      final bribe =
          state.pendingDecisions.singleWhere((d) => d.type == 'electionBribe');
      // Post-war reparations left the finalist in the red.
      state.realm(1).treasury = -1200;

      // The empty "no bribe" submission must be accepted, not rejected for
      // "nicht genügend Taler", and the election must advance past it.
      final result = applyAction(
        state,
        ResolveDecision(
            slot: 1, decisionId: bribe.id, choice: const {'gifts': <int>[]}),
        Rng(state.rngSeed),
      );
      expect(
        result.state.pendingDecisions.any((d) => d.id == bribe.id),
        isFalse,
        reason: 'the bribe decision is consumed, not re-prompted forever',
      );
      expect(result.state.realm(1).treasury, -1200,
          reason: 'a zero bribe spends nothing');
    });
  });
}
