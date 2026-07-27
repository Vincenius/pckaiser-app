import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/labels.dart' show realmName, troopClassName;
import '../l10n/strings.dart' show tr;
import '../state/game_controller.dart';
import 'decisions.dart' show formatWarStartTime, promptDecisionsFor;
import 'war_report.dart';

/// In-war controls (§11.2): unit selection (tap a unit on the map or via
/// the „Truppen" sheet), march/attack by tapping a target on the map,
/// plunder, peace wish, end round — and the claim-settlement controls of
/// a limited victory. Battle and plunder results appear as report popups.
///
/// Docked full-width at the BOTTOM of the screen (above the status row),
/// visually extending the category bar instead of floating over the map.
/// Collapsible to its header line (opponent, round) so the map gets the
/// full height back on small screens.
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

  /// The war-start preparation window for the seated player's own war
  /// side ([GameController.warPrepSlot]): answer the warPlan decision and
  /// line up every troop INDIVIDUALLY (hold / attack) on the visible map
  /// — user rule 2026-07-13, replacing the old all-troops stance choice.
  /// Stays available after this side answered (online the war may only
  /// start hours later at the agreed time) and inside the read-only
  /// off-turn viewer, where stance orders are the one allowed action.
  Widget _preparation(BuildContext context, gc.ActiveWar war, int slot) {
    final theme = Theme.of(context);
    final state = controller.state;
    final realm = state.realm(slot);
    final enemySlot = war.opponentOf(slot);
    // Whether THIS side still owes its warPlan answer. Online the
    // opponent's pending decision is filtered out of the visible state,
    // so the scan only ever finds our own.
    final owesPlan = state.pendingDecisions.any(
      (d) => d.type == 'warPlan' && d.decidingSlot == slot,
    );
    final selected = controller.selectedWarUnit;
    final selectedTroop = selected != null && selected < realm.troops.length
        ? realm.troops[selected]
        : null;
    // Online duel scheduling: once both sides answered, the agreed start
    // (earliest common warPlan slot) is shown here — in local time.
    final scheduled = war.scheduledStartMs;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('war.prepTitle'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                tr('war.prepIntro', {
                  'attacker': realmName(war.attackerSlot),
                  'defender': realmName(war.defenderSlot),
                }),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (scheduled != null && scheduled > 0) ...[
                const SizedBox(height: 4),
                Text(
                  tr('war.scheduledStart', {
                    'time': formatWarStartTime(scheduled),
                  }),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ],
              const SizedBox(height: 4),
              // Own units, individually selectable — same capped, scrolling
              // chip list as during the war rounds.
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
                          movesLeft: null, // no war moves yet
                          selected: i == selected,
                          onTap: () => controller.selectWarUnit(
                            i == selected ? null : i,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (selectedTroop != null && selected != null)
                _stanceToggle(context, slot, selected, selectedTroop)
              else if (realm.troops.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    tr('war.tapTroopHint'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              if (owesPlan)
                FilledButton(
                  onPressed: () =>
                      promptDecisionsFor(context, controller, slot),
                  child: Text(tr('war.choose')),
                )
              else
                Text(
                  tr('war.planChosen'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
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
    if (war == null) return const SizedBox.shrink();

    if (war.phase == gc.WarPhase.preparation) {
      // Keyed to the OWN participant slot (not the acting side): the
      // panel keeps offering the per-unit stance orders after this side
      // answered its warPlan, while the opponent (or the start time) is
      // still awaited.
      final prepSlot = controller.warPrepSlot;
      if (prepSlot == null) return const SizedBox.shrink();
      return _preparation(context, war, prepSlot);
    }

    final slot = controller.warHumanSlot;
    if (slot == null) return const SizedBox.shrink();
    if (war.phase == gc.WarPhase.settlement) {
      return _settlement(context, war, slot);
    }

    final theme = Theme.of(context);
    final state = controller.state;
    final realm = state.realm(slot);
    final enemySlot = war.opponentOf(slot);
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

    final header = Padding(
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: [
          const Icon(Icons.gavel, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr('war.headerVs', {'enemy': realmName(enemySlot)}),
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tooltip(
            message: tr('war.winterRuleTooltip'),
            child: Text(
              tr('war.roundCounter', {'round': war.round + 1}),
              style: theme.textTheme.labelSmall,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            tooltip: _collapsed
                ? tr('war.openMenuTooltip')
                : tr('war.collapse'),
            icon: Icon(_collapsed ? Icons.expand_more : Icons.expand_less),
            onPressed: () => setState(() => _collapsed = !_collapsed),
          ),
        ],
      ),
    );

    // Color-coded status banners instead of prose paragraphs: what decides
    // the war right now (capital held/lost, peace diplomacy) — with the
    // standing objective as the fallback, so the player always knows what
    // to play for.
    final banners = <Widget>[];
    if (occupier == slot) {
      banners.add(
        _banner(
          theme,
          Icons.emoji_events,
          sealsNextRoundEnd
              ? tr('war.capitalHeldSealBanner')
              : tr('war.capitalHeldBanner'),
          background: Colors.green.shade100,
          foreground: Colors.green.shade900,
        ),
      );
    } else if (occupier == enemySlot) {
      banners.add(
        _banner(
          theme,
          Icons.warning_amber,
          tr('war.capitalLostBanner'),
          background: theme.colorScheme.error,
          foreground: theme.colorScheme.onError,
        ),
      );
    }
    if (enemyReady) {
      banners.add(
        _banner(
          theme,
          Icons.handshake,
          tr('war.enemyWantsPeaceBanner'),
          background: Colors.green.shade100,
          foreground: Colors.green.shade900,
        ),
      );
    } else if (war.wantsPeace(slot)) {
      banners.add(
        _banner(
          theme,
          Icons.handshake_outlined,
          tr('war.peaceWishSentBanner'),
          background: theme.colorScheme.surface,
          foreground: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (banners.isEmpty) {
      banners.add(
        _banner(
          theme,
          Icons.flag_outlined,
          tr('war.objectiveBanner'),
          background: theme.colorScheme.surface,
          foreground: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    // Docked full-width above the status row — it REPLACES the hidden
    // category bar during a war, so it wears that bar's neutral surface
    // color instead of the old alarm red.
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          if (!_collapsed) ...[
            ...banners,
            _selectionRow(context, slot, selectedTroop, selected, moves),
            // The autopilot stance only matters online, where an idle
            // war round is fought by each unit's stance. Offline the
            // player moves every unit by hand, so the toggle is hidden.
            if (controller.isOnline &&
                selectedTroop != null &&
                selected != null)
              _stanceToggle(context, slot, selected, selectedTroop),
            _actions(context, war, slot, selectedTroop),
          ],
        ],
      ),
    );
  }

  /// One compact, color-coded war-status line (icon + short sentence) —
  /// e.g. "Der Gegner wünscht Frieden !" or the capital-held victory hint.
  Widget _banner(
    ThemeData theme,
    IconData icon,
    String text, {
    required Color background,
    required Color foreground,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall!.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The one always-visible unit line: the currently selected troop (name +
  /// remaining war moves + a clear button), or a hint to pick one. The full
  /// army roster and strength live behind the „Truppen" action
  /// ([_showWarDetails]) so the panel stays slim.
  Widget _selectionRow(
    BuildContext context,
    int slot,
    gc.Troop? troop,
    int? index,
    List<int> moves,
  ) {
    final theme = Theme.of(context);
    if (troop == null || index == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          tr('war.selectUnitHint'),
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      );
    }
    final movesLeft = index < moves.length ? moves[index] : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            troop.stance == gc.TroopStance.attack
                ? Icons.gps_fixed
                : Icons.shield_outlined,
            size: 14,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              tr('war.selectedUnitMoves', {
                'name': troop.name,
                'moves': movesLeft,
              }),
              style: theme.textTheme.bodySmall!.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            tooltip: tr('war.clearSelection'),
            icon: const Icon(Icons.close),
            onPressed: () => controller.selectWarUnit(null),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet behind the „Truppen" action: the enemy army summary and
  /// the player's own troops (with strength), still tappable to select a
  /// unit — picking one closes the sheet.
  void _showWarDetails(BuildContext context, gc.ActiveWar war, int slot) {
    final state = controller.state;
    final realm = state.realm(slot);
    final enemySlot = war.opponentOf(slot);
    final enemy = state.realm(enemySlot);
    final moves = war.movesLeft[slot] ?? const <int>[];
    final selected = controller.selectedWarUnit;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('war.detailsTitle'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _enemyArmyLine(theme, realm, enemy, enemySlot),
                const SizedBox(height: 12),
                Text(
                  tr('war.yourTroopsHint'),
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
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
                            onTap: () {
                              controller.selectWarUnit(
                                i == selected ? null : i,
                              );
                              Navigator.of(sheetContext).pop();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
            Text(tr('war.autoWarStance'), style: theme.textTheme.bodySmall),
            const SizedBox(width: 4),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: [
                ButtonSegment(
                  value: gc.TroopStance.holdPosition,
                  icon: const Icon(Icons.shield_outlined, size: 14),
                  label: Text(tr('war.stanceHold')),
                ),
                ButtonSegment(
                  value: gc.TroopStance.attack,
                  icon: const Icon(Icons.gps_fixed, size: 14),
                  label: Text(tr('war.stanceAttack')),
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
  /// During a war both sides see each other's units MOVE on the map, and
  /// since 2026-07-19 their GATTUNG is battlefield-observable too (the
  /// Schere-Stein-Papier counters need visible classes to play against).
  /// The enemy's strength (men/combat power) stays hidden information —
  /// shown only from the viewer's own espionage intel (fuzzed and dated),
  /// never read off the live army.
  Widget _enemyArmyLine(
    ThemeData theme,
    gc.Realm viewer,
    gc.Realm enemy,
    int enemySlot,
  ) {
    if (enemy.troops.isEmpty) {
      return Text(
        tr('war.enemyArmyDestroyed'),
        style: theme.textTheme.bodySmall!.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.green.shade800,
        ),
      );
    }
    final units = enemy.troops.length;
    final unitWord = tr(units == 1 ? 'war.troopOne' : 'war.troopMany');
    final classCounts = <int, int>{};
    for (final t in enemy.troops) {
      classCounts[t.troopClass] = (classCounts[t.troopClass] ?? 0) + 1;
    }
    final classText = [
      for (final c in classCounts.keys.toList()..sort())
        tr('war.classCount', {
          'count': classCounts[c],
          'class': troopClassName(c),
        }),
    ].join(', ');
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
        ? tr('war.enemyArmyIntel', {
            'units': units,
            'unitWord': unitWord,
            'classes': classText,
            'men': intel.values['armySize'],
            'year': intel.year,
          })
        : tr('war.enemyArmyUnknown', {
            'units': units,
            'unitWord': unitWord,
            'classes': classText,
          });
    return Text(text, style: theme.textTheme.bodySmall);
  }

  /// [movesLeft] is null during the PREPARATION window — there are no war
  /// moves yet, so the chip shows no move counter.
  Widget _unitChip(
    ThemeData theme,
    gc.GameState state,
    gc.Troop troop,
    int enemySlot, {
    required int? movesLeft,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final onEnemyLand = state.map.ownerAt(troop.x, troop.y) == enemySlot;
    final attackStance = troop.stance == gc.TroopStance.attack;
    return Tooltip(
      message: [
        if (movesLeft != null)
          tr('war.movesLeftTooltip', {'moves': movesLeft}) +
              (onEnemyLand ? tr('war.occupiesEnemySuffix') : '')
        else if (onEnemyLand)
          tr('war.occupiesEnemy'),
        tr('war.stanceTooltip', {
          'stance': attackStance
              ? tr('war.stanceAttack')
              : tr('war.stanceHoldPosition'),
        }),
      ].join('\n'),
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        avatar: movesLeft == null
            ? null
            : CircleAvatar(
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
              tr('war.unitChipLabel', {
                'name': troop.name,
                'men': troop.men,
                'strength': gc.troopStrength(troop).round(),
              }),
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
  ) {
    final state = controller.state;
    // Plunder is TILE-scoped in the engine (`warPlunderBlocker`): the
    // strongest not-yet-spent army on the tile carries it and must meet the
    // minimum strength. Gate the button on that same predicate so it never
    // greys out a plunder the engine would allow (a second unspent army) nor
    // offers one it then rejects (an under-strength lone unit).
    final plunderBlock = selectedTroop == null
        ? null
        : gc.warPlunderBlocker(state, slot, selectedTroop.x, selectedTroop.y);
    final canPlunder = selectedTroop != null && plunderBlock == null;
    final plunderHint = selectedTroop == null
        ? tr('war.plunderNeedUnit')
        : plunderBlock == null
        ? tr('war.plunderHint')
        : gc.coreMessage(plunderBlock);

    final theme = Theme.of(context);
    // Four equal-width icon+label tiles in the style of the category bar
    // right below — the docked panel reads as one bottom-menu block.
    // "Runde beenden" is the filled primary tile.
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
      child: Row(
        children: [
          _actionItem(
            theme,
            icon: Icons.groups,
            label: tr('war.troopsAction'),
            tooltip: tr('war.troopsTooltip'),
            onTap: () => _showWarDetails(context, war, slot),
          ),
          _actionItem(
            theme,
            icon: Icons.local_fire_department,
            label: tr('war.plunderAction'),
            tooltip: plunderHint,
            onTap: canPlunder
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
                      title: tr('war.plunderReportTitle'),
                    );
                  }
                : null,
          ),
          _actionItem(
            theme,
            icon: war.wantsPeace(slot)
                ? Icons.handshake
                : Icons.handshake_outlined,
            label: war.wantsPeace(slot)
                ? tr('war.withdrawPeace')
                : tr('war.peaceAction'),
            tooltip: war.wantsPeace(slot)
                ? tr('war.withdrawPeaceTooltip')
                : tr('war.peaceTooltip'),
            onTap: () async {
              try {
                await controller.applyWarAction(
                  gc.WarPeaceWish(
                    slot: slot,
                    wantsPeace: !war.wantsPeace(slot),
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
          _actionItem(
            theme,
            icon: Icons.skip_next,
            // In a both-human war the side that opens the round hands over to
            // the other; only the second side's tap really ends the round.
            // Read the engine's predicate so the label tracks the alternating
            // initiative (and delegation) instead of a stale attacker-first
            // assumption.
            label: gc.willHandOverRound(state, slot)
                ? tr('war.handOver')
                : tr('war.endRound'),
            emphasized: true,
            onTap: () async {
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
                  title: tr('war.roundReportTitle'),
                );
              }
              // A round end can resolve a ruler capture: the coercion
              // choices (Abdanken, Kurfürstensitz, …) must come right now,
              // not at the next turn's start.
              if (context.mounted) {
                await promptDecisionsFor(context, controller, slot);
              }
            },
          ),
        ],
      ),
    );
  }

  /// One bottom-bar-style action tile (icon over label, quarter width).
  /// Disabled tiles dim like the locked category-bar items; [emphasized]
  /// fills the tile with the primary color for the round-end action —
  /// matching the regular "Zug beenden" button instead of alarm red.
  Widget _actionItem(
    ThemeData theme, {
    required IconData icon,
    required String label,
    String? tooltip,
    VoidCallback? onTap,
    bool emphasized = false,
  }) {
    final fg = emphasized
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    Widget tile = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
    if (emphasized) {
      tile = Material(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
        child: tile,
      );
    }
    if (tooltip != null) tile = Tooltip(message: tooltip, child: tile);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: tile,
      ),
    );
  }

  /// Claim settlement controls, docked at the bottom like the round
  /// panel. Collapsible to a slim header so the map keeps its height —
  /// the remaining claim stays visible either way.
  Widget _settlement(BuildContext context, gc.ActiveWar war, int slot) {
    final theme = Theme.of(context);
    final state = controller.state;
    final isWinner = war.winnerSlot == slot;
    // The auto-annex button is ALWAYS available to the winner (user
    // request 2026-07-19 — hand-tapping every tile of a big late-game
    // claim was a chore). Its label says what it will do: the whole land
    // when the claim covers everything, otherwise a border wave worth of
    // tiles ("Auto-Annexion", engine `annexAffordableTiles`).
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
    final coversAll =
        isWinner && loserValue > 0 && loserValue <= war.remainingClaim;

    // Drag-select annexation: the valid, affordable, border-ordered subset
    // of the tiles the winner has drag-selected (see game_screen) — exactly
    // what the "Annektieren" button will take. The rest stay with the loser.
    final selection = controller.settlementSelection;
    final plan = isWinner
        ? gc.planSettlementAnnexSelection(state, selection)
        : const <({int x, int y})>[];
    var planValue = 0;
    for (final t in plan) {
      planValue += gc.settlementTileValue(
        state,
        state.map.buildingAt(t.x, t.y),
      );
    }

    final header = Row(
      children: [
        Icon(
          isWinner ? Icons.emoji_events : Icons.flag,
          size: 18,
          color: isWinner ? Colors.orange : null,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            isWinner
                ? tr('war.victoryClaim', {'claim': war.remainingClaim})
                : tr('war.defeatClaim', {'claim': war.remainingClaim}),
            style: theme.textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: _settlementCollapsed
              ? tr('war.showExplanation')
              : tr('war.collapse'),
          icon: Icon(
            _settlementCollapsed ? Icons.expand_more : Icons.expand_less,
          ),
          onPressed: () =>
              setState(() => _settlementCollapsed = !_settlementCollapsed),
        ),
        if (isWinner && _settlementCollapsed)
          TextButton(
            onPressed: () => _finishSettlement(context, slot),
            child: Text(tr('war.done')),
          ),
      ],
    );

    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            if (!_settlementCollapsed) ...[
              Text(
                isWinner
                    ? tr('war.settlementWinnerHelp', {
                        'market': gc.Building.value[gc.Building.markt],
                        'town': gc.Building.value[gc.Building.stadt],
                        'bare': gc.settlementTileValue(
                          controller.state,
                          gc.Building.none,
                        ),
                      })
                    : tr('war.settlementLoserHelp'),
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              if (isWinner) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    selection.isEmpty
                        ? tr('war.annexDragHint')
                        : tr('war.annexSelectionStatus', {
                            'selected': selection.length,
                            'plan': plan.length,
                          }),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (selection.isNotEmpty)
                        FilledButton.icon(
                          icon: const Icon(Icons.select_all, size: 18),
                          onPressed: plan.isEmpty
                              ? null
                              : () => _annexSelection(context, slot),
                          label: Text(
                            tr('war.annexSelected', {
                              'count': plan.length,
                              'value': planValue,
                            }),
                          ),
                        ),
                      FilledButton.icon(
                        icon: const Icon(Icons.flag, size: 18),
                        onPressed: () => _takeAllLand(context, slot),
                        label: Text(
                          coversAll
                              ? tr('war.takeWholeLand')
                              : tr('war.autoAnnex'),
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _finishSettlement(context, slot),
                        child: Text(tr('war.doneRemainderTaler')),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Annexes the winner's drag-selection: the engine-planned valid, ordered,
  /// affordable subset (`planSettlementAnnexSelection`) is submitted as one
  /// `SettlementAnnexMany`; unreachable / unaffordable tiles stay with the
  /// loser. The settlement usually stays OPEN afterwards — the winner can
  /// keep selecting, auto-annex the rest, or press Fertig. Annexing the
  /// loser's LAST tile however ends the war on the spot (engine,
  /// 2026-07-27) — then this must resume the paused AI advance and show
  /// the treaty report, exactly like _takeAllLand.
  Future<void> _annexSelection(BuildContext context, int slot) async {
    final plan = gc.planSettlementAnnexSelection(
      controller.state,
      controller.settlementSelection,
    );
    if (plan.isEmpty) return;
    final gc.ActionResult result;
    try {
      result = await controller.applyWarAction(
        gc.SettlementAnnexMany(slot: slot, tiles: plan),
      );
    } on gc.ActionException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    controller.clearSettlementSelection();
    if (controller.state.activeWar != null) return;
    // The annex took the loser's last tile — the settlement is over.
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
        title: tr('war.peaceTreatyTitle'),
      );
    }
    if (context.mounted) {
      await promptDecisionsFor(context, controller, slot);
    }
  }

  /// Auto-annex: takes affordable loser tiles in a wave from the own
  /// border (engine `annexAffordableTiles`) and finishes the settlement —
  /// the whole land when the claim covers it, otherwise as much compact
  /// border territory as the claim buys (`SettlementTakeAll`).
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
        title: tr('war.peaceTreatyTitle'),
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
        title: tr('war.peaceTreatyTitle'),
      );
    }
    // The victor's coercion options (Abdanken, Kurfürstensitz, …) appear
    // right after the peace report instead of at the next turn's start.
    if (context.mounted) {
      await promptDecisionsFor(context, controller, slot);
    }
  }
}
