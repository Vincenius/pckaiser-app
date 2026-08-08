import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../app_version.dart';
import '../l10n/labels.dart';
import '../l10n/strings.dart';
import '../state/game_controller.dart';
import 'decisions.dart' show promptDecisionsFor;
import 'event_feed.dart';

void _toast(BuildContext context, String message) {
  if (!context.mounted) return;
  // Replace instead of queue, so repeated errors don't stack snackbars.
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _tryAction(
  BuildContext context,
  GameController controller,
  gc.PlayerAction action, {
  bool undoable = false,
}) async {
  try {
    undoable
        ? await controller.applyUndoable(action)
        : await controller.applyIrreversible(action);
  } on gc.ActionException catch (e) {
    if (context.mounted) _toast(context, e.message);
  }
}

/// Merge gate, mirrored from the engine: no merging while either realm
/// fights the active war.
bool _mergeAtWar(gc.GameState state, int slot, int source) {
  final war = state.activeWar;
  return war != null && (war.isParticipant(slot) || war.isParticipant(source));
}

// --- Commerce ---------------------------------------------------------

/// The Handel sheet — opened directly from the bottom action bar.
void showCommerceMenu(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final realm = controller.currentRealm;
  final state = controller.visibleState;
  // Follow-up sheets use the stable screen [context] — the sheet's own
  // context dies with the pop (see showMilitaryMenu).
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(tr('sellGrain')),
            subtitle: Text(
              tr('menus.surplusMarketPrice', {
                'surplus': realm.grainHarvest,
                'price': state.grainPrice.toStringAsFixed(1),
              }),
            ),
            enabled: !realm.soldGrainThisTurn && realm.grainHarvest > 0,
            onTap: () {
              Navigator.pop(sheetContext);
              _sellSheet(
                context,
                controller,
                gc.MarketGood.grain,
                realm.grainHarvest,
                state.grainPrice,
              );
            },
          ),
          ListTile(
            title: Text(tr('sellCattle')),
            subtitle: Text(
              tr('menus.surplusMarketPrice', {
                'surplus': realm.livestockHarvest,
                'price': state.cattlePrice.toStringAsFixed(1),
              }),
            ),
            enabled: !realm.soldCattleThisTurn && realm.livestockHarvest > 0,
            onTap: () {
              Navigator.pop(sheetContext);
              _sellSheet(
                context,
                controller,
                gc.MarketGood.cattle,
                realm.livestockHarvest,
                state.cattlePrice,
              );
            },
          ),
          ListTile(
            title: Text(tr('investShips')),
            subtitle: Text(
              tr('menus.investMax', {
                'max': gc.shipInvestmentCap(realm),
                'harbors': realm.tileCount[gc.Building.hafen],
              }),
            ),
            enabled:
                !realm.investedThisTurn &&
                realm.tileCount[gc.Building.hafen] > 0,
            onTap: () {
              Navigator.pop(sheetContext);
              _investSheet(context, controller);
            },
          ),
          ListTile(
            title: Text(tr('menus.sendMoney')),
            subtitle: Text(tr('menus.sendMoneySubtitle')),
            enabled: realm.treasury > 0,
            onTap: () {
              Navigator.pop(sheetContext);
              _targetThenAmount(
                context,
                controller,
                max: realm.treasury,
                titlePrefix: tr('menus.taler'),
                onSubmit: (target, amount) => _tryAction(
                  context,
                  controller,
                  gc.SendMoney(slot: slot, targetSlot: target, amount: amount),
                  undoable: true,
                ),
              );
            },
          ),
          for (final source in gc.mergeableSlots(controller.state, slot))
            ListTile(
              title: Text(tr('menus.mergeWith', {'realm': realmName(source)})),
              // No merging mid-war (engine gate, mirrored).
              subtitle: _mergeAtWar(state, slot, source)
                  ? Text(tr('menus.notMidWar'))
                  : null,
              enabled: !_mergeAtWar(state, slot, source),
              onTap: () {
                Navigator.pop(sheetContext);
                _tryAction(
                  context,
                  controller,
                  gc.MergeRealms(slot: slot, sourceSlot: source),
                );
              },
            ),
          if (gc.transferableSlots(controller.state, slot).isNotEmpty)
            ListTile(
              title: Text(tr('menus.transferRealm')),
              // No transferring mid-war (engine gate, mirrored).
              subtitle: (state.activeWar?.isParticipant(slot) ?? false)
                  ? Text(tr('menus.notMidWar'))
                  : Text(tr('menus.transferRealmSubtitle')),
              enabled: !(state.activeWar?.isParticipant(slot) ?? false),
              onTap: () {
                Navigator.pop(sheetContext);
                _transferRealmSheet(context, controller);
              },
            ),
        ],
      ),
    ),
  );
}

/// Target picker + confirmation for "Reich übertragen" — hands the whole
/// realm to a foreign ruler, so the confirm dialog spells out what leaves
/// with it. Irreversible by nature (the seat is vacated).
void _transferRealmSheet(BuildContext context, GameController controller) {
  final state = controller.state;
  final slot = controller.currentSlot;
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final target in gc.transferableSlots(state, slot))
            ListTile(
              title: Text(realmName(target)),
              // No transferring mid-war (engine gate, mirrored).
              subtitle: _mergeAtWar(state, slot, target)
                  ? Text(tr('menus.notMidWar'))
                  : null,
              enabled: !_mergeAtWar(state, slot, target),
              onTap: () async {
                Navigator.pop(sheetContext);
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                      tr('menus.transferConfirm', {'realm': realmName(target)}),
                    ),
                    content: Text(tr('menus.transferConfirmBody')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr('cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(tr('menus.ok')),
                      ),
                    ],
                  ),
                );
                if (sure != true || !context.mounted) return;
                await _tryAction(
                  context,
                  controller,
                  gc.TransferRealm(slot: slot, targetSlot: target),
                );
              },
            ),
        ],
      ),
    ),
  );
}

void _sellSheet(
  BuildContext context,
  GameController controller,
  gc.MarketGood good,
  int stock,
  double price,
) {
  _amountSheet(
    context,
    title: good == gc.MarketGood.grain ? tr('sellGrain') : tr('sellCattle'),
    max: stock,
    detail: (amount) => tr('menus.yields', {'amount': (amount * price).round()}),
    onSubmit: (amount) => _tryAction(
      context,
      controller,
      gc.SellGood(slot: controller.currentSlot, good: good, amount: amount),
    ),
  );
}

void _investSheet(BuildContext context, GameController controller) {
  final realm = controller.currentRealm;
  final cap = gc.shipInvestmentCap(realm);
  _amountSheet(
    context,
    title: tr('investShips'),
    max: cap < realm.treasury ? cap : realm.treasury,
    detail: (amount) => tr('menus.investDetail', {'amount': amount}),
    onSubmit: (amount) => _tryAction(
      context,
      controller,
      gc.InvestShips(slot: controller.currentSlot, amount: amount),
    ),
  );
}

// --- Military ---------------------------------------------------------

/// The Militär sheet — opened directly from the bottom action bar.
void showMilitaryMenu(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final realm = controller.currentRealm;
  final state = controller.state;
  final freeCapacity = realm.troopCapacity - realm.armySize;
  final levyLeft = gc.levyLeft(realm);
  // No recruiting/hiring while at war (engine gate, mirrored).
  final atWar = state.activeWar?.isParticipant(slot) ?? false;

  // The §11.1 war gates — the engine's own blocker, so the disabled
  // button shows exactly the reason a tap would fail with.
  final warBlocked = gc.warDeclarationBlocker(state, realm);

  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(tr('recruit')),
            subtitle: Text(
              atWar
                  ? tr('menus.notMidWar')
                  : tr('menus.recruitSubtitle', {
                      'cost': gc.recruitCostPerMan,
                      'capacity': freeCapacity,
                      'levy': levyLeft,
                    }),
            ),
            enabled:
                !atWar &&
                freeCapacity > 0 &&
                realm.treasury >= gc.recruitCostPerMan &&
                levyLeft > 0,
            onTap: () {
              Navigator.pop(sheetContext);
              // Position first, then class and amount. Follow-up sheets use
              // the stable screen [context] — the sheet's own context dies
              // with the pop and must not leak into later steps.
              _stationSheet(
                context,
                controller,
                onPicked: (x, y) => _recruitSheet(context, controller, x, y),
              );
            },
          ),
          ListTile(
            title: Text(tr('hireSoeldner')),
            subtitle: Text(
              atWar
                  ? tr('menus.notMidWar')
                  : tr('menus.soeldnerSubtitle', {
                      'cost': gc.soeldnerCostPerMan,
                    }),
            ),
            enabled: !atWar && realm.treasury >= gc.soeldnerCostPerMan,
            onTap: () {
              Navigator.pop(sheetContext);
              _stationSheet(
                context,
                controller,
                onPicked: (x, y) {
                  _amountSheet(
                    context,
                    title: tr('hireSoeldner'),
                    max:
                        controller.currentRealm.treasury ~/
                        gc.soeldnerCostPerMan,
                    detail: (men) =>
                        tr('menus.costs', {'cost': gc.soeldnerCost(men)}),
                    onSubmit: (men) => _tryAction(
                      context,
                      controller,
                      gc.HireSoeldner(
                        slot: slot,
                        men: men,
                        name: 'Söldner',
                        x: x,
                        y: y,
                      ),
                    ),
                  );
                },
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.groups_2),
            title: Text(tr('menus.troopList', {'n': realm.troops.length})),
            subtitle: Text(tr('menus.armyMen', {'n': realm.armySize})),
            enabled: realm.troops.isNotEmpty,
            onTap: () {
              Navigator.pop(sheetContext);
              _showTroopList(context, controller);
            },
          ),
          ListTile(
            leading: const Icon(Icons.gavel),
            title: Text(tr('declareWar')),
            subtitle: Text(warBlocked ?? tr('menus.warOncePerYear')),
            enabled: warBlocked == null,
            onTap: () {
              Navigator.pop(sheetContext);
              _declareWarSheet(context, controller);
            },
          ),
        ],
      ),
    ),
  );
}

/// Position picker for a new unit ("ask for the place first"): the
/// capital directly, or any own map tile via "Feld auswählen" — the
/// sheet closes, the player taps the tile, then the unit is configured.
void _stationSheet(
  BuildContext context,
  GameController controller, {
  required void Function(int x, int y) onPicked,
}) {
  final realm = controller.currentRealm;
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              tr('menus.stationWhere'),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.flag),
            title: Text(tr('menus.capital')),
            subtitle: Text(
              tr('menus.tileAt', {
                'x': realm.capitalX + 1,
                'y': realm.capitalY + 1,
              }),
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              onPicked(realm.capitalX, realm.capitalY);
            },
          ),
          ListTile(
            leading: const Icon(Icons.touch_app),
            title: Text(tr('menus.pickTile')),
            subtitle: Text(tr('menus.pickTileSubtitle')),
            onTap: () {
              Navigator.pop(sheetContext);
              controller.startTilePick(
                hint: tr('menus.pickTileHint'),
                onPick: (x, y) async {
                  if (controller.state.map.ownerAt(x, y) !=
                      controller.currentSlot) {
                    _toast(context, tr('menus.stationOwnTerritory'));
                    return false;
                  }
                  onPicked(x, y);
                  return true;
                },
              );
            },
          ),
        ],
      ),
    ),
  );
}

void _recruitSheet(
  BuildContext context,
  GameController controller,
  int x,
  int y,
) {
  final slot = controller.currentSlot;
  final realm = controller.currentRealm;
  var troopClass = gc.TroopClass.infanterie;
  final nameController = TextEditingController(text: tr('menus.recruitsName'));
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setState) {
        // 5 T per man plus the one-time class surcharge — the slider only
        // offers what the quarters, the treasury and this year's levy
        // limit can carry.
        final levyLeft = gc.levyLeft(realm);
        final maxMen = [
          realm.troopCapacity - realm.armySize,
          levyLeft,
          (realm.treasury - gc.classSurcharge(troopClass)) ~/
              gc.recruitCostPerMan,
        ].reduce(math.min);
        return SafeArea(
          child: Padding(
            // Keep the sheet above the on-screen keyboard.
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            // Scrollable so a small screen with the keyboard up never overflows.
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      controller: nameController,
                      maxLength: gc.maxNameLength,
                      decoration: InputDecoration(
                        labelText: tr('menus.troopNameLabel'),
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ),
                  // FittedBox: three class labels overflow narrow phones in a
                  // fixed SegmentedButton — scale the whole control down instead.
                  // The one-time surcharge is reflected live in the cost line
                  // below, so the segment labels stay short.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: [
                          for (var cls = 0; cls <= 2; cls++)
                            ButtonSegment(
                              value: cls,
                              label: Text(troopClassName(cls)),
                            ),
                        ],
                        selected: {troopClass},
                        onSelectionChanged: (s) =>
                            setState(() => troopClass = s.first),
                      ),
                    ),
                  ),
                  if (maxMen < 1)
                    ListTile(
                      title: Text(
                        levyLeft < 1
                            ? tr('menus.levyExhausted')
                            : tr('menus.notEnoughTaler'),
                      ),
                    )
                  else
                    _AmountSlider(
                      key: ValueKey(troopClass),
                      title: tr('recruit'),
                      max: maxMen,
                      detail: (men) => tr('menus.recruitCostDetail', {
                        'cost': gc.recruitCost(men, troopClass),
                        'strength': gc.previewTroopStrength(
                          men,
                          troopClass,
                          gc.TroopQuality.regular,
                        ),
                      }),
                      onSubmit: (men) {
                        Navigator.pop(sheetContext);
                        _tryAction(
                          context,
                          controller,
                          gc.RecruitTroops(
                            slot: slot,
                            men: men,
                            troopClass: troopClass,
                            name: nameController.text.trim().isEmpty
                                ? tr('menus.recruitsName')
                                : nameController.text.trim(),
                            x: x,
                            y: y,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// "Truppen(l)iste": overview of all own units — tap to inspect/edit.
void _showTroopList(BuildContext context, GameController controller) {
  final realm = controller.currentRealm;
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              tr('menus.troopListTitle', {'n': realm.armySize}),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          for (var i = 0; i < realm.troops.length; i++)
            ListTile(
              leading: const Icon(Icons.groups_2),
              title: Text(
                tr('menus.troopTitle', {
                  'name': realm.troops[i].name,
                  'men': realm.troops[i].men,
                }),
              ),
              subtitle: Text(
                tr('menus.troopSubtitle', {
                  'cls': troopClassName(realm.troops[i].troopClass),
                  'tag': !realm.troops[i].garrisonCounted
                      ? tr('menus.soeldnerTag')
                      : '',
                  'strength': gc.troopStrength(realm.troops[i]).round(),
                  'x': realm.troops[i].x + 1,
                  'y': realm.troops[i].y + 1,
                }),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(sheetContext);
                showTroopActions(context, controller, i);
              },
            ),
        ],
      ),
    ),
  );
}

/// Per-unit info & edit sheet (§10.2): verlegen, verstärken, vereinigen,
/// auflösen. Public — the tile sheet opens it when tapping a stationed army.
void showTroopActions(
  BuildContext context,
  GameController controller,
  int index,
) {
  // The screen's context — onPick of the move tile fires long after the
  // sheet (and its builder context) is gone.
  final screenContext = context;
  final slot = controller.currentSlot;
  showModalBottomSheet<void>(
    context: context,
    // Rebuilt on every controller change: drilling keeps the sheet open
    // (the player drills repeatedly), so cost/quality lines must refresh
    // in place.
    builder: (sheetContext) => ListenableBuilder(
      listenable: controller,
      builder: (sheetContext, _) {
        final realm = controller.currentRealm;
        if (index >= realm.troops.length) {
          // The unit is gone (e.g. undone recruit) — nothing to show.
          return const SafeArea(child: SizedBox(height: 80));
        }
        final troop = realm.troops[index];
        // Mercenaries are identified by NOT counting against the garrison —
        // never by quality == 3, which a drilled regular also reaches and
        // would then be wrongly treated as a Söldner (drill/retrain hidden).
        final soeldner = !troop.garrisonCounted;
        final costPerMan = soeldner
            ? gc.soeldnerCostPerMan
            : gc.recruitCostPerMan;
        final affordable = realm.treasury ~/ costPerMan;
        final capacity = realm.troopCapacity - realm.armySize;
        // Regulars are capped by quarters AND this year's levy limit;
        // Söldner (hired abroad) by the treasury alone.
        final levyLeft = gc.levyLeft(realm);
        final maxReinforce = soeldner
            ? affordable
            : [capacity, affordable, levyLeft].reduce(math.min);
        // Merging/disbanding is forbidden while at war (the war state is
        // keyed to the troop list) — mirror the engine gate so the options
        // grey out (the gate covers reinforcing as well).
        final atWar = controller.state.activeWar?.isParticipant(slot) ?? false;
        final reinforceBlocked = atWar;
        final mergeTargets = [
          for (var i = 0; i < realm.troops.length; i++)
            if (i != index && gc.canMergeTroops(realm.troops[i], troop)) i,
        ];
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  tr('menus.troopTitle', {
                    'name': troop.name,
                    'men': troop.men,
                  }),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                subtitle: Text(
                  tr('menus.troopSubtitle', {
                    'cls': troopClassName(troop.troopClass),
                    'tag': soeldner ? tr('menus.soeldnerTag') : '',
                    'strength': gc.troopStrength(troop).round(),
                    'x': troop.x + 1,
                    'y': troop.y + 1,
                  }),
                ),
              ),
              // Per-unit stance for an UNATTENDED war round (online war clock
              // run out, or the player left): the engine autopilots the side
              // by each unit's stance. Offline the player moves every unit by
              // hand, so the stance is never consulted — only shown online.
              if (controller.isOnline) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.policy_outlined,
                        size: 20,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr('menus.autoWarStance'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: gc.TroopStance.holdPosition,
                        icon: const Icon(Icons.shield_outlined, size: 16),
                        label: Text(tr('menus.stanceHold')),
                      ),
                      ButtonSegment(
                        value: gc.TroopStance.attack,
                        icon: const Icon(Icons.gps_fixed, size: 16),
                        label: Text(tr('menus.stanceAttack')),
                      ),
                    ],
                    selected: {troop.stance},
                    onSelectionChanged: (selection) async {
                      try {
                        await controller.applyUndoable(
                          gc.SetTroopStance(
                            slot: slot,
                            unitIndex: index,
                            stance: selection.first,
                          ),
                        );
                      } on gc.ActionException catch (e) {
                        if (screenContext.mounted) {
                          _toast(screenContext, e.message);
                        }
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    troop.stance == gc.TroopStance.holdPosition
                        ? tr('menus.stanceHoldDesc')
                        : tr('menus.stanceAttackDesc'),
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.open_with),
                title: Text(tr('menus.moveTroop')),
                // Relocating troops is free — only building costs Züge.
                subtitle: Text(tr('menus.moveTroopSubtitle')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  controller.startTilePick(
                    hint: tr('menus.moveTroopHint', {'name': troop.name}),
                    onPick: (x, y) async {
                      try {
                        await controller.applyUndoable(
                          gc.MoveTroop(
                            slot: slot,
                            unitIndex: index,
                            x: x,
                            y: y,
                          ),
                        );
                        return true;
                      } on gc.ActionException catch (e) {
                        if (screenContext.mounted) {
                          _toast(screenContext, e.message);
                        }
                        return false;
                      }
                    },
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.group_add),
                title: Text(tr('menus.reinforceTroop')),
                subtitle: Text(
                  reinforceBlocked
                      ? tr('menus.notMidWar')
                      : tr('menus.costPerMan', {'cost': costPerMan}),
                ),
                enabled: !reinforceBlocked && maxReinforce > 0,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _amountSheet(
                    context,
                    title: tr('menus.reinforceTroop'),
                    max: maxReinforce,
                    detail: (men) => tr('menus.costs', {
                      'cost': gc.reinforceCost(troop, men),
                    }),
                    onSubmit: (men) => _tryAction(
                      context,
                      controller,
                      gc.ReinforceTroop(slot: slot, unitIndex: index, men: men),
                    ),
                  );
                },
              ),
              // Drill (the original "Truppe ausbilden"): +1 quality for
              // 5 T/man, class unchanged; as often per turn as the treasury
              // allows. Kept high in the list (right after "verstärken") so
              // its position never shifts while it is tapped repeatedly —
              // the merge options below come and go as drilling changes this
              // troop's quality, and a button that moved under the finger
              // used to cause mis-taps onto "auflösen".
              ListTile(
                leading: const Icon(Icons.fitness_center),
                title: Text(tr('menus.drillTroop')),
                subtitle: Text(
                  soeldner
                      ? tr('menus.soeldnerNoDrill')
                      : atWar
                      ? tr('menus.notMidWar')
                      : troop.quality >= gc.Troop.drillCap
                      ? tr('menus.fullyDrilled', {'quality': troop.quality})
                      : tr('menus.drillDetail', {
                          'cost': gc.drillCost(troop),
                          'from': troop.quality,
                          'to': troop.quality + 1,
                        }),
                ),
                // Disabled (greyed out), never hidden — a vanishing button
                // shifts the others up and causes accidental taps.
                enabled:
                    !soeldner &&
                    !atWar &&
                    troop.quality < gc.Troop.drillCap &&
                    realm.treasury >= gc.drillCost(troop),
                // The sheet stays open: drilling is repeatable and the
                // ListenableBuilder refreshes quality/cost in place.
                onTap: () => _tryAction(
                  context,
                  controller,
                  gc.DrillTroop(slot: slot, unitIndex: index),
                  undoable: true,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.military_tech),
                title: Text(tr('menus.retrainTroop')),
                subtitle: Text(
                  soeldner
                      ? tr('menus.soeldnerNoRetrain')
                      : atWar
                      ? tr('menus.notMidWar')
                      : tr('menus.retrainSubtitle', {
                          'cost': gc.recruitCostPerMan,
                        }),
                ),
                enabled: !soeldner && !atWar,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _trainSheet(context, controller, index);
                },
              ),
              for (final other in mergeTargets)
                ListTile(
                  leading: const Icon(Icons.merge),
                  title: Text(
                    tr('menus.mergeWithTroop', {
                      'name': realm.troops[other].name,
                      'men': realm.troops[other].men,
                    }),
                  ),
                  subtitle: atWar
                      ? Text(tr('menus.notMidWar'))
                      : null,
                  enabled: !atWar,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _tryAction(
                      context,
                      controller,
                      gc.MergeTroops(
                        slot: slot,
                        fromIndex: index,
                        toIndex: other,
                      ),
                      undoable: true,
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: Text(tr('menus.renameTroop')),
                subtitle: atWar ? Text(tr('menus.notMidWar')) : null,
                enabled: !atWar,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _renameTroopDialog(context, controller, index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(tr('menus.disbandTroop')),
                subtitle: atWar ? Text(tr('menus.notMidWar')) : null,
                enabled: !atWar,
                // Destructive: confirm first, so a stray tap (e.g. while
                // spamming "ausbilden" above) can never disband by accident.
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text(tr('menus.disbandTroopQuestion')),
                      content: Text(
                        tr('menus.disbandTroopConfirm', {
                          'name': troop.name,
                          'men': troop.men,
                        }),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(tr('cancel')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: Text(tr('menus.disband')),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (!context.mounted) return;
                  await _tryAction(
                    context,
                    controller,
                    gc.DisbandTroop(slot: slot, unitIndex: index),
                    undoable: true,
                  );
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// "Truppe umrüsten": retrain to another class — 5 T/man plus
/// the class surcharge; the new strength is shown per option.
void _trainSheet(BuildContext context, GameController controller, int index) {
  final slot = controller.currentSlot;
  final realm = controller.currentRealm;
  final troop = realm.troops[index];
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              tr('menus.retrainTitle', {
                'name': troop.name,
                'strength': gc.troopStrength(troop).round(),
              }),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          for (
            var cls = gc.TroopClass.infanterie;
            cls <= gc.TroopClass.artillerie;
            cls++
          )
            if (cls != troop.troopClass)
              Builder(
                builder: (sheetContext) {
                  final cost = gc.retrainCost(troop, cls);
                  final newStrength = gc.previewTroopStrength(
                    troop.men,
                    cls,
                    troop.quality,
                  );
                  return ListTile(
                    leading: const Icon(Icons.military_tech),
                    title: Text(
                      tr('menus.retrainTo', {'cls': troopClassName(cls)}),
                    ),
                    subtitle: Text(
                      tr('menus.retrainDetail', {
                        'cost': cost,
                        'strength': newStrength,
                      }),
                    ),
                    enabled: realm.treasury >= cost,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _tryAction(
                        context,
                        controller,
                        gc.TrainTroop(
                          slot: slot,
                          unitIndex: index,
                          troopClass: cls,
                        ),
                        undoable: true,
                      );
                    },
                  );
                },
              ),
        ],
      ),
    ),
  );
}

void _renameTroopDialog(
  BuildContext context,
  GameController controller,
  int index,
) {
  final troop = controller.currentRealm.troops[index];
  final nameController = TextEditingController(text: troop.name);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(tr('menus.renameTroop')),
      content: TextField(
        controller: nameController,
        maxLength: gc.maxNameLength,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(tr('cancel')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            _tryAction(
              context,
              controller,
              gc.RenameTroop(
                slot: controller.currentSlot,
                unitIndex: index,
                name: nameController.text,
              ),
              undoable: true,
            );
          },
          child: Text(tr('menus.ok')),
        ),
      ],
    ),
  );
}

void _declareWarSheet(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final state = controller.visibleState;
  // Wars need a shared border — only neighbors are offered.
  final neighbors = controller.state.map.realmNeighbors(slot);
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          if (neighbors.isEmpty)
            ListTile(title: Text(tr('menus.noSharedBorder'))),
          for (final realm in state.realms)
            if (realm.slot != slot &&
                !realm.isVacant &&
                // No war against a slot your own ruler already holds.
                realm.rulerId != controller.currentRealm.rulerId &&
                neighbors.contains(realm.slot))
              // Per-TARGET gates (post-war truce): the engine's own blocker
              // again, so a barred neighbour is greyed out with the reason
              // instead of failing only after the confirmation dialog.
              // `(_)`: the sheet's own context must NOT shadow [context] —
              // the confirmation below deliberately runs on the stable
              // screen context (see the comment there).
              Builder(builder: (_) {
                final blocked = gc.declareWarBlocker(
                    controller.state, controller.currentRealm, realm.slot);
                return ListTile(
                  enabled: blocked == null,
                  title: Text(realmName(realm.slot)),
                  subtitle: Text(
                    blocked ??
                        state.person(realm.rulerId)?.name ??
                        tr('menus.unknown'),
                  ),
                  onTap: () async {
                    // Confirm on the stable screen [context]: the sheet's own
                    // context is unmounted once its exit animation ends, so a
                    // mounted-check on it after the dialog would silently
                    // swallow the war declaration.
                    Navigator.pop(sheetContext);
                    final sure = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(
                          tr('menus.declareWarOn', {
                            'realm': realmName(realm.slot),
                          }),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(tr('cancel')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(tr('declareWar')),
                          ),
                        ],
                      ),
                    );
                    if (sure == true && context.mounted) {
                      await _tryAction(
                        context,
                        controller,
                        gc.DeclareWar(slot: slot, targetSlot: realm.slot),
                      );
                      // A human-vs-human war opens the preparation phase:
                      // the attacker answers their own warPlan right away
                      // (live vs autopilot + stance) instead of waiting for
                      // the next handoff.
                      if (context.mounted &&
                          controller.state.activeWar?.phase ==
                              gc.WarPhase.preparation) {
                        await promptDecisionsFor(context, controller, slot);
                      }
                    }
                  },
                );
              }),
        ],
      ),
    ),
  );
}

// --- Espionage --------------------------------------------------------

/// The Spionage sheet — opened directly from the bottom action bar.
void showEspionageMenu(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final realm = controller.currentRealm;
  // Follow-up sheets/dialogs use the stable screen [context] — the
  // sheet's own context dies with the pop (see showMilitaryMenu).
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(tr('menus.spyEconomy')),
            subtitle: Text(
              tr('menus.costPerAgent', {'cost': gc.economySpyCost}),
            ),
            enabled: realm.treasury >= gc.economySpyCost,
            onTap: () {
              Navigator.pop(sheetContext);
              _spySheet(context, controller, gc.SpyKind.economy);
            },
          ),
          ListTile(
            title: Text(tr('menus.spyMilitary')),
            subtitle: Text(
              tr('menus.costPerAgent', {'cost': gc.militarySpyCost}),
            ),
            enabled: realm.treasury >= gc.militarySpyCost,
            onTap: () {
              Navigator.pop(sheetContext);
              _spySheet(context, controller, gc.SpyKind.military);
            },
          ),
          ListTile(
            title: Text(tr('menus.assassinate')),
            subtitle: Text(
              tr('menus.costPerAgent', {'cost': gc.assassinCost}),
            ),
            enabled: realm.treasury >= gc.assassinCost,
            onTap: () {
              Navigator.pop(sheetContext);
              _assassinSheet(context, controller);
            },
          ),
          ListTile(
            title: Text(
              tr('menus.guardsLevel', {
                'level': realm.guardLevel,
                'cap': gc.guardCap,
              }),
            ),
            subtitle: Text(tr('menus.costPerMan', {'cost': gc.guardCost})),
            enabled:
                (realm.guardLevel < gc.guardCap &&
                    realm.treasury >= gc.guardCost) ||
                realm.guardLevel > 0,
            onTap: () {
              Navigator.pop(sheetContext);
              _amountSheet(
                context,
                title: tr('guards'),
                max: gc.guardCap - controller.currentRealm.guardLevel,
                allowNegative: controller.currentRealm.guardLevel,
                detail: (delta) => delta > 0
                    ? tr('menus.costs', {'cost': delta * gc.guardCost})
                    : tr('menus.dismissFree'),
                onSubmit: (delta) => _tryAction(
                  context,
                  controller,
                  gc.AdjustGuards(slot: slot, delta: delta),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

void _spySheet(
  BuildContext context,
  GameController controller,
  gc.SpyKind kind,
) {
  final costPerAgent = kind == gc.SpyKind.economy
      ? gc.economySpyCost
      : gc.militarySpyCost;
  // No more agents than the treasury can pay (engine cap stays at 30).
  _targetThenAmount(
    context,
    controller,
    max: math.min(30, controller.currentRealm.treasury ~/ costPerAgent),
    detail: (agents) =>
        tr('menus.agentsDetail', {'cost': agents * costPerAgent}),
    onSubmit: (target, agents) async {
      final gc.ActionResult result;
      try {
        result = await controller.applyIrreversible(
          gc.SpyMission(
            slot: controller.currentSlot,
            targetSlot: target,
            agents: agents,
            spyKind: kind,
          ),
        );
      } on gc.ActionException catch (e) {
        if (context.mounted) _toast(context, e.message);
        return;
      }
      if (!context.mounted) return;
      // The mission resolves within the action — confirm the dispatch and
      // reveal the outcome after a short suspense beat. On a failure with
      // caught agents the original's torture line tells the player their
      // cover is blown (the target realm learns the sponsor).
      gc.GameEvent? failure;
      for (final e in result.events) {
        if (e.type == 'missionFailed') failure = e;
      }
      final caught = failure?.payload['caught'] as int? ?? 0;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _SuspenseRevealDialog(
          title: tr('menus.spyTitle', {'realm': realmName(target)}),
          waitingText: tr('menus.spiesUnderway'),
          resultText: failure != null
              ? (caught > 0
                    ? tr(
                        caught == 1
                            ? 'menus.spyCaughtOne'
                            : 'menus.spyCaughtMany',
                        {
                          'caught': caught,
                          'realm': realmName(controller.currentSlot),
                        },
                      )
                    : tr('menus.spyNothing'))
              : tr('menus.spySuccess'),
          success: failure == null,
        ),
      );
    },
  );
}

void _assassinSheet(BuildContext context, GameController controller) {
  // No more agents than the treasury can pay (engine cap stays at 30).
  _targetThenAmount(
    context,
    controller,
    max: math.min(30, controller.currentRealm.treasury ~/ gc.assassinCost),
    detail: (agents) =>
        tr('menus.agentsDetail', {'cost': agents * gc.assassinCost}),
    // One attempt per realm per round (engine gate) — a realm already
    // targeted this turn cannot be picked again.
    disabledSlots: controller.currentRealm.assassinatedThisTurnSlots.toSet(),
    disabledNote: tr('menus.assassinAlready'),
    onSubmit: (target, agents) async {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('menus.assassinConfirm', {'realm': realmName(target)})),
          // The odds are deliberately poor (see the espionage ladder in
          // game_core) — say so before the taler are gone.
          content: Text(tr('menus.assassinRisk')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('menus.ok')),
            ),
          ],
        ),
      );
      if (sure != true || !context.mounted) return;
      try {
        await controller.applyIrreversible(
          gc.OrderAssassination(
            slot: controller.currentSlot,
            targetSlot: target,
            agents: agents,
          ),
        );
      } on gc.ActionException catch (e) {
        if (context.mounted) _toast(context, e.message);
        return;
      }
      if (!context.mounted) return;
      // Assassinations resolve later (event phase) — confirm the dispatch
      // so the player knows the order went through.
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('menus.assassinOrdered')),
          content: Text(tr('menus.assassinUnderway')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('menus.ok')),
            ),
          ],
        ),
      );
    },
  );
}

// --- Misc & Info ------------------------------------------------------

/// The Dynastie sheet (menu key 'misc') — opened directly from the
/// bottom action bar.
void showMiscMenu(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final state = controller.state;
  final realm = controller.currentRealm;
  final capitalLost = state.map.ownerAt(realm.capitalX, realm.capitalY) != slot;
  // After a cross-dynasty inheritance the ruling house differs from the
  // slot: the "Dynastie" sheet and the marriage pickers follow the ruler's
  // home dynasty, so the ruler themself stays listed and marriageable.
  final houseSlot = state.persons[realm.rulerId]?.dynasty ?? slot;
  final hasProposer = state.persons.values.any(
    (p) => gc.memberOfRulingHouse(state, realm, p) && _marriageable(state, p),
  );
  // The royal proposal is limited to one per PERSON per turn — blocked only
  // once every marriageable member has already proposed this turn.
  final hasRoyalProposer = state.persons.values.any(
    (p) =>
        gc.memberOfRulingHouse(state, realm, p) &&
        _marriageable(state, p) &&
        !realm.proposedThisTurnIds.contains(p.id),
  );
  final String? marriageBlocked = !hasProposer
      ? tr('menus.nobodyMarriageable')
      : !hasRoyalProposer
      ? tr('menus.allProposed')
      : null;
  // Commoner marriage is always available — it does not count against the
  // per-person proposal limit.
  final String? commonerBlocked = hasProposer
      ? null
      : tr('menus.nobodyMarriageable');
  // Follow-up sheets use the stable screen [context] — the sheet's own
  // context dies with the pop (see showMilitaryMenu).
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.people),
            title: Text(tr('misc')),
            subtitle: Text(
              tr('menus.dynastySubtitle', {
                'n': state.dynasty(houseSlot).memberIds.length,
              }),
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              _showDynastyOf(context, controller, houseSlot);
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: Text(tr('proposeMarriage')),
            subtitle: marriageBlocked == null ? null : Text(marriageBlocked),
            enabled: marriageBlocked == null,
            onTap: () {
              Navigator.pop(sheetContext);
              _showMarriageProposers(context, controller);
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite),
            title: Text(tr('menus.marryCommoner')),
            subtitle: Text(
              commonerBlocked ?? tr('menus.marryCommonerSubtitle'),
            ),
            enabled: commonerBlocked == null,
            onTap: () {
              Navigator.pop(sheetContext);
              _showCommonerMarriage(context, controller);
            },
          ),
          // §17.5: the office holder plunders the crown pot manually — the
          // gottgegebene Recht of every Kaiser/Sultan. A ruler can hold
          // BOTH offices (a Kaiser whose dynasty converted to Islam may
          // win the Sultan election) — then both pots are theirs.
          if ((state.kaiserId != null && realm.rulerId == state.kaiserId) ||
              (state.sultanId != null && realm.rulerId == state.sultanId))
            ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: Text(tr('menus.plunderTreasury')),
              subtitle: Text(
                [
                  if (state.kaiserId != null && realm.rulerId == state.kaiserId)
                    tr('menus.kaiserPot', {'amount': state.kaiserPot}),
                  if (state.sultanId != null && realm.rulerId == state.sultanId)
                    tr('menus.sultanPot', {'amount': state.sultanPot}),
                ].join(' — '),
              ),
              enabled:
                  (state.kaiserId != null &&
                      realm.rulerId == state.kaiserId &&
                      state.kaiserPot > 0) ||
                  (state.sultanId != null &&
                      realm.rulerId == state.sultanId &&
                      state.sultanPot > 0),
              onTap: () {
                Navigator.pop(sheetContext);
                _tryAction(
                  context,
                  controller,
                  gc.CollectTribute(slot: slot),
                  undoable: true,
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.location_city),
            title: Text(tr('menus.relocateSeat')),
            subtitle: Text(
              capitalLost
                  ? tr('menus.relocateSeatLost')
                  : tr('menus.relocateSeatSubtitle', {
                      'cost': gc.relocateCapitalCost,
                    }),
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              _showRelocateCapital(context, controller);
            },
          ),
          // §15.2 religion availability and prices straight from the
          // engine ([religionAvailable]/[religionChangeCost]) — hidden
          // entirely until a faith exists.
          for (final (religion, nameKey) in const [
            (gc.Religion.katholisch, 'menus.religionCatholic'),
            (gc.Religion.evangelisch, 'menus.religionProtestant'),
            (gc.Religion.moslemisch, 'menus.religionMuslim'),
          ])
            if (gc.religionAvailable(state, religion) &&
                state.dynasty(slot).religion != religion)
              ListTile(
                title: Text(
                  tr('menus.religionOption', {'religion': tr(nameKey)}),
                ),
                trailing: Text(
                  tr('menus.religionCost', {
                    'cost': gc.religionChangeCost(religion),
                    'pop': gc.religionChangePopularityCost,
                  }),
                ),
                enabled: realm.treasury >= gc.religionChangeCost(religion),
                // A faith change is momentous and easy to tap by accident
                // once the options appear — always confirm first.
                onTap: () async {
                  final sure = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text(tr('menus.changeReligionQuestion')),
                      content: Text(
                        tr('menus.religionConfirmBody', {
                          'faith': tr(nameKey),
                          'cost': gc.religionChangeCost(religion),
                          'pop': gc.religionChangePopularityCost,
                        }),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(tr('cancel')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: Text(tr('menus.change')),
                        ),
                      ],
                    ),
                  );
                  if (sure != true || !context.mounted) return;
                  Navigator.pop(context);
                  _tryAction(
                    context,
                    controller,
                    gc.ChangeReligion(slot: slot, religion: religion),
                  );
                },
              ),
          ListTile(
            title: Text(tr('menus.electors')),
            subtitle: Text(
              state.kurfuerstenIds
                  .map((id) => state.persons[id]?.name ?? '?')
                  .join(', '),
            ),
          ),
        ],
      ),
    ),
  );
}

/// "Sitz verlegen" (§6.2): pick one of the own Stadt/Burg/Palast tiles.
/// Allowed any time — 5000 T voluntarily, free when the seat is lost.
void _showRelocateCapital(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final state = controller.state;
  final map = state.map;
  final realm = state.realm(slot);
  final lost = map.ownerAt(realm.capitalX, realm.capitalY) != slot;
  final costLabel = lost
      ? tr('menus.free')
      : '${gc.relocateCapitalCost} T';
  final candidates = <(int, int, int)>[];
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      final building = map.buildingAt(x, y);
      // The engine's seat rule (§6.2): Stadt, Burg or Palast.
      if (map.ownerAt(x, y) == slot && gc.Building.isSeat(building)) {
        candidates.add((x, y, building));
      }
    }
  }
  if (candidates.isEmpty) {
    _toast(context, tr('menus.needSeatBuilding'));
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    // The error toast must outlive the sheet: pop with the SHEET context,
    // act (and toast) through the stable screen context — an engine
    // rejection (e.g. treasury below 5000 T online) arrives after the
    // sheet is unmounted and would otherwise vanish silently.
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final (x, y, building) in candidates)
            ListTile(
              leading: const Icon(Icons.location_city),
              title: Text('${buildingName(building)} (${x + 1}, ${y + 1})'),
              trailing: Text(costLabel),
              onTap: () {
                Navigator.pop(sheetContext);
                _tryAction(
                  context,
                  controller,
                  gc.RelocateCapital(slot: slot, x: x, y: y),
                  undoable: true,
                );
              },
            ),
        ],
      ),
    ),
  );
}

/// Dynasty overview ("Dynastien-Info"): every living member of [slot]'s
/// dynasty with age, spouse and children. Dynasty composition is public
/// information, so foreign dynasties may be viewed too.
void _showDynastyOf(BuildContext context, GameController controller, int slot) {
  final state = controller.state;
  final members = [
    for (final id in state.dynasty(slot).memberIds)
      if (state.persons[id] != null) state.persons[id]!,
  ];
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: ListView(
          children: [
            ListTile(
              title: Text(
                tr('menus.dynastyOf', {'realm': realmName(slot)}),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            for (final p in members)
              ListTile(
                leading: Icon(p.isMale ? Icons.male : Icons.female),
                title: Text(
                  '${p.name} (${p.age})'
                  '${state.realm(slot).rulerId == p.id ? ' — ${titleName(state.realm(slot).titleClass)}' : ''}',
                ),
                subtitle: Text(
                  [
                    _spouseLine(state, p),
                    if (p.childrenIds.isNotEmpty)
                      tr(
                        p.childrenIds.length == 1
                            ? 'menus.childCount'
                            : 'menus.childrenCount',
                        {'n': p.childrenIds.length},
                      ),
                  ].join(' — '),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Marital status line: spouses from another dynasty carry their country
/// ("verheiratet mit Anna von Sachsen"); commoner spouses share the
/// member's dynasty and are marked "(bürgerlich)".
String _spouseLine(gc.GameState state, gc.Person p) {
  if (p.spouseId == null) return tr('menus.single');
  final spouse = state.persons[p.spouseId!];
  if (spouse == null) return tr('menus.married');
  return spouse.dynasty == p.dynasty
      ? tr('menus.marriedToCommoner', {'name': spouse.name})
      : tr('menus.marriedTo', {
          'name': spouse.name,
          'realm': realmName(spouse.dynasty),
        });
}

// --- Marriage -----------------------------------------------------------

/// Unmarried, of age, and not sitting on an unanswered proposal (either
/// side of a pending `marriageConsent` — mirrors the engine's guard).
bool _marriageable(gc.GameState state, gc.Person p) =>
    p.spouseId == null &&
    p.age >= 14 &&
    !gc.awaitingMarriageConsent(state, p.id);

/// Step 1 of "Heirat vorschlagen" (§14.1): pick the own dynasty member.
/// Members who already proposed this turn are filtered out (one royal
/// proposal per person per turn — mirrors the engine's guard).
void _showMarriageProposers(BuildContext context, GameController controller) {
  final state = controller.state;
  final realm = controller.currentRealm;
  final proposers = [
    for (final p in state.persons.values)
      if (gc.memberOfRulingHouse(state, realm, p) &&
          _marriageable(state, p) &&
          !realm.proposedThisTurnIds.contains(p.id))
        p,
  ];
  if (proposers.isEmpty) {
    _toast(context, tr('menus.noPartner'));
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              tr('proposeMarriage'),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            subtitle: Text(tr('menus.whoShallMarry')),
          ),
          const Divider(height: 1),
          for (final p in proposers)
            ListTile(
              leading: Icon(p.isMale ? Icons.male : Icons.female),
              title: Text('${p.name} (${p.age})'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showMarriageCandidates(context, controller, p);
              },
            ),
        ],
      ),
    ),
  );
}

/// Step 2: pick the partner. Uses the engine's own §14.1 pair predicate
/// ([gc.marriageEligible]) so only proposals `applyAction` accepts are
/// offered.
void _showMarriageCandidates(
  BuildContext context,
  GameController controller,
  gc.Person proposer,
) {
  final slot = controller.currentSlot;
  final state = controller.state;
  final candidates = [
    for (final p in state.persons.values)
      if (gc.marriageEligible(state, proposer, p) &&
          !gc.awaitingMarriageConsent(state, p.id))
        p,
  ];
  if (candidates.isEmpty) {
    _toast(context, tr('menus.noPartner'));
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              tr('menus.partnerFor', {
                'name': proposer.name,
                'age': proposer.age,
              }),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          for (final p in candidates)
            ListTile(
              leading: Icon(p.isMale ? Icons.male : Icons.female),
              title: Text('${p.name} (${p.age})'),
              subtitle: Text(realmName(p.dynasty)),
              onTap: () {
                Navigator.pop(sheetContext);
                _proposeAndReveal(
                  context,
                  controller,
                  gc.ProposeMarriage(
                    slot: slot,
                    proposerId: proposer.id,
                    targetId: p.id,
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );
}

/// "(B)ürgerlich heiraten": pick the dynasty member, then roll the 25%
/// commoner acceptance with the reveal modal.
void _showCommonerMarriage(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final state = controller.state;
  final proposers = [
    for (final p in state.persons.values)
      if (gc.memberOfRulingHouse(state, controller.currentRealm, p) &&
          _marriageable(state, p))
        p,
  ];
  if (proposers.isEmpty) {
    _toast(context, tr('menus.noPartner'));
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              tr('menus.marryCommoner'),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            subtitle: Text(tr('menus.whoShallMarry')),
          ),
          const Divider(height: 1),
          for (final p in proposers)
            ListTile(
              leading: Icon(p.isMale ? Icons.male : Icons.female),
              title: Text('${p.name} (${p.age})'),
              onTap: () {
                Navigator.pop(sheetContext);
                _proposeAndReveal(
                  context,
                  controller,
                  gc.MarryCommoner(slot: slot, personId: p.id),
                );
              },
            ),
        ],
      ),
    ),
  );
}

/// Applies the proposal and reveals the answer in a modal — with a short
/// suspense beat before "Angenommen !" / "Abgelehnt !". A human target
/// answers at their next turn instead (pending decision).
Future<void> _proposeAndReveal(
  BuildContext context,
  GameController controller,
  gc.PlayerAction action,
) async {
  final gc.ActionResult result;
  try {
    result = await controller.applyIrreversible(action);
  } on gc.ActionException catch (e) {
    if (context.mounted) _toast(context, e.message);
    return;
  }
  final accepted = result.events.any((e) => e.type == 'wedding');
  final rejected = result.events.any((e) => e.type == 'marriageRejected');
  if (!context.mounted) return;
  if (!accepted && !rejected) {
    // Human target: the answer arrives as a pending decision next turn —
    // confirm the dispatch in a modal so the action visibly succeeded.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('menus.marriageProposal')),
        content: Text(tr('menus.proposalPending')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('menus.ok')),
          ),
        ],
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SuspenseRevealDialog(
      title: tr('menus.marriageProposal'),
      waitingText: tr('menus.proposalUnderway'),
      resultText: accepted ? tr('menus.accepted') : tr('menus.rejected'),
      success: accepted,
    ),
  );
}

/// Modal with a short suspense beat before revealing an action's outcome
/// (marriage answers, spy missions): spinner + waiting text first, then
/// the colored result.
class _SuspenseRevealDialog extends StatefulWidget {
  const _SuspenseRevealDialog({
    required this.title,
    required this.waitingText,
    required this.resultText,
    required this.success,
  });

  final String title;
  final String waitingText;
  final String resultText;
  final bool success;

  @override
  State<_SuspenseRevealDialog> createState() => _SuspenseRevealDialogState();
}

class _SuspenseRevealDialogState extends State<_SuspenseRevealDialog> {
  bool _revealed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _revealed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _revealed
            ? Text(
                widget.resultText,
                key: const ValueKey('answer'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: widget.success ? Colors.green : Colors.red,
                ),
              )
            : Row(
                key: const ValueKey('waiting'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Flexible(child: Text(widget.waitingText)),
                ],
              ),
      ),
      actions: [
        FilledButton(
          onPressed: _revealed ? () => Navigator.pop(context) : null,
          child: Text(tr('menus.ok')),
        ),
      ],
    );
  }
}

/// The Info sheet — "Mein Reich" stats, events, dynasties, chronicle.
void showInfoMenu(BuildContext context, GameController controller) {
  final state = controller.visibleState;
  final realm = controller.currentRealm;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.75,
        child: ListView(
          children: [
            // "Mein Reich" — the stats that used to crowd the HUD.
            ListTile(
              title: Text(
                '${tr('menus.myRealm', {'realm': realmName(realm.slot)})}'
                '${state.person(realm.rulerId) == null ? '' : ' (${titleName(realm.titleClass)} ${state.person(realm.rulerId)!.name})'}',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text('${tr('treasury')}: ${realm.treasury} T'),
                    Text('${tr('population')}: ${realm.population}'),
                    Text(
                      '${tr('food')}: ${realm.grainHarvest + realm.livestockHarvest}',
                    ),
                    Text('${tr('popularity')}: ${realm.popularity}'),
                    Text(tr('menus.armyStat', {'n': realm.armySize})),
                    Text('${tr('guards')}: ${realm.guardLevel}'),
                    Text('${tr('moves')}: ${realm.movementPoints}'),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.article),
              title: Text(tr('eventFeed')),
              onTap: () {
                Navigator.pop(sheetContext);
                showEventFeed(context, controller);
              },
            ),
            ListTile(
              leading: const Icon(Icons.home_work),
              title: Text(tr('menus.settlements', {'n': realm.towns.length})),
              onTap: () {
                Navigator.pop(sheetContext);
                _showSettlements(context, controller);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: Text(tr('menus.dynasties')),
              subtitle: Text(tr('menus.dynastiesSubtitle')),
              onTap: () {
                Navigator.pop(sheetContext);
                _showDynasties(context, controller);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_edu),
              title: Text(tr('chronicle')),
              subtitle: Text(tr('menus.chronicleSubtitle')),
              onTap: () {
                Navigator.pop(sheetContext);
                _showChronicle(context, controller);
              },
            ),
            const Divider(),
            // Which app build THIS running game uses — every game always
            // plays the latest rules, so the app version is the only thing
            // that matters for online compatibility.
            ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline),
              title: Text(tr('menus.version', {'version': appVersion})),
              subtitle: Text(
                tr('menus.saveFormat', {'version': state.schemaVersion}),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// "S(i)edlungs-Info": the own towns with tier, population and garrison.
void _showSettlements(BuildContext context, GameController controller) {
  final realm = controller.currentRealm;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              tr('menus.settlementsOf', {'realm': realmName(realm.slot)}),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          if (realm.towns.isEmpty)
            ListTile(title: Text(tr('menus.noSettlements'))),
          for (final town in realm.towns)
            ListTile(
              leading: const Icon(Icons.home_work),
              title: Text(
                '${town.name} — ${buildingName(town.buildingType, empty: '?')}',
              ),
              subtitle: Text(
                tr('menus.settlementSubtitle', {
                  'pop': town.population,
                  'garrison': town.garrison,
                  'cap': town.troopCapacity,
                  'x': town.x + 1,
                  'y': town.y + 1,
                }),
              ),
            ),
        ],
      ),
    ),
  );
}

/// "Kaiserchronik" (the original's "Urkunde" screen): every Kaiser and
/// Sultan reign with home country, years and epithet.
void _showChronicle(BuildContext context, GameController controller) {
  final state = controller.visibleState;
  String line(gc.ChronicleRecord r) {
    // Pre-`slot` records (older saves): the person's dynasty is the home
    // realm, as long as the person still exists.
    final slot = r.slot ?? state.persons[r.personId]?.dynasty;
    final country = slot == null
        ? ''
        : tr('menus.ofRealm', {'realm': realmName(slot)});
    return '${r.name}$country (${r.accessionYear}–${r.deathYear ?? ''})'
        '${r.epithet == null ? '' : ' "${r.epithet}"'}';
  }

  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              tr('chronicle'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          if (state.kaiserChronicle.isEmpty && state.sultanChronicle.isEmpty)
            ListTile(title: Text(tr('menus.noKaiserYet'))),
          if (state.kaiserChronicle.isNotEmpty)
            ListTile(
              title: Text(tr('menus.kaiser')),
              subtitle: Text(
                [for (final r in state.kaiserChronicle) line(r)].join('\n'),
              ),
            ),
          if (state.sultanChronicle.isNotEmpty)
            ListTile(
              title: Text(tr('menus.sultans')),
              subtitle: Text(
                [for (final r in state.sultanChronicle) line(r)].join('\n'),
              ),
            ),
        ],
      ),
    ),
  );
}

/// "Dynastien" (formerly Statistiken): every realm ranked by territory
/// size, from public information only (size, settlements, title) plus
/// the own intel reports — hidden numbers stay hidden. Tapping a realm
/// opens its dynasty.
void _showDynasties(BuildContext context, GameController controller) {
  final state = controller.visibleState;
  final rows = [
    for (final realm in state.realms)
      if (!realm.isVacant) (realm, realm.tileCount.fold(0, (a, b) => a + b)),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.6,
        child: ListView(
          children: [
            ListTile(
              title: Text(
                tr('menus.dynastiesTitle'),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            for (var i = 0; i < rows.length; i++)
              ListTile(
                leading: Text(
                  '${i + 1}.',
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
                title: Text(
                  '${realmName(rows[i].$1.slot)}'
                  '${controller.ownedSlots.contains(rows[i].$1.slot) ? tr('menus.youTag') : ''}'
                  ' — ${state.person(rows[i].$1.rulerId)?.name ?? '?'}',
                ),
                subtitle: Text(
                  '${tr('menus.realmSizeLine', {'tiles': rows[i].$2, 'towns': rows[i].$1.towns.length})}\n'
                  '${_realmInfoLine(controller, rows[i].$1)}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.people, size: 18),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDynastyOf(context, controller, rows[i].$1.slot);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Own realms (a player can hold several — control follows the ruler):
/// full numbers. Foreign realms: only public data plus the newest economy
/// and military intel reports, if any (hidden information), written out
/// as readable text.
String _realmInfoLine(GameController controller, gc.Realm realm) {
  final own = controller.ownedSlots.contains(realm.slot);
  final title = titleName(realm.titleClass);
  if (own) {
    return tr('menus.ownRealmInfo', {
      'title': title,
      'pop': realm.population,
      'treasury': realm.treasury,
      'army': realm.armySize,
    });
  }
  // Newest report per kind (the list is in chronological order).
  gc.IntelReport? economy;
  gc.IntelReport? military;
  for (final report in controller.currentRealm.intelReports) {
    if (report.targetSlot != realm.slot) continue;
    if (report.values.containsKey('unitCount')) {
      military = report;
    } else {
      economy = report;
    }
  }
  if (economy == null && military == null) {
    return tr('menus.noIntel', {'title': title});
  }
  final lines = <String>[
    title,
    if (economy != null) _intelText(economy),
    if (military != null) _intelText(military),
  ];
  return lines.join('\n');
}

/// One intel report as a readable German line ("Spionage Anno X: …").
String _intelText(gc.IntelReport report) {
  final v = report.values;
  final parts = <String>[
    if (v.containsKey('unitCount'))
      v['unitCount'] == 0
          ? tr('menus.intelNoTroops')
          : tr(v['unitCount'] == 1 ? 'menus.intelTroop' : 'menus.intelTroops', {
              'n': v['unitCount'],
            }),
    if (v.containsKey('treasury'))
      tr('menus.intelTreasury', {'n': v['treasury']}),
    if (v.containsKey('grainStock'))
      tr('menus.intelGrain', {'n': v['grainStock']}),
    if (v.containsKey('livestockStock'))
      tr('menus.intelCattle', {'n': v['livestockStock']}),
    if (v.containsKey('population'))
      tr('menus.intelPopulation', {'n': v['population']}),
    if (v.containsKey('armySize')) tr('menus.intelArmy', {'n': v['armySize']}),
    if (v.containsKey('guardLevel'))
      tr('menus.intelGuards', {'n': v['guardLevel']}),
  ];
  return tr('menus.intelLine', {
    'year': report.year,
    'parts': parts.join(', '),
  });
}

// --- Shared amount pickers ---------------------------------------------

void _amountSheet(
  BuildContext context, {
  required String title,
  required int max,
  int allowNegative = 0,
  String Function(int amount)? detail,
  required void Function(int amount) onSubmit,
}) {
  if (max <= 0 && allowNegative <= 0) return;
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: _AmountSlider(
        title: title,
        max: max,
        min: -allowNegative,
        detail: detail,
        onSubmit: (amount) {
          Navigator.pop(sheetContext);
          onSubmit(amount);
        },
      ),
    ),
  );
}

void _targetThenAmount(
  BuildContext context,
  GameController controller, {
  required int max,
  String? titlePrefix,
  String Function(int amount)? detail,
  Set<int> disabledSlots = const {},
  String? disabledNote,
  required void Function(int targetSlot, int amount) onSubmit,
}) {
  final state = controller.visibleState;
  // [context] must be the stable screen context: the follow-up sheet and
  // the caller's onSubmit run long after this sheet's own context died.
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final realm in state.realms)
            if (realm.slot != controller.currentSlot && !realm.isVacant)
              ListTile(
                title: Text(realmName(realm.slot)),
                subtitle: disabledSlots.contains(realm.slot) && disabledNote != null
                    ? Text(disabledNote)
                    : null,
                enabled: !disabledSlots.contains(realm.slot),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _amountSheet(
                    context,
                    title:
                        '${titlePrefix ?? tr('menus.agents')} → ${realmName(realm.slot)}',
                    max: max,
                    detail: detail,
                    onSubmit: (amount) => onSubmit(realm.slot, amount),
                  );
                },
              ),
        ],
      ),
    ),
  );
}

/// Slider + confirm, the touch replacement for the original's number
/// input (PROJECT_REQUIREMENTS "Sliders for numeric inputs").
class _AmountSlider extends StatefulWidget {
  const _AmountSlider({
    super.key,
    required this.title,
    required this.max,
    this.min = 0,
    this.detail,
    required this.onSubmit,
  });

  final String title;
  final int max;
  final int min;

  /// Live caption under the title for the current value — used to show
  /// the cost ("kostet 600 T") or proceeds of the chosen amount
  /// (PROJECT_REQUIREMENTS: sliders show their cost up front).
  final String Function(int value)? detail;

  final void Function(int) onSubmit;

  @override
  State<_AmountSlider> createState() => _AmountSliderState();
}

class _AmountSliderState extends State<_AmountSlider> {
  late double _value = widget.max > 0 ? (widget.max / 2).ceilToDouble() : 0;

  @override
  Widget build(BuildContext context) {
    final max = widget.max.toDouble();
    final min = widget.min.toDouble();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.title}: ${_value.round()}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (widget.detail != null)
            Text(
              widget.detail!(_value.round()),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          Slider(
            value: _value.clamp(min, max),
            min: min,
            max: max <= min ? min + 1 : max,
            divisions: (max - min) > 0 && (max - min) <= 1000
                ? (max - min).round()
                : null,
            onChanged: (v) => setState(() => _value = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(tr('menus.back')),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _value.round() == 0
                    ? null
                    : () => widget.onSubmit(_value.round()),
                child: Text(tr('menus.ok')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
