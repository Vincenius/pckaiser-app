import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/strings.dart';
import '../state/game_controller.dart';

const _warTypes = {
  'warDeclared', 'battle', 'rulerCaptured', 'warWon', 'warDraw',
  'tileConquered', 'plunder', 'peaceWish', 'winterEndsWar', 'claimPaidOut',
  'forcedMarriage', 'forcedAbdication', 'execution',
};
const _dynastyTypes = {
  'wedding', 'birth', 'personDied', 'succession', 'divorce',
  'marriageRejected', 'titlePromoted', 'assassination',
  'islamicSuccessionCrisis', 'dynastyExtinct', 'dynastyConverted',
};
const _worldTypes = {
  'earthquake', 'disease', 'reformation', 'ottomanInvasion',
  'merchantFounder', 'crowned', 'electionStarted', 'electionTie',
  'interregnum', 'newKurfuerst', 'officeHolderDied', 'gameWon',
  'totalExtinction',
};

/// Human-readable line for an event. Falls back to the type name so new
/// event types never break the feed.
String describeEvent(gc.GameEvent e) {
  final p = e.payload;
  final realm =
      e.slot >= 1 && e.slot <= 30 ? gc.countryNames[e.slot] : 'Welt';
  return switch (e.type) {
    'turnUpkeep' => '$realm: Steuern ${p['tax']} T, Ernte '
        '${p['grainYield']}/${p['livestockYield']}, Sold ${p['wages']} T',
    'tileClaimed' => '$realm claims (${p['x']}, ${p['y']})',
    'buildingBuilt' => '$realm builds on (${p['x']}, ${p['y']})',
    'townFounded' => '$realm founds ${p['name']}',
    'townPromoted' => 'Dem Ort ${p['name']} wurde das '
        '${p['building'] == gc.Building.markt ? 'Marktrecht' : 'Stadtrecht'} verliehen',
    'townDied' => '${p['name']} ist verlassen',
    'goodsSold' => '$realm verkauft ${p['amount']} für ${p['proceeds']} T',
    'shipsReturned' =>
      '$realm: Schiffe kehren zurück — ${p['returned']} T',
    'wedding' => '${p['a']} heiratet ${p['b']}',
    'birth' => '${p['parent']} feiert die Geburt von ${p['child']}',
    'personDied' => '${p['name']} ist im Alter von ${p['age']} Jahren '
        'verstorben (${p['cause']})',
    'succession' => 'Die Weisen erwählen ${p['heir']} zum Erben',
    'titlePromoted' => '$realm: neuer Titel ${p['title']}',
    'warDeclared' =>
      '$realm erklärt ${gc.countryNames[p['targetSlot'] as int]} den Krieg!',
    'battle' => 'Schlacht: ${p['attackerUnit']} (−${p['attackerLosses']}) '
        'vs ${p['defenderUnit']} (−${p['defenderLosses']})',
    'rulerCaptured' => '$realm nimmt den Herrscher von '
        '${gc.countryNames[p['loserSlot'] as int]} gefangen!',
    'warWon' => '$realm gewinnt den Krieg — Anspruch ${p['claim']}',
    'crowned' => '${p['name']} wird ${p['office'] == 'kaiser' ? 'Kaiser' : 'Sultan'}',
    'assassination' => '${p['victim']} wird hinterhältig ermordet !!!',
    'assassinationFailed' => 'Anschlag auf ${p['victim']} vereitelt — '
        'Auftraggeber: ${gc.countryNames[p['sponsorSlot'] as int]}',
    'earthquake' => 'Ein verheerendes Erdbeben verwüstet das Reich',
    'disease' => 'Die ${p['name']} geht um!',
    'reformation' => 'Die Reformation! ',
    'ottomanInvasion' => 'Eine riesige Reiterhorde dringt in das Reich ein!',
    'gameWon' => '$realm ist der alleinige Herrscher des ganzen Landes!',
    _ => '$realm: ${e.type}',
  };
}

/// Scrolling event feed with filters (my realm / wars / dynasty / world).
Future<void> showEventFeed(
    BuildContext context, GameController controller) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        _EventFeedSheet(controller: controller),
  );
}

class _EventFeedSheet extends StatefulWidget {
  const _EventFeedSheet({required this.controller});

  final GameController controller;

  @override
  State<_EventFeedSheet> createState() => _EventFeedSheetState();
}

class _EventFeedSheetState extends State<_EventFeedSheet> {
  String _filter = 'all';

  bool _matches(gc.GameEvent e) => switch (_filter) {
        'mine' => e.slot == widget.controller.currentSlot,
        'wars' => _warTypes.contains(e.type),
        'dynasty' => _dynastyTypes.contains(e.type),
        'world' => _worldTypes.contains(e.type),
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final slot = widget.controller.currentSlot;
    final events = widget.controller.state.events.reversed
        .where((e) => e.visibleTo(slot) && _matches(e))
        .take(200)
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'mine', label: Text('Mine')),
                ButtonSegment(value: 'wars', label: Text('Wars')),
                ButtonSegment(value: 'dynasty', label: Text('Dynasty')),
                ButtonSegment(value: 'world', label: Text('World')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: events.length,
              itemBuilder: (context, i) => ListTile(
                dense: true,
                leading: Text('${events[i].year}'),
                title: Text(describeEvent(events[i])),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The "since your last turn" recap card, shown right after the handoff.
Future<void> showRecapCard(
    BuildContext context, GameController controller, int slot) async {
  final recap = controller.recapFor(slot)
      .where((e) => e.type != 'turnUpkeep')
      .toList();
  controller.markRecapSeen(slot);
  if (recap.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('eventFeed')),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(shrinkWrap: true, children: [
          for (final e in recap.reversed.take(30))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${e.year}: ${describeEvent(e)}'),
            ),
        ]),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK')),
      ],
    ),
  );
}
