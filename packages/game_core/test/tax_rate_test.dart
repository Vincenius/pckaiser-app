import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Tests for the adjustable tax rate (§7.1 tuning, user request
/// 2026-08-13): the default is the current value (100% = the original
/// formula), higher taxes collect more but cost popularity, lower taxes
/// collect less and buy goodwill — and a war's popularity cost always
/// outweighs the goodwill from low taxes (the goodwill is withheld while
/// at war or war-weary).
void main() {
  late GameState state;

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
  });

  group('SetTaxRate', () {
    test('sets the rate; default is the current (100) value', () {
      expect(state.realm(1).taxRate, taxRateDefault);
      final rng = Rng(1);
      final result = applyAction(state, SetTaxRate(slot: 1, rate: 150), rng);
      expect(result.state.realm(1).taxRate, 150);
      // Input state untouched (purity).
      expect(state.realm(1).taxRate, taxRateDefault);
    });

    test('rejects out-of-range rates; 0 is legal (never below 0)', () {
      final rng = Rng(1);
      expect(
        () => applyAction(state, SetTaxRate(slot: 1, rate: -1), rng),
        throwsA(isA<ActionException>()),
      );
      expect(
        () => applyAction(state, SetTaxRate(slot: 1, rate: taxRateMax + 1),
            rng),
        throwsA(isA<ActionException>()),
      );
      final zero = applyAction(state, SetTaxRate(slot: 1, rate: 0), rng);
      expect(zero.state.realm(1).taxRate, 0);
    });

    test('taxRate survives a JSON round-trip', () {
      final started = startGame(state, Rng(7)).state;
      started.realm(1).taxRate = 175;
      final back = GameState.fromJson(
          jsonDecode(jsonEncode(started.toJson())) as Map<String, dynamic>);
      expect(back.realm(1).taxRate, 175);
    });
  });

  group('tax income (§7.1)', () {
    test('scales with the rate; 100 is the original formula', () {
      final started = startGame(state, Rng(7)).state;
      final realm = started.realm(1);
      realm.population = 1000;

      int tax(int rate) {
        realm.taxRate = rate;
        // Same seed each probe → the base roll [pop, 2×pop) is identical,
        // so the comparison isolates the rate scaling.
        return runEconomy(started, realm, Rng(42)).tax;
      }

      final normal = tax(taxRateDefault);
      expect(tax(taxRateMax), greaterThan(normal));
      expect(tax(taxRateDefault ~/ 2), lessThan(normal));
      expect(tax(0), 0);
    });
  });

  group('tax popularity reaction', () {
    test('high taxes lower popularity, low taxes raise it', () {
      final started = startGame(state, Rng(7)).state;
      final realm = started.realm(1);

      int delta(int rate, {bool atWar = false}) {
        realm.taxRate = rate;
        realm.popularity = 50;
        realm.recentWars = 0;
        started.activeWar = atWar
            ? ActiveWar(attackerSlot: realm.slot, defenderSlot: 2)
            : null;
        return runEconomy(started, realm, Rng(1)).taxPopularity;
      }

      expect(delta(taxRateDefault), 0);
      expect(delta(taxRateMax), lessThan(0));
      expect(delta(0), greaterThan(0));
    });

    test('resentment steps tighter than goodwill (user request)', () {
      final started = startGame(state, Rng(7)).state;
      final realm = started.realm(1);

      int delta(int rate) {
        realm.taxRate = rate;
        realm.popularity = 50;
        realm.recentWars = 0;
        started.activeWar = null;
        return runEconomy(started, realm, Rng(1)).taxPopularity;
      }

      // Goodwill: +1 per [taxPopularityStep] below 100 (unchanged).
      expect(delta(0), 4);
      // Resentment: −1 per [taxPopularityHighStep] above 100 — tighter,
      // so high taxes grind popularity down a little faster.
      expect(delta(180), -4);
      expect(delta(taxRateMax), -5);
    });

    test('a war withholds the low-tax goodwill but not the resentment', () {
      final started = startGame(state, Rng(7)).state;
      final realm = started.realm(1);

      int delta(int rate, {required bool atWar}) {
        realm.taxRate = rate;
        realm.popularity = 50;
        realm.recentWars = 0;
        started.activeWar = atWar
            ? ActiveWar(attackerSlot: realm.slot, defenderSlot: 2)
            : null;
        return runEconomy(started, realm, Rng(1)).taxPopularity;
      }

      // Low taxes: no goodwill while actually fighting — the war's
      // popularity cost cannot be bought back.
      expect(delta(0, atWar: true), 0);
      // High taxes still anger the people, war or not.
      expect(delta(taxRateMax, atWar: true), lessThan(0));
    });

    test('war weariness withholds the low-tax goodwill entirely', () {
      final started = startGame(state, Rng(7)).state;
      final realm = started.realm(1);
      realm.recentWars = 2; // war-weary: goodwill is withheld
      realm.popularity = 50; // below the (otherwise) recovery ceiling
      realm.taxRate = 0;
      final report = runEconomy(started, realm, Rng(1));
      expect(report.taxPopularity, 0);
      expect(realm.popularity, 50); // no goodwill while war-weary
    });
  });
}
