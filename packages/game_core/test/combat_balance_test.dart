import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// 2026-07-08 combat balancing: casualties scale with the winner's
/// superiority instead of being flat shares of each side's own size.
/// Before, a 10-man unit stripped 10–25% off ANY army it touched (chaff
/// spam multiplied damage) and the [0.5, 1.5) fortune band let a 3× weaker
/// side win on luck — small units regularly beat and out-damaged big ones.
void main() {
  late GameState state;
  late int openX, openY;

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
    // A bonus-free battlefield: open ground, no Berg, no building.
    outer:
    for (var y = 0; y < state.map.height; y++) {
      for (var x = 0; x < state.map.width; x++) {
        if (!state.map.isWaterAt(x, y) &&
            state.map.terrainAt(x, y) != Terrain.berg &&
            state.map.buildingAt(x, y) == Building.none) {
          openX = x;
          openY = y;
          break outer;
        }
      }
    }
  });

  Troop unit(String name, int men, {int quality = TroopQuality.regular}) =>
      Troop(
        name: name,
        men: men,
        troopClass: TroopClass.infanterie,
        quality: quality,
        garrisonCounted: false,
        x: openX,
        y: openY,
      );

  /// One clash between fresh units on open ground; returns the battle
  /// payload (losses read from the event, the troops are discarded).
  Map<String, dynamic> clash(Troop a, Troop b, int seed) {
    state.realm(1).troops
      ..clear()
      ..add(a);
    state.realm(2).troops
      ..clear()
      ..add(b);
    final events = resolveCombat(state, 1, a, 2, b, Rng(seed));
    return events.single.payload;
  }

  test('a huge unit crushes chaff near-bloodlessly and wipes it', () {
    for (var seed = 0; seed < 50; seed++) {
      final payload = clash(unit('Heer', 1000), unit('Chaff', 10), seed);
      expect(payload['defenderDestroyed'], isTrue,
          reason: 'a 100× outmatched unit is routed outright (seed $seed)');
      expect(payload['attackerLosses'], lessThanOrEqualTo(5),
          reason: 'chaff must not strip 10–25% off a giant (seed $seed)');
    }
  });

  test('a ≥ 5/3× stronger equal-quality force wins every clash', () {
    for (var seed = 0; seed < 50; seed++) {
      final payload = clash(unit('Gross', 200), unit('Klein', 100), seed);
      expect(payload['attackerDestroyed'], isFalse,
          reason: 'the bigger force can no longer lose on luck (seed $seed)');
      expect(payload['attackerLosses'],
          lessThan(payload['defenderLosses'] as int),
          reason: 'the outnumbered loser bleeds more (seed $seed)');
    }
  });

  test('an upset winner bloodies a bigger army, it does not shred it', () {
    // 100 vs 150 regulars: the smaller side CAN still win inside the
    // [0.75, 1.25) fortune band — but its kills stay within its own reach
    // (≈ its effective headcount), never the old 35–65% of the giant.
    for (var seed = 0; seed < 200; seed++) {
      final payload = clash(unit('Klein', 100), unit('Gross', 150), seed);
      if (payload['defenderDestroyed'] == true ||
          (payload['defenderLosses'] as int) >
              (payload['attackerLosses'] as int)) {
        // The 100-man side won this clash.
        expect(payload['defenderLosses'], lessThanOrEqualTo(125),
            reason: '100 winners cannot cut down more men than their own '
                'effective strength reaches (seed $seed)');
      }
    }
  });

  test('quality still beats mass: elite Janitscharen rout regulars', () {
    for (var seed = 0; seed < 50; seed++) {
      final payload = clash(
          unit('Janitscharen', 10, quality: TroopQuality.janitscharen),
          unit('Rekruten', 100),
          seed);
      expect(payload['defenderLosses'],
          greaterThan(payload['attackerLosses'] as int),
          reason: '10 Janitscharen (5× the power) maul 100 regulars '
              '(seed $seed)');
      expect(payload['attackerDestroyed'], isFalse);
    }
  });

  test('equal forces on open ground still bleed both sides', () {
    for (var seed = 0; seed < 50; seed++) {
      final payload = clash(unit('A', 50), unit('B', 50), seed);
      final attacker = payload['attackerLosses'] as int;
      final defender = payload['defenderLosses'] as int;
      expect(attacker + defender, greaterThanOrEqualTo(10),
          reason: 'no 0-loss skirmishes between equals (seed $seed)');
      expect(attacker, greaterThanOrEqualTo(1), reason: 'seed $seed');
      expect(defender, greaterThanOrEqualTo(1), reason: 'seed $seed');
    }
  });
}
