/// Display names for engine indices — the ONE label table shared by
/// every widget (tile sheet, war report, menus, decisions), localized
/// via [appLocale]. Engine state stays language-neutral (slot/type
/// indices); only these client-side labels switch with the UI language.
library;

import 'package:game_core/game_core.dart' as gc;

import 'strings.dart' show appLocale;

const List<String> _buildingNamesDe = [
  '', // Building.none — callers pass [empty] for running text
  'Kornfeld',
  'Weide',
  'Dorf',
  'Markt',
  'Stadt',
  'Burg',
  'Palast',
  'Hafen',
];

const List<String> _buildingNamesEn = [
  '', // Building.none
  'Grain field',
  'Pasture',
  'Village',
  'Market',
  'Town',
  'Castle',
  'Palace',
  'Harbor',
];

/// Display name of a building type; a bare tile (Building.none) renders
/// as [empty] — tr('bareTile') in running text, '' where the caller shows
/// terrain instead.
String buildingName(int building, {String empty = ''}) {
  final names = appLocale.value == 'de' ? _buildingNamesDe : _buildingNamesEn;
  if (building == gc.Building.none) return empty;
  if (building < 0 || building >= names.length) return '?';
  return names[building];
}

/// Display names of the §10.1 troop classes, indexed by `gc.TroopClass.*`.
const List<String> _troopClassNamesDe = [
  'Infanterie',
  'Kavallerie',
  'Artillerie',
];
const List<String> _troopClassNamesEn = ['Infantry', 'Cavalry', 'Artillery'];

String troopClassName(int troopClass) {
  final names =
      appLocale.value == 'de' ? _troopClassNamesDe : _troopClassNamesEn;
  return names[troopClass.clamp(0, names.length - 1)];
}

/// The single-letter badge for a troop class (map glyphs), derived from its
/// localized name so it tracks the active language — 'K'avallerie in German,
/// 'C'avalry in English — instead of a hardcoded German-initial table.
String troopClassInitial(int troopClass) =>
    troopClassName(troopClass).substring(0, 1).toUpperCase();

/// English names for the engine's §18 disease values (stored German in the
/// `personDied`/`disease` payloads). Unlisted names keep the German original.
const Map<String, String> _diseaseNamesEn = {
  'Pest': 'Plague',
  'Ruhr': 'Dysentery',
};

/// Display name for a stored §18 disease value (German in game state).
String diseaseName(String name) =>
    appLocale.value == 'de' ? name : (_diseaseNamesEn[name] ?? name);

/// Display name for a stored death cause (`personDied` payload): the code
/// 'age' or one of the engine's §18 disease names.
String deathCauseName(String cause) => cause == 'age'
    ? (appLocale.value == 'de' ? 'Altersschwäche' : 'old age')
    : diseaseName(cause);

/// English exonyms for `gc.countryNames` (same indices, §22.3). Names
/// without an established English form keep the German original.
const List<String> _countryNamesEn = [
  'Nobody',
  'Brandenburg',
  'Hesse',
  'Bavaria',
  'Bohemia',
  'Saxony',
  'Moravia',
  'Tyrol',
  'Palatinate',
  'Flanders',
  'Austria',
  'Styria',
  'Carinthia',
  'Carniola',
  'Gorizia',
  'Upper Palatinate',
  'Pomerania',
  'Mecklenburg',
  'Silesia',
  'Holstein',
  'Swabia',
  'Lorraine',
  'Isenburg',
  'Holland',
  'Frisia',
  'Luxembourg',
  'Liechtenstein',
  'Lüneburg',
  'Zweibrücken',
  'Oldenburg',
  'Brabant',
  'Ben Mohammed',
];

/// Localized realm name for a slot — use this instead of indexing
/// `gc.countryNames` directly anywhere the name is shown to the player.
String realmName(int slot) {
  if (slot < 0 || slot >= gc.countryNames.length) return '?';
  return appLocale.value == 'de' ? gc.countryNames[slot] : _countryNamesEn[slot];
}

/// Label for world-scope events (event feed rows without a realm slot).
String worldLabel() => appLocale.value == 'de' ? 'Welt' : 'World';

/// English forms of the §16.1 title ladders (`gc.maleTitles` /
/// `gc.femaleTitles`; female classes stored as `class + 12`).
const List<String> _maleTitlesEn = [
  '',
  'Knight',
  'Baron',
  'Count',
  'Prince',
  'Grand Prince',
  'Duke',
  'Archduke',
  'King',
  'Sheikh',
  'Pasha',
  'Emir',
  'Caliph',
];

const List<String> _femaleTitlesEn = [
  '',
  'Lady',
  'Baroness',
  'Countess',
  'Princess',
  'Grand Princess',
  'Duchess',
  'Archduchess',
  'Queen',
  'Sheikha',
  'Pasha',
  'Emira',
  'Calipha',
];

/// Localized display title for a title class — use this instead of
/// `gc.titleName` anywhere the title is shown to the player.
String titleName(int titleClass) {
  if (appLocale.value == 'de') return gc.titleName(titleClass);
  if (titleClass < 0 || titleClass > 24) return '?';
  return titleClass > 12
      ? _femaleTitlesEn[titleClass - 12]
      : _maleTitlesEn[titleClass];
}
