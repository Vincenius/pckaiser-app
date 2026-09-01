/// String-table part for the "What's new" release-notes modal — merged into
/// the app-wide table in `l10n/strings.dart`. The modal shows once per app
/// version (see `release_notes.dart` / `widgets/whats_new_dialog.dart`).
///
/// Keys are `whatsnew.<version>.<index>` so every release appends its own
/// bullets without touching older entries; the version string has its dots
/// replaced by `_` (`0.2.6` → `0_2_6`) to stay a plain map key.
const Map<String, String> whatsnewDe = {
  'whatsnew.title': 'Was ist neu?',
  'whatsnew.close': 'Schließen',
  // --- v0.2.8 --- Headlines only: the modal is a glance, not a changelog.
  'whatsnew.0_2_8.0': 'Angriffsbefehl mit eigenem Marschziel auf der Karte',
  'whatsnew.0_2_8.1': 'Warnung, wenn noch Bauzüge offen sind',
  'whatsnew.0_2_8.2': 'KI lässt kein Land mehr unbebaut liegen',
  'whatsnew.0_2_8.3': 'Stammbaum: die eigene Dynastie als zoombarer Baum',
  // --- v0.2.7 --- Headlines only: the modal is a glance, not a changelog.
  'whatsnew.0_2_7.0':
      'Truppen laufen auch zu weit entfernten Feldern – beste Route automatisch',
  'whatsnew.0_2_7.1': 'KI-Truppen nutzen Häfen und die kürzesten Wege',
  'whatsnew.0_2_7.2': 'Beliebtheit bestimmt Züge und Kampfmoral',
  'whatsnew.0_2_7.3':
      'Mehr Zeit für den Kriegsstart, abschaltbare Benachrichtigungen',
  'whatsnew.0_2_7.4': 'Kontrolle nach verpasstem Kriegsstart zurückholen',
  // --- v0.2.6 --- Headlines only: the modal is a glance, not a changelog.
  'whatsnew.0_2_6.0': 'Steuern sind einstellbar (Geld gegen Beliebtheit)',
  'whatsnew.0_2_6.1': 'Truppen können an andere Reiche verschenkt werden',
  'whatsnew.0_2_6.2': 'Einzelne Felder sind übertragen',
  'whatsnew.0_2_6.3': 'Kriegstermin bis zum Beginn änderbar',
  'whatsnew.0_2_6.4': 'Geschlecht der Nachkommen wird angezeigt',
};

const Map<String, String> whatsnewEn = {
  'whatsnew.title': "What's new?",
  'whatsnew.close': 'Close',
  // --- v0.2.8 --- Headlines only: the modal is a glance, not a changelog.
  'whatsnew.0_2_8.0': 'Attack orders can name their own march target',
  'whatsnew.0_2_8.1': 'A warning when build moves are still unspent',
  'whatsnew.0_2_8.2': 'The AI no longer leaves its land uncultivated',
  'whatsnew.0_2_8.3': 'Family tree: your dynasty as a zoomable tree',
  // --- v0.2.7 --- Headlines only: the modal is a glance, not a changelog.
  'whatsnew.0_2_7.0':
      'March to distant tiles — troops take the best route on their own',
  'whatsnew.0_2_7.1': 'AI troops use harbors and the shortest paths',
  'whatsnew.0_2_7.2': 'Popularity now drives movement points and combat morale',
  'whatsnew.0_2_7.3': 'More time for war starts, switchable notifications',
  'whatsnew.0_2_7.4': 'Take your side back after a missed war start',
  // --- v0.2.6 --- Headlines only: the modal is a glance, not a changelog.
  'whatsnew.0_2_6.0': 'Set your own tax rate',
  'whatsnew.0_2_6.1': 'Gift troops, hand over tiles',
  'whatsnew.0_2_6.2': 'War start time stays changeable',
  'whatsnew.0_2_6.3': 'Reworked victory conditions, many fixes',
  'whatsnew.0_2_6.4': 'Gender of offspring is displayed',
};
