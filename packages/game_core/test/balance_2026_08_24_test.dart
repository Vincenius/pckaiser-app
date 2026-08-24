import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Balance round 2026-08-24 (user request): Beliebtheit as the
/// counter-weight to realm size. Two changes, pinned here:
///  - the §6.3 Züge roll rides on popularity, not on the (size-driven)
///    title ladder;
///  - a realm's mood multiplies its units' combat strength — bonus only,
///    and bigger for the side defending the tile it stands on.
/// The long-run effect is measured with `tool/balance_sim.dart`; these
/// tests pin the mechanics the measurement rests on.
void main() {
  group('Züge follow the mood, not the realm', () {
    test('a hated Kaiser rolls the floor, a beloved Ritter rolls high', () {
      // Same random draws, opposite moods: the roll no longer knows the
      // title at all, so only the popularity term can separate them.
      for (var seed = 0; seed < 50; seed++) {
        final hated = rollMovementPoints(0, Rng(seed));
        final loved = rollMovementPoints(100, Rng(seed));
        expect(hated, greaterThanOrEqualTo(movementPointsMinimum),
            reason: 'never frozen out of playing (seed $seed)');
        expect(loved - hated,
            100 ~/ movementPopularityDivisor - movementPointsMinimum,
            reason: 'the whole spread is the popularity term (seed $seed)');
      }
    });

    test('the turn pipeline rolls the realm\'s mood', () {
      var state = startGame(
              newGame(GameSetup(
                humans: const [],
                reformationYear: 1020,
                ottomanYear: 1040,
                seed: 5,
              )),
              Rng(5))
          .state;
      // Drive one realm's mood to the floor and one to the ceiling, then
      // let both take a turn: over many turns the loved realm must draw
      // the bigger budget.
      var lovedTotal = 0;
      var hatedTotal = 0;
      for (var i = 0; i < 60; i++) {
        final slot = state.currentPlayer;
        final realm = state.realm(slot);
        if (!realm.isVacant) {
          realm.popularity = slot.isEven ? 100 : 10;
        }
        state = completeTurn(state, Rng(state.rngSeed)).state;
        final next = state.realm(state.currentPlayer);
        if (next.isVacant) continue;
        if (state.currentPlayer.isEven) {
          lovedTotal += next.movementPoints;
        } else {
          hatedTotal += next.movementPoints;
        }
      }
      expect(lovedTotal, greaterThan(hatedTotal));
    });
  });

  group('combat morale', () {
    late GameState state;

    setUp(() {
      state = startGame(
              newGame(GameSetup(
                humans: const [],
                reformationYear: 1020,
                ottomanYear: 1040,
                seed: 2026,
              )),
              Rng(11))
          .state;
    });

    test('no bonus at or below the neutral mood of 50 — never a malus', () {
      for (final mood in [0, 20, 49, 50]) {
        state.realm(1).popularity = mood;
        expect(moraleFactor(state, 1, defending: false), 1.0,
            reason: 'a slump must not weaken the army that has to save the '
                'realm (mood $mood)');
        expect(moraleFactor(state, 1, defending: true), 1.0,
            reason: 'mood $mood');
      }
    });

    test('defending is worth more than attacking, and both scale', () {
      state.realm(1).popularity = 100;
      final attack = moraleFactor(state, 1, defending: false);
      final defence = moraleFactor(state, 1, defending: true);
      expect(attack, closeTo(1 + combatAttackPopularityBonus, 1e-9));
      expect(defence, closeTo(1 + combatDefencePopularityBonus, 1e-9));
      expect(defence, greaterThan(attack));

      state.realm(1).popularity = 75; // halfway up from the pivot
      expect(moraleFactor(state, 1, defending: true),
          closeTo(1 + combatDefencePopularityBonus / 2, 1e-9));
    });

    test('a beloved defender bleeds less against the same attacker', () {
      // Identical units on identical open ground and the same dice — only
      // the defender's mood differs.
      int lossesWithMood(int mood, int seed) {
        final s = startGame(
                newGame(GameSetup(
                  humans: const [],
                  reformationYear: 1020,
                  ottomanYear: 1040,
                  seed: 2026,
                )),
                Rng(11))
            .state;
        int x = 0, y = 0;
        outer:
        for (var yy = 0; yy < s.map.height; yy++) {
          for (var xx = 0; xx < s.map.width; xx++) {
            if (!s.map.isWaterAt(xx, yy) &&
                s.map.buildingAt(xx, yy) == Building.none) {
              x = xx;
              y = yy;
              break outer;
            }
          }
        }
        Troop unit(String name) => Troop(
              name: name,
              men: 500,
              troopClass: TroopClass.infanterie,
              quality: TroopQuality.regular,
              garrisonCounted: false,
              x: x,
              y: y,
            );
        s.realm(1).popularity = 50; // attacker: neutral in both runs
        s.realm(2).popularity = mood;
        final a = unit('Angreifer');
        final b = unit('Verteidiger');
        s.realm(1).troops
          ..clear()
          ..add(a);
        s.realm(2).troops
          ..clear()
          ..add(b);
        final events = resolveCombat(s, 1, a, 2, b, Rng(seed));
        return events.single.payload['defenderLosses'] as int;
      }

      var better = 0;
      for (var seed = 0; seed < 40; seed++) {
        if (lossesWithMood(100, seed) < lossesWithMood(50, seed)) better++;
      }
      expect(better, 40,
          reason: 'the loved realm must lose fewer men in every single '
              'clash — morale is deterministic, not a second dice roll');
    });
  });
}
