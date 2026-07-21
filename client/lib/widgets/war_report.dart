import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/labels.dart';
import '../l10n/strings.dart' show tr;

/// One rendered line of the war report popup.
class _ReportEntry {
  _ReportEntry(this.icon, this.color, this.title, this.body);

  final IconData icon;
  final Color color;
  final String title;
  final String body;
}

/// Event types the report popup covers; everything else stays in the feed.
const _reportTypes = {
  'battle',
  'plunder',
  'rulerCaptured',
  'capitalHeld',
  'tileConquered',
  'warWon',
  'warDraw',
  'winterEndsWar',
  'claimPaidOut',
  'realmOverrun',
  'peaceWish',
  'peaceAgreed',
  'forcedMarriage',
  'forcedAbdication',
  'dynastyConverted',
  'execution',
  'kurfuerstStripped',
  'enemyMoved',
  'enemyHolds',
};

/// Shows battle/plunder/war-end results as a popup (like the marriage
/// dialog) instead of burying them in the event feed. [viewerSlot] is the
/// human war side — losses are phrased from their perspective. No-op when
/// [events] contains nothing report-worthy. [title] defaults to the
/// localized "Kriegsbericht"/"War report".
Future<void> showWarReport(
  BuildContext context,
  List<gc.GameEvent> events, {
  required int viewerSlot,
  String? title,
}) async {
  final entries = <_ReportEntry>[];
  var conquered = 0;
  int? conqueredBy;

  for (final event in events) {
    if (!_reportTypes.contains(event.type)) continue;
    // Tile conquests come in bursts (decisive victory, settlement) —
    // aggregated into one line below.
    if (event.type == 'tileConquered') {
      conquered++;
      conqueredBy = event.slot;
      continue;
    }
    final entry = _entryFor(event, viewerSlot);
    if (entry != null) entries.add(entry);
    // War-ending events carry the cumulative tally — render it as its own
    // "Kriegsbilanz" block right after the ending line.
    final summary = (event.payload['summary'] as Map?)?.cast<String, dynamic>();
    if (summary != null) entries.add(_warSummaryEntry(summary, viewerSlot));
  }

  // More than one battle in this report: lead with the round's totals so
  // the player sees both sides' losses at a glance.
  var ownLosses = 0, enemyLosses = 0, battles = 0;
  for (final event in events) {
    if (event.type != 'battle') continue;
    final p = event.payload;
    final attackerLosses = p['attackerLosses'] as int? ?? 0;
    final defenderLosses = p['defenderLosses'] as int? ?? 0;
    if (event.slot == viewerSlot) {
      ownLosses += attackerLosses;
      enemyLosses += defenderLosses;
    } else if (p['defenderSlot'] == viewerSlot) {
      ownLosses += defenderLosses;
      enemyLosses += attackerLosses;
    } else {
      continue;
    }
    battles++;
  }
  if (battles > 1) {
    entries.insert(
      0,
      _ReportEntry(
        Icons.functions,
        ownLosses > enemyLosses ? Colors.red : Colors.green,
        tr('war.totalLossesTitle'),
        tr('war.totalLossesBody', {
          'own': ownLosses,
          'enemy': enemyLosses,
          'battles': battles,
        }),
      ),
    );
  }
  if (conquered > 0 && conqueredBy != null) {
    final mine = conqueredBy == viewerSlot;
    entries.add(
      _ReportEntry(
        Icons.flag,
        mine ? Colors.green : Colors.red,
        tr('war.conquestTitle'),
        conquered == 1
            ? tr('war.conquestOne', {'realm': realmName(conqueredBy)})
            : tr('war.conquestMany', {
                'realm': realmName(conqueredBy),
                'count': conquered,
              }),
      ),
    );
  }
  if (entries.isEmpty) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.military_tech),
          const SizedBox(width: 8),
          Expanded(child: Text(title ?? tr('war.reportTitle'))),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: entries.length,
          separatorBuilder: (_, _) => const Divider(height: 12),
          itemBuilder: (context, i) {
            final e = entries[i];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(e.icon, color: e.color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(e.body),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('war.continueLabel')),
        ),
      ],
    ),
  );
}

/// The end-of-war overview: rounds, battles, and per side the men lost,
/// plunder loot and tiles conquered over the WHOLE war (cumulative tally
/// from `ActiveWar.summary()`).
_ReportEntry _warSummaryEntry(Map<String, dynamic> s, int viewerSlot) {
  String side(int? slot) {
    if (slot == null || slot < 1 || slot >= gc.countryNames.length) return '?';
    return slot == viewerSlot
        ? tr('war.sideYou', {'realm': realmName(slot)})
        : realmName(slot);
  }

  String tally(String prefix, int menLost, int loot, int tiles, int won) {
    final parts = [
      tr('war.tallyMenLost', {'n': menLost}),
      // Won battles feed the war score since 2026-07-19 — worth showing.
      if (won > 0)
        tr(won == 1 ? 'war.tallyBattleWonOne' : 'war.tallyBattlesWon', {
          'n': won,
        }),
      if (loot > 0) tr('war.tallyLoot', {'n': loot}),
      if (tiles > 0)
        tr(tiles == 1 ? 'war.tallyTileOne' : 'war.tallyTilesMany', {
          'n': tiles,
        }),
    ];
    return tr('war.tallyLine', {'side': prefix, 'parts': parts.join(', ')});
  }

  final lines = [
    tr('war.summaryRounds', {
      'rounds': s['rounds'] ?? '?',
      'battles': s['battles'] ?? 0,
    }),
    tally(
      side(s['attackerSlot'] as int?),
      s['attackerMenLost'] as int? ?? 0,
      s['attackerLoot'] as int? ?? 0,
      s['attackerTilesTaken'] as int? ?? 0,
      s['attackerBattlesWon'] as int? ?? 0,
    ),
    tally(
      side(s['defenderSlot'] as int?),
      s['defenderMenLost'] as int? ?? 0,
      s['defenderLoot'] as int? ?? 0,
      s['defenderTilesTaken'] as int? ?? 0,
      s['defenderBattlesWon'] as int? ?? 0,
    ),
  ];
  return _ReportEntry(
    Icons.summarize,
    Colors.blueGrey,
    tr('war.summaryTitle'),
    lines.join('\n'),
  );
}

_ReportEntry? _entryFor(gc.GameEvent event, int viewerSlot) {
  final p = event.payload;
  final realm = realmName(event.slot);

  switch (event.type) {
    case 'battle':
      final attacker = realm;
      final defenderSlot = p['defenderSlot'] as int?;
      final defender = defenderSlot == null
          ? tr('war.theEnemy')
          : realmName(defenderSlot);
      final attackerDestroyed = p['attackerDestroyed'] == true;
      final defenderDestroyed = p['defenderDestroyed'] == true;
      // Every clash is decided by strength (`attackerWon`); the destroyed
      // flags only say whether the loser was wiped out or retreated intact.
      // Deriving the winner from the flags alone mislabels a battle whose
      // loser survives (both flags false) — read the explicit result.
      final attackerWon = p['attackerWon'] == true;
      final lines = [
        tr(attackerDestroyed ? 'war.battleLossDestroyed' : 'war.battleLoss', {
          'realm': attacker,
          'unit': p['attackerUnit'],
          'losses': p['attackerLosses'],
        }),
        tr(defenderDestroyed ? 'war.battleLossDestroyed' : 'war.battleLoss', {
          'realm': defender,
          'unit': p['defenderUnit'],
          'losses': p['defenderLosses'],
        }),
        if (defenderDestroyed)
          tr('war.attackSucceeded')
        else if (attackerDestroyed)
          tr('war.attackRepelled')
        else if (attackerWon)
          tr('war.attackPrevailed')
        else
          tr('war.defenderPrevailed'),
      ];
      final won =
          event.slot == viewerSlot ? attackerWon : !attackerWon;
      return _ReportEntry(
        Icons.gavel,
        won ? Colors.green : Colors.red,
        tr('war.battleAt', {
          'x': (p['x'] as int) + 1,
          'y': (p['y'] as int) + 1,
        }),
        lines.join('\n'),
      );

    case 'plunder':
      final building = p['building'] as int? ?? 0;
      final name = buildingName(building, empty: tr('war.bareTile'));
      final victim = realmName(p['victim'] as int? ?? 0);
      final details = <String>[
        if (p['destroyed'] == true)
          tr('war.plunderDevastated',
              {'years': p['recoversIn'] ?? gc.fieldDevastationYears}),
        if ((p['loot'] as int? ?? 0) > 0)
          tr('war.plunderLoot', {'loot': p['loot']}),
        if ((p['killed'] as int? ?? 0) > 0)
          tr('war.plunderKilled', {'count': p['killed']}),
      ];
      return _ReportEntry(
        Icons.local_fire_department,
        event.slot == viewerSlot ? Colors.orange : Colors.red,
        tr('war.plunderEntryTitle', {'building': name, 'victim': victim}),
        details.isEmpty
            ? tr('war.plunderAt', {
                'realm': realm,
                'x': (p['x'] as int) + 1,
                'y': (p['y'] as int) + 1,
              })
            : details.join('\n'),
      );

    case 'rulerCaptured':
      final loser = realmName(p['loserSlot'] as int? ?? 0);
      return _ReportEntry(
        Icons.lock,
        event.slot == viewerSlot ? Colors.green : Colors.red,
        tr('war.rulerCapturedTitle'),
        tr('war.rulerCapturedBody', {
          'realm': realm,
          'ruler': p['ruler'] ?? tr('war.theRuler'),
          'loser': loser,
        }),
      );

    case 'capitalHeld':
      final besieged = realmName(p['loserSlot'] as int? ?? 0);
      final mine = event.slot == viewerSlot;
      return _ReportEntry(
        Icons.flag,
        mine ? Colors.green : Colors.red,
        mine ? tr('war.capitalSeizedTitle') : tr('war.capitalLostTitle'),
        mine
            ? tr('war.capitalSeizedBody', {'besieged': besieged})
            : tr('war.capitalLostBody', {'realm': realm}),
      );

    case 'warWon':
      final loser = realmName(p['loserSlot'] as int? ?? 0);
      return _ReportEntry(
        Icons.emoji_events,
        event.slot == viewerSlot ? Colors.green : Colors.red,
        tr('war.warEndTitle'),
        p['conquered'] == true
            ? tr('war.warWonConquered', {'realm': realm, 'loser': loser})
            : tr('war.warWonClaim', {
                'realm': realm,
                'loser': loser,
                'claim': p['claim'],
              }),
      );

    case 'warDraw':
      return _ReportEntry(
        Icons.handshake,
        Colors.blueGrey,
        tr('war.peaceTitle'),
        tr('war.warDrawBody'),
      );

    case 'peaceAgreed':
      return _ReportEntry(
        Icons.handshake,
        Colors.green,
        tr('war.peaceAgreedTitle'),
        tr('war.peaceAgreedBody'),
      );

    case 'winterEndsWar':
      // The original's wording: "Der Krieg mußte wegen des
      // hereinbrechenden Winters beendet werden."
      return _ReportEntry(
        Icons.ac_unit,
        Colors.blueGrey,
        tr('war.winterTitle'),
        tr('war.winterBody'),
      );

    case 'claimPaidOut':
      final from = realmName(p['from'] as int? ?? 0);
      return _ReportEntry(
        Icons.toll,
        event.slot == viewerSlot ? Colors.green : Colors.red,
        tr('war.claimPaidTitle'),
        tr('war.claimPaidBody', {
          'realm': realm,
          'amount': p['amount'],
          'from': from,
        }),
      );

    case 'realmOverrun':
      // event.slot is the realm that lost its last tile.
      final mine = event.slot == viewerSlot;
      return _ReportEntry(
        Icons.public_off,
        mine ? Colors.red : Colors.green,
        mine ? tr('war.allLostTitle') : tr('war.totalConquestTitle'),
        mine
            ? tr('war.allLostBody')
            : tr('war.realmOverrunBody', {'realm': realm}),
      );

    case 'peaceWish':
      // Only the opponent's wish is news to the viewer.
      if (event.slot == viewerSlot) return null;
      return _ReportEntry(
        Icons.handshake,
        Colors.blueGrey,
        tr('war.peaceWishTitle'),
        tr('war.peaceWishBody', {'realm': realm}),
      );

    case 'enemyMoved':
      return _ReportEntry(
        Icons.directions_walk,
        Colors.blueGrey,
        tr('war.enemyMovedTitle'),
        tr('war.enemyMovedBody', {
          'unit': p['unit'],
          'fromX': (p['fromX'] as int) + 1,
          'fromY': (p['fromY'] as int) + 1,
          'x': (p['x'] as int) + 1,
          'y': (p['y'] as int) + 1,
        }),
      );

    case 'enemyHolds':
      return _ReportEntry(
        Icons.shield,
        Colors.blueGrey,
        tr('war.enemyHoldsTitle'),
        tr('war.enemyHoldsBody', {'realm': realm}),
      );

    case 'forcedMarriage':
      return _ReportEntry(
        Icons.favorite,
        Colors.purple,
        tr('war.forcedMarriageTitle'),
        tr('war.forcedMarriageBody', {
          'victor': p['victor'],
          'spouse': p['spouse'],
        }),
      );

    case 'forcedAbdication':
      return _ReportEntry(
        Icons.cancel,
        Colors.red,
        tr('war.abdicationTitle'),
        tr('war.abdicationBody', {'name': p['name']}),
      );

    case 'dynastyConverted':
      return _ReportEntry(
        Icons.church,
        Colors.purple,
        tr('war.conversionTitle'),
        tr('war.conversionBody', {'realm': realm}),
      );

    case 'execution':
      return _ReportEntry(
        Icons.dangerous,
        Colors.red,
        tr('war.executionTitle'),
        tr('war.executionBody', {'name': p['name']}),
      );

    case 'kurfuerstStripped':
      return _ReportEntry(
        Icons.remove_circle,
        Colors.red,
        tr('war.electorStrippedTitle'),
        tr('war.electorStrippedBody', {'name': p['name']}),
      );
  }
  return null;
}
