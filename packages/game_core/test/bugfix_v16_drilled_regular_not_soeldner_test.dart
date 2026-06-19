import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// v5: a regular drilled to quality 3 must NOT be mistaken for a Söldner
/// (the discriminator is `garrisonCounted`, not `quality == 3`).
void main() {
  late GameState state;

  GameState recruitRegular() {
    final s = applyAction(
      state,
      RecruitTroops(
          slot: 1, men: 10, troopClass: TroopClass.infanterie, name: 'A'),
      Rng(state.rngSeed),
    ).state;
    return s;
  }

  int idxOfRegular(GameState s) =>
      s.realm(1).troops.indexWhere((t) => t.garrisonCounted);

  setUp(() {
    state = newGame(GameSetup(
      humans: [
        HumanPlayerSetup(
            founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'Berlin'),
      ],
      reformationYear: 1020,
      ottomanYear: 1040,
      seed: 11,
    ));
    state.realm(1).treasury = 1000000;
    state.realm(1).movementPoints = 5;
  });

  test('drilling a regular to quality 3 keeps it garrison-counted', () {
    var s = recruitRegular();
    final idx = idxOfRegular(s);
    for (var i = 0; i < 2; i++) {
      s = applyAction(s, DrillTroop(slot: 1, unitIndex: idx), Rng(s.rngSeed))
          .state;
    }
    final troop = s.realm(1).troops[idx];
    expect(troop.quality, TroopQuality.soeldner); // == 3, the collision point
    expect(troop.garrisonCounted, isTrue, reason: 'still a regular');
  });

  test('reinforcing a quality-3 regular costs 5 T/man (not the Söldner 50)',
      () {
    var s = recruitRegular();
    final idx = idxOfRegular(s);
    for (var i = 0; i < 2; i++) {
      s = applyAction(s, DrillTroop(slot: 1, unitIndex: idx), Rng(s.rngSeed))
          .state;
    }
    final before = s.realm(1).treasury;
    s = applyAction(
            s, ReinforceTroop(slot: 1, unitIndex: idx, men: 4), Rng(s.rngSeed))
        .state;
    final spent = before - s.realm(1).treasury;
    expect(spent, 5 * 4, reason: 'regular price, not 50/man');
  });

  test('reinforcing a quality-3 regular still respects garrison capacity', () {
    var s = recruitRegular();
    final idx = idxOfRegular(s);
    for (var i = 0; i < 2; i++) {
      s = applyAction(s, DrillTroop(slot: 1, unitIndex: idx), Rng(s.rngSeed))
          .state;
    }
    // Over-fill the quarters: a regular must hit the capacity guard.
    final overshoot = s.realm(1).troopCapacity + 1;
    expect(
      () => applyAction(s,
          ReinforceTroop(slot: 1, unitIndex: idx, men: overshoot), Rng(s.rngSeed)),
      throwsA(isA<ActionException>()),
    );
  });

  test('wages do not double-count a quality-3 regular', () {
    var s = recruitRegular();
    final idx = idxOfRegular(s);
    for (var i = 0; i < 2; i++) {
      s = applyAction(s, DrillTroop(slot: 1, unitIndex: idx), Rng(s.rngSeed))
          .state;
    }
    final realm = s.realm(1);
    // No actual Söldner present, so wages must be exactly armySize × 0.5.
    // The bug counted the quality-3 regular twice (armySize + soeldnerMen).
    final report = runEconomy(s, realm, Rng(s.rngSeed));
    expect(report.wages, (realm.armySize * 0.5).round(),
        reason: 'no Söldner double-count at quality 3');
  });
}
