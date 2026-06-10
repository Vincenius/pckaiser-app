import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../state/game_controller.dart';

/// In-war controls (§11.2): unit selection (tap a unit on the map or its
/// chip here), march by tapping a target tile, plunder, peace wish, end
/// round — and the claim-settlement controls of a limited victory.
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

    final state = controller.state;
    final realm = state.realm(slot);
    final enemySlot = war.opponentOf(slot);
    final enemy = state.realm(enemySlot);
    final moves = war.movesLeft[slot] ?? const <int>[];
    final selected = controller.selectedWarUnit;
    final selectedTroop = selected != null && selected < realm.troops.length
        ? realm.troops[selected]
        : null;
    final canPlunder = selectedTroop != null &&
        !war.plunderedThisRound(slot) &&
        state.map.ownerAt(selectedTroop.x, selectedTroop.y) != slot &&
        state.map.buildingAt(selectedTroop.x, selectedTroop.y) !=
            gc.Building.none;

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
          Text(
            'Ziel: Königssitz von ${gc.countryNames[enemySlot]} bei '
            '(${enemy.capitalX + 1}, ${enemy.capitalY + 1}) — '
            'Punkte: ${gc.warScore(state, slot)} '
            'vs ${gc.warScore(state, enemySlot)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            selectedTroop == null
                ? 'Truppe antippen, dann das Ziel auf der Karte antippen'
                : '„${selectedTroop.name}" gewählt — Ziel antippen'
                    '${war.wantsPeace(slot) ? ' (Friedenswunsch geäußert)' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Wrap(spacing: 4, children: [
            for (var i = 0; i < realm.troops.length; i++)
              ChoiceChip(
                selected: i == selected,
                onSelected: (_) =>
                    controller.selectWarUnit(i == selected ? null : i),
                label: Text(
                    '${realm.troops[i].name}: ${realm.troops[i].men} '
                    '(${i < moves.length ? moves[i] : 0} Züge)'),
              ),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton.icon(
              onPressed: canPlunder
                  ? () {
                      try {
                        controller.applyWarAction(gc.WarPlunder(
                            slot: slot,
                            x: selectedTroop.x,
                            y: selectedTroop.y));
                      } on gc.ActionException catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.message)));
                      }
                    }
                  : null,
              icon: const Icon(Icons.local_fire_department),
              label: const Text('Plündern'),
            ),
            TextButton(
              onPressed: () => controller.applyWarAction(gc.WarPeaceWish(
                  slot: slot, wantsPeace: !war.wantsPeace(slot))),
              child: Text(war.wantsPeace(slot)
                  ? 'Friedenswunsch zurückziehen'
                  : 'Frieden wünschen'),
            ),
            FilledButton(
              onPressed: () => controller.endWarRound(),
              child: const Text('Runde beenden'),
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
              'Tippe auf Felder des Verlierers, um sie zu übernehmen. '
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
