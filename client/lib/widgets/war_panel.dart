import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../state/game_controller.dart';
import 'war_report.dart';

/// In-war controls (§11.2): unit selection (tap a unit on the map or its
/// chip here), march/attack by tapping a target on the map, plunder,
/// peace wish, end round — and the claim-settlement controls of a limited
/// victory. Battle and plunder results appear as report popups.
///
/// Collapsible so the map stays visible; the header always shows the
/// essentials (opponent, round, score).
class WarPanel extends StatefulWidget {
  const WarPanel({super.key, required this.controller});

  final GameController controller;

  @override
  State<WarPanel> createState() => _WarPanelState();
}

class _WarPanelState extends State<WarPanel> {
  bool _collapsed = false;

  GameController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final war = controller.state.activeWar;
    final slot = controller.warHumanSlot;
    if (war == null || slot == null) return const SizedBox.shrink();

    if (war.phase == gc.WarPhase.settlement) {
      return _settlement(context, war, slot);
    }

    final theme = Theme.of(context);
    final state = controller.state;
    final realm = state.realm(slot);
    final enemySlot = war.opponentOf(slot);
    final enemy = state.realm(enemySlot);
    final moves = war.movesLeft[slot] ?? const <int>[];
    final selected = controller.selectedWarUnit;
    final selectedTroop = selected != null && selected < realm.troops.length
        ? realm.troops[selected]
        : null;
    final myScore = gc.warScore(state, slot);
    final enemyScore = gc.warScore(state, enemySlot);
    // §11.2 AI peace rules, surfaced: when the AI opponent would say yes,
    // tell the player that wishing for peace actually ends the war.
    final enemyReady =
        state.dynasty(enemySlot).status != gc.DynastyStatus.human &&
            gc.aiWouldAcceptPeace(state, enemySlot);

    final header = Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.gavel, size: 18),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          'Krieg gegen ${gc.countryNames[enemySlot]}',
          style: theme.textTheme.titleSmall,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 8),
      Tooltip(
        message: 'Nach Runde 20 beendet der Winter den Krieg — dann '
            'entscheiden die Kriegspunkte.',
        child: Text('Runde ${war.round + 1}/20',
            style: theme.textTheme.labelSmall),
      ),
      if (_collapsed) ...[
        const SizedBox(width: 8),
        _scoreboard(theme, myScore, enemyScore, dense: true),
      ],
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: _collapsed ? 'Kriegsmenü öffnen' : 'Einklappen',
        icon: Icon(_collapsed ? Icons.expand_more : Icons.expand_less),
        onPressed: () => setState(() => _collapsed = !_collapsed),
      ),
    ]);

    return Card(
      margin: const EdgeInsets.all(8),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          header,
          if (!_collapsed) ...[
            _scoreboard(theme, myScore, enemyScore),
            const SizedBox(height: 2),
            _enemyArmyLine(theme, enemy),
            if (war.wantsPeace(slot) || enemyReady)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  enemyReady
                      ? 'Der Gegner ist friedensbereit ! „Frieden wünschen" '
                          'und „Runde beenden" beendet den Krieg ohne '
                          'Gebietsänderungen.'
                      : 'Friedenswunsch geäußert — der Gegner muss '
                          'zustimmen.',
                  style: theme.textTheme.bodySmall!.copyWith(
                      color: enemyReady
                          ? Colors.green.shade800
                          : theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              selectedTroop == null
                  ? 'Tippe eine deiner Truppen an, um sie zu befehligen.'
                  : '„${selectedTroop.name}" gewählt — tippe ein Ziel auf '
                      'der Karte: feindliche Armee = Angriff, Königssitz '
                      '(rotes Fadenkreuz) = Sieg.',
              style: theme.textTheme.bodySmall!
                  .copyWith(fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: -8, children: [
              for (var i = 0; i < realm.troops.length; i++)
                _unitChip(theme, state, realm.troops[i], enemySlot,
                    movesLeft: i < moves.length ? moves[i] : 0,
                    selected: i == selected,
                    onTap: () =>
                        controller.selectWarUnit(i == selected ? null : i)),
            ]),
            _actions(context, war, slot, selectedTroop, enemySlot),
          ],
        ]),
      ),
    );
  }

  Widget _scoreboard(ThemeData theme, int mine, int enemy,
      {bool dense = false}) {
    final lead = mine > enemy
        ? Colors.green.shade800
        : mine < enemy
            ? theme.colorScheme.error
            : null;
    final text = Text(
      dense ? '$mine — $enemy' : 'Kriegspunkte: Du $mine — $enemy Gegner',
      style: (dense ? theme.textTheme.labelSmall : theme.textTheme.bodySmall)!
          .copyWith(color: lead, fontWeight: FontWeight.w600),
    );
    if (dense) return text;
    return Tooltip(
      message: 'Punkte gibt es für Truppen auf feindlichen Feldern '
          '(je wertvoller das Feld, desto mehr) — sie entscheiden den '
          'Krieg, wenn der Winter kommt.',
      child: text,
    );
  }

  /// During a war both sides see each other's units (visibility rules) —
  /// summarize the enemy army so the player can judge peace vs. press on.
  Widget _enemyArmyLine(ThemeData theme, gc.Realm enemy) {
    final men = enemy.troops.fold(0, (a, t) => a + t.men);
    final strength =
        enemy.troops.fold(0.0, (a, t) => a + gc.troopStrength(t)).round();
    return Text(
      enemy.troops.isEmpty
          ? 'Das feindliche Heer ist vernichtet !'
          : 'Feindliches Heer: ${enemy.troops.length} '
              'Truppe${enemy.troops.length == 1 ? '' : 'n'} · $men Mann · '
              '⚔ $strength',
      style: theme.textTheme.bodySmall!.copyWith(
          fontWeight: enemy.troops.isEmpty ? FontWeight.w600 : null,
          color: enemy.troops.isEmpty ? Colors.green.shade800 : null),
    );
  }

  Widget _unitChip(ThemeData theme, gc.GameState state, gc.Troop troop,
      int enemySlot,
      {required int movesLeft,
      required bool selected,
      required VoidCallback onTap}) {
    final onEnemyLand =
        state.map.ownerAt(troop.x, troop.y) == enemySlot;
    return Tooltip(
      message: 'Verbleibende Züge: $movesLeft'
          '${onEnemyLand ? ' — besetzt feindliches Gebiet (zählt Punkte)' : ''}',
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        avatar: CircleAvatar(
          backgroundColor: movesLeft > 0
              ? theme.colorScheme.surface
              : theme.colorScheme.surfaceContainerHighest,
          child: Text('$movesLeft', style: theme.textTheme.labelSmall),
        ),
        onSelected: (_) => onTap(),
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          if (onEnemyLand)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(Icons.flag,
                  size: 14, color: Colors.green.shade800),
            ),
          Text('${troop.name} · ${troop.men} Mann · '
              '⚔ ${gc.troopStrength(troop).round()}'),
        ]),
      ),
    );
  }

  Widget _actions(BuildContext context, gc.ActiveWar war, int slot,
      gc.Troop? selectedTroop, int enemySlot) {
    final state = controller.state;
    // Rules v2: only the war opponent may be plundered (engine gate).
    final plunderVictimOk = selectedTroop != null &&
        (state.rulesVersion >= 2
            ? state.map.ownerAt(selectedTroop.x, selectedTroop.y) ==
                enemySlot
            : state.map.ownerAt(selectedTroop.x, selectedTroop.y) != slot);
    final canPlunder = selectedTroop != null &&
        !war.plunderedThisRound(slot) &&
        plunderVictimOk &&
        state.map.buildingAt(selectedTroop.x, selectedTroop.y) !=
            gc.Building.none;
    final plunderHint = selectedTroop == null
        ? 'Erst eine Truppe wählen'
        : war.plunderedThisRound(slot)
            ? 'In dieser Runde schon geplündert'
            : !plunderVictimOk
                ? 'Die Truppe muss auf feindlichem Gebiet stehen'
                : state.map.buildingAt(
                            selectedTroop.x, selectedTroop.y) ==
                        gc.Building.none
                    ? 'Hier steht nichts zum Plündern'
                    : 'Bebautes feindliches Feld plündern';

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Tooltip(
        message: plunderHint,
        child: TextButton.icon(
          onPressed: canPlunder
              ? () async {
                  final List<gc.GameEvent> events;
                  try {
                    events = controller
                        .applyWarAction(gc.WarPlunder(
                            slot: slot,
                            x: selectedTroop.x,
                            y: selectedTroop.y))
                        .events;
                  } on gc.ActionException catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.message)));
                    return;
                  }
                  await showWarReport(context, events,
                      viewerSlot: slot, title: 'Plünderung');
                }
              : null,
          icon: const Icon(Icons.local_fire_department),
          label: const Text('Plündern'),
        ),
      ),
      TextButton(
        onPressed: () => controller.applyWarAction(gc.WarPeaceWish(
            slot: slot, wantsPeace: !war.wantsPeace(slot))),
        child: Text(war.wantsPeace(slot)
            ? 'Frieden zurückziehen'
            : 'Frieden wünschen'),
      ),
      FilledButton(
        onPressed: () async {
          final events = await controller.endWarRound();
          if (context.mounted) {
            await showWarReport(context, events,
                viewerSlot: slot, title: 'Rundenbericht');
          }
        },
        child: const Text('Runde beenden'),
      ),
    ]);
  }

  Widget _settlement(BuildContext context, gc.ActiveWar war, int slot) {
    final isWinner = war.winnerSlot == slot;
    final bareLandNote =
        controller.state.rulesVersion >= 2 ? ', leeres Land 100' : '';
    return Card(
      margin: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              isWinner
                  ? 'Sieg ! Dein Anspruch: ${war.remainingClaim} Punkte'
                  : 'Niederlage — der Sieger teilt das Land auf',
              style: Theme.of(context).textTheme.titleSmall),
          Text(
              isWinner
                  ? 'Wähle deine Beute: Tippe Felder des Verlierers an, '
                      'die an dein Land grenzen, um sie zu übernehmen. '
                      'Jedes Feld kostet seinen Wert (Markt 2500, Stadt '
                      '5000$bareLandNote). Der nicht genutzte Rest wird '
                      'in Talern ausgezahlt.'
                  : 'Anspruch des Siegers: ${war.remainingClaim} Punkte.',
              textAlign: TextAlign.center),
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
