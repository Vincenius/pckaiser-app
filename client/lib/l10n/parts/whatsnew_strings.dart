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
  // --- v0.2.6 --- Headlines only: the modal is a glance, not a changelog.
  'whatsnew.0_2_6.0': 'Set your own tax rate',
  'whatsnew.0_2_6.1': 'Gift troops, hand over tiles',
  'whatsnew.0_2_6.2': 'War start time stays changeable',
  'whatsnew.0_2_6.3': 'Reworked victory conditions, many fixes',
  'whatsnew.0_2_6.4': 'Gender of offspring is displayed',
};
