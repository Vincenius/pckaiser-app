import 'dart:async';

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/strings.dart';
import '../state/game_controller.dart';
import 'event_feed.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

void _tryAction(BuildContext context, GameController controller,
    gc.PlayerAction action, {bool undoable = false}) {
  try {
    undoable
        ? controller.applyUndoable(action)
        : controller.applyIrreversible(action);
  } on gc.ActionException catch (e) {
    _toast(context, e.message);
  }
}

// --- Commerce ---------------------------------------------------------

/// The Handel sheet — opened directly from the bottom action bar.
void showCommerceMenu(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final realm = controller.currentRealm;
  final state = controller.visibleState;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(children: [
        ListTile(
          title: Text(tr('sellGrain')),
          subtitle: Text(
              'Überschuß: ${realm.grainHarvest} — Marktpreis ${state.grainPrice.toStringAsFixed(1)} T'),
          enabled: !realm.soldGrainThisTurn && realm.grainHarvest > 0,
          onTap: () => _sellSheet(context, controller, gc.MarketGood.grain,
              realm.grainHarvest, state.grainPrice),
        ),
        ListTile(
          title: Text(tr('sellCattle')),
          subtitle: Text(
              'Überschuß: ${realm.livestockHarvest} — Marktpreis ${state.cattlePrice.toStringAsFixed(1)} T'),
          enabled: !realm.soldCattleThisTurn && realm.livestockHarvest > 0,
          onTap: () => _sellSheet(context, controller, gc.MarketGood.cattle,
              realm.livestockHarvest, state.cattlePrice),
        ),
        ListTile(
          title: Text(tr('investShips')),
          subtitle: Text(
              'Maximal: ${realm.tileCount[gc.Building.hafen] * 600} T (Häfen: ${realm.tileCount[gc.Building.hafen]})'),
          enabled: !realm.investedThisTurn &&
              realm.tileCount[gc.Building.hafen] > 0,
          onTap: () => _investSheet(context, controller),
        ),
        ListTile(
          title: const Text('Geld schicken'),
          subtitle: const Text('Taler an ein anderes Land überweisen'),
          enabled: realm.treasury > 0,
          onTap: () {
            Navigator.pop(context);
            _targetThenAmount(context, controller,
                max: realm.treasury,
                titlePrefix: 'Taler',
                onSubmit: (target, amount) => _tryAction(
                    context,
                    controller,
                    gc.SendMoney(
                        slot: slot, targetSlot: target, amount: amount),
                    undoable: true));
          },
        ),
        for (final source in gc.mergeableSlots(controller.state, slot))
          ListTile(
            title: Text('${tr('mergeRealms')}: ${gc.countryNames[source]}'),
            onTap: () {
              Navigator.pop(context);
              _tryAction(context, controller,
                  gc.MergeRealms(slot: slot, sourceSlot: source));
            },
          ),
      ]),
    ),
  );
}

void _sellSheet(BuildContext context, GameController controller,
    gc.MarketGood good, int stock, double price) {
  Navigator.pop(context);
  _amountSheet(
    context,
    title: good == gc.MarketGood.grain ? tr('sellGrain') : tr('sellCattle'),
    max: stock,
    onSubmit: (amount) => _tryAction(context, controller,
        gc.SellGood(slot: controller.currentSlot, good: good, amount: amount)),
  );
}

void _investSheet(BuildContext context, GameController controller) {
  Navigator.pop(context);
  final realm = controller.currentRealm;
  final cap = realm.tileCount[gc.Building.hafen] * 600;
  _amountSheet(
    context,
    title: tr('investShips'),
    max: cap < realm.treasury ? cap : realm.treasury,
    onSubmit: (amount) => _tryAction(context, controller,
        gc.InvestShips(slot: controller.currentSlot, amount: amount)),
  );
}

// --- Military ---------------------------------------------------------

/// The Militär sheet — opened directly from the bottom action bar.
void showMilitaryMenu(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final realm = controller.currentRealm;
  final state = controller.state;
  final freeCapacity = realm.troopCapacity - realm.armySize;

  // The §11.1 war gates, mirrored so the button is disabled (with the
  // reason shown) instead of failing on tap.
  final hasTroops = realm.troops.any((t) => t.men > 0);
  final String? warBlocked = state.year < gc.firstWarYear
      ? 'Kriege sind erst ab dem Jahr 1010 erlaubt !'
      : realm.warThisYear
          ? 'Sie haben dieses Jahr schon einmal Krieg geführt !'
          : !hasTroops
              ? 'Sie haben nicht genug Truppen !'
              : state.activeWar != null
                  ? 'Es tobt bereits ein anderer Krieg !'
                  : null;

  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          title: Text(tr('recruit')),
          subtitle: Text(
              '5 T pro Mann — freie Kapazität: $freeCapacity'),
          enabled: freeCapacity > 0 && realm.treasury >= 5,
          onTap: () {
            Navigator.pop(context);
            // Position first, then class and amount.
            _stationSheet(context, controller,
                onPicked: (x, y) =>
                    _recruitSheet(context, controller, x, y));
          },
        ),
        ListTile(
          title: Text(tr('hireSoeldner')),
          subtitle: const Text('50 T pro Mann (plus Sold)'),
          enabled: realm.treasury >= 50,
          onTap: () {
            Navigator.pop(context);
            _stationSheet(context, controller, onPicked: (x, y) {
              _amountSheet(context,
                  title: tr('hireSoeldner'),
                  max: controller.currentRealm.treasury ~/ 50,
                  onSubmit: (men) => _tryAction(
                      context,
                      controller,
                      gc.HireSoeldner(
                          slot: slot,
                          men: men,
                          name: 'Söldner',
                          x: x,
                          y: y)));
            });
          },
        ),
        ListTile(
          leading: const Icon(Icons.groups_2),
          title: Text('Truppenliste (${realm.troops.length})'),
          subtitle: Text('Armee: ${realm.armySize} Mann'),
          enabled: realm.troops.isNotEmpty,
          onTap: () {
            Navigator.pop(context);
            _showTroopList(context, controller);
          },
        ),
        ListTile(
          leading: const Icon(Icons.gavel),
          title: Text(tr('declareWar')),
          subtitle: Text(warBlocked ?? 'Einmal pro Jahr — nur Nachbarn'),
          enabled: warBlocked == null,
          onTap: () {
            Navigator.pop(context);
            _declareWarSheet(context, controller);
          },
        ),
      ]),
    ),
  );
}

/// Position picker for a new unit ("ask for the place first"): the
/// capital or one of the own towns.
void _stationSheet(BuildContext context, GameController controller,
    {required void Function(int x, int y) onPicked}) {
  final realm = controller.currentRealm;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
            title: Text('Wo soll die Truppe stationiert werden?',
                style: Theme.of(context).textTheme.titleMedium)),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.flag),
          title: const Text('Hauptsitz'),
          subtitle:
              Text('Feld (${realm.capitalX + 1}, ${realm.capitalY + 1})'),
          onTap: () {
            Navigator.pop(context);
            onPicked(realm.capitalX, realm.capitalY);
          },
        ),
        for (final town in realm.towns)
          ListTile(
            leading: const Icon(Icons.home_work),
            title: Text(town.name),
            subtitle: Text('Feld (${town.x + 1}, ${town.y + 1})'),
            onTap: () {
              Navigator.pop(context);
              onPicked(town.x, town.y);
            },
          ),
      ]),
    ),
  );
}

void _recruitSheet(
    BuildContext context, GameController controller, int x, int y) {
  final slot = controller.currentSlot;
  var troopClass = gc.TroopClass.infanterie;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Infanterie +0')),
              ButtonSegment(value: 1, label: Text('Kavallerie +500')),
              ButtonSegment(value: 2, label: Text('Artillerie +1000')),
            ],
            selected: {troopClass},
            onSelectionChanged: (s) => setState(() => troopClass = s.first),
          ),
          _AmountSlider(
            title: tr('recruit'),
            max: controller.currentRealm.troopCapacity -
                controller.currentRealm.armySize,
            onSubmit: (men) {
              Navigator.pop(context);
              _tryAction(
                  context,
                  controller,
                  gc.RecruitTroops(
                      slot: slot,
                      men: men,
                      troopClass: troopClass,
                      name: 'Rekruten',
                      x: x,
                      y: y));
            },
          ),
        ]),
      ),
    ),
  );
}

/// "Truppen(l)iste": overview of all own units — tap to inspect/edit.
void _showTroopList(BuildContext context, GameController controller) {
  final realm = controller.currentRealm;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
            title: Text('Truppenliste — Armee: ${realm.armySize} Mann',
                style: Theme.of(context).textTheme.titleMedium)),
        const Divider(height: 1),
        for (var i = 0; i < realm.troops.length; i++)
          ListTile(
            leading: const Icon(Icons.groups_2),
            title: Text(
                '${realm.troops[i].name} — ${realm.troops[i].men} Mann'),
            subtitle: Text(
                '${['Infanterie', 'Kavallerie', 'Artillerie'][realm.troops[i].troopClass]}'
                '${realm.troops[i].quality == gc.TroopQuality.soeldner ? ' (Söldner)' : ''}'
                ' — Feld (${realm.troops[i].x + 1}, ${realm.troops[i].y + 1})'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              showTroopActions(context, controller, i);
            },
          ),
      ]),
    ),
  );
}

/// Per-unit info & edit sheet (§10.2): verstärken, vereinigen, auflösen.
/// Public — the tile sheet opens it when tapping a stationed army.
void showTroopActions(
    BuildContext context, GameController controller, int index) {
  final slot = controller.currentSlot;
  final realm = controller.currentRealm;
  final troop = realm.troops[index];
  final soeldner = troop.quality == gc.TroopQuality.soeldner;
  final costPerMan = soeldner ? 50 : 5;
  final affordable = realm.treasury ~/ costPerMan;
  final capacity = realm.troopCapacity - realm.armySize;
  final maxReinforce =
      soeldner ? affordable : (capacity < affordable ? capacity : affordable);
  // Merging/disbanding is forbidden while at war (the war state is keyed
  // to the troop list) — mirror the engine gate so the options grey out.
  final atWar = controller.state.activeWar?.isParticipant(slot) ?? false;
  final mergeTargets = [
    for (var i = 0; i < realm.troops.length; i++)
      if (i != index &&
          realm.troops[i].troopClass == troop.troopClass &&
          realm.troops[i].quality == troop.quality)
        i,
  ];
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          title: Text('${troop.name} — ${troop.men} Mann',
              style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(
              '${['Infanterie', 'Kavallerie', 'Artillerie'][troop.troopClass]}'
              '${soeldner ? ' (Söldner)' : ''}'
              ' — Feld (${troop.x + 1}, ${troop.y + 1})'),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.group_add),
          title: const Text('Truppe verstärken'),
          subtitle: Text('$costPerMan T pro Mann'),
          enabled: maxReinforce > 0,
          onTap: () {
            Navigator.pop(context);
            _amountSheet(context,
                title: 'Truppe verstärken',
                max: maxReinforce,
                onSubmit: (men) => _tryAction(context, controller,
                    gc.ReinforceTroop(slot: slot, unitIndex: index, men: men)));
          },
        ),
        for (final other in mergeTargets)
          ListTile(
            leading: const Icon(Icons.merge),
            title: Text('Vereinigen mit „${realm.troops[other].name}" '
                '(${realm.troops[other].men} Mann)'),
            subtitle: atWar ? const Text('Nicht mitten im Krieg !') : null,
            enabled: !atWar,
            onTap: () {
              Navigator.pop(context);
              _tryAction(
                  context,
                  controller,
                  gc.MergeTroops(
                      slot: slot, fromIndex: index, toIndex: other),
                  undoable: true);
            },
          ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Truppe auflösen'),
          subtitle: atWar ? const Text('Nicht mitten im Krieg !') : null,
          enabled: !atWar,
          onTap: () {
            Navigator.pop(context);
            _tryAction(context, controller,
                gc.DisbandTroop(slot: slot, unitIndex: index),
                undoable: true);
          },
        ),
      ]),
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
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        if (neighbors.isEmpty)
          const ListTile(
              title: Text('Sie haben keine gemeinsame Grenze '
                  'mit einem anderen Reich !')),
        for (final realm in state.realms)
          if (realm.slot != slot &&
              !realm.isVacant &&
              // No war against a slot your own ruler already holds.
              realm.rulerId != controller.currentRealm.rulerId &&
              neighbors.contains(realm.slot))
            ListTile(
              title: Text(gc.countryNames[realm.slot]),
              subtitle:
                  Text(state.person(realm.rulerId)?.name ?? 'unbekannt'),
              onTap: () async {
                Navigator.pop(context);
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                        '${tr('declareWar')}: ${gc.countryNames[realm.slot]}?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(tr('cancel'))),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(tr('declareWar'))),
                    ],
                  ),
                );
                if (sure == true && context.mounted) {
                  _tryAction(context, controller,
                      gc.DeclareWar(slot: slot, targetSlot: realm.slot));
                }
              },
            ),
      ]),
    ),
  );
}

// --- Espionage --------------------------------------------------------

/// The Spionage sheet — opened directly from the bottom action bar.
void showEspionageMenu(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final realm = controller.currentRealm;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(children: [
        ListTile(
          title: const Text('Daten ausspionieren'),
          subtitle: const Text('200 T pro Agent'),
          enabled: realm.treasury >= 200,
          onTap: () => _spySheet(context, controller, gc.SpyKind.economy),
        ),
        ListTile(
          title: const Text('Truppen ausspionieren'),
          subtitle: const Text('200 T pro Agent'),
          enabled: realm.treasury >= 200,
          onTap: () => _spySheet(context, controller, gc.SpyKind.military),
        ),
        ListTile(
          title: const Text('Anschlag verüben'),
          subtitle: const Text('250 T pro Agent'),
          enabled: realm.treasury >= 250,
          onTap: () => _assassinSheet(context, controller),
        ),
        ListTile(
          title: Text(
              '${tr('guards')}: ${realm.guardLevel} / ${gc.guardCap}'),
          subtitle: const Text('100 T pro Mann'),
          enabled: (realm.guardLevel < gc.guardCap &&
                  realm.treasury >= 100) ||
              realm.guardLevel > 0,
          onTap: () {
            Navigator.pop(context);
            _amountSheet(context,
                title: tr('guards'),
                max: gc.guardCap - controller.currentRealm.guardLevel,
                allowNegative: controller.currentRealm.guardLevel,
                onSubmit: (delta) => _tryAction(context, controller,
                    gc.AdjustGuards(slot: slot, delta: delta)));
          },
        ),
      ]),
    ),
  );
}

void _spySheet(
    BuildContext context, GameController controller, gc.SpyKind kind) {
  Navigator.pop(context);
  _targetThenAmount(context, controller, max: 30,
      onSubmit: (target, agents) {
    _tryAction(
        context,
        controller,
        gc.SpyMission(
            slot: controller.currentSlot,
            targetSlot: target,
            agents: agents,
            spyKind: kind));
  });
}

void _assassinSheet(BuildContext context, GameController controller) {
  Navigator.pop(context);
  _targetThenAmount(context, controller, max: 30,
      onSubmit: (target, agents) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            'Anschlag auf ${gc.countryNames[target]} — wirklich?'),
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
    if (sure == true && context.mounted) {
      _tryAction(
          context,
          controller,
          gc.OrderAssassination(
              slot: controller.currentSlot,
              targetSlot: target,
              agents: agents));
    }
  });
}

// --- Misc & Info ------------------------------------------------------

/// The Sonstiges sheet — opened directly from the bottom action bar.
void showMiscMenu(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final state = controller.state;
  final realm = controller.currentRealm;
  final capitalLost =
      state.map.ownerAt(realm.capitalX, realm.capitalY) != slot;
  final hasProposer = state.persons.values
      .any((p) => p.dynasty == slot && _marriageable(p));
  final String? marriageBlocked = realm.proposedMarriageThisTurn
      ? 'Nur ein Heiratsantrag pro Zug !'
      : !hasProposer
          ? 'Niemand in Ihrer Dynastie kann heiraten !'
          : null;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(children: [
        ListTile(
          leading: const Icon(Icons.people),
          title: const Text('Dynastie'),
          subtitle: Text(
              '${state.dynasty(slot).memberIds.length} Mitglieder — '
              'fremde Dynastien über Info → Reiche'),
          onTap: () {
            Navigator.pop(context);
            _showDynastyOf(context, controller, slot);
          },
        ),
        ListTile(
          leading: const Icon(Icons.favorite_border),
          title: Text(tr('proposeMarriage')),
          subtitle: marriageBlocked == null ? null : Text(marriageBlocked),
          enabled: marriageBlocked == null,
          onTap: () {
            Navigator.pop(context);
            _showMarriageProposers(context, controller);
          },
        ),
        ListTile(
          leading: const Icon(Icons.favorite),
          title: const Text('Bürgerlich heiraten'),
          subtitle: Text(marriageBlocked ??
              'Eine Person aus dem Volk heiraten (25% Zusage)'),
          enabled: marriageBlocked == null,
          onTap: () {
            Navigator.pop(context);
            _showCommonerMarriage(context, controller);
          },
        ),
        ListTile(
          leading: const Icon(Icons.location_city),
          title: const Text('Sitz verlegen'),
          subtitle: Text(capitalLost
              ? '5000 T — eigene Stadt, Burg oder Palast wählen'
              : 'Nur möglich, wenn der Sitz verloren ist'),
          enabled: capitalLost,
          onTap: () {
            Navigator.pop(context);
            _showRelocateCapital(context, controller);
          },
        ),
        // §15.2 religion availability: evangelisch only after the
        // Reformation, moslemisch only after the Ottoman invasion —
        // hidden entirely until then (mirrors the core gates).
        for (final (religion, name, cost, available) in [
          (gc.Religion.katholisch, 'katholisch', 0, true),
          (
            gc.Religion.evangelisch,
            'evangelisch',
            500,
            state.year > state.reformationYear
          ),
          (
            gc.Religion.moslemisch,
            'moslemisch',
            1000,
            state.year > state.ottomanYear
          ),
        ])
          if (available && state.dynasty(slot).religion != religion)
            ListTile(
              title: Text('Religion: $name'),
              trailing: Text('$cost T, −70 ${tr('popularity')}'),
              enabled: realm.treasury >= cost,
              onTap: () {
                Navigator.pop(context);
                _tryAction(context, controller,
                    gc.ChangeReligion(slot: slot, religion: religion));
              },
            ),
        ListTile(
          title: const Text('Kurfürsten'),
          subtitle: Text(state.kurfuerstenIds
              .map((id) => state.persons[id]?.name ?? '?')
              .join(', ')),
        ),
      ]),
    ),
  );
}

/// "Sitz verlegen" (§6.2): pick one of the own Stadt/Burg/Palast tiles.
void _showRelocateCapital(
    BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final state = controller.state;
  final map = state.map;
  const buildingNames = {
    gc.Building.stadt: 'Stadt',
    gc.Building.burg: 'Burg',
    gc.Building.palast: 'Palast',
  };
  final candidates = <(int, int, int)>[];
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      final building = map.buildingAt(x, y);
      if (map.ownerAt(x, y) == slot &&
          buildingNames.containsKey(building)) {
        candidates.add((x, y, building));
      }
    }
  }
  if (candidates.isEmpty) {
    _toast(context,
        'Sie brauchen eine eigene Stadt, Burg oder einen Palast !');
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        for (final (x, y, building) in candidates)
          ListTile(
            leading: const Icon(Icons.location_city),
            title: Text('${buildingNames[building]} (${x + 1}, ${y + 1})'),
            trailing: const Text('5000 T'),
            onTap: () {
              Navigator.pop(context);
              _tryAction(context, controller,
                  gc.RelocateCapital(slot: slot, x: x, y: y),
                  undoable: true);
            },
          ),
      ]),
    ),
  );
}

/// Dynasty overview ("Dynastien-Info"): every living member of [slot]'s
/// dynasty with age, spouse and children. Dynasty composition is public
/// information, so foreign dynasties may be viewed too.
void _showDynastyOf(
    BuildContext context, GameController controller, int slot) {
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
        child: ListView(children: [
          ListTile(
            title: Text('Dynastie von ${gc.countryNames[slot]}',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          for (final p in members)
            ListTile(
              leading: Icon(p.isMale ? Icons.male : Icons.female),
              title: Text(
                  '${p.name} (${p.age})'
                  '${state.realm(slot).rulerId == p.id ? ' — ${gc.titleName(state.realm(slot).titleClass)}' : ''}'),
              subtitle: Text([
                _spouseLine(state, p),
                if (p.childrenIds.isNotEmpty)
                  '${p.childrenIds.length} ${p.childrenIds.length == 1 ? 'Kind' : 'Kinder'}',
              ].join(' — ')),
            ),
        ]),
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

bool _marriageable(gc.Person p) => p.spouseId == null && p.age >= 14;

/// Step 1 of "Heirat vorschlagen" (§14.1): pick the own dynasty member.
void _showMarriageProposers(
    BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final state = controller.state;
  final proposers = [
    for (final p in state.persons.values)
      if (p.dynasty == slot && _marriageable(p)) p,
  ];
  if (proposers.isEmpty) {
    _toast(context, 'Es gibt zur Zeit keinen passenden Partner !');
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          title: Text(tr('proposeMarriage'),
              style: Theme.of(context).textTheme.titleMedium),
          subtitle: const Text('Wer aus Ihrer Dynastie soll heiraten?'),
        ),
        const Divider(height: 1),
        for (final p in proposers)
          ListTile(
            leading: Icon(p.isMale ? Icons.male : Icons.female),
            title: Text('${p.name} (${p.age})'),
            onTap: () {
              Navigator.pop(context);
              _showMarriageCandidates(context, controller, p);
            },
          ),
      ]),
    ),
  );
}

/// Step 2: pick the partner. Mirrors the §14.1 eligibility rules so only
/// proposals that `applyAction` would accept are offered.
void _showMarriageCandidates(BuildContext context,
    GameController controller, gc.Person proposer) {
  final slot = controller.currentSlot;
  final state = controller.state;
  final religion = state.dynasty(slot).religion;
  final candidates = [
    for (final p in state.persons.values)
      if (p.dynasty != slot &&
          _marriageable(p) &&
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
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          title: Text('Partner für ${proposer.name} (${proposer.age})',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        const Divider(height: 1),
        for (final p in candidates)
          ListTile(
            leading: Icon(p.isMale ? Icons.male : Icons.female),
            title: Text('${p.name} (${p.age})'),
            subtitle: Text(gc.countryNames[p.dynasty]),
            onTap: () {
              Navigator.pop(context);
              _proposeAndReveal(
                  context,
                  controller,
                  gc.ProposeMarriage(
                      slot: slot,
                      proposerId: proposer.id,
                      targetId: p.id));
            },
          ),
      ]),
    ),
  );
}

/// "(B)ürgerlich heiraten": pick the dynasty member, then roll the 25%
/// commoner acceptance with the reveal modal.
void _showCommonerMarriage(
    BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final state = controller.state;
  final proposers = [
    for (final p in state.persons.values)
      if (p.dynasty == slot && _marriageable(p)) p,
  ];
  if (proposers.isEmpty) {
    _toast(context, 'Es gibt zur Zeit keinen passenden Partner !');
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          title: Text('Bürgerlich heiraten',
              style: Theme.of(context).textTheme.titleMedium),
          subtitle: const Text('Wer aus Ihrer Dynastie soll heiraten?'),
        ),
        const Divider(height: 1),
        for (final p in proposers)
          ListTile(
            leading: Icon(p.isMale ? Icons.male : Icons.female),
            title: Text('${p.name} (${p.age})'),
            onTap: () {
              Navigator.pop(context);
              _proposeAndReveal(context, controller,
                  gc.MarryCommoner(slot: slot, personId: p.id));
            },
          ),
      ]),
    ),
  );
}

/// Applies the proposal and reveals the answer in a modal — with a short
/// suspense beat before "Angenommen !" / "Abgelehnt !". A human target
/// answers at their next turn instead (pending decision).
Future<void> _proposeAndReveal(BuildContext context,
    GameController controller, gc.PlayerAction action) async {
  final gc.ActionResult result;
  try {
    result = controller.applyIrreversible(action);
  } on gc.ActionException catch (e) {
    _toast(context, e.message);
    return;
  }
  final accepted = result.events.any((e) => e.type == 'wedding');
  final rejected = result.events.any((e) => e.type == 'marriageRejected');
  if (!accepted && !rejected) {
    _toast(context,
        'Der Antrag wird überbracht — die Antwort folgt im nächsten Zug.');
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _MarriageRevealDialog(accepted: accepted),
  );
}

class _MarriageRevealDialog extends StatefulWidget {
  const _MarriageRevealDialog({required this.accepted});

  final bool accepted;

  @override
  State<_MarriageRevealDialog> createState() => _MarriageRevealDialogState();
}

class _MarriageRevealDialogState extends State<_MarriageRevealDialog> {
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
      title: const Text('Heiratsantrag'),
      content: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _revealed
            ? Text(
                widget.accepted ? 'Angenommen !' : 'Abgelehnt !',
                key: const ValueKey('answer'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: widget.accepted ? Colors.green : Colors.red),
              )
            : const Row(
                key: ValueKey('waiting'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('Der Antrag wird überbracht …'),
                ],
              ),
      ),
      actions: [
        FilledButton(
          onPressed:
              _revealed ? () => Navigator.pop(context) : null,
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// The Info sheet — "Mein Reich" stats, events, chronicle, realm list.
void showInfoMenu(BuildContext context, GameController controller) {
  final state = controller.visibleState;
  final realm = controller.currentRealm;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: ListView(children: [
          // "Mein Reich" — the stats that used to crowd the HUD.
          ListTile(
            title: Text(
                'Mein Reich — ${gc.countryNames[realm.slot]}'
                '${state.person(realm.rulerId) == null ? '' : ' (${gc.titleName(realm.titleClass)} ${state.person(realm.rulerId)!.name})'}',
                style: Theme.of(context).textTheme.titleMedium),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 16, runSpacing: 4, children: [
                Text('${tr('treasury')}: ${realm.treasury} T'),
                Text('${tr('population')}: ${realm.population}'),
                Text(
                    '${tr('food')}: ${realm.grainHarvest + realm.livestockHarvest}'),
                Text('${tr('popularity')}: ${realm.popularity}'),
                Text('Armee: ${realm.armySize}'),
                Text('${tr('guards')}: ${realm.guardLevel}'),
                Text('${tr('moves')}: ${realm.movementPoints}'),
              ]),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.article),
            title: Text(tr('eventFeed')),
            onTap: () {
              Navigator.pop(context);
              showEventFeed(context, controller);
            },
          ),
          ListTile(
            leading: const Icon(Icons.home_work),
            title: Text('Siedlungen (${realm.towns.length})'),
            onTap: () {
              Navigator.pop(context);
              _showSettlements(context, controller);
            },
          ),
          ListTile(
            leading: const Icon(Icons.leaderboard),
            title: const Text('Statistiken'),
            onTap: () {
              Navigator.pop(context);
              _showStatistics(context, controller);
            },
          ),
          const Divider(),
          ListTile(
              title: Text(tr('chronicle')),
              subtitle: Text([
                for (final r in state.kaiserChronicle)
                  '${r.name} (${r.accessionYear}–${r.deathYear ?? ''})'
                      '${r.epithet == null ? '' : ' "${r.epithet}"'}',
              ].join('\n'))),
          const Divider(),
          for (final realm in state.realms)
            if (!realm.isVacant)
              ListTile(
                title: Text(
                    '${gc.countryNames[realm.slot]} — ${state.person(realm.rulerId)?.name ?? '?'}'),
                subtitle: Text(_realmInfoLine(controller, realm)),
                trailing: const Icon(Icons.people, size: 18),
                onTap: () {
                  Navigator.pop(context);
                  _showDynastyOf(context, controller, realm.slot);
                },
              ),
        ]),
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
      child: ListView(shrinkWrap: true, children: [
        ListTile(
            title: Text('Siedlungen von ${gc.countryNames[realm.slot]}',
                style: Theme.of(context).textTheme.titleMedium)),
        const Divider(height: 1),
        if (realm.towns.isEmpty)
          const ListTile(title: Text('Sie haben keine Siedlungen !')),
        for (final town in realm.towns)
          ListTile(
            leading: const Icon(Icons.home_work),
            title: Text(
                '${town.name} — ${tierNames[town.buildingType] ?? '?'}'),
            subtitle: Text(
                '${town.population} Einwohner — Garnison '
                '${town.garrison}/${town.troopCapacity} — '
                'Feld (${town.x + 1}, ${town.y + 1})'),
          ),
      ]),
    ),
  );
}

/// "S(t)atistiken": realm ranking from public information only (territory
/// size, settlements, title) — hidden numbers stay hidden.
void _showStatistics(BuildContext context, GameController controller) {
  final state = controller.visibleState;
  final rows = [
    for (final realm in state.realms)
      if (!realm.isVacant)
        (
          realm.slot,
          realm.tileCount.fold(0, (a, b) => a + b),
          realm.towns.length,
          realm.titleClass,
        ),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: ListView(children: [
          ListTile(
              title: Text('Statistiken — Reiche nach Größe',
                  style: Theme.of(context).textTheme.titleMedium)),
          const Divider(height: 1),
          for (var i = 0; i < rows.length; i++)
            ListTile(
              leading: Text('${i + 1}.',
                  style: Theme.of(context).textTheme.titleSmall),
              title: Text(gc.countryNames[rows[i].$1] +
                  (rows[i].$1 == controller.currentSlot ? ' (Sie)' : '')),
              subtitle: Text(
                  '${rows[i].$2} Felder — ${rows[i].$3} Siedlungen — '
                  '${gc.titleName(rows[i].$4)}'),
            ),
        ]),
      ),
    ),
  );
}

/// Own realm: full numbers. Foreign realms: only public data plus the
/// newest intel report, if any (hidden information).
String _realmInfoLine(GameController controller, gc.Realm realm) {
  final own = realm.slot == controller.currentSlot;
  final title = gc.titleName(realm.titleClass);
  if (own) {
    return '$title — ${realm.population} Einwohner, ${realm.treasury} T, '
        'Armee ${realm.armySize}';
  }
  final intel = controller.currentRealm.intelReports
      .where((r) => r.targetSlot == realm.slot)
      .toList();
  if (intel.isEmpty) {
    return '$title — keine Informationen (Spione aussenden!)';
  }
  final latest = intel.last;
  final values = latest.values.entries
      .map((e) => '${e.key} ~${e.value}')
      .join(', ');
  return '$title — Stand ${latest.year}: $values';
}

// --- Shared amount pickers ---------------------------------------------

void _amountSheet(BuildContext context,
    {required String title,
    required int max,
    int allowNegative = 0,
    required void Function(int amount) onSubmit}) {
  if (max <= 0 && allowNegative <= 0) return;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: _AmountSlider(
        title: title,
        max: max,
        min: -allowNegative,
        onSubmit: (amount) {
          Navigator.pop(context);
          onSubmit(amount);
        },
      ),
    ),
  );
}

void _targetThenAmount(BuildContext context, GameController controller,
    {required int max,
    String titlePrefix = 'Agenten',
    required void Function(int targetSlot, int amount) onSubmit}) {
  final state = controller.visibleState;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        for (final realm in state.realms)
          if (realm.slot != controller.currentSlot && !realm.isVacant)
            ListTile(
              title: Text(gc.countryNames[realm.slot]),
              onTap: () {
                Navigator.pop(context);
                _amountSheet(context,
                    title: '$titlePrefix → ${gc.countryNames[realm.slot]}',
                    max: max,
                    onSubmit: (amount) => onSubmit(realm.slot, amount));
              },
            ),
      ]),
    ),
  );
}

/// Slider + confirm, the touch replacement for the original's number
/// input (PROJECT_REQUIREMENTS "Sliders for numeric inputs").
class _AmountSlider extends StatefulWidget {
  const _AmountSlider({
    required this.title,
    required this.max,
    this.min = 0,
    required this.onSubmit,
  });

  final String title;
  final int max;
  final int min;
  final void Function(int) onSubmit;

  @override
  State<_AmountSlider> createState() => _AmountSliderState();
}

class _AmountSliderState extends State<_AmountSlider> {
  late double _value =
      widget.max > 0 ? (widget.max / 2).ceilToDouble() : 0;

  @override
  Widget build(BuildContext context) {
    final max = widget.max.toDouble();
    final min = widget.min.toDouble();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${widget.title}: ${_value.round()}',
            style: Theme.of(context).textTheme.titleMedium),
        Slider(
          value: _value.clamp(min, max),
          min: min,
          max: max <= min ? min + 1 : max,
          divisions:
              (max - min) > 0 && (max - min) <= 1000 ? (max - min).round() : null,
          onChanged: (v) => setState(() => _value = v),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
        ]),
      ]),
    );
  }
}
