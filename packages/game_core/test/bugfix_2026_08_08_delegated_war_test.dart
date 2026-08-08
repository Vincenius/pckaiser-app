import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// User report 2026-08-08: "die KI hat den Krieg für mich geführt und
/// gewonnen — trotzdem gab es keine Gebietsänderung."
///
/// Cause: `Troop.stance` defaults to [TroopStance.holdPosition], and the
/// stance is what governs a side fought by the autopilot. An ATTACKER who
/// handed the war to the computer without touching a single unit therefore
/// left its whole army standing at home for all 20 rounds — no battle, no
/// ground held, a guaranteed `warDraw` at winter (or, once the defender
/// blundered out, a points win paid in cash because nothing was occupied).
///
/// Fix: [startWar] issues starting ORDERS — the aggressor's units advance,
/// the defender's hold. Both sides may still re-order every unit during
/// the preparation window.
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
    for (final slot in [1, 2]) {
      final realm = state.realm(slot);
      realm.treasury = 10000;
      realm.towns.first.troopCapacity = 400;
      realm.troopCapacity = 400;
      realm.troops.add(Troop(
        name: 'Heer$slot',
        men: slot == 1 ? 300 : 40, // the attacker is clearly superior
        troopClass: TroopClass.infanterie,
        quality: TroopQuality.regular,
        garrisonCounted: false,
        x: realm.capitalX,
        y: realm.capitalY,
      ));
    }
    return state;
  }

  test('the aggressor\'s units start under ATTACK orders, the defender holds',
      () {
    final state = build(42);
    startWar(state, 1, 2, Rng(42), events: <GameEvent>[]);
    expect(state.realm(1).troops.map((t) => t.stance),
        everyElement(TroopStance.attack));
    expect(state.realm(2).troops.map((t) => t.stance),
        everyElement(TroopStance.holdPosition));
  });

  test('a fully delegated war actually gets fought, not slept through', () {
    // Both humans hand the war to the computer and touch nothing else —
    // the case the user hit. Before the fix EVERY seed ended 0 battles /
    // 0 tiles moved; the attacker must now at least reach and engage.
    var decisive = 0;
    for (final seed in [7, 42, 1234]) {
      final state = build(seed);
      final rng = Rng(seed);
      final events = <GameEvent>[];
      final loserTilesBefore = state.map.owner.where((o) => o == 2).length;
      final war = startWar(state, 1, 2, rng, events: events);
      war.autoSlots.addAll([1, 2]);
      resolveWarPreparation(state, rng, events, force: true);

      expect(state.activeWar, isNull,
          reason: 'a war nobody plays live resolves in one pass');
      final loserTilesAfter = state.map.owner.where((o) => o == 2).length;
      if (events.any((e) => e.type == 'warWon') &&
          loserTilesAfter < loserTilesBefore) {
        decisive++;
      }
    }
    expect(decisive, greaterThan(0),
        reason: 'a delegated aggressor with a 7:1 army must be able to take '
            'ground — a guaranteed white peace is what the report was about');
  });

  test('an unattended war never stays open (warIsUnattended guard)', () {
    final state = build(42);
    final rng = Rng(42);
    final events = <GameEvent>[];
    final war = startWar(state, 1, 2, rng, events: events);
    war.autoSlots.addAll([1, 2]);
    expect(warIsUnattended(state), isTrue);
    fastForwardUnattendedWar(state, rng, events);
    expect(state.activeWar, isNull);
    expect(state.pendingDecisions.where((d) => d.type == 'warPlan'), isEmpty,
        reason: 'the delegated sides own no open war plan any more');
  });

  test('a live side still stops the fast-forward', () {
    final state = build(42);
    final rng = Rng(42);
    final events = <GameEvent>[];
    final war = startWar(state, 1, 2, rng, events: events);
    war.autoSlots.add(1); // only the attacker delegates
    expect(warIsUnattended(state), isFalse);
    fastForwardUnattendedWar(state, rng, events);
    expect(state.activeWar, isNotNull,
        reason: 'the live defender drives their own rounds');
  });
}
