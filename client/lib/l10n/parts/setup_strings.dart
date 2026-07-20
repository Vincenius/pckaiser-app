/// String-table part for the "setup" UI area — merged into the app-wide
/// table in `l10n/strings.dart`. Keys are prefixed `setup.`; `{name}`-style
/// placeholders are filled by `tr(key, params)`.
const Map<String, String> setupDe = {
  // New-game setup screen
  'setup.defaultSlotName': 'Partie 1',
  'setup.slotNameLabel': 'Name des Spielstands',
  'setup.playersHeading': 'Spieler',
  'setup.playersHeadingCount': 'Spieler ({count}/16)',
  'setup.playerN': 'Spieler {n}',
  'setup.addPlayer': 'Spieler hinzufügen',
  'setup.removePlayer': 'Spieler entfernen',
  'setup.founderNameLabel': 'Name des Gründers',
  'setup.randomDorfHint': 'Leer = Dorf des zugelosten Landes',
  'setup.randomRealm': 'Zufällig',
  'setup.startGame': 'Spiel starten',
  'setup.errorSlotName': 'Bitte dem Spielstand einen Namen geben',
  'setup.errorFounderName': 'Jeder Gründer braucht einen Namen',
  'setup.errorDorfName': 'Jedes erste Dorf braucht einen Namen',
  'setup.errorDuplicateCountry': 'Zwei Spieler haben dasselbe Land gewählt',
  'setup.overwriteTitle': 'Spielstand überschreiben ?',
  'setup.overwriteBody':
      'Es gibt bereits einen Spielstand namens '
      '"{name}". Neues Spiel darüber speichern ?',
  'setup.overwrite': 'Überschreiben',
  // Advanced options card (local + online setup)
  'setup.advancedOptions': 'Erweiterte Optionen',
  'setup.advancedOptionsSubtitle': 'Ereignis-Jahre, KI-Stärke, Regeln',
  'setup.aiStrengthLabel': 'Stärke der KI-Gegner',
  'setup.reformationYearLabel': 'Jahr der Reformation',
  'setup.ottomanInvasionLabel': 'Osmanen-Invasion',
  'setup.warStartYearLabel': 'Krieg möglich ab Jahr',
  'setup.originalYearHint': 'Original: {year}',
  'setup.tooEarlyReformation': 'Das ist zu früh !!! (Reformation ≥ {year})',
  'setup.tooEarlyOttoman': 'Das ist zu früh !!! (Osmanen ≥ {year})',
  'setup.tooEarlyWar': 'Das ist zu früh !!! (Krieg ab ≥ {year})',
  'setup.genderEqualTitle': 'Frauen können überall herrschen',
  'setup.genderEqualSubtitle':
      'Abweichend vom Original: das älteste Kind erbt '
      'unabhängig vom Geschlecht und Frauen können auch '
      'islamische Reiche erben, ohne auszuscheiden.',
  'setup.childNamesTitle': 'Namensvorschläge für Kinder',
  'setup.childNamesSubtitle':
      'Bei Geburten einen zufälligen Namen vorschlagen — '
      'ausgeschaltet bleibt das Namensfeld leer.',
  // AI difficulty picker
  'setup.aiEasy': 'Leicht',
  'setup.aiMedium': 'Mittel',
  'setup.aiHard': 'Schwer',
  'setup.aiEasyDesc':
      'Die KI wirtschaftet nachlässig, rüstet halbherzig '
      'und verübt keine Attentate.',
  'setup.aiMediumDesc':
      'Die KI spielt wie das Original — gelegentliche '
      'Kriege und seltene Attentate.',
  'setup.aiHardDesc':
      'Die KI plant Wirtschaft und Militär, bildet '
      'Truppen aus und greift gezielt Schwächere an.',
  // Online map viewer
  'setup.mapTitle': 'Karte — Anno {year}',
  'setup.switchRealm': 'Reich wechseln',
  'setup.viewOnly': 'Nur ansehen',
  // About screen
  'setup.version': 'Version {version}',
  'setup.githubSource': 'GitHub — Quellcode',
  'setup.discordCommunity': 'Discord — Community',
  // Update-required banner
  'setup.updateRequiredTitle': 'App-Update erforderlich',
  'setup.updateRequiredBody':
      'Diese Partie läuft auf Version {version}. Bitte '
      'aktualisiere die App, um deinen Zug zu machen.',
  'setup.updatePlayStore': 'Im Play Store aktualisieren',
};

const Map<String, String> setupEn = {
  // New-game setup screen
  'setup.defaultSlotName': 'Game 1',
  'setup.slotNameLabel': 'Save name',
  'setup.playersHeading': 'Players',
  'setup.playersHeadingCount': 'Players ({count}/16)',
  'setup.playerN': 'Player {n}',
  'setup.addPlayer': 'Add player',
  'setup.removePlayer': 'Remove player',
  'setup.founderNameLabel': "Founder's name",
  'setup.randomDorfHint': "Empty = the drawn realm's village",
  'setup.randomRealm': 'Random',
  'setup.startGame': 'Start game',
  'setup.errorSlotName': 'Please give the save a name',
  'setup.errorFounderName': 'Every founder needs a name',
  'setup.errorDorfName': 'Every first village needs a name',
  'setup.errorDuplicateCountry': 'Two players have chosen the same realm',
  'setup.overwriteTitle': 'Overwrite save?',
  'setup.overwriteBody':
      'A save named "{name}" already exists. '
      'Save the new game over it?',
  'setup.overwrite': 'Overwrite',
  // Advanced options card (local + online setup)
  'setup.advancedOptions': 'Advanced options',
  'setup.advancedOptionsSubtitle': 'Event years, AI strength, rules',
  'setup.aiStrengthLabel': 'AI opponent strength',
  'setup.reformationYearLabel': 'Year of the Reformation',
  'setup.ottomanInvasionLabel': 'Ottoman invasion',
  'setup.warStartYearLabel': 'War possible from year',
  'setup.originalYearHint': 'Original: {year}',
  'setup.tooEarlyReformation': 'That is too early!!! (Reformation ≥ {year})',
  'setup.tooEarlyOttoman': 'That is too early!!! (Ottomans ≥ {year})',
  'setup.tooEarlyWar': 'That is too early!!! (War from ≥ {year})',
  'setup.genderEqualTitle': 'Women can rule everywhere',
  'setup.genderEqualSubtitle':
      'Deviation from the original: the eldest child inherits '
      'regardless of gender, and women can inherit '
      'Islamic realms without being eliminated.',
  'setup.childNamesTitle': 'Name suggestions for children',
  'setup.childNamesSubtitle':
      'Suggest a random name at each birth — '
      'when off, the name field stays empty.',
  // AI difficulty picker
  'setup.aiEasy': 'Easy',
  'setup.aiMedium': 'Medium',
  'setup.aiHard': 'Hard',
  'setup.aiEasyDesc':
      'The AI manages its economy carelessly, arms half-heartedly '
      'and carries out no assassinations.',
  'setup.aiMediumDesc':
      'The AI plays like the original — occasional '
      'wars and rare assassinations.',
  'setup.aiHardDesc':
      'The AI plans economy and military, drills its '
      'troops and deliberately attacks the weak.',
  // Online map viewer
  'setup.mapTitle': 'Map — Anno {year}',
  'setup.switchRealm': 'Switch realm',
  'setup.viewOnly': 'View only',
  // About screen
  'setup.version': 'Version {version}',
  'setup.githubSource': 'GitHub — Source code',
  'setup.discordCommunity': 'Discord — Community',
  // Update-required banner
  'setup.updateRequiredTitle': 'App update required',
  'setup.updateRequiredBody':
      'This match runs on version {version}. Please '
      'update the app to take your turn.',
  'setup.updatePlayStore': 'Update in the Play Store',
};
