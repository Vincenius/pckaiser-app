import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/strings.dart';
import '../state/game_controller.dart';

/// §21.2 popularity tier text for the turn report.
String popularityTier(int value) => switch (value) {
  <= 10 => 'Ihr Land steht am Rande einer Revolution !!!',
  <= 25 => 'In ihrem Land gibt es kleinere Aufstände !!!',
  <= 40 => 'Sie sind nicht gerade sehr beliebt.',
  <= 60 => 'Durchschnittlich',
  <= 75 => 'Nicht gerade niedrig',
  <= 90 => 'Sehr hoch',
  _ => 'Unglaublich hoch',
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
      title: Text('Anno ${state.year} — ${gc.countryNames[slot]}'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (ruler != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${gc.titleName(realm.titleClass)} ${ruler.name}, '
                  'Ihr seid am Zug !',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            row(
              Icons.toll,
              'Steuern: +${n('tax')} T'
              '${n('harborIncome') > 0 ? ' — Häfen: +${n('harborIncome')} T' : ''}',
            ),
            // The office holder's pot waits for the explicit "Staatskasse
            // plündern" action (Dynastie-Menü) — remind them here.
            if (state.kaiserId != null &&
                realm.rulerId == state.kaiserId &&
                state.kaiserPot > 0)
              row(
                Icons.account_balance_wallet,
                'Kronschatz: ${state.kaiserPot} T warten — '
                '„Staatskasse plündern" im Dynastie-Menü !',
                color: Colors.amber.shade800,
              ),
            if (state.sultanId != null &&
                realm.rulerId == state.sultanId &&
                state.sultanPot > 0)
              row(
                Icons.account_balance_wallet,
                'Sultansschatz: ${state.sultanPot} T warten — '
                '„Staatskasse plündern" im Dynastie-Menü !',
                color: Colors.amber.shade800,
              ),
            if (n('tribute') > 0 || n('wages') > 0)
              row(
                Icons.money_off,
                'Tribut: −${n('tribute')} T — Sold: −${n('wages')} T',
              ),
            row(
              Icons.account_balance,
              'Schatzkammer: ${realm.treasury} T',
              weight: FontWeight.w600,
            ),
            row(
              Icons.people,
              '${tr('population')}: ${realm.population} Einwohner'
              '${n('populationDelta') != 0 ? ' (${n('populationDelta') > 0 ? '+' : ''}${n('populationDelta')})' : ''}',
            ),
            row(
              Icons.agriculture,
              foodShort
                  ? 'Deine Felder ernähren nur $production von '
                        '${realm.population} Leuten !'
                  : 'Deine Felder ernähren die Bevölkerung '
                        '($production ≥ ${realm.population}).',
              color: foodShort ? theme.colorScheme.error : null,
            ),
            if (foodShort)
              row(
                Icons.warning_amber,
                'Nahrung wird knapp — baue mehr Kornfelder/Weiden, sonst '
                'drohen Hungersnot und Desertion !',
                color: theme.colorScheme.error,
              ),
            if (n('famineLoss') > 0)
              row(
                Icons.warning_amber,
                'Hungersnot: ${n('famineLoss')} Soldaten desertieren !',
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
              'Du kannst diese Runde ${realm.movementPoints} '
              'Feld${realm.movementPoints == 1 ? '' : 'er'} bebauen.',
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Weiter'),
        ),
      ],
    ),
  );
}
