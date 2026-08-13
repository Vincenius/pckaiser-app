import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/labels.dart';
import '../l10n/strings.dart';
import '../state/game_controller.dart';

/// §21.2 popularity tier text for the turn report.
String popularityTier(int value) => switch (value) {
  <= 10 => tr('game.popularityTierRevolt'),
  <= 25 => tr('game.popularityTierUprisings'),
  <= 40 => tr('game.popularityTierUnpopular'),
  <= 60 => tr('game.popularityTierAverage'),
  <= 75 => tr('game.popularityTierDecent'),
  <= 90 => tr('game.popularityTierHigh'),
  _ => tr('game.popularityTierVeryHigh'),
};

/// Turn-start status report (the original's §21.1 "Sie sind am Zug!"
/// screen): income/expenses of the upkeep, food stock, population,
/// popularity with tier text, and the buildable fields of this round.
/// Shown right after the handoff, before decisions and the recap.
Future<void> showTurnReport(
  BuildContext context,
  GameController controller,
  int slot,
) async {
  final state = controller.state;
  final realm = state.realm(slot);
  if (realm.isVacant) return;

  // The §21.1 numbers live in the slot's latest turnUpkeep event.
  gc.GameEvent? upkeep;
  for (final e in state.events.reversed) {
    if (e.type == 'turnUpkeep' && e.slot == slot) {
      upkeep = e;
      break;
    }
  }
  final p = upkeep?.payload ?? const <String, dynamic>{};
  int n(String key) => (p[key] as num?)?.toInt() ?? 0;

  final ruler = state.person(realm.rulerId);
  // Forward-looking food check: does THIS turn's harvest cover the
  // population? (The realm's `grainHarvest`/`livestockHarvest` is the
  // leftover AFTER everyone already ate — for a hand-to-mouth realm always
  // ~0, so it made a useless, alarming-looking warning. Production vs.
  // population is the number that actually tells you whether your fields
  // keep up.)
  final production = n('grainYield') + n('livestockYield');
  final foodShort = production < realm.population;
  final theme = Theme.of(context);

  Widget row(IconData icon, String text, {Color? color, FontWeight? weight}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: weight,
                ),
              ),
            ),
          ],
        ),
      );

  final lowPopularity = realm.popularity < 30;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        tr('game.annoRealm', {'year': state.year, 'realm': realmName(slot)}),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (ruler != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  tr('game.yourTurnGreeting', {
                    'title': titleName(realm.titleClass),
                    'name': ruler.name,
                  }),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            row(
              Icons.toll,
              tr('game.taxesLine', {'tax': n('tax')}) +
                  (n('harborIncome') > 0
                      ? tr('game.harborIncomeSuffix', {
                          'income': n('harborIncome'),
                        })
                      : ''),
            ),
            // The tax RATE's yearly popularity swing (§7.1 tuning). Only a
            // rate away from 100 % produces one, and it is silent
            // otherwise — without this line a realm at 200 % would bleed
            // popularity every year with nothing naming the cause.
            if (n('taxPopularity') != 0)
              row(
                Icons.sentiment_satisfied_alt,
                tr('game.taxPopularityLine', {
                  'rate': realm.taxRate,
                  'pop': '${n('taxPopularity') > 0 ? '+' : ''}'
                      '${n('taxPopularity')}',
                }),
                color: n('taxPopularity') < 0 ? Colors.red.shade700 : null,
              ),
            // The office holder's pot waits for the explicit "Staatskasse
            // plündern" action (Dynastie-Menü) — remind them here.
            if (state.kaiserId != null &&
                realm.rulerId == state.kaiserId &&
                state.kaiserPot > 0)
              row(
                Icons.account_balance_wallet,
                tr('game.kaiserPotLine', {'amount': state.kaiserPot}),
                color: Colors.amber.shade800,
              ),
            if (state.sultanId != null &&
                realm.rulerId == state.sultanId &&
                state.sultanPot > 0)
              row(
                Icons.account_balance_wallet,
                tr('game.sultanPotLine', {'amount': state.sultanPot}),
                color: Colors.amber.shade800,
              ),
            if (n('tribute') > 0 || n('wages') > 0)
              row(
                Icons.money_off,
                tr('game.tributeWagesLine', {
                  'tribute': n('tribute'),
                  'wages': n('wages'),
                }),
              ),
            row(
              Icons.account_balance,
              '${tr('treasury')}: ${realm.treasury} T',
              weight: FontWeight.w600,
            ),
            row(
              Icons.people,
              tr('game.populationLine', {'population': realm.population}) +
                  (n('populationDelta') != 0
                      ? ' (${n('populationDelta') > 0 ? '+' : ''}${n('populationDelta')})'
                      : ''),
            ),
            row(
              Icons.agriculture,
              foodShort
                  ? tr('game.foodShortLine', {
                      'production': production,
                      'population': realm.population,
                    })
                  : tr('game.foodOkLine', {
                      'production': production,
                      'population': realm.population,
                    }),
              color: foodShort ? theme.colorScheme.error : null,
            ),
            if (foodShort)
              row(
                Icons.warning_amber,
                tr('game.foodWarning'),
                color: theme.colorScheme.error,
              ),
            if (n('famineLoss') > 0)
              row(
                Icons.warning_amber,
                tr('game.famineLine', {'loss': n('famineLoss')}),
                color: theme.colorScheme.error,
              ),
            row(
              lowPopularity ? Icons.heart_broken : Icons.favorite,
              '${tr('popularity')}: ${realm.popularity} — '
              '${popularityTier(realm.popularity)}',
              color: lowPopularity ? theme.colorScheme.error : null,
            ),
            row(
              Icons.construction,
              tr(
                realm.movementPoints == 1
                    ? 'game.buildsThisRoundOne'
                    : 'game.buildsThisRoundMany',
                {'moves': realm.movementPoints},
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('game.continueButton')),
        ),
      ],
    ),
  );
}
