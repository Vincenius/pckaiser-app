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
                  'sie dort die nächste Runde, ist der Krieg gewonnen.'
            : '$realm hält deinen Königssitz ! Erobere das Feld in der '
                  'nächsten Runde zurück — sonst ist der Krieg verloren.',
      );

    case 'warWon':
      final loser = gc.countryNames[p['loserSlot'] as int? ?? 0];
      return _ReportEntry(
        Icons.emoji_events,
        event.slot == viewerSlot ? Colors.green : Colors.red,
        'Kriegsende',
        '$realm gewinnt den Krieg gegen $loser '
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
      return _ReportEntry(
        Icons.ac_unit,
        Colors.blueGrey,
        'Winter',
        'Der Winter bricht herein und beendet den Krieg.',
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
