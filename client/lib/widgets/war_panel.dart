import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../state/game_controller.dart';
import 'decisions.dart' show promptDecisionsFor;
import 'war_report.dart';

/// In-war controls (§11.2): unit selection (tap a unit on the map or its
/// chip here), march/attack by tapping a target on the map, plunder,
/// peace wish, end round — and the claim-settlement controls of a limited
/// victory. Battle and plunder results appear as report popups.
///
/// Collapsible so the map stays visible; the header always shows the
/// essentials (opponent, round).
class WarPanel extends StatefulWidget {
  const WarPanel({super.key, required this.controller});

  final GameController controller;

  @override
  State<WarPanel> createState() => _WarPanelState();
}

class _WarPanelState extends State<WarPanel> {
  bool _collapsed = false;
  bool _settlementCollapsed = false;

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
    final enemyHuman =
        state.dynasty(enemySlot).status == gc.DynastyStatus.human;
    // §11.2 AI peace rules, surfaced: when the AI opponent would say yes,
    // tell the player that wishing for peace actually ends the war. A
    // human opponent's explicit peace wish is visible to both combatants
    // and surfaced the same way.
    final enemyReady = enemyHuman
        ? war.wantsPeace(enemySlot)
        : gc.aiWouldAcceptPeace(state, enemySlot);
    // Capital occupation decides the war at round end — but only when
    // held through the enemy's full response round (the first round end
    // merely ARMS it, war.heldCapitalSlot).
    final occupier = gc.capitalOccupier(state, war);
    final sealsNextRoundEnd =
        occupier != null &&
        (war.heldCapitalSlot == occupier ||
            state.realm(war.opponentOf(occupier)).troops.isEmpty);
    final String? capitalNote = occupier == slot
        ? (sealsNextRoundEnd
              ? 'Deine Armee hält den gegnerischen Königssitz ! '
                    '„Runde beenden" besiegelt den Sieg — halte das Feld '
                    'bis dahin.'
              : 'Deine Armee hält den gegnerischen Königssitz ! Übersteht '
                    'sie dort die nächste Runde, besiegelt das Rundenende '
                    'den Sieg.')
        : occupier == enemySlot
        ? 'Der Feind hält deinen Königssitz ! Erobere das Feld '
              'zurück — sonst ist der Krieg verloren.'
        : null;

    final header = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
          message:
              'Nach Runde 20 beendet der Winter den Krieg — dann '
              'entscheidet, wer mehr (und wertvolleres) feindliches '
              'Gebiet besetzt hält.',
          child: Text(
            'Runde ${war.round + 1}/20',
            style: theme.textTheme.labelSmall,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: _collapsed ? 'Kriegsmenü öffnen' : 'Einklappen',
          icon: Icon(_collapsed ? Icons.expand_more : Icons.expand_less),
          onPressed: () => setState(() => _collapsed = !_collapsed),
        ),
      ],
    );

    return Card(
      margin: const EdgeInsets.all(8),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            if (!_collapsed) ...[
              _enemyArmyLine(theme, enemy),
              if (capitalNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    capitalNote,
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: occupier == slot
                          ? Colors.green.shade800
                          : theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
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
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: -8,
                children: [
                  for (var i = 0; i < realm.troops.length; i++)
                    _unitChip(
                      theme,
                      state,
                      realm.troops[i],
                      enemySlot,
                      movesLeft: i < moves.length ? moves[i] : 0,
                      selected: i == selected,
                      onTap: () =>
                          controller.selectWarUnit(i == selected ? null : i),
                    ),
                ],
              ),
              _actions(context, war, slot, selectedTroop, enemySlot),
            ],
          ],
        ),
      ),
    );
  }

  /// During a war both sides see each other's units (visibility rules) —
  /// summarize the enemy army so the player can judge peace vs. press on.
  Widget _enemyArmyLine(ThemeData theme, gc.Realm enemy) {
    final men = enemy.troops.fold(0, (a, t) => a + t.men);
    final strength = enemy.troops
        .fold(0.0, (a, t) => a + gc.troopStrength(t))
        .round();
    return Text(
      enemy.troops.isEmpty
          ? 'Das feindliche Heer ist vernichtet !'
          : 'Feindliches Heer: ${enemy.troops.length} '
                'Truppe${enemy.troops.length == 1 ? '' : 'n'} · $men Mann · '
                '⚔ $strength',
      style: theme.textTheme.bodySmall!.copyWith(
        fontWeight: enemy.troops.isEmpty ? FontWeight.w600 : null,
        color: enemy.troops.isEmpty ? Colors.green.shade800 : null,
      ),
    );
  }

  Widget _unitChip(
    ThemeData theme,
    gc.GameState state,
    gc.Troop troop,
    int enemySlot, {
    required int movesLeft,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final onEnemyLand = state.map.ownerAt(troop.x, troop.y) == enemySlot;
    return Tooltip(
      message:
          'Verbleibende Züge: $movesLeft'
          '${onEnemyLand ? ' — besetzt feindliches Gebiet' : ''}',
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
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEnemyLand)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(Icons.flag, size: 14, color: Colors.green.shade800),
              ),
            Text(
              '${troop.name} · ${troop.men} Mann · '
              '⚔ ${gc.troopStrength(troop).round()}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions(
    BuildContext context,
    gc.ActiveWar war,
    int slot,
    gc.Troop? selectedTroop,
    int enemySlot,
  ) {
    final state = controller.state;
    // Only the war opponent may be plundered (engine gate).
    final plunderVictimOk =
        selectedTroop != null &&
        state.map.ownerAt(selectedTroop.x, selectedTroop.y) == enemySlot;
    final canPlunder =
        selectedTroop != null &&
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
        : state.map.buildingAt(selectedTroop.x, selectedTroop.y) ==
              gc.Building.none
        ? 'Hier steht nichts zum Plündern'
        : 'Bebautes feindliches Feld plündern';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: plunderHint,
          child: TextButton.icon(
            onPressed: canPlunder
                ? () async {
                    final List<gc.GameEvent> events;
                    try {
                      events = (await controller.applyWarAction(
                        gc.WarPlunder(
                          slot: slot,
                          x: selectedTroop.x,
                          y: selectedTroop.y,
                        ),
                      )).events;
                    } on gc.ActionException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                      return;
                    }
                    if (!context.mounted) return;
                    await showWarReport(
                      context,
                      events,
                      viewerSlot: slot,
                      title: 'Plünderung',
                    );
                  }
                : null,
            icon: const Icon(Icons.local_fire_department),
            label: const Text('Plündern'),
          ),
        ),
        TextButton(
          onPressed: () async {
            try {
              await controller.applyWarAction(
                gc.WarPeaceWish(slot: slot, wantsPeace: !war.wantsPeace(slot)),
              );
            } on gc.ActionException catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(e.message)));
              }
            }
          },
          child: Text(
            war.wantsPeace(slot) ? 'Frieden zurückziehen' : 'Frieden wünschen',
          ),
        ),
        FilledButton(
          onPressed: () async {
            final events = await controller.endWarRound();
            if (context.mounted) {
              await showWarReport(
                context,
                events,
                viewerSlot: slot,
                title: 'Rundenbericht',
              );
            }
            // A round end can resolve a ruler capture: the coercion
            // choices (Abdanken, Kurfürstensitz, …) must come right now,
            // not at the next turn's start.
            if (context.mounted) {
              await promptDecisionsFor(context, controller, slot);
            }
          },
          // A human-vs-human attacker hands the round to the defender —
          // only the defender's button really ends the round.
          child: Text(
            slot == war.attackerSlot &&
                    state.dynasty(enemySlot).status == gc.DynastyStatus.human
                ? 'Züge übergeben'
                : 'Runde beenden',
          ),
        ),
      ],
    );
  }

  /// Claim settlement controls. Collapsible to a slim chip so the
  /// explanation never blocks tapping loser tiles near the top edge of
  /// the map — the remaining claim stays visible either way.
  Widget _settlement(BuildContext context, gc.ActiveWar war, int slot) {
    final theme = Theme.of(context);
    final state = controller.state;
    final isWinner = war.winnerSlot == slot;
    // "Ganzes Land übernehmen": offered when the remaining claim covers
    // the loser's entire territory value.
    var loserValue = 0;
    if (isWinner) {
      final map = state.map;
      final loserSlot = war.opponentOf(slot);
      for (var i = 0; i < map.terrain.length; i++) {
        if (map.owner[i] == loserSlot) {
          loserValue += gc.settlementTileValue(state, map.building[i]);
        }
      }
    }
    final canTakeAll =
        isWinner && loserValue > 0 && loserValue <= war.remainingClaim;

    final header = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isWinner ? Icons.emoji_events : Icons.flag,
          size: 18,
          color: isWinner ? Colors.orange : null,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            isWinner
                ? 'Sieg ! Anspruch: ${war.remainingClaim}'
                : 'Niederlage — Anspruch des Siegers: ${war.remainingClaim}',
            style: theme.textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: _settlementCollapsed ? 'Erklärung zeigen' : 'Einklappen',
          icon: Icon(
            _settlementCollapsed ? Icons.expand_more : Icons.expand_less,
          ),
          onPressed: () =>
              setState(() => _settlementCollapsed = !_settlementCollapsed),
        ),
        if (isWinner && _settlementCollapsed)
          TextButton(
            onPressed: () => _finishSettlement(context, slot),
            child: const Text('Fertig'),
          ),
      ],
    );

    return Card(
      margin: const EdgeInsets.all(8),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            if (!_settlementCollapsed) ...[
              Text(
                isWinner
                    ? 'Wähle deine Beute: Tippe Felder des Verlierers an, '
                          'die an dein Land grenzen, um sie zu übernehmen. '
                          'Jedes Feld kostet seinen Wert (Markt 2500, Stadt '
                          '5000, leeres Land 100). Der nicht genutzte Rest wird '
                          'in Talern ausgezahlt.'
                    : 'Der Sieger wählt nun Felder deines Landes.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              if (isWinner)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.flag, size: 18),
                        // Greyed out instead of hidden when the winner cannot
                        // afford every bordering loser tile — a button that
                        // pops in and out under the finger causes mis-taps.
                        onPressed: canTakeAll
                            ? () => _takeAllLand(context, slot)
                            : null,
                        label: const Text('Ganzes Land übernehmen'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _finishSettlement(context, slot),
                        child: const Text('Fertig — Rest in Talern'),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Annexes every affordable bordering loser tile in one stroke and
  /// finishes the settlement (`SettlementTakeAll`).
  Future<void> _takeAllLand(BuildContext context, int slot) async {
    final gc.ActionResult result;
    try {
      result = await controller.applyWarAction(
        gc.SettlementTakeAll(slot: slot),
      );
    } on gc.ActionException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    await controller.endWarRound(); // resumes AI advance
    if (context.mounted) {
      await showWarReport(
        context,
        result.events,
        viewerSlot: slot,
        title: 'Friedensschluss',
      );
    }
    if (context.mounted) {
      await promptDecisionsFor(context, controller, slot);
    }
  }

  Future<void> _finishSettlement(BuildContext context, int slot) async {
    final result = await controller.applyWarAction(
      gc.SettlementFinish(slot: slot),
    );
    await controller.endWarRound(); // resumes AI advance
    if (context.mounted) {
      await showWarReport(
        context,
        result.events,
        viewerSlot: slot,
        title: 'Friedensschluss',
      );
    }
    // The victor's coercion options (Abdanken, Kurfürstensitz, …) appear
    // right after the peace report instead of at the next turn's start.
    if (context.mounted) {
      await promptDecisionsFor(context, controller, slot);
    }
  }
}
