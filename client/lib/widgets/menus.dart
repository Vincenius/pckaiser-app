import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../app_version.dart';
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
              'Überschuß: ${realm.grainHarvest} — Marktpreis ${state.grainPrice.toStringAsFixed(1)} T',
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
              'Überschuß: ${realm.livestockHarvest} — Marktpreis ${state.cattlePrice.toStringAsFixed(1)} T',
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
              'Maximal: ${realm.tileCount[gc.Building.hafen] * 600} T (Häfen: ${realm.tileCount[gc.Building.hafen]})',
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
            title: const Text('Geld schicken'),
            subtitle: const Text('Taler an ein anderes Land überweisen'),
            enabled: realm.treasury > 0,
            onTap: () {
              Navigator.pop(sheetContext);
              _targetThenAmount(
                context,
                controller,
                max: realm.treasury,
                titlePrefix: 'Taler',
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
              title: Text('${tr('mergeRealms')}: ${gc.countryNames[source]}'),
              // No merging mid-war (engine gate, mirrored).
              subtitle: _mergeAtWar(state, slot, source)
                  ? const Text('Nicht mitten im Krieg !')
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
    detail: (amount) => 'bringt ${(amount * price).round()} T',
    onSubmit: (amount) => _tryAction(
      context,
      controller,
      gc.SellGood(slot: controller.currentSlot, good: good, amount: amount),
    ),
  );
}

void _investSheet(BuildContext context, GameController controller) {
  final realm = controller.currentRealm;
  final cap = realm.tileCount[gc.Building.hafen] * 600;
  _amountSheet(
    context,
    title: tr('investShips'),
    max: cap < realm.treasury ? cap : realm.treasury,
    detail: (amount) =>
        'Einsatz $amount T — der Ertrag kehrt nächste Runde zurück',
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
  // No recruiting/hiring while at war (engine gate, mirrored).
  final atWar = state.activeWar?.isParticipant(slot) ?? false;

  // The §11.1 war gates, mirrored so the button is disabled (with the
  // reason shown) instead of failing on tap.
  final hasTroops = realm.troops.any((t) => t.men > 0);
  final String? warBlocked = state.year < state.warStartYear
      ? 'Kriege sind erst ab dem Jahr ${state.warStartYear} erlaubt !'
      : realm.warThisYear
      ? 'Du hast dieses Jahr schon einmal Krieg geführt !'
      : !hasTroops
      ? 'Du hast nicht genug Truppen !'
      : state.activeWar != null
      ? 'Es tobt bereits ein anderer Krieg !'
      : null;

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
                  ? 'Nicht mitten im Krieg !'
                  : '5 T pro Mann — freie Kapazität: $freeCapacity',
            ),
            enabled: !atWar && freeCapacity > 0 && realm.treasury >= 5,
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
              atWar ? 'Nicht mitten im Krieg !' : '50 T pro Mann (plus Sold)',
            ),
            enabled: !atWar && realm.treasury >= 50,
            onTap: () {
              Navigator.pop(sheetContext);
              _stationSheet(
                context,
                controller,
                onPicked: (x, y) {
                  _amountSheet(
                    context,
                    title: tr('hireSoeldner'),
                    max: controller.currentRealm.treasury ~/ 50,
                    detail: (men) => 'kostet ${men * 50} T',
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
            title: Text('Truppenliste (${realm.troops.length})'),
            subtitle: Text('Armee: ${realm.armySize} Mann'),
            enabled: realm.troops.isNotEmpty,
            onTap: () {
              Navigator.pop(sheetContext);
              _showTroopList(context, controller);
            },
          ),
          ListTile(
            leading: const Icon(Icons.gavel),
            title: Text(tr('declareWar')),
            subtitle: Text(warBlocked ?? 'Einmal pro Jahr — nur Nachbarn'),
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
              'Wo soll die Truppe stationiert werden?',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.flag),
            title: const Text('Hauptsitz'),
            subtitle: Text(
              'Feld (${realm.capitalX + 1}, ${realm.capitalY + 1})',
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              onPicked(realm.capitalX, realm.capitalY);
            },
          ),
          ListTile(
            leading: const Icon(Icons.touch_app),
            title: const Text('Feld auswählen'),
            subtitle: const Text('Ein eigenes Feld auf der Karte antippen'),
            onTap: () {
              Navigator.pop(sheetContext);
              controller.startTilePick(
                hint: 'Feld für die neue Truppe antippen',
                onPick: (x, y) async {
                  if (controller.state.map.ownerAt(x, y) !=
                      controller.currentSlot) {
                    _toast(
                      context,
                      'Du musst deine Truppen auf deinem Territorium stationieren !',
                    );
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
  final nameController = TextEditingController(text: 'Rekruten');
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setState) {
        // 5 T per man plus the one-time class surcharge — the slider only
        // offers what the quarters and the treasury can carry.
        final maxMen = math.min(
          realm.troopCapacity - realm.armySize,
          (realm.treasury - gc.classSurcharge(troopClass)) ~/ 5,
        );
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
                      decoration: const InputDecoration(
                        labelText: 'Name der Truppe',
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
                        segments: const [
                          ButtonSegment(value: 0, label: Text('Infanterie')),
                          ButtonSegment(value: 1, label: Text('Kavallerie')),
                          ButtonSegment(value: 2, label: Text('Artillerie')),
                        ],
                        selected: {troopClass},
                        onSelectionChanged: (s) =>
                            setState(() => troopClass = s.first),
                      ),
                    ),
                  ),
                  if (maxMen < 1)
                    const ListTile(
                      title: Text('Du hast nicht genügend Taler !'),
                    )
                  else
                    _AmountSlider(
                      key: ValueKey(troopClass),
                      title: tr('recruit'),
                      max: maxMen,
                      detail: (men) =>
                          'kostet ${5 * men + gc.classSurcharge(troopClass)} T'
                          ' — Stärke ${(men * (3 * troopClass + gc.TroopQuality.regular) / 10).round()}',
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
                                ? 'Rekruten'
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
              'Truppenliste — Armee: ${realm.armySize} Mann',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          for (var i = 0; i < realm.troops.length; i++)
            ListTile(
              leading: const Icon(Icons.groups_2),
              title: Text(
                '${realm.troops[i].name} — ${realm.troops[i].men} Mann',
              ),
              subtitle: Text(
                '${['Infanterie', 'Kavallerie', 'Artillerie'][realm.troops[i].troopClass]}'
                '${!realm.troops[i].garrisonCounted ? ' (Söldner)' : ''}'
                ' — Stärke ${gc.troopStrength(realm.troops[i]).round()}'
                ' — Feld (${realm.troops[i].x + 1}, ${realm.troops[i].y + 1})',
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
        final costPerMan = soeldner ? 50 : 5;
        final affordable = realm.treasury ~/ costPerMan;
        final capacity = realm.troopCapacity - realm.armySize;
        final maxReinforce = soeldner
            ? affordable
            : (capacity < affordable ? capacity : affordable);
        // Merging/disbanding is forbidden while at war (the war state is
        // keyed to the troop list) — mirror the engine gate so the options
        // grey out (the gate covers reinforcing as well).
        final atWar = controller.state.activeWar?.isParticipant(slot) ?? false;
        final reinforceBlocked = atWar;
        final mergeTargets = [
          for (var i = 0; i < realm.troops.length; i++)
            if (i != index &&
                realm.troops[i].troopClass == troop.troopClass &&
                realm.troops[i].quality == troop.quality &&
                // Mirrors the engine: a drilled regular (quartered) never
                // merges with a Söldner (unquartered), even at equal
                // quality — the bookkeeping differs.
                realm.troops[i].garrisonCounted == troop.garrisonCounted)
              i,
        ];
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  '${troop.name} — ${troop.men} Mann',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                subtitle: Text(
                  '${['Infanterie', 'Kavallerie', 'Artillerie'][troop.troopClass]}'
                  '${soeldner ? ' (Söldner)' : ''}'
                  ' — Stärke ${gc.troopStrength(troop).round()}'
                  ' — Feld (${troop.x + 1}, ${troop.y + 1})',
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
                      const Expanded(
                        child: Text(
                          'Verhalten im automatischen Krieg',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: gc.TroopStance.holdPosition,
                        icon: Icon(Icons.shield_outlined, size: 16),
                        label: Text('Halten'),
                      ),
                      ButtonSegment(
                        value: gc.TroopStance.attack,
                        icon: Icon(Icons.gps_fixed, size: 16),
                        label: Text('Angreifen'),
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
                        ? 'Verteidigt die Basis; greift erst an, wenn der Gegner '
                              'keine Truppen mehr hat.'
                        : 'Marschiert sofort auf den gegnerischen Königssitz.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.open_with),
                title: const Text('Truppe verlegen'),
                // Relocating troops is free — only building costs Züge.
                subtitle: const Text(
                  'Kostenlos — Zielfeld auf der Karte antippen',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  controller.startTilePick(
                    hint: 'Zielfeld für „${troop.name}" antippen',
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
                title: const Text('Truppe verstärken'),
                subtitle: Text(
                  reinforceBlocked
                      ? 'Nicht mitten im Krieg !'
                      : '$costPerMan T pro Mann',
                ),
                enabled: !reinforceBlocked && maxReinforce > 0,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _amountSheet(
                    context,
                    title: 'Truppe verstärken',
                    max: maxReinforce,
                    detail: (men) => 'kostet ${men * costPerMan} T',
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
                title: const Text('Truppe ausbilden'),
                subtitle: Text(
                  soeldner
                      ? 'Söldner können nicht ausgebildet werden'
                      : atWar
                      ? 'Nicht mitten im Krieg !'
                      : troop.quality >= gc.Troop.drillCap
                      ? 'Bereits voll ausgebildet (Qualität ${troop.quality})'
                      : '${5 * troop.men * troop.quality} T — Qualität '
                            '${troop.quality} → ${troop.quality + 1}',
                ),
                // Disabled (greyed out), never hidden — a vanishing button
                // shifts the others up and causes accidental taps.
                enabled:
                    !soeldner &&
                    !atWar &&
                    troop.quality < gc.Troop.drillCap &&
                    realm.treasury >= 5 * troop.men * troop.quality,
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
                title: const Text('Truppe umrüsten'),
                subtitle: Text(
                  soeldner
                      ? 'Söldner können nicht umgerüstet werden'
                      : atWar
                      ? 'Nicht mitten im Krieg !'
                      : 'Gattung wechseln — 5 T pro Mann plus Aufpreis',
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
                    'Vereinigen mit „${realm.troops[other].name}" '
                    '(${realm.troops[other].men} Mann)',
                  ),
                  subtitle: atWar
                      ? const Text('Nicht mitten im Krieg !')
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
                title: const Text('Truppe umbenennen'),
                subtitle: atWar ? const Text('Nicht mitten im Krieg !') : null,
                enabled: !atWar,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _renameTroopDialog(context, controller, index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Truppe auflösen'),
                subtitle: atWar ? const Text('Nicht mitten im Krieg !') : null,
                enabled: !atWar,
                // Destructive: confirm first, so a stray tap (e.g. while
                // spamming "ausbilden" above) can never disband by accident.
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Truppe auflösen?'),
                      content: Text(
                        '„${troop.name}" (${troop.men} Mann) wird aufgelöst.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Abbrechen'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Auflösen'),
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
  const classNames = ['Infanterie', 'Kavallerie', 'Artillerie'];
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              '„${troop.name}" umrüsten — aktuelle Stärke '
              '${gc.troopStrength(troop).round()}',
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
                  final cost = 5 * troop.men + gc.classSurcharge(cls);
                  final newStrength =
                      (troop.men * (3 * cls + troop.quality) / 10).round();
                  return ListTile(
                    leading: const Icon(Icons.military_tech),
                    title: Text('Zu ${classNames[cls]} umrüsten'),
                    subtitle: Text('kostet $cost T — neue Stärke $newStrength'),
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
      title: const Text('Truppe umbenennen'),
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
          child: const Text('OK'),
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
            const ListTile(
              title: Text(
                'Du hast keine gemeinsame Grenze '
                'mit einem anderen Reich !',
              ),
            ),
          for (final realm in state.realms)
            if (realm.slot != slot &&
                !realm.isVacant &&
                // No war against a slot your own ruler already holds.
                realm.rulerId != controller.currentRealm.rulerId &&
                neighbors.contains(realm.slot))
              ListTile(
                title: Text(gc.countryNames[realm.slot]),
                subtitle: Text(
                  state.person(realm.rulerId)?.name ?? 'unbekannt',
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
                        '${tr('declareWar')}: ${gc.countryNames[realm.slot]}?',
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
              ),
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
            title: const Text('Daten ausspionieren'),
            subtitle: Text('${gc.economySpyCost} T pro Agent'),
            enabled: realm.treasury >= gc.economySpyCost,
            onTap: () {
              Navigator.pop(sheetContext);
              _spySheet(context, controller, gc.SpyKind.economy);
            },
          ),
          ListTile(
            title: const Text('Truppen ausspionieren'),
            subtitle: Text('${gc.militarySpyCost} T pro Agent'),
            enabled: realm.treasury >= gc.militarySpyCost,
            onTap: () {
              Navigator.pop(sheetContext);
              _spySheet(context, controller, gc.SpyKind.military);
            },
          ),
          ListTile(
            title: const Text('Anschlag verüben'),
            subtitle: Text('${gc.assassinCost} T pro Agent'),
            enabled: realm.treasury >= gc.assassinCost,
            onTap: () {
              Navigator.pop(sheetContext);
              _assassinSheet(context, controller);
            },
          ),
          ListTile(
            title: Text(
              '${tr('guards')}: ${realm.guardLevel} / ${gc.guardCap}',
            ),
            subtitle: Text('${gc.guardCost} T pro Mann'),
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
                    ? 'kostet ${delta * gc.guardCost} T'
                    : 'Entlassen ist kostenlos',
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
        'kostet ${agents * costPerAgent} T — mehr '
        'Agenten, bessere Chancen',
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
          title: 'Spionage — ${gc.countryNames[target]}',
          waitingText: 'Die Spione sind unterwegs …',
          resultText: failure != null
              ? (caught > 0
                    ? 'Die Mission ist gescheitert ! '
                          '${caught == 1 ? 'Einer deiner Spione wurde gefangengenommen — er gesteht' : '$caught deiner Spione wurden gefangengenommen — einer gesteht'} '
                          'unter Folter, aus '
                          '${gc.countryNames[controller.currentSlot]} '
                          'geschickt worden zu sein !!!'
                    : 'Deine Spione konnten nichts in Erfahrung bringen !')
              : 'Mission erfolgreich ! Den Bericht findest du unter '
                    'Info → Dynastien.',
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
        'kostet ${agents * gc.assassinCost} T — mehr '
        'Agenten, bessere Chancen',
    onSubmit: (target, agents) async {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Anschlag auf ${gc.countryNames[target]} — wirklich?'),
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
          title: const Text('Anschlag in Auftrag gegeben'),
          content: const Text(
            'Die Attentäter sind auf dem Weg !!!\n\n'
            'Ob der Anschlag gelingt, erfährst du in einem der '
            'nächsten Züge.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
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
      ? 'Niemand in deiner Dynastie kann heiraten !'
      : !hasRoyalProposer
      ? 'Alle haben diesen Zug schon einen Antrag gestellt !'
      : null;
  // Commoner marriage is always available — it does not count against the
  // per-person proposal limit.
  final String? commonerBlocked = hasProposer
      ? null
      : 'Niemand in deiner Dynastie kann heiraten !';
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
            title: const Text('Dynastie'),
            subtitle: Text(
              '${state.dynasty(houseSlot).memberIds.length} Mitglieder — '
              'fremde Dynastien über Info → Dynastien',
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
            title: const Text('Bürgerlich heiraten'),
            subtitle: Text(
              commonerBlocked ?? 'Eine Person aus dem Volk heiraten',
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
              title: const Text('Staatskasse plündern'),
              subtitle: Text(
                [
                  if (state.kaiserId != null &&
                      realm.rulerId == state.kaiserId)
                    '${state.kaiserPot} T im Kronschatz',
                  if (state.sultanId != null &&
                      realm.rulerId == state.sultanId)
                    '${state.sultanPot} T im Sultansschatz',
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
            title: const Text('Sitz verlegen'),
            subtitle: Text(
              capitalLost
                  ? 'Sitz verloren — neue Stadt, Burg oder Palast wählen (gratis)'
                  : '5000 T — eigene Stadt, Burg oder Palast wählen',
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              _showRelocateCapital(context, controller);
            },
          ),
          // §15.2 religion availability: evangelisch from the Reformation
          // year on, moslemisch from the Ottoman invasion on — hidden
          // entirely until then (mirrors the core gates, which include the
          // event year itself).
          for (final (religion, name, cost, available) in [
            (gc.Religion.katholisch, 'katholisch', 0, true),
            (
              gc.Religion.evangelisch,
              'evangelisch',
              500,
              state.year >= state.reformationYear,
            ),
            (
              gc.Religion.moslemisch,
              'moslemisch',
              1000,
              state.year >= state.ottomanYear,
            ),
          ])
            if (available && state.dynasty(slot).religion != religion)
              ListTile(
                title: Text('Religion: $name'),
                trailing: Text(
                  '$cost T, −${gc.religionChangePopularityCost} '
                  '${tr('popularity')}',
                ),
                enabled: realm.treasury >= cost,
                // A faith change is momentous and easy to tap by accident
                // once the options appear — always confirm first.
                onTap: () async {
                  final sure = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Religion wechseln?'),
                      content: Text(
                        'Deine Dynastie tritt zum ${name}en Glauben über.\n\n'
                        'Das kostet $cost T und '
                        '${gc.religionChangePopularityCost} Beliebtheit, '
                        'löst religiös unpassende Ehen und kann den '
                        'Kurfürstensitz kosten. Wirklich wechseln?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(tr('cancel')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Wechseln'),
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
            title: const Text('Kurfürsten'),
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
  final costLabel = lost ? 'gratis' : '5000 T';
  const buildingNames = {
    gc.Building.stadt: 'Stadt',
    gc.Building.burg: 'Burg',
    gc.Building.palast: 'Palast',
  };
  final candidates = <(int, int, int)>[];
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      final building = map.buildingAt(x, y);
      if (map.ownerAt(x, y) == slot && buildingNames.containsKey(building)) {
        candidates.add((x, y, building));
      }
    }
  }
  if (candidates.isEmpty) {
    _toast(context, 'Du brauchst eine eigene Stadt, Burg oder einen Palast !');
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
              title: Text('${buildingNames[building]} (${x + 1}, ${y + 1})'),
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
                'Dynastie von ${gc.countryNames[slot]}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            for (final p in members)
              ListTile(
                leading: Icon(p.isMale ? Icons.male : Icons.female),
                title: Text(
                  '${p.name} (${p.age})'
                  '${state.realm(slot).rulerId == p.id ? ' — ${gc.titleName(state.realm(slot).titleClass)}' : ''}',
                ),
                subtitle: Text(
                  [
                    _spouseLine(state, p),
                    if (p.childrenIds.isNotEmpty)
                      '${p.childrenIds.length} ${p.childrenIds.length == 1 ? 'Kind' : 'Kinder'}',
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
  if (p.spouseId == null) return 'ledig';
  final spouse = state.persons[p.spouseId!];
  if (spouse == null) return 'verheiratet';
  return spouse.dynasty == p.dynasty
      ? 'verheiratet mit ${spouse.name} (bürgerlich)'
      : 'verheiratet mit ${spouse.name} von ${gc.countryNames[spouse.dynasty]}';
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
    _toast(context, 'Es gibt zur Zeit keinen passenden Partner !');
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
            subtitle: const Text('Wer aus deiner Dynastie soll heiraten?'),
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

/// Step 2: pick the partner. Mirrors the §14.1 eligibility rules so only
/// proposals that `applyAction` would accept are offered.
void _showMarriageCandidates(
  BuildContext context,
  GameController controller,
  gc.Person proposer,
) {
  final slot = controller.currentSlot;
  final state = controller.state;
  // Keyed to the proposer's own dynasty (not the slot): mirrors the engine's
  // §14.1 check, which matters when the ruling house differs from the slot.
  final religion = state.dynasty(proposer.dynasty).religion;
  final candidates = [
    for (final p in state.persons.values)
      if (p.dynasty != proposer.dynasty &&
          _marriageable(state, p) &&
          p.gender != proposer.gender &&
          (p.age - proposer.age).abs() < 10 &&
          state.dynasty(p.dynasty).religion == religion)
        p,
  ];
  if (candidates.isEmpty) {
    _toast(context, 'Es gibt zur Zeit keinen passenden Partner !');
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
              'Partner für ${proposer.name} (${proposer.age})',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          for (final p in candidates)
            ListTile(
              leading: Icon(p.isMale ? Icons.male : Icons.female),
              title: Text('${p.name} (${p.age})'),
              subtitle: Text(gc.countryNames[p.dynasty]),
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
    _toast(context, 'Es gibt zur Zeit keinen passenden Partner !');
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
              'Bürgerlich heiraten',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            subtitle: const Text('Wer aus deiner Dynastie soll heiraten?'),
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
        title: const Text('Heiratsantrag'),
        content: const Text(
          'Der Antrag wird überbracht — die Antwort '
          'folgt im nächsten Zug.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
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
      title: 'Heiratsantrag',
      waitingText: 'Der Antrag wird überbracht …',
      resultText: accepted ? 'Angenommen !' : 'Abgelehnt !',
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
          child: const Text('OK'),
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
                'Mein Reich — ${gc.countryNames[realm.slot]}'
                '${state.person(realm.rulerId) == null ? '' : ' (${gc.titleName(realm.titleClass)} ${state.person(realm.rulerId)!.name})'}',
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
                    Text('Armee: ${realm.armySize}'),
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
              title: Text('Siedlungen (${realm.towns.length})'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showSettlements(context, controller);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Dynastien'),
              subtitle: const Text('Alle Reiche und ihre Herrscherhäuser'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showDynasties(context, controller);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_edu),
              title: Text(tr('chronicle')),
              subtitle: const Text('Alle bisherigen Kaiser und Sultane'),
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
              title: Text('Version $appVersion'),
              subtitle: Text('Spielstand-Format v${state.schemaVersion}'),
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
  const tierNames = {
    gc.Building.dorf: 'Dorf',
    gc.Building.markt: 'Markt',
    gc.Building.stadt: 'Stadt',
  };
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              'Siedlungen von ${gc.countryNames[realm.slot]}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          if (realm.towns.isEmpty)
            const ListTile(title: Text('Du hast keine Siedlungen !')),
          for (final town in realm.towns)
            ListTile(
              leading: const Icon(Icons.home_work),
              title: Text(
                '${town.name} — ${tierNames[town.buildingType] ?? '?'}',
              ),
              subtitle: Text(
                '${town.population} Einwohner — Garnison '
                '${town.garrison}/${town.troopCapacity} — '
                'Feld (${town.x + 1}, ${town.y + 1})',
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
    final country = slot == null ? '' : ' von ${gc.countryNames[slot]}';
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
            const ListTile(title: Text('Noch wurde kein Kaiser gekrönt.')),
          if (state.kaiserChronicle.isNotEmpty)
            ListTile(
              title: const Text('Kaiser'),
              subtitle: Text(
                [for (final r in state.kaiserChronicle) line(r)].join('\n'),
              ),
            ),
          if (state.sultanChronicle.isNotEmpty)
            ListTile(
              title: const Text('Sultane'),
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
                'Dynastien — Reiche nach Größe',
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
                  '${gc.countryNames[rows[i].$1.slot]}'
                  '${controller.ownedSlots.contains(rows[i].$1.slot) ? ' (du)' : ''}'
                  ' — ${state.person(rows[i].$1.rulerId)?.name ?? '?'}',
                ),
                subtitle: Text(
                  '${rows[i].$2} Felder — ${rows[i].$1.towns.length} Siedlungen\n'
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
  final title = gc.titleName(realm.titleClass);
  if (own) {
    return '$title — ${realm.population} Einwohner, ${realm.treasury} T, '
        'Armee ${realm.armySize}';
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
    return '$title — keine Informationen (Spione aussenden!)';
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
          ? 'keine Truppen'
          : '${v['unitCount']} Truppe${v['unitCount'] == 1 ? '' : 'n'} '
                '(auf der Karte sichtbar)',
    if (v.containsKey('treasury')) 'Schatzkammer ~${v['treasury']} T',
    if (v.containsKey('grainStock')) 'Korn ~${v['grainStock']}',
    if (v.containsKey('livestockStock')) 'Vieh ~${v['livestockStock']}',
    if (v.containsKey('population')) '~${v['population']} Einwohner',
    if (v.containsKey('armySize')) 'Armee ~${v['armySize']} Mann',
    if (v.containsKey('guardLevel')) 'Spionageabwehr ~${v['guardLevel']}',
  ];
  return 'Spionage Anno ${report.year}: ${parts.join(', ')}';
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
  String titlePrefix = 'Agenten',
  String Function(int amount)? detail,
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
                title: Text(gc.countryNames[realm.slot]),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _amountSheet(
                    context,
                    title: '$titlePrefix → ${gc.countryNames[realm.slot]}',
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
                child: const Text('Zurück'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _value.round() == 0
                    ? null
                    : () => widget.onSubmit(_value.round()),
                child: const Text('OK'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
