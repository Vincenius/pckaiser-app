import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

const _buildingNames = [
  'Feld',
  'Kornfeld',
  'Weide',
  'Dorf',
  'Markt',
  'Stadt',
  'Burg',
  'Palast',
  'Hafen',
];

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
/// [events] contains nothing report-worthy.
Future<void> showWarReport(
  BuildContext context,
  List<gc.GameEvent> events, {
  required int viewerSlot,
  String title = 'Kriegsbericht',
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
        'Verluste gesamt',
        'Du: −$ownLosses Mann · Gegner: −$enemyLosses Mann '
            '($battles Schlachten).',
      ),
    );
  }
  if (conquered > 0 && conqueredBy != null) {
    final mine = conqueredBy == viewerSlot;
    entries.add(
      _ReportEntry(
        Icons.flag,
        mine ? Colors.green : Colors.red,
        'Eroberung',
        conquered == 1
            ? '${gc.countryNames[conqueredBy]} übernimmt 1 Feld.'
            : '${gc.countryNames[conqueredBy]} übernimmt $conquered Felder.',
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
          Expanded(child: Text(title)),
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
          child: const Text('Weiter'),
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
        ? '${gc.countryNames[slot]} (du)'
        : gc.countryNames[slot];
  }

  String tally(String prefix, int menLost, int loot, int tiles) {
    final parts = [
      '−$menLost Mann',
      if (loot > 0) '$loot T erbeutet',
      if (tiles > 0) '$tiles ${tiles == 1 ? 'Feld' : 'Felder'} erobert',
    ];
    return '$prefix: ${parts.join(', ')}.';
  }

  final lines = [
    '${s['rounds'] ?? '?'} Runden, ${s['battles'] ?? 0} Schlachten.',
    tally(
      side(s['attackerSlot'] as int?),
      s['attackerMenLost'] as int? ?? 0,
      s['attackerLoot'] as int? ?? 0,
      s['attackerTilesTaken'] as int? ?? 0,
    ),
    tally(
      side(s['defenderSlot'] as int?),
      s['defenderMenLost'] as int? ?? 0,
      s['defenderLoot'] as int? ?? 0,
      s['defenderTilesTaken'] as int? ?? 0,
    ),
  ];
  return _ReportEntry(
    Icons.summarize,
    Colors.blueGrey,
    'Kriegsbilanz',
    lines.join('\n'),
  );
}

_ReportEntry? _entryFor(gc.GameEvent event, int viewerSlot) {
  final p = event.payload;
  final realm = gc.countryNames[event.slot];

  switch (event.type) {
    case 'battle':
      final attacker = realm;
      final defenderSlot = p['defenderSlot'] as int?;
      final defender = defenderSlot == null
          ? 'der Feind'
          : gc.countryNames[defenderSlot];
      final attackerDestroyed = p['attackerDestroyed'] == true;
      final defenderDestroyed = p['defenderDestroyed'] == true;
      final lines = [
        '$attacker: „${p['attackerUnit']}" verliert '
            '${p['attackerLosses']} Mann'
            '${attackerDestroyed ? ' — vernichtet !' : '.'}',
        '$defender: „${p['defenderUnit']}" verliert '
            '${p['defenderLosses']} Mann'
            '${defenderDestroyed ? ' — vernichtet !' : '.'}',
        if (attackerDestroyed)
          'Der Angriff wurde abgeschlagen.'
        else if (defenderDestroyed)
          'Der Angriff war erfolgreich.'
        else
          'Die Verteidiger halten das Feld.',
      ];
      final won = event.slot == viewerSlot
          ? defenderDestroyed && !attackerDestroyed
          : attackerDestroyed && !defenderDestroyed;
      return _ReportEntry(
        Icons.gavel,
        won ? Colors.green : Colors.red,
        'Schlacht bei (${(p['x'] as int) + 1}, ${(p['y'] as int) + 1})',
        lines.join('\n'),
      );

    case 'plunder':
      final building = p['building'] as int? ?? 0;
      final name = building < _buildingNames.length
          ? _buildingNames[building]
          : 'Feld';
      final victim = gc.countryNames[p['victim'] as int? ?? 0];
      final details = <String>[
        if (p['destroyed'] == true) 'Das Land liegt verwüstet und brach.',
        if ((p['loot'] as int? ?? 0) > 0) '${p['loot']} Taler erbeutet.',
        if ((p['killed'] as int? ?? 0) > 0) '${p['killed']} Einwohner getötet.',
      ];
      return _ReportEntry(
        Icons.local_fire_department,
        event.slot == viewerSlot ? Colors.orange : Colors.red,
        'Plünderung: $name von $victim',
        details.isEmpty
            ? '$realm plündert bei (${(p['x'] as int) + 1}, '
                  '${(p['y'] as int) + 1}).'
            : details.join('\n'),
      );

    case 'rulerCaptured':
      final loser = gc.countryNames[p['loserSlot'] as int? ?? 0];
      return _ReportEntry(
        Icons.lock,
        event.slot == viewerSlot ? Colors.green : Colors.red,
        'Herrscher gefangen !',
        '$realm nimmt ${p['ruler'] ?? 'den Herrscher'} von $loser gefangen '
            '— der Krieg ist entschieden.',
      );

    case 'capitalHeld':
      final besieged = gc.countryNames[p['loserSlot'] as int? ?? 0];
      final mine = event.slot == viewerSlot;
      return _ReportEntry(
        Icons.flag,
        mine ? Colors.green : Colors.red,
        mine ? 'Königssitz besetzt !' : 'Dein Königssitz ist besetzt !',
        mine
            ? 'Deine Armee hält den Königssitz von $besieged — übersteht '
                  'sie dort die nächste Runde, ist der Krieg gewonnen. '
                  'Besetzen deine Armeen dabei ALLE Orte des Feindes '
                  '(jedes Dorf, jeden Markt, jede Stadt, Burg, jeden '
                  'Palast und Hafen), fällt das ganze Land an dich — '
                  'sonst stellst du Ansprüche nach Punkten.'
            : '$realm hält deinen Königssitz ! Erobere das Feld in der '
                  'nächsten Runde zurück — sonst ist der Krieg verloren. '
                  'Sind dabei ALLE deine Orte besetzt, fällt dein ganzes '
                  'Land an den Feind !',
      );

    case 'warWon':
      final loser = gc.countryNames[p['loserSlot'] as int? ?? 0];
      return _ReportEntry(
        Icons.emoji_events,
        event.slot == viewerSlot ? Colors.green : Colors.red,
        'Kriegsende',
        p['conquered'] == true
            ? '$realm gewinnt den Krieg und übernimmt das gesamte '
                  'Reich von $loser !'
            : '$realm gewinnt den Krieg gegen $loser '
                  '(Anspruch: ${p['claim']} Punkte).',
      );

    case 'warDraw':
      return _ReportEntry(
        Icons.handshake,
        Colors.blueGrey,
        'Frieden',
        'Der Krieg endet unentschieden — alle Truppen kehren heim.',
      );

    case 'peaceAgreed':
      return _ReportEntry(
        Icons.handshake,
        Colors.green,
        'Frieden geschlossen',
        'Beide Seiten beenden den Krieg. Alle Truppen kehren heim — '
            'das Land bleibt unverändert.',
      );

    case 'winterEndsWar':
      // The original's wording: "Der Krieg mußte wegen des
      // hereinbrechenden Winters beendet werden."
      return _ReportEntry(
        Icons.ac_unit,
        Colors.blueGrey,
        'Winter',
        'Der Krieg musste wegen des hereinbrechenden Winters beendet '
            'werden.',
      );

    case 'claimPaidOut':
      final from = gc.countryNames[p['from'] as int? ?? 0];
      return _ReportEntry(
        Icons.toll,
        event.slot == viewerSlot ? Colors.green : Colors.red,
        'Kriegsentschädigung',
        '$realm erhält ${p['amount']} Taler von $from.',
      );

    case 'realmOverrun':
      // event.slot is the realm that lost its last tile.
      final mine = event.slot == viewerSlot;
      return _ReportEntry(
        Icons.public_off,
        mine ? Colors.red : Colors.green,
        mine ? 'Alles verloren !' : 'Totale Eroberung !',
        mine
            ? 'Du hast dein gesamtes Land verloren — dir bleibt kein '
                  'einziges Feld mehr.'
            : '$realm hat sein gesamtes Land verloren — das Reich ist '
                  'von der Karte getilgt.',
      );

    case 'peaceWish':
      // Only the opponent's wish is news to the viewer.
      if (event.slot == viewerSlot) return null;
      return _ReportEntry(
        Icons.handshake,
        Colors.blueGrey,
        'Friedenswunsch',
        '$realm wünscht Frieden.',
      );

    case 'enemyMoved':
      return _ReportEntry(
        Icons.directions_walk,
        Colors.blueGrey,
        'Feindbewegung',
        '„${p['unit']}" rückt von (${(p['fromX'] as int) + 1}, '
            '${(p['fromY'] as int) + 1}) nach (${(p['x'] as int) + 1}, '
            '${(p['y'] as int) + 1}) vor.',
      );

    case 'enemyHolds':
      return _ReportEntry(
        Icons.shield,
        Colors.blueGrey,
        'Feindlage',
        '$realm hält seine Stellungen — keine Bewegung.',
      );

    case 'forcedMarriage':
      return _ReportEntry(
        Icons.favorite,
        Colors.purple,
        'Zwangsheirat',
        '${p['victor']} heiratet ${p['spouse']}.',
      );

    case 'forcedAbdication':
      return _ReportEntry(
        Icons.cancel,
        Colors.red,
        'Abdankung',
        '${p['name']} muss die Kaiserwürde niederlegen.',
      );

    case 'dynastyConverted':
      return _ReportEntry(
        Icons.church,
        Colors.purple,
        'Bekehrung',
        'Die Dynastie von $realm wechselt den Glauben.',
      );

    case 'execution':
      return _ReportEntry(
        Icons.dangerous,
        Colors.red,
        'Hinrichtung',
        '${p['name']} wird hingerichtet.',
      );

    case 'kurfuerstStripped':
      return _ReportEntry(
        Icons.remove_circle,
        Colors.red,
        'Kurwürde verloren',
        '${p['name']} verliert die Kurwürde.',
      );
  }
  return null;
}
