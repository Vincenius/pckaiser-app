import 'package:flutter/foundation.dart';

/// Minimal string table — German default for v1, English optional.
/// The German entries follow §23 of ORIGINAL_GAME.md where a verbatim
/// original string exists.
final ValueNotifier<String> appLocale = ValueNotifier('de');

const Map<String, Map<String, String>> _table = {
  'en': {
    'appTitle': 'PC Kaiser',
    'tagline': 'From knight to emperor — conquer the realm',
    'newGame': 'New game',
    'tutorial': 'Tutorial — learn the game',
    'savedGames': 'Saved games',
    'noSaves': 'No saved games yet.',
    'noSavesHint':
        'Start a new game, or learn the basics in the tutorial.',
    'saveNeedsUpdate':
        'Saved with a newer app version — update the app to play it.',
    'about': 'About',
    'aboutDescription':
        'A mobile remake of the 1992 DOS strategy classic "PC Kaiser": '
            'lead a small realm in the medieval Holy Roman Empire — '
            'build, trade, marry, scheme and wage war until the '
            'electors crown you Kaiser.',
    'creditsOriginal':
        'Original game: "PC Kaiser" by Martin Gelter, 1992.',
    'creditsApp': 'This app: Vincent Will.',
    'resume': 'Resume',
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
    'misc': 'Misc',
    'info': 'Info',
    'eventFeed': 'Events',
    'demolish': 'Demolish (100 T)',
    'handoff': 'Hand the device to',
    'yourTurn': 'Begin turn',
    'warDeclared': 'War declared!',
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
    'appTitle': 'PC Kaiser',
    'tagline': 'Vom Ritter zum Kaiser — erobere das Reich',
    'newGame': 'Neues Spiel',
    'tutorial': 'Tutorial — das Spiel lernen',
    'savedGames': 'Spielstände',
    'noSaves': 'Noch keine Spielstände.',
    'noSavesHint':
        'Starte ein neues Spiel — oder lerne die Grundlagen im Tutorial.',
    'saveNeedsUpdate':
        'Mit neuerer App-Version gespeichert — App aktualisieren, '
            'um weiterzuspielen.',
    'about': 'Über das Spiel',
    'aboutDescription':
        'Ein mobiles Remake des DOS-Strategieklassikers „PC Kaiser" von '
            '1992: Führe ein Kleinstaat-Reich im mittelalterlichen '
            'Heiligen Römischen Reich — baue, handle, heirate, intrigiere '
            'und führe Krieg, bis die Kurfürsten dich zum Kaiser wählen.',
    'creditsOriginal':
        'Originalspiel: „PC Kaiser" von Martin Gelter, 1992.',
    'creditsApp': 'App: Vincent Will.',
    'resume': 'Fortsetzen',
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
    'misc': 'Sonstiges',
    'info': 'Info',
    'eventFeed': 'Ereignisse',
    'demolish': 'Abreißen (100 T)',
    'handoff': 'Gerät weitergeben an',
    'yourTurn': 'Zug beginnen',
    'warDeclared': 'Krieg erklärt!',
    'sellGrain': 'Korn verkaufen',
    'sellCattle': 'Rinder verkaufen',
    'investShips': 'Handelsschiffe aussenden',
    'mergeRealms': 'Reiche zusammenlegen',
    // Original menu wording: "Truppe bilden" creates a unit; "Truppe
    // ausbilden" (the troop sheet, rules v7) drills quality +1.
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
