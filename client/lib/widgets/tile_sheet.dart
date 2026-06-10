import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/strings.dart';
import '../state/game_controller.dart';
import 'menus.dart' show showTroopActions;

const _buildingNames = [
  '', 'Kornfeld', 'Weide', 'Dorf', 'Markt', 'Stadt', 'Burg', 'Palast',
  'Hafen',
];

bool _adjacentToOwn(gc.WorldMap map, int slot, int x, int y) {
  for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
    if (map.inBounds(x + dx, y + dy) &&
        map.ownerAt(x + dx, y + dy) == slot) {
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
    BuildContext context, GameController controller, int x, int y) async {
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> run(gc.PlayerAction action) async {
    try {
      controller.applyUndoable(action);
    } on gc.ActionException catch (e) {
      toastError(e);
    }
  }

  void act(String label, String cost, gc.PlayerAction action,
      {bool confirm = false}) {
    actions.add(ListTile(
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
                    child: Text(tr('cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('OK')),
              ],
            ),
          );
          if (sure != true) return;
        }
        await run(action);
      },
    ));
  }

  final isLand = gc.Terrain.isLand(terrain);
  // The build menu: on own empty tiles directly, on unowned adjacent land
  // with an implicit claim (game_core claims as part of the build). Only
  // buildings the treasury can pay for are offered, and only while a
  // movement point is left (every build costs exactly 1).
  final hasMoves = realm.movementPoints >= 1;
  final expandable = owner == gc.World.niemand &&
      isLand &&
      hasMoves &&
      _adjacentToOwn(map, slot, x, y);
  final buildable =
      owner == slot && building == gc.Building.none && isLand && hasMoves;
  final money = realm.treasury;

  if (buildable || expandable) {
    if (terrain == gc.Terrain.ebene && money >= 100) {
      act('Kornfeld', '100 T',
          gc.Build(slot: slot, x: x, y: y, building: gc.Building.kornfeld));
    }
    if (money >= 150) {
      act('Weide', '150 T',
          gc.Build(slot: slot, x: x, y: y, building: gc.Building.weide));
    }
    if (money >= 1000) {
      actions.add(ListTile(
        title: const Text('Dorf'),
        trailing: const Text('1000 T'),
        onTap: () async {
          Navigator.pop(context);
          final name = await _askTownName(context);
          if (name == null || name.isEmpty) return;
          await run(gc.Build(
              slot: slot,
              x: x,
              y: y,
              building: gc.Building.dorf,
              townName: name));
        },
      ));
    }
    if (money >= 5000) {
      act('Burg', '5000 T',
          gc.Build(slot: slot, x: x, y: y, building: gc.Building.burg));
    }
    if (money >= 10000) {
      act('Palast', '10000 T',
          gc.Build(slot: slot, x: x, y: y, building: gc.Building.palast));
    }
  }

  // Hafen: an unowned water tile next to own land.
  if (gc.Terrain.isWater(terrain) &&
      owner == gc.World.niemand &&
      hasMoves &&
      money >= 700) {
    act('Hafen', '700 T',
        gc.Build(slot: slot, x: x, y: y, building: gc.Building.hafen));
  }

  if (owner == slot &&
      building != gc.Building.none &&
      building != gc.Building.dorf &&
      building != gc.Building.markt &&
      building != gc.Building.stadt) {
    act(tr('demolish'), '100 T', gc.Demolish(slot: slot, x: x, y: y),
        confirm: true);
  }

  // Armies standing on the tapped tile: info & edit sheet.
  if (owner == slot) {
    for (var i = 0; i < realm.troops.length; i++) {
      final troop = realm.troops[i];
      if (troop.x != x || troop.y != y) continue;
      actions.add(ListTile(
        leading: const Icon(Icons.groups_2),
        title: Text('„${troop.name}" — ${troop.men} Mann'),
        subtitle: const Text('Info & Bearbeiten'),
        onTap: () {
          Navigator.pop(context);
          showTroopActions(context, controller, i);
        },
      ));
    }
  }

  // Troop placement onto own tiles — costs 1 movement point like a build.
  if (owner == slot && realm.troops.isNotEmpty && hasMoves) {
    for (var i = 0; i < realm.troops.length; i++) {
      final troop = realm.troops[i];
      if (troop.x == x && troop.y == y) continue; // already here
      act('„${troop.name}" hierher ziehen (${troop.men})', '1 MP',
          gc.MoveTroop(slot: slot, unitIndex: i, x: x, y: y));
    }
  }

  final ownerLine = owner == gc.World.niemand
      ? 'Niemand'
      : gc.countryNames[owner];
  final town = owner != gc.World.niemand
      ? state
          .realm(owner)
          .towns
          .where((t) => t.x == x && t.y == y)
          .toList()
      : const <gc.Town>[];

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text(
              '(${x + 1}, ${y + 1}) — ${terrain == gc.Terrain.ebene ? 'Ebene' : terrain == gc.Terrain.berg ? 'Berg' : 'Wasser'}'
              '${building == gc.Building.none ? '' : ' — ${_buildingNames[building]}'}'),
          subtitle: Text(town.isNotEmpty
              ? '$ownerLine — ${town.first.name}'
              : ownerLine),
          trailing: Text(
            '${realm.treasury} T\nnoch ${realm.movementPoints} Züge',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        const Divider(height: 1),
        if (actions.isEmpty)
          ListTile(
              title: Text(!hasMoves
                  ? 'Sie haben keine Züge mehr !'
                  : (buildable || expandable) && money < 100
                      ? 'Sie haben nicht genügend Taler !'
                      : 'Hier ist keine Aktion möglich')),
        ...actions,
      ]),
    ),
  );
}

Future<String?> _askTownName(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Wie soll Ihr Dorf heißen?'),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel'))),
        FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
}
