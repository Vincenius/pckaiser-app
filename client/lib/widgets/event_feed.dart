import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/labels.dart';
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
  'seatLost',
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
/// Death causes stored in `personDied` payloads: the code 'age' or a
/// disease name from the engine's fixed list — mapped at render time so
/// the stored (language-neutral / German) value localizes both ways.
String _deathCause(String cause) => switch (cause) {
  'age' => appLocale.value == 'de' ? 'Altersschwäche' : 'old age',
  _ => _diseaseName(cause),
};

/// The engine's four §18 disease names are stored in event payloads;
/// English forms are mapped here at render time.
String _diseaseName(String name) => appLocale.value == 'de'
    ? name
    : switch (name) {
        'Pest' => 'Plague',
        'Cholera' => 'Cholera',
        'Typhus' => 'Typhus',
        'Ruhr' => 'Dysentery',
        _ => name,
      };

String describeEvent(gc.GameEvent e) {
  final p = e.payload;
  final realm = e.slot >= 1 && e.slot <= 30 ? realmName(e.slot) : worldLabel();
  return switch (e.type) {
    'turnUpkeep' => tr('ev.turnUpkeep', {
      'realm': realm,
      'tax': p['tax'],
      'grainYield': p['grainYield'],
      'livestockYield': p['livestockYield'],
      'wages': p['wages'],
    }),
    'tileClaimed' => tr('ev.tileClaimed', {
      'realm': realm,
      'x': p['x'],
      'y': p['y'],
    }),
    'shipBought' => tr('ev.shipBought', {
      'realm': realm,
      'x': p['x'],
      'y': p['y'],
    }),
    'shipColonized' => tr('ev.shipColonized', {
      'realm': realm,
      'x': p['x'],
      'y': p['y'],
    }),
    'buildingBuilt' => tr('ev.buildingBuilt', {
      'realm': realm,
      'x': p['x'],
      'y': p['y'],
    }),
    'townFounded' => tr('ev.townFounded', {'realm': realm, 'name': p['name']}),
    'townPromoted' => tr(
      p['building'] == gc.Building.markt
          ? 'ev.townPromotedMarket'
          : 'ev.townPromotedTown',
      {'name': p['name']},
    ),
    'townDied' => tr('ev.townDied', {'name': p['name']}),
    'goodsSold' => tr('ev.goodsSold', {
      'realm': realm,
      'amount': p['amount'],
      'proceeds': p['proceeds'],
    }),
    'shipsSent' => tr('ev.shipsSent', {
      'realm': realm,
      'invested': p['invested'],
    }),
    'shipsReturned' => tr('ev.shipsReturned', {
      'realm': realm,
      'returned': p['returned'],
      'invested': p['invested'],
    }),
    'moneySent' => tr('ev.moneySent', {
      'realm': realm,
      'amount': p['amount'],
      'target': realmName(p['targetSlot'] as int),
    }),
    'capitalRelocated' => tr('ev.capitalRelocated', {
      'realm': realm,
      'x': (p['x'] as int) + 1,
      'y': (p['y'] as int) + 1,
    }),
    'capitalReseated' => tr('ev.capitalReseated', {
      'realm': realm,
      'x': (p['x'] as int) + 1,
      'y': (p['y'] as int) + 1,
    }),
    'capitalLost' => tr('ev.capitalLost', {'realm': realm}),
    'wedding' => tr('ev.wedding', {'realm': realm, 'a': p['a'], 'b': p['b']}),
    'marriageRejected' => tr(
      p['reason'] == 'invalid'
          ? 'ev.marriageRejectedInvalid'
          : 'ev.marriageRejected',
      {'realm': realm},
    ),
    'divorce' => tr('ev.divorce', {'a': p['a'], 'b': p['b']}),
    'birth' => tr('ev.birth', {
      'realm': realm,
      'parent': p['parent'],
      'child': p['child'],
    }),
    'personDied' => tr('ev.personDied', {
      'realm': realm,
      'name': p['name'],
      'age': p['age'],
      'cause': _deathCause(p['cause'] as String? ?? '?'),
    }),
    'succession' => tr('ev.succession', {'realm': realm, 'heir': p['heir']}),
    // Old events carry only the stored (German) 'title'; newer ones also
    // the language-neutral 'titleClass' — prefer the localized lookup.
    'titlePromoted' => tr('ev.titlePromoted', {
      'realm': realm,
      'title': p['titleClass'] != null
          ? titleName(p['titleClass'] as int)
          : p['title'],
    }),
    'troopsRecruited' => tr('ev.troopsRecruited', {
      'realm': realm,
      'men': p['men'],
    }),
    'soeldnerHired' => tr('ev.soeldnerHired', {
      'realm': realm,
      'men': p['men'],
    }),
    'warDeclared' => tr('ev.warDeclared', {
      'realm': realm,
      'target': realmName(p['targetSlot'] as int),
    }),
    'battle' => tr('ev.battle', {
      'attackerUnit': p['attackerUnit'],
      'attackerLosses': p['attackerLosses'],
      'defenderUnit': p['defenderUnit'],
      'defenderLosses': p['defenderLosses'],
    }),
    'rulerCaptured' => tr('ev.rulerCaptured', {
      'realm': realm,
      'loser': realmName(p['loserSlot'] as int),
    }),
    'capitalHeld' => tr('ev.capitalHeld', {
      'realm': realm,
      'loser': realmName(p['loserSlot'] as int),
    }),
    'warWon' => tr(p['conquered'] == true ? 'ev.warWonConquered' : 'ev.warWon', {
      'realm': realm,
      'loser': realmName(p['loserSlot'] as int),
    }),
    'warDraw' => tr('ev.warDraw'),
    'peaceAgreed' => tr('ev.peaceAgreed'),
    'winterEndsWar' => tr('ev.winterEndsWar'),
    'peaceWish' => tr('ev.peaceWish', {'realm': realm}),
    'tileConquered' => tr('ev.tileConquered', {
      'realm': realm,
      'x': p['x'],
      'y': p['y'],
      'from': realmName(p['from'] as int),
    }),
    'plunder' => tr('ev.plunder', {
      'realm': realm,
      'x': p['x'],
      'y': p['y'],
      'victim': realmName(p['victim'] as int),
    }),
    'claimPaidOut' => tr('ev.claimPaidOut', {
      'realm': realm,
      'amount': p['amount'],
      'from': realmName(p['from'] as int),
    }),
    'realmOverrun' => tr('ev.realmOverrun', {'realm': realm}),
    'humansDefeated' => tr('ev.humansDefeated'),
    'playerLeft' => tr('ev.playerLeft', {'realm': realm}),
    'playerKicked' => tr('ev.playerKicked', {'realm': realm}),
    'forcedMarriage' => tr('ev.forcedMarriage', {
      'victor': p['victor'],
      'spouse': p['spouse'],
    }),
    'forcedAbdication' => tr('ev.forcedAbdication', {'name': p['name']}),
    'execution' => tr('ev.execution', {'name': p['name']}),
    'realmsMerged' => tr('ev.realmsMerged', {
      'realm': realm,
      'source': realmName(p['sourceSlot'] as int),
    }),
    'crowned' => tr('ev.crowned', {
      'realm': realm,
      'name': p['name'],
      'office': _officeName(p['office']),
    }),
    'electionStarted' => tr(
      p['office'] == 'kaiser'
          ? 'ev.electionStartedKaiser'
          : 'ev.electionStartedSultan',
    ),
    'electionTie' => tr('ev.electionTie'),
    'interregnum' => tr('ev.interregnum'),
    'tributeCollected' => tr(
      p['office'] == 'sultan'
          ? 'ev.tributeCollectedSultan'
          : 'ev.tributeCollectedKaiser',
      {'realm': realm, 'amount': p['amount']},
    ),
    'newKurfuerst' => tr('ev.newKurfuerst', {'name': p['name']}),
    'kurfuerstStripped' => tr('ev.kurfuerstStripped', {'name': p['name']}),
    'officeHolderDied' => tr('ev.officeHolderDied'),
    'assassination' => tr('ev.assassination', {
      'realm': realm,
      'victim': p['victim'],
    }),
    'assassinationSucceeded' => tr('ev.assassinationSucceeded', {
      'victim': p['victim'],
      'target': realmName(p['targetSlot'] as int? ?? 0),
    }),
    'assassinationFailed' => tr('ev.assassinationFailed', {
      'victim': p['victim'],
      'sponsor': realmName(p['sponsorSlot'] as int),
    }),
    'assassinsDispatched' => tr('ev.assassinsDispatched', {
      'realm': realm,
      'agents': p['agents'],
      'target': realmName(p['targetSlot'] as int),
    }),
    'intelGathered' => tr('ev.intelGathered', {
      'realm': realm,
      'target': realmName(p['targetSlot'] as int),
    }),
    'missionFailed' => tr(
      (p['caught'] as int? ?? 0) > 0
          ? 'ev.missionFailedCaught'
          : 'ev.missionFailed',
      {'realm': realm, 'target': realmName(p['targetSlot'] as int)},
    ),
    'religionChanged' => (p['popularityLost'] as int? ?? 0) > 0
        ? tr('ev.religionChangedPopularity', {
            'realm': realm,
            'popularityLost': p['popularityLost'],
          })
        : tr('ev.religionChanged', {'realm': realm}),
    'dynastyConverted' => tr('ev.dynastyConverted', {'realm': realm}),
    'dynastyExtinct' => tr('ev.dynastyExtinct', {'realm': realm}),
    'realmInherited' => tr('ev.realmInherited', {
      'realm': realm,
      'heir': p['heir'],
      'realms': ((p['slots'] as List?) ?? const [])
          .map((s) => realmName(s as int))
          .join(', '),
    }),
    'islamicSuccessionCrisis' => tr(
      p['human'] == true
          ? 'ev.islamicSuccessionCrisisHuman'
          : 'ev.islamicSuccessionCrisis',
      {'realm': realm, 'heir': p['heir']},
    ),
    'internalStrife' => tr(
      p['human'] == true ? 'ev.internalStrifeHuman' : 'ev.internalStrife',
      {'realm': realm, 'newRuler': p['newRuler']},
    ),
    'seatLost' => tr(p['heir'] != null ? 'ev.seatLostHeir' : 'ev.seatLost', {
      'realm': realm,
      'heir': p['heir'],
    }),
    'bankruptcy' => tr(
      p['human'] == true ? 'ev.bankruptcyHuman' : 'ev.bankruptcy',
      {'realm': realm, 'debt': p['debt']},
    ),
    'debtWarning' => tr(
      (p['turnsLeft'] as int) == 1 ? 'ev.debtWarningOne' : 'ev.debtWarning',
      {'realm': realm, 'debt': p['debt'], 'turnsLeft': p['turnsLeft']},
    ),
    'merchantFounder' => tr('ev.merchantFounder', {'name': p['name']}),
    'totalExtinction' => tr('ev.totalExtinction'),
    'earthquake' => tr('ev.earthquake'),
    'disease' => tr('ev.disease', {
      'name': _diseaseName(p['name'] as String? ?? '?'),
    }),
    'reformation' => tr('ev.reformation'),
    'ottomanInvasion' => tr('ev.ottomanInvasion'),
    'buildingDemolished' => tr('ev.buildingDemolished', {
      'realm': realm,
      'x': p['x'],
      'y': p['y'],
    }),
    'gameWon' => tr('ev.gameWon', {'realm': realm}),
    'gameDraw' => tr('ev.gameDraw'),
    _ => '$realm: ${e.type}',
  };
}

/// Localized office noun ('Kaiser'/'Sultan') inserted as `{office}` into
/// coronation templates — the noun is identical in German and English.
String _officeName(Object? office) =>
    tr(office == 'kaiser' ? 'ev.officeKaiser' : 'ev.officeSultan');

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

  // (filter value, label key) — labels are translated at build time.
  static const _filters = [
    ('relevant', 'ev.filterRelevant'),
    ('mine', 'ev.filterMine'),
    ('wars', 'ev.filterWars'),
    ('dynasty', 'ev.filterDynasty'),
    ('world', 'ev.filterWorld'),
    ('all', 'ev.filterAll'),
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
                          label: Text(tr(label)),
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
                  ? Center(child: Text(tr('ev.noEvents')))
                  : ListView(
                      children: [
                        for (final year in years) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                            child: Row(
                              children: [
                                Text(
                                  tr('ev.anno', {'year': year}),
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
  // A coronation is table-wide news: EVERY player gets the popup (the
  // reported gap: observers learned a Kaiserwahl's outcome only from the
  // dynasty screen), the winner a personal one.
  'crowned' => true,
  // Your house inherited whole realms — easy to miss as a feed line.
  'realmInherited' => e.slot == slot,
  // A human player losing their whole realm (or their ruler captured) is a
  // story-worthy event the whole table should see as a strong popup — and
  // the victim themselves above all.
  'realmOverrun' => e.payload['human'] == true,
  'rulerCaptured' => e.payload['loserHuman'] == true,
  // A human player losing CONTROL of a realm without losing the land —
  // popularity coup, foreclosure, succession crisis, inheritance to a
  // foreign house. Reported gap (2026-07-13): a player's realm silently
  // flipped to the AI and they "never got told why" — these popups are
  // that answer, for the victim above all.
  'internalStrife' => e.payload['human'] == true,
  'bankruptcy' => e.payload['human'] == true,
  'islamicSuccessionCrisis' => e.payload['human'] == true,
  'seatLost' => true, // only ever emitted for a human seat's loss
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
  'seatLost' ||
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
  'seatLost' => (Icons.account_balance, Colors.red),
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
      tr('ev.dramaAssassinationTitle'),
      tr('ev.dramaAssassinationBody', {'victim': p['victim']}),
    ),
    'assassinationSucceeded' => (
      Icons.dangerous,
      Colors.green,
      tr('ev.dramaAssassinationSucceededTitle'),
      tr('ev.dramaAssassinationSucceededBody', {
        'victim': p['victim'],
        'target': realmName(p['targetSlot'] as int? ?? 0),
      }),
    ),
    'assassinationFailed' when e.slot == slot => (
      Icons.report,
      Colors.orange,
      tr('ev.dramaAssassinationFoiledTitle'),
      (p['caught'] as int? ?? 0) > 0
          ? tr('ev.dramaAssassinationFoiledBodyCaught', {
              'victim': p['victim'],
              'sponsor': realmName(p['sponsorSlot'] as int),
            })
          : tr('ev.dramaAssassinationFoiledBody', {'victim': p['victim']}),
    ),
    'assassinationFailed' => (
      Icons.report,
      Colors.orange,
      tr('ev.dramaAssassinationFailedTitle'),
      tr(
        (p['caught'] as int? ?? 0) > 0
            ? 'ev.dramaAssassinationFailedBodyCaught'
            : 'ev.dramaAssassinationFailedBody',
        {'victim': p['victim']},
      ),
    ),
    'crowned' when e.slot == slot => (
      Icons.emoji_events,
      Colors.amber,
      tr('ev.dramaCrownedYouTitle', {'office': _officeName(p['office'])}),
      tr(
        p['acclaimed'] == true
            ? 'ev.dramaCrownedYouBodyAcclaimed'
            : 'ev.dramaCrownedYouBody',
        {'name': p['name'], 'office': _officeName(p['office'])},
      ),
    ),
    'crowned' => (
      Icons.emoji_events,
      Colors.amber,
      tr('ev.dramaCrownedOtherTitle', {'office': _officeName(p['office'])}),
      tr(
        p['acclaimed'] == true
            ? 'ev.dramaCrownedOtherBodyAcclaimed'
            : 'ev.dramaCrownedOtherBody',
        {
          'name': p['name'],
          'realm': realmName(e.slot),
          'office': _officeName(p['office']),
        },
      ),
    ),
    'realmInherited' => (
      Icons.account_balance,
      Colors.amber,
      tr('ev.dramaInheritanceTitle'),
      tr('ev.dramaInheritanceBody', {
        'deceased': p['deceased'],
        'heir': p['heir'],
        'realms': ((p['slots'] as List?) ?? const [])
            .map((s) => realmName(s as int))
            .join(', '),
      }),
    ),
    'realmOverrun' when e.slot == slot => (
      Icons.public_off,
      Colors.red,
      tr('ev.dramaRealmLostTitle'),
      tr('ev.dramaRealmOverrunYouBody'),
    ),
    'realmOverrun' => (
      Icons.public_off,
      Colors.red,
      tr('ev.dramaRealmFallenTitle'),
      tr('ev.dramaRealmOverrunOtherBody', {'realm': realmName(e.slot)}),
    ),
    'rulerCaptured' => (
      Icons.lock,
      Colors.red,
      tr('ev.dramaRulerCapturedTitle'),
      tr(
        p['ruler'] == null
            ? 'ev.dramaRulerCapturedBody'
            : 'ev.dramaRulerCapturedBodyNamed',
        {
          'realm': realmName(e.slot),
          'loser': realmName(p['loserSlot'] as int),
          'ruler': p['ruler'],
        },
      ),
    ),
    'internalStrife' when e.slot == slot => (
      Icons.local_fire_department,
      Colors.red,
      tr('ev.dramaRealmLostTitle'),
      tr('ev.dramaInternalStrifeYouBody', {
        'realm': realmName(e.slot),
        'newRuler': p['newRuler'],
      }),
    ),
    'internalStrife' => (
      Icons.local_fire_department,
      Colors.red,
      tr('ev.dramaInternalStrifeTitle'),
      tr('ev.dramaInternalStrifeOtherBody', {
        'realm': realmName(e.slot),
        'newRuler': p['newRuler'],
      }),
    ),
    'bankruptcy' when e.slot == slot => (
      Icons.money_off,
      Colors.red,
      tr('ev.dramaRealmLostTitle'),
      tr('ev.dramaBankruptcyYouBody', {
        'realm': realmName(e.slot),
        'debt': p['debt'],
      }),
    ),
    'bankruptcy' => (
      Icons.money_off,
      Colors.red,
      tr('ev.dramaBankruptcyTitle'),
      tr('ev.dramaBankruptcyOtherBody', {
        'realm': realmName(e.slot),
        'debt': p['debt'],
      }),
    ),
    'islamicSuccessionCrisis' when e.slot == slot => (
      Icons.account_balance,
      Colors.red,
      tr('ev.dramaRealmLostTitle'),
      tr('ev.dramaIslamicCrisisYouBody', {
        'realm': realmName(e.slot),
        'heir': p['heir'],
      }),
    ),
    'islamicSuccessionCrisis' => (
      Icons.account_balance,
      Colors.red,
      tr('ev.dramaIslamicCrisisTitle'),
      tr('ev.dramaIslamicCrisisOtherBody', {
        'realm': realmName(e.slot),
        'heir': p['heir'],
      }),
    ),
    'seatLost' when e.slot == slot => (
      Icons.account_balance,
      Colors.red,
      tr('ev.dramaRealmLostTitle'),
      tr(
        p['heir'] == null
            ? 'ev.dramaSeatLostYouBody'
            : 'ev.dramaSeatLostYouBodyHeir',
        {'realm': realmName(e.slot), 'heir': p['heir']},
      ),
    ),
    'seatLost' => (
      Icons.account_balance,
      Colors.red,
      tr('ev.dramaSeatLostOtherTitle'),
      tr(
        p['heir'] == null
            ? 'ev.dramaSeatLostOtherBody'
            : 'ev.dramaSeatLostOtherBodyHeir',
        {'realm': realmName(e.slot), 'heir': p['heir']},
      ),
    ),
    'playerKicked' => (
      Icons.person_off,
      Colors.blueGrey,
      tr('ev.dramaPlayerKickedTitle'),
      tr('ev.dramaPlayerKickedBody', {'realm': realmName(e.slot)}),
    ),
    _ => (
      Icons.campaign,
      Colors.blueGrey,
      tr('ev.dramaDefaultTitle'),
      describeEvent(e),
    ),
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
          child: Text(tr('ev.continue')),
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
          child: Text(tr('ev.ok')),
        ),
      ],
    ),
  );
}
