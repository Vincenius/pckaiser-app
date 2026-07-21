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
      // 2026-07-21: the last-stand scaling doubles the chaff's reach (its
      // share runs up to 50% of its strength) — still bounded by its own
      // tiny strength, never a percentage of the giant.
      expect(payload['attackerLosses'], lessThanOrEqualTo(7),
          reason: 'chaff must not strip percentages off a giant (seed $seed)');
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

  // 2026-07-19 rebalance (user-designed): the DISPLAYED strength (men ×
  // per-man power) is the one base factor. On top: Burg +15% / Palast +25%
  // fortification, Artillerie besieges (halves the enemy's fortification
  // bonus, ×1.1 vs a fortified enemy), and Schere-Stein-Papier ×1.15
  // (Inf > Kav > Art > Inf).
  group('2026-07-19: Stärke, Befestigung und Schere-Stein-Papier', () {
    /// A fresh bonus-free tile (≠ the shared one and ≠ already used ones)
    /// with [building] placed on it — the fortified defender's position.
    final placed = <(int, int)>[];
    (int, int) place(int building) {
      for (var y = 0; y < state.map.height; y++) {
        for (var x = 0; x < state.map.width; x++) {
          if ((x != openX || y != openY) &&
              !placed.contains((x, y)) &&
              !state.map.isWaterAt(x, y) &&
              state.map.buildingAt(x, y) == Building.none) {
            state.map.building[state.map.index(x, y)] = building;
            placed.add((x, y));
            return (x, y);
          }
        }
      }
      throw StateError('no free open tile');
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

    test('Stärke entscheidet: die ausgebildete Einheit schlägt den 3×-Mob',
        () {
      // 100 men quality 5 (strength 50) vs 300 regulars (strength 30): the
      // 5/3 strength edge wins every clash inside the fortune band, and
      // the veterans' losses stay small (10–25% of the mob's reach).
      for (var seed = 0; seed < 100; seed++) {
        final payload = clash(unit('Veteranen', 100, quality: 5),
            unit('Aufgebot', 300), seed);
        expect(payload['attackerDestroyed'], isFalse, reason: 'seed $seed');
        expect(payload['defenderLosses'],
            greaterThan(payload['attackerLosses'] as int),
            reason: 'strength superiority carries the clash (seed $seed)');
        expect(payload['attackerLosses'], lessThanOrEqualTo(20),
            reason: 'the drilled unit keeps its order (seed $seed)');
      }
    });

    test('2× Stärke gewinnt jede Schlacht und blutet den Verlierer aus', () {
      for (var seed = 0; seed < 100; seed++) {
        final payload = clash(unit('Gross', 200), unit('Klein', 100), seed);
        expect(payload['attackerDestroyed'], isFalse, reason: 'seed $seed');
        expect(payload['defenderLosses'],
            greaterThan(payload['attackerLosses'] as int),
            reason: 'the weaker force bleeds more (seed $seed)');
      }
    });

    test('overwhelming strength (20×) wipes a unit outright', () {
      for (var seed = 0; seed < 50; seed++) {
        final payload = clash(unit('Heer', 1000), unit('Häuflein', 50), seed);
        expect(payload['defenderDestroyed'], isTrue, reason: 'seed $seed');
      }
    });

    test('Burg (+15%) und Palast (+25%) schützen die Besatzung', () {
      final (bx, by) = place(Building.burg);
      final (px, py) = place(Building.palast);
      var openHeld = 0;
      var burgHeld = 0;
      var palastHeld = 0;
      for (var seed = 0; seed < 200; seed++) {
        // Equal 100 vs 100 infantry — only the defender's tile differs.
        if (clash(unit('Sturm', 100), unit('Feldlager', 100),
                seed)['attackerWon'] !=
            true) {
          openHeld++;
        }
        if (clash(
                unit('Sturm', 100),
                typed('Burgwache', 100, TroopClass.infanterie, x: bx, y: by),
                seed)['attackerWon'] !=
            true) {
          burgHeld++;
        }
        if (clash(
                unit('Sturm', 100),
                typed('Palastwache', 100, TroopClass.infanterie, x: px, y: py),
                seed)['attackerWon'] !=
            true) {
          palastHeld++;
        }
      }
      expect(burgHeld, greaterThan(openHeld),
          reason: 'the Burg bonus must win the garrison clashes it '
              'would lose on open ground ($openHeld vs $burgHeld)');
      expect(palastHeld, greaterThan(burgHeld),
          reason: 'the Palast bonus (+25%) tops the Burg (+15%) '
              '($burgHeld vs $palastHeld)');
    });

    test('Artillerie bricht Burgen besser als gleichstarke Infanterie', () {
      final (bx, by) = place(Building.burg);
      // Both attackers have strength 70; the defender holds the Burg with
      // strength 70 too. Artillerie halves the wall bonus, fires ×1.1 at
      // the fortress and counters the infantry garrison (×1.15) — plain
      // infantry faces the full +15% walls with no bonus of its own.
      var artWins = 0;
      var infWins = 0;
      for (var seed = 0; seed < 200; seed++) {
        if (clash(
                typed('Belagerer', 100, TroopClass.artillerie),
                typed('Besatzung', 700, TroopClass.infanterie, x: bx, y: by),
                seed)['attackerWon'] ==
            true) {
          artWins++;
        }
        if (clash(
                typed('Sturmhaufen', 700, TroopClass.infanterie),
                typed('Besatzung', 700, TroopClass.infanterie, x: bx, y: by),
                seed)['attackerWon'] ==
            true) {
          infWins++;
        }
      }
      expect(artWins, greaterThan(infWins),
          reason: 'siege guns must crack the Burg clearly more often '
              '($artWins vs $infWins)');
      expect(artWins, greaterThan(100),
          reason: 'artillery cracks an equal-strength Burg more often '
              'than not ($artWins/200)');
    });

    test('2026-07-21 letztes Gefecht: der Unterlegene verkauft sich teuer',
        () {
      // 100 men falling to a 500 stack take ~34 along (last-stand scaling,
      // ×√(strength ratio) capped at ×2) — before, only ~17.5. Averaged
      // over many seeds; individual clashes stay within the share band.
      var stackLosses = 0;
      const n = 200;
      for (var seed = 0; seed < n; seed++) {
        final payload = clash(unit('Heer', 500), unit('Trupp', 100), seed);
        expect(payload['attackerWon'], isTrue, reason: 'seed $seed');
        stackLosses += payload['attackerLosses'] as int;
      }
      expect(stackLosses / n, greaterThan(25),
          reason: 'a doomstack must pay real men per cleared unit');
      expect(stackLosses / n, lessThan(45),
          reason: 'the outmatched side must not out-trade its strength');
    });

    test('2026-07-21 Overkill-Deckel: unter 2× Reichweite flieht der Rest',
        () {
      // 167 vs 100 (the 5/3 deterministic win): the loser routs with ≥ 20%
      // of its men unless the winner's reach hits 2× — a full wipe is now
      // the rare high-fortune case, not the default.
      var wipes = 0;
      var routed = 0; // capped at 80 losses — the unit keeps ≥ 20%
      const n = 200;
      for (var seed = 0; seed < n; seed++) {
        final payload = clash(unit('Gross', 167), unit('Klein', 100), seed);
        expect(payload['attackerWon'], isTrue, reason: 'seed $seed');
        if (payload['defenderDestroyed'] == true) {
          wipes++;
        } else if ((payload['defenderLosses'] as int) <= 80) {
          routed++;
        }
        // The remaining case (losses > 80 without a wipe) is the winner's
        // high-fortune ≥ 2× reach, where the cap intentionally lifts.
      }
      expect(wipes, lessThan(n ~/ 4),
          reason: 'full wipes must be the exception ($wipes/$n)');
      expect(routed, greaterThan(n ~/ 2),
          reason: 'most beaten units rout with ≥ 20% of their men '
              '($routed/$n)');
    });

    test('Schere-Stein-Papier: Inf > Kav > Art > Inf (×1.15)', () {
      // Equal-strength open-field matchups; the countering class must win
      // clearly more than half the clashes, but never all of them.
      final matchups = [
        (
          typed('Fussvolk', 140, TroopClass.infanterie), // strength 14
          typed('Reiterei', 35, TroopClass.kavallerie), // strength 14
        ),
        (
          typed('Reiterei', 70, TroopClass.kavallerie), // strength 28
          typed('Kanonen', 40, TroopClass.artillerie), // strength 28
        ),
        (
          typed('Kanonen', 40, TroopClass.artillerie), // strength 28
          typed('Fussvolk', 280, TroopClass.infanterie), // strength 28
        ),
      ];
      for (final (counter, countered) in matchups) {
        var wins = 0;
        for (var seed = 0; seed < 200; seed++) {
          final payload = clash(counter.copy(), countered.copy(), seed);
          if (payload['attackerWon'] == true) wins++;
        }
        expect(wins, greaterThan(110),
            reason: '${counter.name} must beat ${countered.name} in '
                'clearly more than half the clashes ($wins/200)');
        expect(wins, lessThan(190),
            reason: 'the ×1.15 bonus must not make ${counter.name} vs '
                '${countered.name} a foregone conclusion ($wins/200)');
      }
    });
  });
}
