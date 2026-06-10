import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/strings.dart';
import '../state/game_controller.dart';

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

/// The main menu hub: commerce, military, espionage, misc, info.
Future<void> showGameMenus(
    BuildContext context, GameController controller) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(children: [
        ListTile(
          leading: const Icon(Icons.storefront),
          title: Text(tr('commerce')),
          onTap: () {
            Navigator.pop(context);
            _showCommerce(context, controller);
          },
        ),
        ListTile(
          leading: const Icon(Icons.shield),
          title: Text(tr('military')),
          onTap: () {
            Navigator.pop(context);
            _showMilitary(context, controller);
          },
        ),
        ListTile(
          leading: const Icon(Icons.visibility),
          title: Text(tr('espionage')),
          onTap: () {
            Navigator.pop(context);
            _showEspionage(context, controller);
          },
        ),
        ListTile(
          leading: const Icon(Icons.church),
          title: Text(tr('misc')),
          onTap: () {
            Navigator.pop(context);
            _showMisc(context, controller);
          },
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(tr('info')),
          onTap: () {
            Navigator.pop(context);
            _showInfo(context, controller);
          },
        ),
      ]),
    ),
  );
}

// --- Commerce ---------------------------------------------------------

void _showCommerce(BuildContext context, GameController controller) {
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
              'Cap: ${realm.tileCount[gc.Building.hafen] * 600} T (Häfen: ${realm.tileCount[gc.Building.hafen]})'),
          enabled: !realm.investedThisTurn &&
              realm.tileCount[gc.Building.hafen] > 0,
          onTap: () => _investSheet(context, controller),
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

void _showMilitary(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final realm = controller.currentRealm;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          title: Text(tr('recruit')),
          subtitle: Text(
              '5 T/man — free capacity: ${realm.troopCapacity - realm.armySize}'),
          onTap: () {
            Navigator.pop(context);
            _recruitSheet(context, controller);
          },
        ),
        ListTile(
          title: Text(tr('hireSoeldner')),
          subtitle: const Text('50 T pro Mann (plus Sold)'),
          onTap: () {
            Navigator.pop(context);
            _amountSheet(context,
                title: tr('hireSoeldner'),
                max: controller.currentRealm.treasury ~/ 50,
                onSubmit: (men) => _tryAction(context, controller,
                    gc.HireSoeldner(slot: slot, men: men, name: 'Söldner')));
          },
        ),
        for (var i = 0; i < realm.troops.length; i++)
          ListTile(
            leading: const Icon(Icons.groups_2),
            title: Text(
                '${realm.troops[i].name} — ${realm.troops[i].men} Mann'),
            subtitle: Text(['Inf', 'Kav', 'Art'][realm.troops[i].troopClass] +
                (realm.troops[i].quality == gc.TroopQuality.soeldner
                    ? ' (Söldner)'
                    : '')),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Disband',
              onPressed: () {
                Navigator.pop(context);
                _tryAction(context, controller,
                    gc.DisbandTroop(slot: slot, unitIndex: i));
              },
            ),
          ),
        ListTile(
          leading: const Icon(Icons.gavel),
          title: Text(tr('declareWar')),
          subtitle: Text(controller.state.year < gc.firstWarYear
              ? 'Kriege sind erst ab dem Jahr 1010 erlaubt !'
              : 'Once per year'),
          onTap: () {
            Navigator.pop(context);
            _declareWarSheet(context, controller);
          },
        ),
      ]),
    ),
  );
}

void _recruitSheet(BuildContext context, GameController controller) {
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
                      name: 'Rekruten'));
            },
          ),
        ]),
      ),
    ),
  );
}

void _declareWarSheet(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final state = controller.visibleState;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        for (final realm in state.realms)
          if (realm.slot != slot && !realm.isVacant)
            ListTile(
              title: Text(gc.countryNames[realm.slot]),
              subtitle:
                  Text(state.person(realm.rulerId)?.name ?? 'unknown'),
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
                          child: const Text('Cancel')),
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

void _showEspionage(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(children: [
        ListTile(
          title: const Text('Daten ausspionieren'),
          subtitle: const Text('200 T pro Agent'),
          onTap: () => _spySheet(context, controller, gc.SpyKind.economy),
        ),
        ListTile(
          title: const Text('Truppen ausspionieren'),
          subtitle: const Text('200 T pro Agent'),
          onTap: () => _spySheet(context, controller, gc.SpyKind.military),
        ),
        ListTile(
          title: const Text('Anschlag verüben'),
          subtitle: const Text('250 T pro Agent'),
          onTap: () => _assassinSheet(context, controller),
        ),
        ListTile(
          title: Text(
              '${tr('guards')}: ${controller.currentRealm.guardLevel} / ${gc.guardCap}'),
          subtitle: const Text('100 T pro Mann'),
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
  _targetThenAmount(context, controller, maxAgents: 30,
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
  _targetThenAmount(context, controller, maxAgents: 30,
      onSubmit: (target, agents) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            'Anschlag auf ${gc.countryNames[target]} — wirklich?'),
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

void _showMisc(BuildContext context, GameController controller) {
  final slot = controller.currentSlot;
  final state = controller.state;
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(children: [
        for (final (religion, name, cost) in [
          (gc.Religion.katholisch, 'katholisch', 0),
          (gc.Religion.evangelisch, 'evangelisch', 500),
          (gc.Religion.moslemisch, 'moslemisch', 1000),
        ])
          if (state.dynasty(slot).religion != religion)
            ListTile(
              title: Text('Religion: $name'),
              trailing: Text('$cost T, −70 ${tr('popularity')}'),
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

void _showInfo(BuildContext context, GameController controller) {
  final state = controller.visibleState;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: ListView(children: [
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
    {required int maxAgents,
    required void Function(int targetSlot, int agents) onSubmit}) {
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
                    title: 'Agents → ${gc.countryNames[realm.slot]}',
                    max: maxAgents,
                    onSubmit: (agents) => onSubmit(realm.slot, agents));
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
        FilledButton(
          onPressed: _value.round() == 0
              ? null
              : () => widget.onSubmit(_value.round()),
          child: const Text('OK'),
        ),
      ]),
    );
  }
}
