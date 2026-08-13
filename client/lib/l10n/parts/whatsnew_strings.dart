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
  // --- v0.2.6 ---
  'whatsnew.0_2_6.0':
      'Steuern: Im Handel-Menü lässt sich der Steuersatz jetzt anpassen — '
      'höhere Steuern füllen die Schatzkammer, senken aber die Beliebtheit.',
  'whatsnew.0_2_6.1':
      'Truppen & Gebiete: Schicke Truppen an andere Reiche und übertrage '
      'einzelne Felder oder ganze Reiche.',
  'whatsnew.0_2_6.2':
      'Kriegstermin: Der vereinbarte Beginn einer Online-Schlacht lässt '
      'sich bis zum Kriegsbeginn anpassen.',
  'whatsnew.0_2_6.3':
      'Weitere Verbesserungen: überarbeitete Siegbedingungen und viele '
      'kleine Korrekturen.',
};

const Map<String, String> whatsnewEn = {
  'whatsnew.title': "What's new?",
  'whatsnew.close': 'Close',
  // --- v0.2.6 ---
  'whatsnew.0_2_6.0':
      'Taxes: the trade menu now lets you adjust your realm\'s tax rate — '
      'higher taxes fill the treasury but lower popularity.',
  'whatsnew.0_2_6.1':
      'Troops & territory: send troops to other realms and hand over '
      'single tiles or whole realms.',
  'whatsnew.0_2_6.2':
      'War start: the agreed start of an online battle can be changed '
      'right up until the war begins.',
  'whatsnew.0_2_6.3':
      'More improvements: reworked victory conditions and many small fixes.',
};
