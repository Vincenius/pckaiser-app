import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// User request 2026-08-24: a side handed to the no-show autopilot
/// (`war.autoSlots`, `[FIX 2026-08-08]`) after missing the war's start could
/// never take manual command back — `WarPrepPlan` explicitly rejects any
/// revision once `WarPhase.rounds` has begun. `ResumeWarCommand` is the one
/// new, narrow way back: out of autopilot, mid-war, any time — never the
/// other direction.
void main() {
  GameState build(int seed) {
    final state = startGame(
      newGame(GameSetup(
        humans: [
          HumanPlayerSetup(
              founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'A'),
          HumanPlayerSetup(
              founderName: 'Berta', gender: 1, countrySlot: 2, dorfName: 'B'),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: seed,
      )),
      Rng(seed),
    ).state;
    state.year = 1010;
    return state;
  }

  test('takes a delegated slot out of the no-show autopilot', () {
    final state = build(42);
    final war = startWar(state, 1, 2, Rng(42), events: <GameEvent>[]);
    // Both sides are human, so `startWar` opens a PREPARATION window
    // (§11.1's user-designed mechanic) — the no-show autopilot only ever
    // hands a slot to `autoSlots` once the rounds are actually running.
    war.phase = WarPhase.rounds;
    war.autoSlots.add(1);
    expect(warSideIsHuman(state, war, 1), isFalse);

    applyResumeWarCommand(state, state.realm(1), ResumeWarCommand(slot: 1));

    expect(war.autoSlots.contains(1), isFalse);
    expect(warSideIsHuman(state, war, 1), isTrue);
  });

  test('refuses a slot that is not delegated', () {
    final state = build(42);
    final war = startWar(state, 1, 2, Rng(42), events: <GameEvent>[]);
    war.phase = WarPhase.rounds;
    expect(war.autoSlots.contains(1), isFalse);

    expect(
      () => applyResumeWarCommand(
          state, state.realm(1), ResumeWarCommand(slot: 1)),
      throwsA(isA<ActionException>()),
    );
  });

  test('refuses during the preparation window (wrong phase)', () {
    final state = build(42);
    final war = startWar(state, 1, 2, Rng(42), events: <GameEvent>[]);
    expect(war.phase, WarPhase.preparation);

    expect(
      () => applyResumeWarCommand(
          state, state.realm(1), ResumeWarCommand(slot: 1)),
      throwsA(isA<ActionException>()),
    );
  });

  test('refuses outside the war rounds (no active war)', () {
    final state = build(42);

    expect(
      () => applyResumeWarCommand(
          state, state.realm(1), ResumeWarCommand(slot: 1)),
      throwsA(isA<ActionException>()),
    );
  });
}
