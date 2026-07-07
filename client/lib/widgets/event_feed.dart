import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/strings.dart';
import '../state/game_controller.dart';

const _warTypes = {
  'warDeclared',
  'battle',
  'rulerCaptured',
  'capitalHeld',
  'warWon',
  'warDraw',
  'tileConquered',
  'plunder',
  'peaceWish',
  'peaceAgreed',
  'winterEndsWar',
  'claimPaidOut',
  'realmOverrun',
  'forcedMarriage',
  'forcedAbdication',
  'execution',
};
const _dynastyTypes = {
  'wedding',
  'birth',
  'personDied',
  'succession',
  'divorce',
  'marriageRejected',
  'titlePromoted',
  'assassination',
  'assassinationSucceeded',
  'assassinationFailed',
  'islamicSuccessionCrisis',
  'dynastyExtinct',
  'realmInherited',
  'dynastyConverted',
  'internalStrife',
  'religionChanged',
};
const _worldTypes = {
  'earthquake',
  'disease',
  'reformation',
  'ottomanInvasion',
  'merchantFounder',
  'crowned',
  'electionStarted',
  'electionTie',
  'interregnum',
  'newKurfuerst',
  'kurfuerstStripped',
  'officeHolderDied',
  'tributeCollected',
  'gameWon',
  'gameDraw',
  'totalExtinction',
  'humansDefeated',
};

/// Human-readable line for an event. Falls back to the type name so new
/// event types never break the feed.
String describeEvent(gc.GameEvent e) {
  final p = e.payload;
  final realm = e.slot >= 1 && e.slot <= 30 ? gc.countryNames[e.slot] : 'Welt';
  return switch (e.type) {
    'turnUpkeep' =>
      '$realm: Steuern ${p['tax']} T, Ernte '
          '${p['grainYield']}/${p['livestockYield']}, Sold ${p['wages']} T',
    'tileClaimed' => '$realm beansprucht (${p['x']}, ${p['y']})',
    'shipBought' =>
      '$realm kauft ein Schiff im Hafen '
          '(${p['x']}, ${p['y']})',
    'shipColonized' => '$realm kolonisiert (${p['x']}, ${p['y']}) per Schiff',
    'buildingBuilt' => '$realm baut auf (${p['x']}, ${p['y']})',
    'townFounded' => '$realm gründet ${p['name']}',
    'townPromoted' =>
      'Dem Ort ${p['name']} wurde das '
          '${p['building'] == gc.Building.markt ? 'Marktrecht' : 'Stadtrecht'} verliehen',
    'townDied' => '${p['name']} ist verlassen',
    'goodsSold' => '$realm verkauft ${p['amount']} für ${p['proceeds']} T',
    'shipsSent' =>
      '$realm sendet Handelsschiffe aus — Einsatz ${p['invested']} T',
    'shipsReturned' =>
      '$realm: Handelsschiffe kehren zurück — Erlös ${p['returned']} T '
          '(Einsatz ${p['invested']} T)',
    'moneySent' =>
      '$realm schickt ${p['amount']} T an ${gc.countryNames[p['targetSlot'] as int]}',
    'capitalRelocated' =>
      '$realm verlegt den Sitz nach (${(p['x'] as int) + 1}, ${(p['y'] as int) + 1})',
    'capitalReseated' =>
      '$realm bestimmt nach dem Verlust einen neuen Sitz bei '
          '(${(p['x'] as int) + 1}, ${(p['y'] as int) + 1})',
    'capitalLost' =>
      '$realm hat seinen Sitz verloren — ein neuer muss bestimmt werden !',
    'wedding' => '${p['a']} von $realm heiratet ${p['b']}',
    'marriageRejected' =>
      p['reason'] == 'invalid'
          ? '$realm: die Heirat ist nicht mehr möglich '
                '(einer der Partner ist inzwischen gebunden) !'
          : '$realm: der Heiratsantrag wurde abgelehnt !',
    'divorce' =>
      'Die Ehe von ${p['a']} und ${p['b']} wird geschieden (Religion)',
    'birth' => '${p['parent']} von $realm feiert die Geburt von ${p['child']}',
    'personDied' =>
      '${p['name']} von $realm ist im Alter von ${p['age']} '
          'Jahren verstorben (${p['cause']})',
    'succession' => '$realm: Die Weisen erwählen ${p['heir']} zum Erben',
    'titlePromoted' => '$realm: neuer Titel ${p['title']}',
    'troopsRecruited' => '$realm bildet ${p['men']} Rekruten aus',
    'soeldnerHired' => '$realm wirbt ${p['men']} Söldner an',
    'warDeclared' =>
      '$realm erklärt ${gc.countryNames[p['targetSlot'] as int]} den Krieg!',
    'battle' =>
      'Schlacht: ${p['attackerUnit']} (−${p['attackerLosses']}) '
          'vs ${p['defenderUnit']} (−${p['defenderLosses']})',
    'rulerCaptured' =>
      '$realm nimmt den Herrscher von '
          '${gc.countryNames[p['loserSlot'] as int]} gefangen!',
    'capitalHeld' =>
      '$realm besetzt den Königssitz von '
          '${gc.countryNames[p['loserSlot'] as int]} !',
    'warWon' =>
      '$realm gewinnt den Krieg gegen ${gc.countryNames[p['loserSlot'] as int]}',
    'warDraw' => 'Der Krieg endet unentschieden',
    'peaceAgreed' => 'Friedensschluss — der Krieg endet ohne Gebietsänderungen',
    'winterEndsWar' =>
      'Der Krieg musste wegen des hereinbrechenden Winters beendet werden',
    'peaceWish' => '$realm wünscht ein Ende des Krieges',
    'tileConquered' =>
      '$realm erobert (${p['x']}, ${p['y']}) von '
          '${gc.countryNames[p['from'] as int]}',
    'plunder' =>
      '$realm plündert (${p['x']}, ${p['y']}) — Opfer: '
          '${gc.countryNames[p['victim'] as int]}',
    'claimPaidOut' =>
      '$realm erhält ${p['amount']} T Kriegsentschädigung '
          'von ${gc.countryNames[p['from'] as int]}',
    'realmOverrun' => '$realm hat sein gesamtes Land verloren !',
    'humansDefeated' =>
      'Keine menschliche Dynastie hält mehr die Macht — das Spiel ist aus',
    'playerLeft' =>
      '$realm: der Spieler hat die Partie verlassen — der Computer übernimmt',
    'playerKicked' =>
      '$realm: der Spieler wurde wegen Inaktivität ersetzt — '
          'der Computer übernimmt',
    'forcedMarriage' => '${p['victor']} erzwingt die Heirat mit ${p['spouse']}',
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
    'tributeCollected' =>
      '$realm plündert den '
          '${p['office'] == 'sultan' ? 'Sultansschatz' : 'Kronschatz'}: '
          '+${p['amount']} T',
    'newKurfuerst' => '${p['name']} wird Kurfürst',
    'kurfuerstStripped' => '${p['name']} verliert die Kurfürstenwürde',
    'officeHolderDied' => 'Der Amtsinhaber ist verstorben',
    'assassination' =>
      '${p['victim']} von $realm wird hinterhältig ermordet !!!',
    'assassinationSucceeded' =>
      'Deine Attentäter haben ${p['victim']} in '
          '${gc.countryNames[p['targetSlot'] as int? ?? 0]} ermordet',
    'assassinationFailed' =>
      'Anschlag auf ${p['victim']} vereitelt — '
          'Auftraggeber: ${gc.countryNames[p['sponsorSlot'] as int]}',
    'assassinsDispatched' =>
      '$realm entsendet ${p['agents']} Attentäter '
          'nach ${gc.countryNames[p['targetSlot'] as int]}',
    'intelGathered' =>
      '$realm: Spionagebericht über '
          '${gc.countryNames[p['targetSlot'] as int]} liegt vor',
    'missionFailed' =>
      (p['caught'] as int? ?? 0) > 0
          ? 'Spione in ${gc.countryNames[p['targetSlot'] as int]} '
                'gefangengenommen — einer gesteht unter Folter, aus '
                '$realm geschickt worden zu sein !!!'
          : '$realm: Spionagemission in '
                '${gc.countryNames[p['targetSlot'] as int]} gescheitert',
    'religionChanged' =>
      '$realm wechselt die Religion'
          '${(p['popularityLost'] as int? ?? 0) > 0 ? ' (−${p['popularityLost']} Beliebtheit)' : ''}',
    'dynastyConverted' => '$realm: die Dynastie konvertiert',
    'dynastyExtinct' => '$realm: die Dynastie ist erloschen',
    'realmInherited' =>
      'Durch Erbfolge fällt '
          '${((p['slots'] as List?) ?? const []).map((s) => gc.countryNames[s as int]).join(', ')} '
          'an ${p['heir']} von $realm',
    'islamicSuccessionCrisis' =>
      '$realm: Erbfolgekrise — ${p['heir']} setzt sich durch',
    'internalStrife' =>
      '$realm: innere Unruhen — ${p['newRuler']} ergreift die Macht',
    'bankruptcy' => '$realm ist bankrott (${p['debt']} T Schulden) !',
    'debtWarning' =>
      '$realm steckt tief in Schulden (${p['debt']} T) — noch '
          '${p['turnsLeft']} ${(p['turnsLeft'] as int) == 1 ? 'Zug' : 'Züge'} '
          'bis zum Staatsbankrott !',
    'merchantFounder' => 'Der Kaufmann ${p['name']} gründet eine neue Dynastie',
    'totalExtinction' => 'Alle Dynastien sind erloschen — das Land verfällt',
    'earthquake' => 'Ein verheerendes Erdbeben verwüstet das Reich',
    'disease' => 'Die ${p['name']} geht um!',
    'reformation' => 'Die Reformation! ',
    'ottomanInvasion' => 'Eine riesige Reiterhorde dringt in das Reich ein!',
    'buildingDemolished' => '$realm reißt (${p['x']}, ${p['y']}) ab',
    'gameWon' => '$realm ist der alleinige Herrscher des ganzen Landes!',
    'gameDraw' => 'Alle Dynastien sind erloschen — das Land bleibt herrenlos',
    _ => '$realm: ${e.type}',
  };
}

/// Scrolling event feed with filters (my realm / wars / dynasty / world).
Future<void> showEventFeed(
  BuildContext context,
  GameController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _EventFeedSheet(controller: controller),
  );
}

class _EventFeedSheet extends StatefulWidget {
  const _EventFeedSheet({required this.controller});

  final GameController controller;

  @override
  State<_EventFeedSheet> createState() => _EventFeedSheetState();
}

/// Routine bookkeeping of OTHER realms — noise in the "Wichtig" filter.
const _routineTypes = {
  'tileClaimed',
  'buildingBuilt',
  'buildingDemolished',
  'goodsSold',
  'shipsSent',
  'shipsReturned',
  'shipBought',
  'shipColonized',
  'troopsRecruited',
  'soeldnerHired',
  'moneySent',
};

/// The default "Wichtig" filter: what the seated player actually cares
/// about. Drops the upkeep number wall (now the turn-start report),
/// other realms' routine map/economy management, and blow-by-blow war
/// detail that doesn't involve the player.
bool _isRelevant(gc.GameEvent e, int slot) {
  if (e.type == 'turnUpkeep') return false;
  if (e.slot != slot && _routineTypes.contains(e.type)) return false;
  if (e.type == 'battle' || e.type == 'peaceWish') return false;
  if (e.type == 'tileConquered' || e.type == 'plunder') {
    return e.slot == slot ||
        e.payload['from'] == slot ||
        e.payload['victim'] == slot;
  }
  return true;
}

class _EventFeedSheetState extends State<_EventFeedSheet> {
  String _filter = 'relevant';

  static const _filters = [
    ('relevant', 'Wichtig'),
    ('mine', 'Mein Reich'),
    ('wars', 'Kriege'),
    ('dynasty', 'Dynastie'),
    ('world', 'Welt'),
    ('all', 'Alles'),
  ];

  bool _matches(gc.GameEvent e, int slot) => switch (_filter) {
    'relevant' => _isRelevant(e, slot),
    'mine' => e.slot == slot,
    'wars' => _warTypes.contains(e.type),
    'dynasty' => _dynastyTypes.contains(e.type),
    'world' => _worldTypes.contains(e.type),
    _ => e.type != 'turnUpkeep',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slot = widget.controller.currentSlot;
    // Realms played by a human (the seated player or — online — a rival):
    // their events are highlighted so real players' moves stand out from the
    // AI's routine bookkeeping.
    final humanSlots = {
      for (final d in widget.controller.state.dynasties)
        if (d.status == gc.DynastyStatus.human) d.index,
    };
    final events = [
      for (final e in widget.controller.state.events)
        if (e.visibleTo(slot) && _matches(e, slot)) e,
    ];
    // Bounded, newest years first — but top-down WITHIN a year, so a
    // sequence (war declared → battle → war won) reads chronologically.
    final visible = events.length > 300
        ? events.sublist(events.length - 300)
        : events;
    final byYear = <int, List<gc.GameEvent>>{};
    for (final e in visible) {
      byYear.putIfAbsent(e.year, () => []).add(e);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (value, label) in _filters)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _filter == value,
                          onSelected: (_) => setState(() => _filter = value),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('Keine Ereignisse.'))
                  : ListView(
                      children: [
                        for (final year in years) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                            child: Row(
                              children: [
                                Text(
                                  'Anno $year',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Expanded(child: Divider()),
                              ],
                            ),
                          ),
                          for (final e in byYear[year]!)
                            _eventRow(theme, e, slot, humanSlots),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// One feed line: type icon (colored for drama), the description, bold
  /// text when the event concerns the seated player's realm, and a small
  /// person badge highlighting events of OTHER human players (so real
  /// rivals' moves stand out from the AI's bookkeeping, especially online).
  Widget _eventRow(
    ThemeData theme,
    gc.GameEvent e,
    int slot,
    Set<int> humanSlots,
  ) {
    final (icon, color) = _eventStyle(e);
    final mine = e.slot == slot;
    final otherHuman = !mine && e.slot >= 1 && humanSlots.contains(e.slot);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: otherHuman
          ? BoxDecoration(
              border: Border(
                left: BorderSide(color: theme.colorScheme.primary, width: 3),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: color ?? theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              describeEvent(e),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: (mine || otherHuman) ? FontWeight.w600 : null,
              ),
            ),
          ),
          if (otherHuman)
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 1),
              child: Icon(
                Icons.person,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}

/// Routine map management by other players — noise in the recap.
const _trivialTypes = {'tileClaimed', 'buildingBuilt', 'buildingDemolished'};

/// Blow-by-blow war detail — the recap only shows the result
/// (warWon/warDraw/winterEndsWar/rulerCaptured); the full feed keeps all.
const _warDetailTypes = {
  'battle',
  'tileConquered',
  'plunder',
  'peaceWish',
  'capitalHeld',
};

/// Rare, personal drama that gets its own popup at turn start (the recap
/// card then skips it): an assassination hitting your dynasty, the fate
/// of assassins YOU sent, your coronation.
bool _popupWorthy(gc.GameEvent e, int slot) => switch (e.type) {
  'assassination' => e.slot == slot,
  // The sponsor's own confirmation (owner-visible only anyway).
  'assassinationSucceeded' => e.slot == slot,
  'assassinationFailed' => e.slot == slot || e.payload['sponsorSlot'] == slot,
  'crowned' => e.slot == slot,
  // Your house inherited whole realms — easy to miss as a feed line.
  'realmInherited' => e.slot == slot,
  // A human player losing their whole realm (or their ruler captured) is a
  // story-worthy event the whole table should see as a strong popup — and
  // the victim themselves above all.
  'realmOverrun' => e.payload['human'] == true,
  'rulerCaptured' => e.payload['loserHuman'] == true,
  // An idle player replaced by the AI — the whole table should be told.
  'playerKicked' => true,
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
  'totalExtinction' ||
  'realmInherited' ||
  'playerKicked' => true,
  'realmOverrun' => e.slot == slot,
  // Caught foreign spies confessed the sponsor — big news for the realm
  // they were caught in.
  'missionFailed' =>
    e.payload['targetSlot'] == slot && (e.payload['caught'] as int? ?? 0) > 0,
  'earthquake' ||
  'disease' ||
  'bankruptcy' ||
  'debtWarning' ||
  'internalStrife' ||
  'realmsMerged' ||
  'dynastyExtinct' ||
  'islamicSuccessionCrisis' => e.slot == slot,
  _ => false,
};

/// Icon + accent color per event type — drama gets color, routine events
/// a neutral icon (the feed falls back to the surface-variant color).
(IconData, Color?) _eventStyle(gc.GameEvent e) => switch (e.type) {
  'warDeclared' => (Icons.gavel, Colors.red),
  'rulerCaptured' => (Icons.lock, Colors.red),
  'capitalHeld' => (Icons.flag, Colors.deepOrange),
  'warWon' => (Icons.emoji_events, Colors.orange),
  'warDraw' ||
  'peaceAgreed' ||
  'winterEndsWar' => (Icons.handshake, Colors.green),
  'peaceWish' => (Icons.handshake, null),
  'battle' => (Icons.shield, null),
  'tileConquered' => (Icons.flag_circle, Colors.deepOrange),
  'plunder' => (Icons.local_fire_department, Colors.deepOrange),
  'claimPaidOut' => (Icons.payments, Colors.orange),
  'realmOverrun' => (Icons.public_off, Colors.red),
  'crowned' => (Icons.emoji_events, Colors.amber),
  'electionStarted' ||
  'electionTie' ||
  'interregnum' ||
  'newKurfuerst' ||
  'kurfuerstStripped' => (Icons.how_to_vote, Colors.indigo),
  'reformation' ||
  'religionChanged' ||
  'dynastyConverted' => (Icons.church, Colors.purple),
  'ottomanInvasion' => (Icons.warning, Colors.red),
  'assassination' => (Icons.dangerous, Colors.red),
  'assassinationSucceeded' => (Icons.dangerous, Colors.green),
  'assassinationFailed' => (Icons.report, Colors.orange),
  'assassinsDispatched' => (Icons.visibility_off, null),
  'intelGathered' || 'missionFailed' => (Icons.visibility, Colors.indigo),
  'earthquake' => (Icons.warning_amber, Colors.brown),
  'disease' => (Icons.coronavirus, Colors.red),
  'bankruptcy' => (Icons.money_off, Colors.red),
  'debtWarning' => (Icons.warning_amber, Colors.orange),
  'internalStrife' => (Icons.local_fire_department, Colors.red),
  'realmsMerged' => (Icons.merge_type, Colors.green),
  'dynastyExtinct' ||
  'totalExtinction' => (Icons.heart_broken, Colors.blueGrey),
  'realmInherited' => (Icons.account_balance, Colors.amber),
  'wedding' || 'forcedMarriage' => (Icons.favorite, Colors.pink),
  'marriageRejected' || 'divorce' => (Icons.heart_broken, null),
  'birth' => (Icons.child_care, Colors.teal),
  'personDied' || 'officeHolderDied' => (Icons.church, Colors.blueGrey),
  'execution' || 'forcedAbdication' => (Icons.dangerous, Colors.red),
  'succession' ||
  'islamicSuccessionCrisis' => (Icons.account_balance, Colors.indigo),
  'titlePromoted' => (Icons.military_tech, Colors.amber),
  'capitalRelocated' ||
  'capitalReseated' => (Icons.location_city, Colors.brown),
  'capitalLost' => (Icons.location_off, Colors.red),
  'townFounded' || 'townPromoted' => (Icons.home_work, Colors.brown),
  'townDied' => (Icons.home_work, Colors.blueGrey),
  'troopsRecruited' || 'soeldnerHired' => (Icons.shield, null),
  'goodsSold' ||
  'moneySent' ||
  'shipsReturned' ||
  'merchantFounder' => (Icons.storefront, null),
  'shipBought' || 'shipColonized' || 'shipsSent' => (Icons.sailing, null),
  'gameWon' => (Icons.emoji_events, Colors.amber),
  'gameDraw' || 'humansDefeated' => (Icons.history_edu, Colors.blueGrey),
  'playerLeft' || 'playerKicked' => (Icons.person_off, Colors.blueGrey),
  _ => (Icons.campaign, null),
};

/// Title/body/style for a drama popup, or null when the event is not
/// popup-worthy for [slot]. Shared by the turn-start recap ([showDramaPopups])
/// and the online out-of-turn surfacing ([showDramaPopupsFor]).
(IconData, Color, String, String)? _dramaContent(gc.GameEvent e, int slot) {
  if (!_popupWorthy(e, slot)) return null;
  final p = e.payload;
  return switch (e.type) {
    'assassination' => (
      Icons.dangerous,
      Colors.red,
      'Attentat !!!',
      '${p['victim']} wurde von gedungenen Mördern ermordet !',
    ),
    'assassinationSucceeded' => (
      Icons.dangerous,
      Colors.green,
      'Attentat erfolgreich !',
      'Deine Attentäter haben ${p['victim']} in '
          '${gc.countryNames[p['targetSlot'] as int? ?? 0]} ermordet — '
          'niemand ahnt, wer den Auftrag gab.',
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
    'realmInherited' => (
      Icons.account_balance,
      Colors.amber,
      'Erbschaft !',
      'Nach dem Tod von ${p['deceased']} fällt '
          '${((p['slots'] as List?) ?? const []).map((s) => gc.countryNames[s as int]).join(', ')} '
          'durch Erbfolge an ${p['heir']} — das Reich gehört nun '
          'deinem Haus, du führst es ab sofort mit !',
    ),
    'realmOverrun' when e.slot == slot => (
      Icons.public_off,
      Colors.red,
      'Reich verloren !',
      'Dein Reich wurde im Krieg vollständig überrannt — du hast all '
          'dein Land verloren !',
    ),
    'realmOverrun' => (
      Icons.public_off,
      Colors.red,
      'Ein Reich ist gefallen !',
      '${gc.countryNames[e.slot]} wurde im Krieg vollständig überrannt '
          'und hat sein gesamtes Land verloren !',
    ),
    'rulerCaptured' => (
      Icons.lock,
      Colors.red,
      'Herrscher gefangen !',
      '${gc.countryNames[e.slot]} nimmt den Herrscher von '
          '${gc.countryNames[p['loserSlot'] as int]}'
          '${p['ruler'] == null ? '' : ' (${p['ruler']})'} gefangen !',
    ),
    'playerKicked' => (
      Icons.person_off,
      Colors.blueGrey,
      'Spieler ersetzt',
      'Der Spieler von ${gc.countryNames[e.slot]} wurde wegen '
          'Inaktivität aus der Partie entfernt — der Computer übernimmt '
          'das Reich.',
    ),
    _ => (Icons.campaign, Colors.blueGrey, 'Nachricht', describeEvent(e)),
  };
}

Future<void> _showDramaDialog(
  BuildContext context,
  (IconData, Color, String, String) c,
) async {
  final (icon, color, title, body) = c;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: Text(body),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Weiter'),
        ),
      ],
    ),
  );
}

/// Standalone drama popups, shown after pending decisions and before the
/// recap card (which skips these events). One dialog per event, styled
/// like the marriage prompt.
Future<void> showDramaPopups(
  BuildContext context,
  GameController controller,
  int slot,
) async {
  await showDramaPopupsFor(context, controller.recapFor(slot), slot);
}

/// Shows drama popups for an explicit event list — used by the online
/// waiting screen to surface strong events (a coronation, a player losing
/// their land) as they happen, even out of the player's own turn.
Future<void> showDramaPopupsFor(
  BuildContext context,
  Iterable<gc.GameEvent> events,
  int slot,
) async {
  for (final e in events) {
    if (!context.mounted) return;
    final content = _dramaContent(e, slot);
    if (content == null) continue;
    await _showDramaDialog(context, content);
  }
}

/// The "since your last turn" recap card, shown right after the handoff.
/// Upkeep lines, other players' trivial tile actions, war details and
/// popup-worthy drama (already shown by [showDramaPopups]) are skipped;
/// big news gets styled headline rows above the plain lines.
Future<void> showRecapCard(
  BuildContext context,
  GameController controller,
  int slot,
) async {
  final recap = controller
      .recapFor(slot)
      .where(
        (e) =>
            e.type != 'turnUpkeep' &&
            !_warDetailTypes.contains(e.type) &&
            !(_trivialTypes.contains(e.type) && e.slot != slot) &&
            !_popupWorthy(e, slot),
      )
      .toList();
  controller.markRecapSeen(slot);
  if (recap.isEmpty) return;
  // Chronological top-down (oldest first), keeping the newest N when the
  // recap overflows — "A erklärt Krieg → A gewinnt" must read downward.
  List<gc.GameEvent> newest(Iterable<gc.GameEvent> events, int n) {
    final list = events.toList();
    return list.length <= n ? list : list.sublist(list.length - n);
  }

  final headlines = newest(recap.where((e) => _isHeadline(e, slot)), 10);
  final rest = newest(recap.where((e) => !_isHeadline(e, slot)), 30);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('eventFeed')),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in headlines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _eventStyle(e).$1,
                      color: _eventStyle(e).$2 ?? Colors.blueGrey,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${e.year}: ${describeEvent(e)}',
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (headlines.isNotEmpty && rest.isNotEmpty)
              const Divider(height: 16),
            for (final e in rest)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('${e.year}: ${describeEvent(e)}'),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
