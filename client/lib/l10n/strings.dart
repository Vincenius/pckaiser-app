import 'package:flutter/foundation.dart';

/// Minimal string table — German default for v1, English optional.
/// The German entries follow §23 of ORIGINAL_GAME.md where a verbatim
/// original string exists.
final ValueNotifier<String> appLocale = ValueNotifier('de');

const Map<String, Map<String, String>> _table = {
  'en': {
    'appTitle': 'PCKaiser',
    'tagline': 'From knight to emperor — conquer the realm',
    'newGame': 'New game',
    'tutorial': 'Tutorial — learn the game',
    'online': 'Play online (beta)',
    'onlineGames': 'Online games',
    'onlineYourTurn': 'Your turn!',
    'onlineWaitingForPlayers': 'Waiting for players',
    'onlineWaitingForOthers': 'Waiting for the other players …',
    // Suffixed to the awaited player's name: "Anna is taking her turn …"
    'onlineIsPlaying': 'is taking their turn …',
    'onlineLoading': 'Loading online games …',
    'savedGames': 'Saved games',
    'noSaves': 'No saved games yet.',
    'noSavesHint': 'Start a new game, or learn the basics in the tutorial.',
    'saveNeedsUpdate':
        'Saved with a newer app version — update the app to play it.',
    'about': 'About',
    'aboutDescription':
        'A mobile remake of the 1992 DOS strategy classic "PCKaiser++": '
        'lead a small realm in the medieval Holy Roman Empire — '
        'build, trade, marry, scheme and wage war until the '
        'electors crown you Kaiser.',
    // Split so the game title can be rendered as a link to the archive
    // (see AboutScreen); the three pieces concatenate to the full credit.
    'creditsOriginalPrefix': 'Original game: ',
    'creditsOriginalGame': '"PCKaiser"',
    'creditsOriginalSuffix': ' by Martin Gelter & Lorenz Giefing, 1992.',
    'creditsApp': 'This app: Vincent Will.',
    'endTurn': 'End turn',
    'undo': 'Undo',
    'treasury': 'Treasury',
    'population': 'Population',
    'food': 'Food',
    'popularity': 'Popularity',
    'moves': 'Moves',
    'commerce': 'Commerce',
    'military': 'Military',
    'espionage': 'Espionage',
    'misc': 'Dynasty',
    'info': 'Info',
    'eventFeed': 'Events',
    'demolish': 'Demolish (100 T)',
    'handoff': 'Hand the device to',
    'yourTurn': 'Begin turn',
    'sellGrain': 'Sell grain',
    'sellCattle': 'Sell cattle',
    'investShips': 'Send trade ships',
    'mergeRealms': 'Merge realms',
    'recruit': 'Recruit troops',
    'hireSoeldner': 'Hire Söldner',
    'declareWar': 'Declare war',
    'guards': 'Guards',
    'chronicle': 'Kaiser chronicle',
    'gameOver': 'Victory!',
    'gameLost': 'Defeat!',
    'proposeMarriage': 'Propose marriage',
    'cancel': 'Cancel',
  },
  'de': {
    'appTitle': 'PCKaiser',
    'tagline': 'Vom Ritter zum Kaiser — erobere das Reich',
    'newGame': 'Neues Spiel',
    'tutorial': 'Tutorial — das Spiel lernen',
    'online': 'Online spielen (Beta)',
    'onlineGames': 'Online-Partien',
    'onlineYourTurn': 'Du bist am Zug !',
    'onlineWaitingForPlayers': 'Wartet auf Spieler',
    'onlineWaitingForOthers': 'Warten auf Mitspieler …',
    'onlineIsPlaying': 'ist am Zug …',
    'onlineLoading': 'Online-Partien werden geladen …',
    'savedGames': 'Spielstände',
    'noSaves': 'Noch keine Spielstände.',
    'noSavesHint':
        'Starte ein neues Spiel — oder lerne die Grundlagen im Tutorial.',
    'saveNeedsUpdate':
        'Mit neuerer App-Version gespeichert — App aktualisieren, '
        'um weiterzuspielen.',
    'about': 'Über das Spiel',
    'aboutDescription':
        'Ein mobiles Remake des DOS-Strategieklassikers „PCKaiser++" von '
        '1992: Führe ein Kleinstaat-Reich im mittelalterlichen '
        'Heiligen Römischen Reich — baue, handle, heirate, intrigiere '
        'und führe Krieg, bis die Kurfürsten dich zum Kaiser wählen.',
    // Split so the game title links to the archive (see AboutScreen).
    'creditsOriginalPrefix': 'Originalspiel: ',
    'creditsOriginalGame': '„PCKaiser++"',
    'creditsOriginalSuffix': ' von Martin Gelter & Lorenz Giefing, 1992.',
    'creditsApp': 'App: Vincent Will.',
    'endTurn': 'Zug beenden',
    'undo': 'Rückgängig',
    'treasury': 'Schatzkammer',
    'population': 'Bevölkerung',
    'food': 'Nahrung',
    'popularity': 'Beliebtheit',
    'moves': 'Ziehen',
    'commerce': 'Handel',
    'military': 'Militär',
    'espionage': 'Spionage',
    'misc': 'Dynastie',
    'info': 'Info',
    'eventFeed': 'Ereignisse',
    'demolish': 'Abreißen (100 T)',
    'handoff': 'Gerät weitergeben an',
    'yourTurn': 'Zug beginnen',
    'sellGrain': 'Korn verkaufen',
    'sellCattle': 'Rinder verkaufen',
    'investShips': 'Handelsschiffe aussenden',
    'mergeRealms': 'Reiche zusammenlegen',
    // Original menu wording: "Truppe bilden" creates a unit; "Truppe
    // ausbilden" (the troop sheet) drills quality +1.
    'recruit': 'Truppe bilden',
    'hireSoeldner': 'Söldner anwerben',
    'declareWar': 'Krieg erklären',
    'guards': 'Spionageabwehr',
    'chronicle': 'Kaiserchronik',
    'gameOver': 'Sieg!',
    'gameLost': 'Niederlage!',
    'proposeMarriage': 'Heirat vorschlagen',
    'cancel': 'Abbrechen',
  },
};

/// Translated string for [key]; falls back to English, then the key.
String tr(String key) =>
    _table[appLocale.value]?[key] ?? _table['en']![key] ?? key;

/// Server timestamps (ISO 8601, UTC) rendered in the device's timezone
/// and the active locale's date format — e.g. "15.06.2026, 14:30".
String formatTimestamp(String iso) {
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso;
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(dt.hour)}:${two(dt.minute)}';
  return appLocale.value == 'de'
      ? '${two(dt.day)}.${two(dt.month)}.${dt.year}, $time'
      : '${dt.year}-${two(dt.month)}-${two(dt.day)}, $time';
}
