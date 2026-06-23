import '../rng/rng.dart';
import '../state/constants.dart';
import '../state/game_state.dart';
import '../state/realm.dart';

/// What the economy upkeep did this turn — feeds the §21.1 status report.
class EconomyReport {
  int tax = 0;
  int tribute = 0;
  int potCollected = 0;
  int harborIncome = 0;
  int wages = 0;
}

/// Economy upkeep (ORIGINAL_GAME.md §7), in order: taxes, crown-pot
/// collection (§17.5), tribute, harbor income, wages. Mutates [realm] and
/// the global pots in place — the turn pipeline owns the state copy.
EconomyReport runEconomy(GameState state, Realm realm, Rng rng) {
  final report = EconomyReport();

  // §7.1 Tax: uniform [pop, 2×pop).
  if (realm.population > 0) {
    report.tax = rng.nextInt(realm.population) + realm.population;
    realm.treasury += report.tax;
  }
  realm.lastTax = report.tax;

  // §17.5: the office holder collects the whole pot on their own turn.
  final isKaiser = state.kaiserId != null && realm.rulerId == state.kaiserId;
  final isSultan = state.sultanId != null && realm.rulerId == state.sultanId;
  if (isKaiser) {
    report.potCollected += state.kaiserPot;
    realm.treasury += state.kaiserPot;
    state.kaiserPot = 0;
  }
  if (isSultan) {
    report.potCollected += state.sultanPot;
    realm.treasury += state.sultanPot;
    state.sultanPot = 0;
  }

  // §7.2 Feudal tribute: 5% skim into the religion's crown pot
  // (simplified per spec note — the office holder does not pay their own
  // pot, they would only collect it back). [DESIGNED: reduced from
  // original 10% — the accumulated pot gave the Kaiser an overwhelming
  // compounding advantage that was near-impossible to overcome.]
  if (realm.treasury > 0) {
    final muslim = state.dynasty(realm.slot).religion == Religion.moslemisch;
    final paysTribute = muslim ? !isSultan : !isKaiser;
    if (paysTribute) {
      report.tribute = realm.treasury ~/ 20;
      realm.treasury -= report.tribute;
      if (muslim) {
        state.sultanPot += report.tribute;
      } else {
        state.kaiserPot += report.tribute;
      }
    }
  }
  realm.lastTribute = report.tribute;

  // §7.3 Harbor income: random(70) per Hafen.
  for (var i = 0; i < realm.tileCount[Building.hafen]; i++) {
    report.harborIncome += rng.nextInt(70);
  }
  realm.treasury += report.harborIncome;

  // §7.4 Wages: 0.5 T per man (§27 constants), regulars and Söldner alike.
  // Söldner are the non-garrison-counted troops (not in armySize); keying
  // off quality == 3 would double-count a regular drilled to quality 3.
  final soeldnerMen = realm.troops
      .where((t) => !t.garrisonCounted)
      .fold(0, (sum, t) => sum + t.men);
  report.wages = ((realm.armySize + soeldnerMen) * 0.5).round();
  realm.treasury -= report.wages;

  return report;
}
