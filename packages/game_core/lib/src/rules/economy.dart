import '../rng/rng.dart';
import '../state/constants.dart';
import '../state/game_state.dart';
import '../state/realm.dart';

/// What the economy upkeep did this turn — feeds the §21.1 status report.
class EconomyReport {
  int tax = 0;
  int tribute = 0;
  int harborIncome = 0;
  int wages = 0;

  /// The popularity change the tax RATE caused this turn (positive =
  /// goodwill from low taxes, negative = resentment from high taxes).
  int taxPopularity = 0;
}

/// Economy upkeep (ORIGINAL_GAME.md §7), in order: taxes, tribute, harbor
/// income, wages. Mutates [realm] and the global pots in place — the turn
/// pipeline owns the state copy.
///
/// `[DESIGNED 2026-07-06, user request]` The crown pot (§17.5) is NOT
/// auto-collected here anymore: the office holder empties it with the
/// explicit `CollectTribute` action ("Staatskasse plündern"); AI office
/// holders trigger that at turn start.
EconomyReport runEconomy(GameState state, Realm realm, Rng rng) {
  final report = EconomyReport();

  // §7.1 Tax: uniform [pop, 2×pop), scaled by the tax rate (§7.1 tuning).
  // 100% is the original formula; a higher rate collects more, a lower one
  // less (down to 0 at 0%).
  if (realm.population > 0) {
    final base = rng.nextInt(realm.population) + realm.population;
    report.tax = base * realm.taxRate ~/ taxRateDefault;
    realm.treasury += report.tax;
  }
  realm.lastTax = report.tax;

  // §7.1 tax-rate reaction: the people feel the burden every turn — high
  // taxes breed resentment, low taxes buy goodwill. The goodwill is
  // withheld while at war or war-weary (user rule: taxes may not outweigh
  // a war's popularity cost), so a warring realm's mood still sinks even
  // with low taxes.
  report.taxPopularity = _taxPopularityEffect(state, realm);

  final isKaiser = state.kaiserId != null && realm.rulerId == state.kaiserId;
  final isSultan = state.sultanId != null && realm.rulerId == state.sultanId;

  // §7.2 Feudal tribute: 5% skim into the religion's crown pot
  // (simplified per spec note — the office holder does not pay their own
  // pot, they would only collect it back). [DESIGNED: reduced from
  // original 10% — the accumulated pot gave the Kaiser an overwhelming
  // compounding advantage that was near-impossible to overcome.]
  // [DESIGNED] No tribute accrues while the throne is VACANT: there is no
  // one to collect it, so it must not pile up through the kaiserless first
  // decade (no Kaiser before year 1010) or any later interregnum and then
  // dump a windfall on whoever is crowned next — that hoard was exactly
  // what made a freshly crowned Kaiser instantly, unbeatably rich.
  if (realm.treasury > 0) {
    final muslim = state.dynasty(realm.slot).religion == Religion.moslemisch;
    final officeFilled =
        muslim ? state.sultanId != null : state.kaiserId != null;
    final paysTribute = officeFilled && (muslim ? !isSultan : !isKaiser);
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

/// The per-turn popularity reaction to [Realm.taxRate] (§7.1 tuning):
/// resentment (high taxes) steps in every [taxPopularityHighStep] points
/// above [taxRateDefault] — tighter than the goodwill side, so heavy
/// taxation grinds mood down a little faster (user request). Goodwill
/// (low taxes) accrues every [taxPopularityStep] points below the default
/// but is withheld entirely while the realm is at war or war-weary
/// (`Realm.recentWars > 0`) — taxes can never buy back the popularity a
/// war costs, so a warring realm's mood keeps sinking even with
/// rock-bottom taxes (user rule). Returns the applied change.
int _taxPopularityEffect(GameState state, Realm realm) {
  final rate = realm.taxRate;
  final before = realm.popularity;
  if (rate > taxRateDefault) {
    final delta = -((rate - taxRateDefault) ~/ taxPopularityHighStep);
    if (delta == 0) return 0;
    realm.popularity = (realm.popularity + delta).clamp(0, 100);
    return realm.popularity - before;
  }
  if (rate < taxRateDefault) {
    final delta = (taxRateDefault - rate) ~/ taxPopularityStep;
    if (delta == 0) return 0;
    final atWar = state.activeWar?.isParticipant(realm.slot) ?? false;
    if (atWar || realm.recentWars > 0) return 0;
    realm.popularity = (realm.popularity + delta).clamp(0, 100);
    return realm.popularity - before;
  }
  return 0;
}
