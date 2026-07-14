/// German display names for engine indices — the ONE label table shared
/// by every widget (tile sheet, war report, menus, decisions). The
/// previous per-widget copies had already drifted (one spelled a bare
/// tile '', another 'Feld').
library;

import 'package:game_core/game_core.dart' as gc;

const List<String> _buildingNames = [
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

/// Display name of a building type; a bare tile (Building.none) renders
/// as [empty] — 'Feld' in running text, '' where the caller shows terrain
/// instead.
String buildingName(int building, {String empty = ''}) {
  if (building == gc.Building.none) return empty;
  if (building < 0 || building >= _buildingNames.length) return '?';
  return _buildingNames[building];
}

/// Display names of the §10.1 troop classes, indexed by `gc.TroopClass.*`.
const List<String> troopClassNames = ['Infanterie', 'Kavallerie', 'Artillerie'];

String troopClassName(int troopClass) =>
    troopClassNames[troopClass.clamp(0, troopClassNames.length - 1)];
