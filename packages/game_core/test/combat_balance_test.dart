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

  // 2026-07-14 rebalance: superiority = √(men ratio) × per-man-power ratio.
  // Mass is dampened in the casualty math; the drilled/class edge counts in
  // full, and each class has a tactical role (walls / charge / siege).
  group('2026-07-14: Ausbildung und Gattung', () {
    /// A second bonus-free tile (≠ the shared one) with a Burg placed on
    /// it — the fortified defender's position for the wall/siege tests.
    (int, int) placeBurg() {
      for (var y = 0; y < state.map.height; y++) {
        for (var x = 0; x < state.map.width; x++) {
          if ((x != openX || y != openY) &&
              !state.map.isWaterAt(x, y) &&
              state.map.terrainAt(x, y) != Terrain.berg &&
              state.map.buildingAt(x, y) == Building.none) {
            state.map.building[state.map.index(x, y)] = Building.burg;
            return (x, y);
          }
        }
      }
      throw StateError('no second open tile');
    }

    Troop typed(String name, int men, int troopClass,
            {int quality = TroopQuality.regular, int? x, int? y}) =>
        Troop(
          name: name,
          men: men,
          troopClass: troopClass,
          quality: quality,
          garrisonCounted: false,
          x: x ?? openX,
          y: y ?? openY,
        );

    test('a drilled unit routs an untrained mob of 3× its size', () {
      // 100 men quality 5 (power 50) vs 300 regulars (power 30): the 5/3
      // edge wins every clash, and the FULL quality ratio in the casualty
      // superiority makes it a rout — while the veterans stay coherent.
      for (var seed = 0; seed < 100; seed++) {
        final payload = clash(unit('Veteranen', 100, quality: 5),
            unit('Aufgebot', 300), seed);
        expect(payload['attackerDestroyed'], isFalse, reason: 'seed $seed');
        expect(payload['defenderLosses'], greaterThanOrEqualTo(200),
            reason: 'quality superiority routs the mob (seed $seed)');
        expect(payload['attackerLosses'], lessThanOrEqualTo(20),
            reason: 'the drilled unit keeps its order (seed $seed)');
      }
    });

    test('2× the men still wins — but no longer annihilates', () {
      // √2 ≈ 1.41 < 1.5: the loser share stays at its 35–65% base, so a
      // merely-bigger equal-quality force bloodies the loser instead of
      // erasing it (before: 47–87%, annihilation from ~4.3× men).
      for (var seed = 0; seed < 100; seed++) {
        final payload = clash(unit('Gross', 200), unit('Klein', 100), seed);
        expect(payload['defenderDestroyed'], isFalse,
            reason: 'no annihilation at 2× men (seed $seed)');
        expect(payload['defenderLosses'], lessThanOrEqualTo(66),
            reason: 'base 35–65% share only (seed $seed)');
      }
    });

    test('overwhelming mass (20×) still wipes a unit outright', () {
      for (var seed = 0; seed < 50; seed++) {
        final payload = clash(unit('Heer', 1000), unit('Häuflein', 50), seed);
        expect(payload['defenderDestroyed'], isTrue, reason: 'seed $seed');
      }
    });

    test('Artillerie bricht Mauern, gleichstarke Infanterie nicht', () {
      final (bx, by) = placeBurg();
      var infantryAttackerEverLost = false;
      for (var seed = 0; seed < 100; seed++) {
        // 60 Artillerie (power 42) vs 100 Infanterie in the Burg: the
        // defender's def 4 (3 + wall bonus) counts only half against the
        // siege guns — the Burg falls every time.
        final artPayload = clash(
            typed('Belagerer', 60, TroopClass.artillerie),
            typed('Besatzung', 100, TroopClass.infanterie, x: bx, y: by),
            seed);
        expect(artPayload['defenderDestroyed'], isTrue,
            reason: 'siege guns negate half the walls (seed $seed)');

        // The same total power as plain infantry (420 men, power 42) faces
        // the full def 4 — it can be repelled.
        final infPayload = clash(
            typed('Sturmhaufen', 420, TroopClass.infanterie),
            typed('Besatzung', 100, TroopClass.infanterie, x: bx, y: by),
            seed);
        if (infPayload['defenderDestroyed'] != true) {
          infantryAttackerEverLost = true;
        }
      }
      expect(infantryAttackerEverLost, isTrue,
          reason: 'equal-power infantry must not crack the Burg as '
              'reliably as artillery');
    });

    test('Kavallerie-Charge entscheidet die Feldschlacht', () {
      // 100 Kavallerie (power 40, ×1.2 charge = 48) vs 288 Infanterie
      // (power 28): with the charge the cavalry clears the 5/3 bar and
      // wins EVERY open-field clash — without it (40 vs 28) it would
      // lose on bad fortune.
      for (var seed = 0; seed < 100; seed++) {
        final payload = clash(
            typed('Reiterei', 100, TroopClass.kavallerie),
            typed('Fussvolk', 288, TroopClass.infanterie),
            seed);
        expect(payload['attackerDestroyed'], isFalse, reason: 'seed $seed');
        expect(payload['defenderLosses'],
            greaterThan(payload['attackerLosses'] as int),
            reason: 'the charge carries the field (seed $seed)');
      }
    });

    test('Infanterie hält Mauern besser als gleichstarke Kavallerie', () {
      final (bx, by) = placeBurg();
      // A 5-man Janitscharen storm (power 25): its huge per-man edge means
      // any WIN routs the garrison outright, so `defenderDestroyed`
      // cleanly marks who held the walls. Against the infantry garrison
      // (raw 10, wall bonus → eff 30) it needs far better fortune than
      // against equal-power cavalry (raw 10, no wall bonus → eff 25).
      var infDefFell = 0;
      var kavDefFell = 0;
      for (var seed = 0; seed < 100; seed++) {
        final infPayload = clash(
            typed('Sturm', 5, TroopClass.infanterie,
                quality: TroopQuality.janitscharen),
            typed('Stadtwache', 100, TroopClass.infanterie, x: bx, y: by),
            seed);
        if (infPayload['defenderDestroyed'] == true) infDefFell++;

        final kavPayload = clash(
            typed('Sturm', 5, TroopClass.infanterie,
                quality: TroopQuality.janitscharen),
            typed('Reiterwache', 25, TroopClass.kavallerie, x: bx, y: by),
            seed);
        if (kavPayload['defenderDestroyed'] == true) kavDefFell++;
      }
      expect(kavDefFell, greaterThan(infDefFell),
          reason: 'the +1 wall bonus must make the infantry garrison '
              'hold noticeably more storms ($infDefFell vs $kavDefFell)');
    });
  });
}
