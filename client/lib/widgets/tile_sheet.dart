import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/strings.dart';
import '../state/game_controller.dart';

const _buildingNames = [
  '', 'Kornfeld', 'Weide', 'Dorf', 'Markt', 'Stadt', 'Burg', 'Palast',
  'Hafen',
];

/// Tap-tile action sheet (PROJECT_REQUIREMENTS "Tap tile → action sheet"):
/// available builds/claims with inline costs; confirmation before
/// irreversible actions (demolish).
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

  void act(String label, String cost, gc.PlayerAction action,
      {bool confirm = false, bool undoable = true}) {
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
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('OK')),
              ],
            ),
          );
          if (sure != true) return;
        }
        try {
          undoable
              ? controller.applyUndoable(action)
              : controller.applyIrreversible(action);
        } on gc.ActionException catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
      },
    ));
  }

  final isLand = gc.Terrain.isLand(terrain);
  if (owner == gc.World.niemand && isLand) {
    act(tr('claimTile'), '1 MP', gc.ClaimTile(slot: slot, x: x, y: y));
  }

  if (owner == slot && building == gc.Building.none) {
    if (terrain == gc.Terrain.ebene) {
      act('Kornfeld', '100 T',
          gc.Build(slot: slot, x: x, y: y, building: gc.Building.kornfeld));
    }
    if (terrain == gc.Terrain.berg) {
      act('Weide', '150 T',
          gc.Build(slot: slot, x: x, y: y, building: gc.Building.weide));
    }
    if (isLand) {
      actions.add(ListTile(
        title: const Text('Dorf'),
        trailing: const Text('1000 T'),
        onTap: () async {
          Navigator.pop(context);
          final name = await _askTownName(context);
          if (name == null || name.isEmpty) return;
          try {
            controller.applyUndoable(gc.Build(
                slot: slot,
                x: x,
                y: y,
                building: gc.Building.dorf,
                townName: name));
          } on gc.ActionException catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(e.message)));
            }
          }
        },
      ));
      act('Burg', '5000 T',
          gc.Build(slot: slot, x: x, y: y, building: gc.Building.burg));
      act('Palast', '10000 T',
          gc.Build(slot: slot, x: x, y: y, building: gc.Building.palast));
    }
  }

  // Hafen: an unowned water tile next to own land.
  if (gc.Terrain.isWater(terrain) && owner == gc.World.niemand) {
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

  // Troop placement onto own tiles.
  if (owner == slot && realm.troops.isNotEmpty) {
    for (var i = 0; i < realm.troops.length; i++) {
      final troop = realm.troops[i];
      act('Move "${troop.name}" here (${troop.men})', '1 MP',
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
        ),
        const Divider(height: 1),
        if (actions.isEmpty)
          const ListTile(title: Text('No actions available here')),
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
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
}
