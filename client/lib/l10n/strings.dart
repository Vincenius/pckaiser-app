import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart' as gc;

import 'parts/events_strings.dart';
import 'parts/game_strings.dart';
import 'parts/menus_strings.dart';
import 'parts/misc_strings.dart';
import 'parts/online_strings.dart';
import 'parts/setup_strings.dart';
import 'parts/tutorial_strings.dart';
import 'parts/war_strings.dart';
import 'parts/whatsnew_strings.dart';

/// Active UI locale ('de' or 'en'). Set at startup by [SettingsService]
/// from the stored choice (default: the device language — German devices
/// get German, everything else English) and switched live from the
/// Options screen; `main.dart` rebuilds the whole app when it changes.
final ValueNotifier<String> appLocale = ValueNotifier('de');

/// The string table, merged from the core entries below plus one part
/// file per UI area (`parts/`). The German entries follow §23 of
/// ORIGINAL_GAME.md where a verbatim original string exists.
final Map<String, Map<String, String>> _table = {
  'en': {
    ..._coreEn,
    ...menusEn,
    ...eventsEn,
    ...warEn,
    ...gameEn,
    ...onlineEn,
    ...setupEn,
    ...miscEn,
    ...tutorialEn,
    ...whatsnewEn,
  },
  'de': {
    ..._coreDe,
    ...menusDe,
    ...eventsDe,
    ...warDe,
    ...gameDe,
    ...onlineDe,
    ...setupDe,
    ...miscDe,
    ...tutorialDe,
    ...whatsnewDe,
  },
};

const Map<String, String> _coreEn = {
  'appTitle': 'PCKaiser',
  'tagline': 'From knight to emperor — conquer the realm',
  'newGame': 'New game',
  'tutorial': 'Tutorial — learn the game',
  'online': 'Play online',
  'onlineGames': 'Online games',
  'onlineYourTurn': 'Your turn!',
  'onlineWaitingForPlayers': 'Waiting for players',
  // Active match, nobody awaited and no war pending (rare) — a neutral
  // line instead of the old, misleading "waiting for the other players".
  'onlineInProgress': 'Game in progress …',
  // Duel scheduling: the agreed start time is appended.
  'onlineWarScheduledPrefix': '⚔️ War agreed — begins: ',
  'onlineWarPending': '⚔️ War ahead — begins when the time runs out',
  // Suffixed to the awaited player's name: "Anna is taking her turn …"
  'onlineIsPlaying': 'is taking their turn …',
  'onlineLoading': 'Loading online games …',
  'onlineRoom': 'Room {id}',
  'savedGames': 'Saved games',
  'noSaves': 'No saved games yet.',
  'noSavesHint': 'Start a new game, or learn the basics in the tutorial.',
  'saveNeedsUpdate':
      'Saved with a newer app version — update the app to play it.',
  'slotSubtitlePlayers': '{n} players',
  'slotSubtitleYear': 'Anno {year}',
  'deleteSlotQuestion': 'Delete "{name}"?',
  'delete': 'Delete',
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
  'options': 'Options',
  'language': 'Language',
  'languageSystem': 'Device language',
  'languageSystemHint': 'German on German devices, otherwise English',
  'languageGerman': 'Deutsch',
  'languageEnglish': 'English',
  // Options ▸ Notifications (2026-08-24): the optional online pushes.
  // Everything not listed there — "your turn", a waiting decision, a match
  // about to be deleted — is always sent.
  'notifications': 'Notifications',
  'notificationsHint':
      'Optional messages for online games. Turn-of-play reminders are '
      'always sent.',
  'notifySyncFailed':
      'Could not reach the server — the change applies on the next launch.',
  'notify.war_started.title': 'Declaration of war',
  'notify.war_started.subtitle': 'Someone has declared war on you.',
  'notify.war_start_fixed.title': 'War appointment set',
  'notify.war_start_fixed.subtitle':
      'Both sides have chosen — the start time is fixed.',
  'notify.war_start_soon.title': 'Reminder before the war',
  'notify.war_start_soon.subtitle': 'About 15 minutes before an agreed start.',
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
  'taxes': 'Taxes',
  'chronicle': 'Kaiser chronicle',
  'gameOver': 'Victory!',
  'gameLost': 'Defeat!',
  'proposeMarriage': 'Propose marriage',
  'cancel': 'Cancel',
};

const Map<String, String> _coreDe = {
  'appTitle': 'PCKaiser',
  'tagline': 'Vom Ritter zum Kaiser — erobere das Reich',
  'newGame': 'Neues Spiel',
  'tutorial': 'Tutorial — das Spiel lernen',
  'online': 'Online spielen',
  'onlineGames': 'Online-Partien',
  'onlineYourTurn': 'Du bist am Zug !',
  'onlineWaitingForPlayers': 'Wartet auf Spieler',
  'onlineInProgress': 'Die Partie läuft …',
  'onlineWarScheduledPrefix': '⚔️ Krieg vereinbart — Beginn: ',
  'onlineWarPending': '⚔️ Krieg steht bevor — Beginn nach Ablauf der Frist',
  'onlineIsPlaying': 'ist am Zug …',
  'onlineLoading': 'Online-Partien werden geladen …',
  'onlineRoom': 'Raum {id}',
  'savedGames': 'Spielstände',
  'noSaves': 'Noch keine Spielstände.',
  'noSavesHint':
      'Starte ein neues Spiel — oder lerne die Grundlagen im Tutorial.',
  'saveNeedsUpdate':
      'Mit neuerer App-Version gespeichert — App aktualisieren, '
      'um weiterzuspielen.',
  'slotSubtitlePlayers': '{n} Spieler',
  'slotSubtitleYear': 'Anno {year}',
  'deleteSlotQuestion': '„{name}" löschen?',
  'delete': 'Löschen',
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
  'options': 'Optionen',
  'language': 'Sprache',
  'languageSystem': 'Gerätesprache',
  'languageSystemHint': 'Deutsch auf deutschen Geräten, sonst Englisch',
  'languageGerman': 'Deutsch',
  'languageEnglish': 'English',
  'notifications': 'Benachrichtigungen',
  'notificationsHint':
      'Optionale Meldungen für Online-Partien. Dass du am Zug bist, wird '
      'immer gemeldet.',
  'notifySyncFailed':
      'Server nicht erreichbar — die Änderung greift beim nächsten Start.',
  'notify.war_started.title': 'Kriegserklärung',
  'notify.war_started.subtitle': 'Jemand hat dir den Krieg erklärt.',
  'notify.war_start_fixed.title': 'Kriegstermin steht',
  'notify.war_start_fixed.subtitle':
      'Beide Seiten haben gewählt — der Beginn steht fest.',
  'notify.war_start_soon.title': 'Erinnerung vor dem Krieg',
  'notify.war_start_soon.subtitle':
      'Etwa 15 Minuten vor einem vereinbarten Beginn.',
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
  'taxes': 'Steuern',
  'chronicle': 'Kaiserchronik',
  'gameOver': 'Sieg!',
  'gameLost': 'Niederlage!',
  'proposeMarriage': 'Heirat vorschlagen',
  'cancel': 'Abbrechen',
};

/// Translated string for [key]; falls back to English, then the key.
/// Optional [params] replace `{name}`-style placeholders in the template:
/// `tr('deleteSlotQuestion', {'name': slot.name})`.
String tr(String key, [Map<String, Object?>? params]) {
  final template = _table[appLocale.value]?[key] ?? _table['en']![key] ?? key;
  // Shared placeholder substitution with the engine's coreMessage, so UI and
  // engine-produced strings format identically.
  return gc.formatTemplate(template, params);
}

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
