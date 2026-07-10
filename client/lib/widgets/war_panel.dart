import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../state/game_controller.dart';
import 'decisions.dart' show formatWarStartTime, promptDecisionsFor;
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

  /// The war-start preparation window: [slot] still owes their warPlan
  /// answer (live control vs autopilot + stance) — everything else waits.
  Widget _preparation(BuildContext context, gc.ActiveWar war, int slot) {
    final theme = Theme.of(context);
    // Online duel scheduling: once both sides answered, the agreed start
    // (earliest common warPlan slot) is shown here — in local time.
    final scheduled = war.scheduledStartMs;
    return SafeArea(
      child: Card(
        margin: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Kriegsvorbereitung', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                '${gc.countryNames[war.attackerSlot]} gegen '
                '${gc.countryNames[war.defenderSlot]} — beide Seiten wählen, '
                'ob sie ihre Truppen selbst befehligen. Der Krieg beginnt, '
                'sobald die Wahl steht.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (scheduled != null && scheduled > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Vereinbarter Beginn: ${formatWarStartTime(scheduled)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => promptDecisionsFor(context, controller, slot),
                child: const Text('Wählen'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final war = controller.state.activeWar;
    final slot = controller.warHumanSlot;
    if (war == null || slot == null) return const SizedBox.shrink();

    if (war.phase == gc.WarPhase.preparation) {
      return _preparation(context, war, slot);
    }
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
              _enemyArmyLine(theme, realm, enemy, enemySlot),
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
              // Cap the unit list and let it scroll: a large army would
              // otherwise grow the panel past the map's bottom edge and push
              // the action buttons ("Runde beenden") off small screens.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 124),
                child: SingleChildScrollView(
                  child: Wrap(
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
                          onTap: () => controller.selectWarUnit(
                            i == selected ? null : i,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // The autopilot stance only matters online, where an idle
              // war round is fought by each unit's stance. Offline the
              // player moves every unit by hand, so the toggle is hidden.
              if (controller.isOnline &&
                  selectedTroop != null &&
                  selected != null)
                _stanceToggle(context, slot, selected, selectedTroop),
              _actions(context, war, slot, selectedTroop, enemySlot),
            ],
          ],
        ),
      ),
    );
  }

  /// Lets the player set the selected unit's autopilot stance (used if the
  /// war clock runs out before they finish — see [gc.TroopStance]). Its own
  /// thin row so it never crowds the move/plunder/peace actions.
  Widget _stanceToggle(
    BuildContext context,
    int slot,
    int unitIndex,
    gc.Troop troop,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      // FittedBox: the label + two-segment toggle overflows very narrow phones
      // in a fixed Row — scale it down instead of clipping.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Bei Auto-Krieg: ', style: theme.textTheme.bodySmall),
            const SizedBox(width: 4),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                  value: gc.TroopStance.holdPosition,
                  icon: Icon(Icons.shield_outlined, size: 14),
                  label: Text('Halten'),
                ),
                ButtonSegment(
                  value: gc.TroopStance.attack,
                  icon: Icon(Icons.gps_fixed, size: 14),
                  label: Text('Angreifen'),
                ),
              ],
              selected: {troop.stance},
              onSelectionChanged: (selection) async {
                try {
                  await controller.applyWarAction(
                    gc.SetTroopStance(
                      slot: slot,
                      unitIndex: unitIndex,
                      stance: selection.first,
                    ),
                  );
                } on gc.ActionException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Summarizes the enemy army so the player can judge peace vs. press on.
  /// During a war both sides see each other's units MOVE on the map, but the
  /// enemy's strength (men/combat power) is hidden information — it is shown
  /// only from the viewer's own espionage intel (fuzzed and dated), never
  /// read off the live army. Whether the enemy host still stands is
  /// observable on the battlefield, so that stays visible.
  Widget _enemyArmyLine(
    ThemeData theme,
    gc.Realm viewer,
    gc.Realm enemy,
    int enemySlot,
  ) {
    if (enemy.troops.isEmpty) {
      return Text(
        'Das feindliche Heer ist vernichtet !',
        style: theme.textTheme.bodySmall!.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.green.shade800,
        ),
      );
    }
    final units = enemy.troops.length;
    final unitWord = 'Truppe${units == 1 ? '' : 'n'}';
    // Newest military intel on this enemy (reports are in chronological
    // order, so the last match wins).
    gc.IntelReport? intel;
    for (final report in viewer.intelReports) {
      if (report.targetSlot == enemySlot &&
          report.values.containsKey('armySize')) {
        intel = report;
      }
    }
    final text = intel != null
        ? 'Feindliches Heer: $units $unitWord · laut Spionage '
              '~${intel.values['armySize']} Mann (Stand Anno ${intel.year})'
        : 'Feindliches Heer: $units $unitWord im Feld — ihre Stärke bleibt '
              'ohne Spionage verborgen.';
    return Text(text, style: theme.textTheme.bodySmall);
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
    final attackStance = troop.stance == gc.TroopStance.attack;
    return Tooltip(
      message:
          'Verbleibende Züge: $movesLeft'
          '${onEnemyLand ? ' — besetzt feindliches Gebiet' : ''}'
          '\nHaltung: ${attackStance ? 'Angreifen' : 'Position halten'}',
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
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(
                attackStance ? Icons.gps_fixed : Icons.shield_outlined,
                size: 12,
                color: theme.colorScheme.outline,
              ),
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
    // Only the war opponent may be plundered (engine gate). §11.5: each
    // ARMY plunders once per round — the gate follows the selected unit.
    final plunderVictimOk =
        selectedTroop != null &&
        state.map.ownerAt(selectedTroop.x, selectedTroop.y) == enemySlot;
    final canPlunder =
        selectedTroop != null &&
        !selectedTroop.plunderedThisRound &&
        plunderVictimOk &&
        state.map.buildingAt(selectedTroop.x, selectedTroop.y) !=
            gc.Building.none;
    final plunderHint = selectedTroop == null
        ? 'Erst eine Truppe wählen'
        : selectedTroop.plunderedThisRound
        ? 'Diese Armee hat diese Runde schon geplündert'
        : !plunderVictimOk
        ? 'Die Truppe muss auf feindlichem Gebiet stehen'
        : state.map.buildingAt(selectedTroop.x, selectedTroop.y) ==
              gc.Building.none
        ? 'Hier steht nichts zum Plündern'
        : 'Bebautes feindliches Feld plündern';

    // Wrap (not Row): on a narrow screen three buttons in a single row
    // overflow and clip the rightmost one — "Runde beenden" then becomes
    // unreachable. Wrapping flows the overflow onto a second line instead.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
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
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(e.message)));
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
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(e.message)));
              }
            }
          },
          child: Text(
            war.wantsPeace(slot) ? 'Frieden zurückziehen' : 'Frieden wünschen',
          ),
        ),
        FilledButton(
          onPressed: () async {
            final List<gc.GameEvent> events;
            try {
              events = await controller.endWarRound();
            } on gc.ActionException catch (e) {
              // Online the server can reject the round end (turn already
              // advanced, or the build is out of date) — show the message
              // instead of crashing, like the plunder/peace buttons.
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(e.message)));
              }
              return;
            }
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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    try {
      await controller.endWarRound(); // resumes AI advance
    } on gc.ActionException catch (e) {
      // Online the server can reject the round end (turn already advanced,
      // or the build is out of date) — mirror the header button's handling.
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
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
    final gc.ActionResult result;
    try {
      result = await controller.applyWarAction(gc.SettlementFinish(slot: slot));
    } on gc.ActionException catch (e) {
      // A double-tap of "Fertig", or an online rejection, can hit a war
      // that already left the settlement phase — show the message instead
      // of crashing (mirrors _takeAllLand).
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    try {
      await controller.endWarRound(); // resumes AI advance
    } on gc.ActionException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
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
