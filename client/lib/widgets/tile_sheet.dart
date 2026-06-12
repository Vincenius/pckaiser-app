import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/strings.dart';
import '../state/game_controller.dart';
import 'menus.dart' show showTroopActions;

const _buildingNames = [
  '',
  'Kornfeld',
  'Weide',
  'Dorf',
  'Markt',
  'Stadt',
  'Burg',
  'Palast',
  'Hafen',
];

bool _adjacentToOwn(gc.WorldMap map, int slot, int x, int y) {
  for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
    if (map.inBounds(x + dx, y + dy) && map.ownerAt(x + dx, y + dy) == slot) {
      return true;
    }
  }
  return false;
}

/// Tap-tile action sheet (PROJECT_REQUIREMENTS "Tap tile → action sheet"):
/// available builds with inline costs; confirmation before irreversible
/// actions (demolish). Tapping an unowned tile next to own territory shows
/// the build menu directly — the claim happens implicitly with the build.
Future<void> showTileActionSheet(
  BuildContext context,
  GameController controller,
  int x,
  int y,
) async {
  final state = controller.visibleState;
  final map = state.map;
  final slot = controller.currentSlot;
  final realm = controller.currentRealm;
  final owner = map.ownerAt(x, y);
  final building = map.buildingAt(x, y);
  final terrain = map.terrainAt(x, y);

  final actions = <Widget>[];

  void toastError(gc.ActionException e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> run(gc.PlayerAction action, {bool undoable = true}) async {
    try {
      undoable
          ? controller.applyUndoable(action)
          : controller.applyIrreversible(action);
    } on gc.ActionException catch (e) {
      toastError(e);
    }
  }

  void act(
    String label,
    String cost,
    gc.PlayerAction action, {
    bool confirm = false,
  }) {
    actions.add(
      ListTile(
        title: Text(label),
        trailing: Text(cost),
        onTap: () async {
          Navigator.pop(context);
          if (confirm) {
            final sure = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('$label?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(tr('cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
            if (sure != true) return;
          }
          await run(action);
        },
      ),
    );
  }

  final isLand = gc.Terrain.isLand(terrain);
  // The build menu: on own empty tiles directly, on unowned adjacent land
  // with an implicit claim (game_core claims as part of the build). Only
  // buildings the treasury can pay for are offered, and only while a
  // movement point is left (every build costs exactly 1).
  final hasMoves = realm.movementPoints >= 1;
  final expandable =
      owner == gc.World.niemand &&
      isLand &&
      hasMoves &&
      _adjacentToOwn(map, slot, x, y);
  final buildable =
      owner == slot && building == gc.Building.none && isLand && hasMoves;
  final money = realm.treasury;

  if (buildable || expandable) {
    if (terrain == gc.Terrain.ebene && money >= 100) {
      act(
        'Kornfeld',
        '100 T',
        gc.Build(slot: slot, x: x, y: y, building: gc.Building.kornfeld),
      );
    }
    if (money >= 150) {
      act(
        'Weide',
        '150 T',
        gc.Build(slot: slot, x: x, y: y, building: gc.Building.weide),
      );
    }
    if (money >= 1000) {
      actions.add(
        ListTile(
          title: const Text('Dorf'),
          trailing: const Text('1000 T'),
          onTap: () async {
            Navigator.pop(context);
            final name = await _askTownName(context);
            if (name == null || name.isEmpty) return;
            // Founding a Dorf rolls its starting population — randomized
            // actions clear the undo stack (PROJECT_REQUIREMENTS).
            await run(
              gc.Build(
                slot: slot,
                x: x,
                y: y,
                building: gc.Building.dorf,
                townName: name,
              ),
              undoable: false,
            );
          },
        ),
      );
    }
    if (money >= 5000) {
      act(
        'Burg',
        '5000 T',
        gc.Build(slot: slot, x: x, y: y, building: gc.Building.burg),
      );
    }
    if (money >= 10000) {
      act(
        'Palast',
        '10000 T',
        gc.Build(slot: slot, x: x, y: y, building: gc.Building.palast),
      );
    }
  }

  // Hafen: an unowned water tile next to own land.
  if (gc.Terrain.isWater(terrain) &&
      owner == gc.World.niemand &&
      hasMoves &&
      money >= 700) {
    act(
      'Hafen',
      '700 T',
      gc.Build(slot: slot, x: x, y: y, building: gc.Building.hafen),
    );
  }

  // Colony ships: buy at an own Hafen, steer over water (1 Zug per
  // tile), colonize a free coastal tile into a Dorf.
  if (owner == slot && building == gc.Building.hafen) {
    actions.add(
      ListTile(
        leading: const Icon(Icons.sailing),
        title: const Text('Schiff kaufen'),
        trailing: const Text('700 T'),
        subtitle: Text(
          !hasMoves
              ? 'Du hast keine Züge mehr !'
              : money < gc.Building.shipCost
              ? 'Du hast nicht genügend Taler !'
              : 'Das Schiff geht hier im Hafen vor Anker — tippe es '
                    'danach an, um es zu steuern',
        ),
        enabled: hasMoves && money >= gc.Building.shipCost,
        onTap: () async {
          Navigator.pop(context);
          await run(gc.BuyShip(slot: slot, x: x, y: y));
        },
      ),
    );
  }

  // Own ship on the tapped tile: steer it. The voyage costs 1 Zug per
  // water tile of the shortest sea route (engine-validated).
  for (var i = 0; i < realm.ships.length; i++) {
    final ship = realm.ships[i];
    if (ship.x != x || ship.y != y) continue;
    final shipIndex = i;
    actions.add(
      ListTile(
        leading: const Icon(Icons.sailing),
        title: const Text('Schiff steuern'),
        subtitle: const Text(
          '1 Zug pro Wasserfeld — ein freies Landfeld '
          'als Ziel gründet dort ein Dorf',
        ),
        enabled: hasMoves,
        onTap: () {
          Navigator.pop(context);
          controller.startTilePick(
            hint:
                'Schiff steuern: Wasserfeld antippen (1 Zug pro Feld) '
                '— ein freies Landfeld wird kolonisiert',
            onPick: (px, py) =>
                _steerShip(context, controller, slot, shipIndex, px, py),
          );
        },
      ),
    );
  }

  // Free land tile next to one of the own ships: found the colony.
  if (owner == gc.World.niemand && isLand && building == gc.Building.none) {
    final shipIndex = realm.ships.indexWhere(
      (s) => (s.x - x).abs() + (s.y - y).abs() == 1,
    );
    if (shipIndex >= 0) {
      actions.add(
        ListTile(
          leading: const Icon(Icons.flag),
          title: const Text('Kolonisieren — Dorf gründen'),
          subtitle: Text(
            hasMoves
                ? 'Das Schiff wird dabei aufgelöst — die Siedler bleiben'
                : 'Du hast keine Züge mehr !',
          ),
          enabled: hasMoves,
          onTap: () async {
            Navigator.pop(context);
            final name = await _askTownName(context);
            if (name == null || name.isEmpty) return;
            // Founding rolls the starting population — randomized
            // actions clear the undo stack (PROJECT_REQUIREMENTS).
            await run(
              gc.ColonizeShip(
                slot: slot,
                shipIndex: shipIndex,
                x: x,
                y: y,
                townName: name,
              ),
              undoable: false,
            );
          },
        ),
      );
    }
  }
  if (owner == slot &&
      building != gc.Building.none &&
      building != gc.Building.dorf &&
      building != gc.Building.markt &&
      building != gc.Building.stadt) {
    act(
      tr('demolish'),
      '100 T',
      gc.Demolish(slot: slot, x: x, y: y),
      confirm: true,
    );
  }

  // Armies standing on the tapped tile: info & edit sheet.
  if (owner == slot) {
    for (var i = 0; i < realm.troops.length; i++) {
      final troop = realm.troops[i];
      if (troop.x != x || troop.y != y) continue;
      actions.add(
        ListTile(
          leading: const Icon(Icons.groups_2),
          title: Text('„${troop.name}" — ${troop.men} Mann'),
          subtitle: const Text('Info, Verlegen & Bearbeiten'),
          onTap: () {
            Navigator.pop(context);
            showTroopActions(context, controller, i);
          },
        ),
      );
    }
  }

  // Spied enemy units on this tile (newest military intel per target):
  // a snapshot from the spy year, matching the map's ghost badges.
  const classNames = ['Infanterie', 'Kavallerie', 'Artillerie'];
  final newestIntel = <int, gc.IntelReport>{};
  for (final report in realm.intelReports) {
    if (report.values.containsKey('unitCount')) {
      newestIntel[report.targetSlot] = report; // reports are in order
    }
  }
  for (final report in newestIntel.values) {
    final units = report.values['unitCount'] ?? 0;
    for (var i = 0; i < units; i++) {
      if (report.values['unit${i}X'] != x || report.values['unit${i}Y'] != y) {
        continue;
      }
      final men = report.values['unit${i}Men'];
      final cls = report.values['unit${i}Class'] ?? 0;
      actions.add(
        ListTile(
          leading: const Icon(Icons.visibility),
          title: Text(
            'Spionage: Armee von '
            '${gc.countryNames[report.targetSlot]}',
          ),
          subtitle: Text(
            '~${men ?? '?'} Mann ${classNames[cls.clamp(0, 2)]} — '
            'Stand Anno ${report.year}',
          ),
        ),
      );
    }
  }

  final ownerLine = owner == gc.World.niemand
      ? 'Niemand'
      : gc.countryNames[owner];
  final town = owner != gc.World.niemand
      ? state.realm(owner).towns.where((t) => t.x == x && t.y == y).toList()
      : const <gc.Town>[];

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              '(${x + 1}, ${y + 1}) — ${terrain == gc.Terrain.ebene
                  ? 'Ebene'
                  : terrain == gc.Terrain.berg
                  ? 'Berg'
                  : 'Wasser'}'
              '${building == gc.Building.none ? '' : ' — ${_buildingNames[building]}'}',
            ),
            subtitle: Text(
              town.isNotEmpty ? '$ownerLine — ${town.first.name}' : ownerLine,
            ),
            trailing: Text(
              '${realm.treasury} T\nnoch ${realm.movementPoints} Züge',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const Divider(height: 1),
          if (actions.isEmpty)
            ListTile(
              title: Text(
                !hasMoves
                    ? 'Du hast keine Züge mehr !'
                    : (buildable || expandable) && money < 100
                    ? 'Du hast nicht genügend Taler !'
                    : 'Hier ist keine Aktion möglich',
              ),
            ),
          ...actions,
        ],
      ),
    ),
  );
}

/// Tile-pick handler for "Schiff steuern": a water target sails the ship
/// there; a FREE land target colonizes it in one flow — the ship sails to
/// the nearest water tile beside the target and founds the Dorf (the
/// separate "move, then tap the coast" dance is no longer needed).
/// Returns false to keep the pick active on an invalid target.
bool _steerShip(
  BuildContext context,
  GameController controller,
  int slot,
  int shipIndex,
  int x,
  int y,
) {
  void toast(String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  final map = controller.visibleState.map;
  if (map.isWaterAt(x, y)) {
    try {
      controller.applyUndoable(
        gc.MoveShip(slot: slot, shipIndex: shipIndex, x: x, y: y),
      );
      return true;
    } on gc.ActionException catch (e) {
      toast(e.message);
      return false;
    }
  }

  if (map.ownerAt(x, y) != gc.World.niemand ||
      map.buildingAt(x, y) != gc.Building.none) {
    toast(
      'Schiffe fahren nur auf dem Wasser — oder kolonisieren ein '
      'freies Landfeld !',
    );
    return false;
  }

  final realm = controller.currentRealm;
  final ship = realm.ships[shipIndex];
  // Nearest water tile orthogonally beside the colony site.
  var distance = -1;
  var anchorX = 0;
  var anchorY = 0;
  for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
    final wx = x + dx;
    final wy = y + dy;
    if (!map.inBounds(wx, wy) || !map.isWaterAt(wx, wy)) continue;
    final d = map.waterPathLength(ship.x, ship.y, wx, wy);
    if (d >= 0 && (distance < 0 || d < distance)) {
      distance = d;
      anchorX = wx;
      anchorY = wy;
    }
  }
  if (distance < 0) {
    toast('Dieses Feld ist über See nicht erreichbar !');
    return false;
  }
  final needed = distance + 1; // the voyage plus the founding Zug
  if (realm.movementPoints < needed) {
    toast(
      'Fahrt und Dorfgründung kosten $needed Züge — so viele hast '
      'du nicht mehr !',
    );
    return false;
  }

  // Accept the pick; name dialog and founding continue asynchronously.
  () async {
    final name = await _askTownName(context);
    if (name == null || name.isEmpty) return;
    try {
      if (distance > 0) {
        controller.applyIrreversible(
          gc.MoveShip(slot: slot, shipIndex: shipIndex, x: anchorX, y: anchorY),
        );
      }
      // Founding rolls the starting population — randomized actions
      // clear the undo stack (PROJECT_REQUIREMENTS).
      controller.applyIrreversible(
        gc.ColonizeShip(
          slot: slot,
          shipIndex: shipIndex,
          x: x,
          y: y,
          townName: name,
        ),
      );
    } on gc.ActionException catch (e) {
      toast(e.message);
    }
  }();
  return true;
}

Future<String?> _askTownName(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Wie soll dein Dorf heißen?'),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
