import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/strings.dart';
import '../state/game_controller.dart';

const _warTypes = {
  'warDeclared', 'battle', 'rulerCaptured', 'warWon', 'warDraw',
  'tileConquered', 'plunder', 'peaceWish', 'peaceAgreed', 'winterEndsWar',
  'claimPaidOut', 'forcedMarriage', 'forcedAbdication', 'execution',
};
const _dynastyTypes = {
  'wedding', 'birth', 'personDied', 'succession', 'divorce',
  'marriageRejected', 'titlePromoted', 'assassination',
  'assassinationFailed', 'islamicSuccessionCrisis', 'dynastyExtinct',
  'dynastyConverted', 'internalStrife', 'religionChanged',
};
const _worldTypes = {
  'earthquake', 'disease', 'reformation', 'ottomanInvasion',
  'merchantFounder', 'crowned', 'electionStarted', 'electionTie',
  'interregnum', 'newKurfuerst', 'kurfuerstStripped', 'officeHolderDied',
  'gameWon', 'gameDraw', 'totalExtinction',
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
    'tileClaimed' => '$realm beansprucht (${p['x']}, ${p['y']})',
    'shipColonized' =>
      '$realm kolonisiert (${p['x']}, ${p['y']}) per Schiff',
    'buildingBuilt' => '$realm baut auf (${p['x']}, ${p['y']})',
    'townFounded' => '$realm gründet ${p['name']}',
    'townPromoted' => 'Dem Ort ${p['name']} wurde das '
        '${p['building'] == gc.Building.markt ? 'Marktrecht' : 'Stadtrecht'} verliehen',
    'townDied' => '${p['name']} ist verlassen',
    'goodsSold' => '$realm verkauft ${p['amount']} für ${p['proceeds']} T',
    'shipsReturned' =>
      '$realm: Schiffe kehren zurück — ${p['returned']} T',
    'moneySent' =>
      '$realm schickt ${p['amount']} T an ${gc.countryNames[p['targetSlot'] as int]}',
    'capitalRelocated' =>
      '$realm verlegt den Sitz nach (${p['x']}, ${p['y']})',
    'wedding' => '${p['a']} von $realm heiratet ${p['b']}',
    'marriageRejected' => '$realm: der Heiratsantrag wurde abgelehnt !',
    'divorce' =>
      'Die Ehe von ${p['a']} und ${p['b']} wird geschieden (Religion)',
    'birth' =>
      '${p['parent']} von $realm feiert die Geburt von ${p['child']}',
    'personDied' => '${p['name']} von $realm ist im Alter von ${p['age']} '
        'Jahren verstorben (${p['cause']})',
    'succession' =>
      '$realm: Die Weisen erwählen ${p['heir']} zum Erben',
    'titlePromoted' => '$realm: neuer Titel ${p['title']}',
    'troopsRecruited' => '$realm bildet ${p['men']} Rekruten aus',
    'soeldnerHired' => '$realm wirbt ${p['men']} Söldner an',
    'warDeclared' =>
      '$realm erklärt ${gc.countryNames[p['targetSlot'] as int]} den Krieg!',
    'battle' => 'Schlacht: ${p['attackerUnit']} (−${p['attackerLosses']}) '
        'vs ${p['defenderUnit']} (−${p['defenderLosses']})',
    'rulerCaptured' => '$realm nimmt den Herrscher von '
        '${gc.countryNames[p['loserSlot'] as int]} gefangen!',
    'warWon' =>
      '$realm gewinnt den Krieg gegen ${gc.countryNames[p['loserSlot'] as int]}',
    'warDraw' => 'Der Krieg endet unentschieden',
    'peaceAgreed' =>
      'Friedensschluss — der Krieg endet ohne Gebietsänderungen',
    'winterEndsWar' => 'Der Winter beendet den Krieg',
    'peaceWish' => '$realm wünscht ein Ende des Krieges',
    'tileConquered' => '$realm erobert (${p['x']}, ${p['y']}) von '
        '${gc.countryNames[p['from'] as int]}',
    'plunder' => '$realm plündert (${p['x']}, ${p['y']}) — Opfer: '
        '${gc.countryNames[p['victim'] as int]}',
    'claimPaidOut' => '$realm erhält ${p['amount']} T Kriegsentschädigung '
        'von ${gc.countryNames[p['from'] as int]}',
    'forcedMarriage' =>
      '${p['victor']} erzwingt die Heirat mit ${p['spouse']}',
    'forcedAbdication' => '${p['name']} muss abdanken !',
    'execution' => '${p['name']} wird hingerichtet !!!',
    'realmsMerged' =>
      '$realm übernimmt ${gc.countryNames[p['sourceSlot'] as int]}',
    'crowned' =>
      '${p['name']} von $realm wird ${p['office'] == 'kaiser' ? 'Kaiser' : 'Sultan'}',
    'electionStarted' =>
      '${p['office'] == 'kaiser' ? 'Kaiserwahl' : 'Sultanswahl'} — die Wahl beginnt',
    'electionTie' => 'Die Wahl endet unentschieden — Stichwahl !',
    'interregnum' => 'Interregnum — der Thron bleibt unbesetzt',
    'newKurfuerst' => '${p['name']} wird Kurfürst',
    'kurfuerstStripped' =>
      '${p['name']} verliert die Kurfürstenwürde',
    'officeHolderDied' => 'Der Amtsinhaber ist verstorben',
    'assassination' =>
      '${p['victim']} von $realm wird hinterhältig ermordet !!!',
    'assassinationFailed' => 'Anschlag auf ${p['victim']} vereitelt — '
        'Auftraggeber: ${gc.countryNames[p['sponsorSlot'] as int]}',
    'assassinsDispatched' => '$realm entsendet ${p['agents']} Attentäter '
        'nach ${gc.countryNames[p['targetSlot'] as int]}',
    'intelGathered' => '$realm: Spionagebericht über '
        '${gc.countryNames[p['targetSlot'] as int]} liegt vor',
    'missionFailed' => '$realm: Spionagemission in '
        '${gc.countryNames[p['targetSlot'] as int]} gescheitert'
        '${p['caught'] == true ? ' — Agenten gefasst !' : ''}',
    'religionChanged' => '$realm wechselt die Religion',
    'dynastyConverted' => '$realm: die Dynastie konvertiert',
    'dynastyExtinct' => '$realm: die Dynastie ist erloschen',
    'islamicSuccessionCrisis' =>
      '$realm: Erbfolgekrise — ${p['heir']} setzt sich durch',
    'internalStrife' =>
      '$realm: innere Unruhen — ${p['newRuler']} ergreift die Macht',
    'bankruptcy' => '$realm ist bankrott (${p['debt']} T Schulden) !',
    'merchantFounder' =>
      'Der Kaufmann ${p['name']} gründet eine neue Dynastie',
    'totalExtinction' => 'Alle Dynastien sind erloschen — das Land verfällt',
    'earthquake' => 'Ein verheerendes Erdbeben verwüstet das Reich',
    'disease' => 'Die ${p['name']} geht um!',
    'reformation' => 'Die Reformation! ',
    'ottomanInvasion' => 'Eine riesige Reiterhorde dringt in das Reich ein!',
    'buildingDemolished' => '$realm reißt (${p['x']}, ${p['y']}) ab',
    'gameWon' => '$realm ist der alleinige Herrscher des ganzen Landes!',
    'gameDraw' =>
      'Alle Dynastien sind erloschen — das Land bleibt herrenlos',
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
                ButtonSegment(value: 'all', label: Text('Alle')),
                ButtonSegment(value: 'mine', label: Text('Mein Reich')),
                ButtonSegment(value: 'wars', label: Text('Kriege')),
                ButtonSegment(value: 'dynasty', label: Text('Dynastie')),
                ButtonSegment(value: 'world', label: Text('Welt')),
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

/// Routine map management by other players — noise in the recap.
const _trivialTypes = {'tileClaimed', 'buildingBuilt', 'buildingDemolished'};

/// Blow-by-blow war detail — the recap only shows the result
/// (warWon/warDraw/winterEndsWar/rulerCaptured); the full feed keeps all.
const _warDetailTypes = {'battle', 'tileConquered', 'plunder', 'peaceWish'};

/// Rare, personal drama that gets its own popup at turn start (the recap
/// card then skips it): an assassination hitting your dynasty, the fate
/// of assassins YOU sent, your coronation.
bool _popupWorthy(gc.GameEvent e, int slot) => switch (e.type) {
      'assassination' => e.slot == slot,
      'assassinationFailed' =>
        e.slot == slot || e.payload['sponsorSlot'] == slot,
      'crowned' => e.slot == slot,
      _ => false,
    };

/// Big news rendered as styled headline rows at the top of the recap.
bool _isHeadline(gc.GameEvent e, int slot) => switch (e.type) {
      'warDeclared' ||
      'rulerCaptured' ||
      'warWon' ||
      'warDraw' ||
      'peaceAgreed' ||
      'crowned' ||
      'reformation' ||
      'ottomanInvasion' ||
      'assassination' ||
      'assassinationFailed' ||
      'totalExtinction' =>
        true,
      'earthquake' ||
      'disease' ||
      'bankruptcy' ||
      'internalStrife' ||
      'realmsMerged' ||
      'dynastyExtinct' ||
      'islamicSuccessionCrisis' =>
        e.slot == slot,
      _ => false,
    };

(IconData, Color) _headlineStyle(gc.GameEvent e) => switch (e.type) {
      'warDeclared' => (Icons.gavel, Colors.red),
      'rulerCaptured' => (Icons.lock, Colors.red),
      'warWon' => (Icons.emoji_events, Colors.orange),
      'warDraw' || 'peaceAgreed' => (Icons.handshake, Colors.green),
      'crowned' => (Icons.emoji_events, Colors.amber),
      'reformation' => (Icons.church, Colors.purple),
      'ottomanInvasion' => (Icons.warning, Colors.red),
      'assassination' => (Icons.dangerous, Colors.red),
      'assassinationFailed' => (Icons.report, Colors.orange),
      'earthquake' => (Icons.warning_amber, Colors.brown),
      'disease' => (Icons.coronavirus, Colors.red),
      'bankruptcy' => (Icons.money_off, Colors.red),
      'internalStrife' => (Icons.local_fire_department, Colors.red),
      'realmsMerged' => (Icons.merge_type, Colors.green),
      'dynastyExtinct' => (Icons.heart_broken, Colors.blueGrey),
      _ => (Icons.campaign, Colors.blueGrey),
    };

/// Standalone drama popups, shown after pending decisions and before the
/// recap card (which skips these events). One dialog per event, styled
/// like the marriage prompt.
Future<void> showDramaPopups(
    BuildContext context, GameController controller, int slot) async {
  final drama = controller
      .recapFor(slot)
      .where((e) => _popupWorthy(e, slot))
      .toList();
  for (final e in drama) {
    if (!context.mounted) return;
    final p = e.payload;
    final (IconData icon, Color color, String title, String body) =
        switch (e.type) {
      'assassination' => (
          Icons.dangerous,
          Colors.red,
          'Attentat !!!',
          '${p['victim']} wurde von gedungenen Mördern ermordet !',
        ),
      'assassinationFailed' when e.slot == slot => (
          Icons.report,
          Colors.orange,
          'Attentat vereitelt !',
          'Ein Anschlag auf ${p['victim']} ist fehlgeschlagen !'
              '${(p['caught'] as int? ?? 0) > 0 ? '\nDie gefassten Attentäter gestehen unter Folter: der Auftrag kam aus ${gc.countryNames[p['sponsorSlot'] as int]} !' : ''}',
        ),
      'assassinationFailed' => (
          Icons.report,
          Colors.orange,
          'Anschlag fehlgeschlagen',
          'Deine Attentäter haben ${p['victim']} nicht erwischt'
              '${(p['caught'] as int? ?? 0) > 0 ? ' — und wurden gefasst ! Dein Auftrag ist nun bekannt !' : '.'}',
        ),
      'crowned' => (
          Icons.emoji_events,
          Colors.amber,
          p['office'] == 'kaiser' ? 'Du bist Kaiser !' : 'Du bist Sultan !',
          '${p['name']} wird '
              '${p['acclaimed'] == true ? 'ohne Gegenstimme ' : ''}'
              'zum ${p['office'] == 'kaiser' ? 'Kaiser' : 'Sultan'} gekrönt !',
        ),
      _ => (Icons.campaign, Colors.blueGrey, 'Nachricht', describeEvent(e)),
    };
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ]),
        content: Text(body),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Weiter')),
        ],
      ),
    );
  }
}

/// The "since your last turn" recap card, shown right after the handoff.
/// Upkeep lines, other players' trivial tile actions, war details and
/// popup-worthy drama (already shown by [showDramaPopups]) are skipped;
/// big news gets styled headline rows above the plain lines.
Future<void> showRecapCard(
    BuildContext context, GameController controller, int slot) async {
  final recap = controller.recapFor(slot)
      .where((e) =>
          e.type != 'turnUpkeep' &&
          !_warDetailTypes.contains(e.type) &&
          !(_trivialTypes.contains(e.type) && e.slot != slot) &&
          !_popupWorthy(e, slot))
      .toList();
  controller.markRecapSeen(slot);
  if (recap.isEmpty) return;
  final headlines =
      recap.reversed.where((e) => _isHeadline(e, slot)).take(10).toList();
  final rest = recap.reversed
      .where((e) => !_isHeadline(e, slot))
      .take(30)
      .toList();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('eventFeed')),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(shrinkWrap: true, children: [
          for (final e in headlines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_headlineStyle(e).$1,
                        color: _headlineStyle(e).$2, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${e.year}: ${describeEvent(e)}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium!
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
            ),
          if (headlines.isNotEmpty && rest.isNotEmpty)
            const Divider(height: 16),
          for (final e in rest)
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
