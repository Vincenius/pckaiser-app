import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../state/game_controller.dart';

/// In-war controls (§11.2): unit selection + movement via tile taps,
/// peace wish, end round — and the claim-settlement controls of a
/// limited victory.
class WarPanel extends StatelessWidget {
  const WarPanel({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final war = controller.state.activeWar;
    final slot = controller.warHumanSlot;
    if (war == null || slot == null) return const SizedBox.shrink();

    if (war.phase == gc.WarPhase.settlement) {
      return _settlement(context, war, slot);
    }

    final realm = controller.state.realm(slot);
    final moves = war.movesLeft[slot] ?? const <int>[];
    return Card(
      margin: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'KRIEG — ${gc.countryNames[war.attackerSlot]} vs '
            '${gc.countryNames[war.defenderSlot]} — Runde ${war.round + 1}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text('Tap a unit\'s neighbor tile to march; '
              '${war.wantsPeace(slot) ? "peace wished" : "fighting"}'),
          Wrap(spacing: 4, children: [
            for (var i = 0; i < realm.troops.length; i++)
              Chip(
                label: Text(
                    '${realm.troops[i].name}: ${realm.troops[i].men} '
                    '(${i < moves.length ? moves[i] : 0} mv)'),
              ),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
              onPressed: () => controller.applyWarAction(gc.WarPeaceWish(
                  slot: slot, wantsPeace: !war.wantsPeace(slot))),
              child: Text(war.wantsPeace(slot)
                  ? 'Withdraw peace wish'
                  : 'Wish for peace'),
            ),
            FilledButton(
              onPressed: () => controller.endWarRound(),
              child: const Text('End war round'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _settlement(BuildContext context, gc.ActiveWar war, int slot) {
    final isWinner = war.winnerSlot == slot;
    return Card(
      margin: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Anspruch: ${war.remainingClaim} Punkte',
              style: Theme.of(context).textTheme.titleSmall),
          const Text(
              'Alles zählt soviel, wie es kostet. Ein Markt zählt 2500 '
              'Punkte, eine Stadt 5000.'),
          if (isWinner)
            FilledButton(
              onPressed: () async {
                controller.applyWarAction(gc.SettlementFinish(slot: slot));
                await controller.endWarRound(); // resumes AI advance
              },
              child: const Text('Fertig — Rest in Talern'),
            ),
        ]),
      ),
    );
  }
}

/// Tile sheet during war: march a unit one step toward the tapped tile,
/// or plunder it (§11.5).
Future<void> showWarTileSheet(BuildContext context,
    GameController controller, int x, int y) async {
  final war = controller.state.activeWar;
  final slot = controller.warHumanSlot;
  if (war == null || slot == null) return;

  if (war.phase == gc.WarPhase.settlement) {
    if (war.winnerSlot != slot) return;
    try {
      controller.applyWarAction(gc.SettlementAnnex(slot: slot, x: x, y: y));
    } on gc.ActionException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    return;
  }

  final realm = controller.state.realm(slot);
  final options = <Widget>[];

  for (var i = 0; i < realm.troops.length; i++) {
    final troop = realm.troops[i];
    final dx = (x - troop.x).clamp(-1, 1);
    final dy = (y - troop.y).clamp(-1, 1);
    final adjacent = (x - troop.x).abs() + (y - troop.y).abs() == 1;
    if (adjacent && (dx == 0 || dy == 0)) {
      options.add(ListTile(
        leading: const Icon(Icons.arrow_forward),
        title: Text('March "${troop.name}" here'),
        onTap: () {
          Navigator.pop(context);
          try {
            controller.applyWarAction(
                gc.WarMove(slot: slot, unitIndex: i, dx: dx, dy: dy));
          } on gc.ActionException catch (e) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(e.message)));
          }
        },
      ));
    }
    if (troop.x == x && troop.y == y) {
      options.add(ListTile(
        leading: const Icon(Icons.local_fire_department),
        title: const Text('Plündern'),
        onTap: () {
          Navigator.pop(context);
          try {
            controller
                .applyWarAction(gc.WarPlunder(slot: slot, x: x, y: y));
          } on gc.ActionException catch (e) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(e.message)));
          }
        },
      ));
    }
  }
  if (options.isEmpty) return;

  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: options),
    ),
  );
}
