import 'package:flutter/foundation.dart';

/// Minimal string table — English default, German optional
/// (PROJECT_REQUIREMENTS). The German entries follow §23 of
/// ORIGINAL_GAME.md where a verbatim original string exists.
final ValueNotifier<String> appLocale = ValueNotifier('en');

const Map<String, Map<String, String>> _table = {
  'en': {
    'appTitle': 'PC Kaiser',
    'newGame': 'New game',
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
    'claimTile': 'Claim tile',
    'demolish': 'Demolish (100 T)',
    'handoff': 'Hand the device to',
    'yourTurn': 'Begin turn',
    'warDeclared': 'War declared!',
    'sellGrain': 'Sell grain',
    'sellCattle': 'Sell cattle',
    'investShips': 'Trade-ship investment',
    'mergeRealms': 'Merge realms',
    'recruit': 'Recruit troops',
    'hireSoeldner': 'Hire Söldner',
    'declareWar': 'Declare war',
    'guards': 'Guards',
    'chronicle': 'Chronicle',
    'gameOver': 'Victory!',
  },
  'de': {
    'appTitle': 'PC Kaiser',
    'newGame': 'Neues Spiel',
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
    'claimTile': 'Feld beanspruchen',
    'demolish': 'Abreißen (100 T)',
    'handoff': 'Gerät weitergeben an',
    'yourTurn': 'Zug beginnen',
    'warDeclared': 'Krieg erklärt!',
    'sellGrain': 'Korn verkaufen',
    'sellCattle': 'Rinder verkaufen',
    'investShips': 'Schiffsbeteiligung',
    'mergeRealms': 'Reiche zusammenlegen',
    'recruit': 'Truppe ausbilden',
    'hireSoeldner': 'Söldner anwerben',
    'declareWar': 'Krieg erklären',
    'guards': 'Spionageabwehr',
    'chronicle': 'Urkunde',
    'gameOver': 'Sieg!',
  },
};

/// Translated string for [key]; falls back to English, then the key.
String tr(String key) =>
    _table[appLocale.value]?[key] ?? _table['en']![key] ?? key;
