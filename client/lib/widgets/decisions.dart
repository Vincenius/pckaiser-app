import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../state/game_controller.dart';
import 'event_feed.dart';
import 'turn_report.dart';
import 'war_report.dart';

/// After the handoff: the §21.1 turn-start status report first ("Sie
/// sind am Zug!" — income, popularity, buildable fields), then every
/// pending decision addressed to [slot] (marriage consent, baby names,
/// …), then the standalone drama popups (assassinations, coronation),
/// then the recap card — the summary reads better once the player has
/// acted.
///
/// During a war the player is a combatant in, that whole sequence is
/// replaced by a single war report of the opponent's actions since this
/// side last acted (battles, plunders, the round's outcome): the routine
/// status/popularity popup and the recap card are noise mid-war, and
/// showing them every round was the reported online-war annoyance. The
/// recap baseline already advances per war round (server + controller), so
/// the report holds only the latest round, never the whole war.
Future<void> showRecapAndDecisions(
  BuildContext context,
  GameController controller,
  int slot,
) async {
  final war = controller.state.activeWar;
  final inWar = war != null &&
      war.phase == gc.WarPhase.rounds &&
      (war.attackerSlot == slot || war.defenderSlot == slot);
  if (inWar) {
    await showWarReport(
      context,
      controller.recapFor(slot),
      viewerSlot: slot,
      title: 'Rundenbericht',
    );
    if (!context.mounted) return;
    // A round may have resolved a ruler capture: surface its coercion
    // choices now rather than deferring them to a non-war turn.
    await promptDecisionsFor(context, controller, slot);
    return;
  }
  await showTurnReport(context, controller, slot);
  if (!context.mounted) return;
  await promptDecisionsFor(context, controller, slot);
  if (!context.mounted) return;
  await showDramaPopups(context, controller, slot);
  if (!context.mounted) return;
  await showRecapCard(context, controller, slot);
}

/// Prompts every pending decision addressed to [slot], in order. Used at
/// turn start — and right after a war resolution, so a victor's coercion
/// options (forced abdication, Kurfürst seat strip, …) appear immediately
/// instead of waiting for the next turn.
Future<void> promptDecisionsFor(
  BuildContext context,
  GameController controller,
  int slot,
) async {
  while (true) {
    if (!context.mounted) return;
    final decisions = controller.state.pendingDecisions
        .where((d) => d.decidingSlot == slot)
        .toList();
    if (decisions.isEmpty) return;
    await _promptDecision(context, controller, decisions.first);
  }
}

Future<void> _promptDecision(
  BuildContext context,
  GameController controller,
  gc.PendingDecision decision,
) async {
  final state = controller.state;
  final p = decision.payload;

  switch (decision.type) {
    case 'marriageConsent':
      final proposer = state.persons[p['proposerId'] as int];
      final target = state.persons[p['targetId'] as int];
      final accept = await _yesNo(
        context,
        'Heiratsantrag',
        '${proposer?.name ?? '?'} hält um die Hand von '
            '${target?.name ?? '?'} an. Einverstanden?',
      );
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'accept': accept,
      });

    case 'heirChoice':
      final candidates = (p['candidateIds'] as List)
          .cast<int>()
          .where((id) => state.persons[id] != null)
          .toList();
      if (candidates.isEmpty) {
        // Everyone died in the meantime (disease): keep the provisional
        // heir instead of showing an undismissable empty dialog.
        await controller.resolveDecision(decision.id, decision.decidingSlot, {
          'heirId': p['provisionalHeirId'],
        });
        return;
      }
      final heir = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (context) => SimpleDialog(
          title: Text('Erbe von ${p['deceasedName']}'),
          children: [
            for (final id in candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, id),
                child: Text(
                  '${state.persons[id]!.name} (${state.persons[id]!.age})',
                ),
              ),
          ],
        ),
      );
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'heirId': heir ?? p['provisionalHeirId'],
      });

    case 'childName':
      final child = state.persons[p['childId'] as int];
      final isBoy = child == null || child.isMale;
      final name = await _askText(
        context,
        'Ein ${isBoy ? 'Junge' : 'Mädchen'} ist geboren ! '
        'Wie soll ${isBoy ? 'er' : 'sie'} heißen?',
        p['suggestedName'] as String? ?? '',
      );
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'name': name,
      });

    case 'electorVote':
      final finalists = (p['finalistIds'] as List).cast<int>();
      final bribes = (p['bribes'] as Map?)?.cast<String, dynamic>() ?? {};
      final vote = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (context) => SimpleDialog(
          title: const Text('Kaiserwahl — deine Stimme'),
          children: [
            for (final id in finalists)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, id),
                child: Text(
                  '${state.persons[id]?.name ?? '?'} '
                  '(Bestechung: ${bribes['$id'] ?? 0} T)',
                ),
              ),
          ],
        ),
      );
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'finalistId': vote ?? finalists.first,
      });

    case 'electionBribe':
      final electors = (p['electorIds'] as List).cast<int>();
      final gifts = <Map<String, dynamic>>[];
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _BribeDialog(
            controller: controller,
            slot: decision.decidingSlot,
            electorIds: electors,
            onSubmit: gifts.addAll,
          ),
        );
      }
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'gifts': gifts,
      });

    case 'coercion':
      final captured = state.persons[p['capturedRulerId'] as int];
      final demand = switch (p['option']) {
        'convertOrDie' => 'vor die Wahl stellen: Bekehrung oder Tod',
        'forcedMarriage' => 'zur Heirat zwingen',
        'abdication' => 'als Kaiser abdanken lassen',
        'stripSeat' => 'den Kurfürstensitz aberkennen',
        _ => 'zwingen (${p['option']})',
      };
      final apply = await _yesNo(
        context,
        'Zwang',
        'Willst du ${captured?.name ?? '?'} $demand?',
      );
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'apply': apply,
      });

    case 'convertOrDie':
      final accept = await _yesNo(
        context,
        'Bekehrung oder Tod',
        'Sterben oder sich bekehren — bekehrst du dich?',
      );
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'accept': accept,
      });

    case 'relocateCapital':
      // The seat was lost (war, earthquake, bankruptcy) — the player must
      // pick a new one. Free, and not dismissible: leaving the realm
      // seatless is not an option.
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
          if (map.ownerAt(x, y) == decision.decidingSlot &&
              buildingNames.containsKey(building)) {
            candidates.add((x, y, building));
          }
        }
      }
      if (candidates.isEmpty) {
        // No eligible tile left — nothing to choose; clear the prompt.
        await controller.resolveDecision(
            decision.id, decision.decidingSlot, const {});
        return;
      }
      final pick = await showDialog<(int, int)>(
        context: context,
        barrierDismissible: false,
        builder: (context) => SimpleDialog(
          title: const Text('Dein Sitz ist verloren — wähle einen neuen'),
          children: [
            for (final (x, y, building) in candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, (x, y)),
                child: Text(
                  '${buildingNames[building]} (${x + 1}, ${y + 1})',
                ),
              ),
          ],
        ),
      );
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        if (pick != null) 'x': pick.$1,
        if (pick != null) 'y': pick.$2,
      });

    default:
      // Unknown decision type: resolve with the empty choice (the rules
      // fall back to defaults) rather than soft-locking the game.
      await controller.resolveDecision(
        decision.id,
        decision.decidingSlot,
        const {},
      );
  }
}

Future<bool> _yesNo(BuildContext context, String title, String message) async {
  final answer = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Nein'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Ja'),
        ),
      ],
    ),
  );
  return answer ?? false;
}

Future<String> _askText(
  BuildContext context,
  String title,
  String initial,
) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return result ?? initial;
}

/// Bribery dialog of a human Kaiser/Sultan finalist (§17.3): one slider
/// amount per elector, bounded by the treasury.
class _BribeDialog extends StatefulWidget {
  const _BribeDialog({
    required this.controller,
    required this.slot,
    required this.electorIds,
    required this.onSubmit,
  });

  final GameController controller;

  /// The deciding finalist's slot — whose treasury pays the bribes.
  final int slot;
  final List<int> electorIds;
  final void Function(List<Map<String, dynamic>>) onSubmit;

  @override
  State<_BribeDialog> createState() => _BribeDialogState();
}

class _BribeDialogState extends State<_BribeDialog> {
  late final Map<int, int> _amounts = {
    for (final id in widget.electorIds) id: 0,
  };

  @override
  Widget build(BuildContext context) {
    final treasury = widget.controller.state.realm(widget.slot).treasury;
    // You can only ever spend what you actually have — a treasury in the red
    // (e.g. after a lost war's reparations) affords no bribe, but the dialog
    // must stay confirmable (with zero) so the election can proceed instead
    // of soft-locking the finalist with a permanently disabled button.
    final affordable = treasury > 0 ? treasury : 0;
    final spent = _amounts.values.fold(0, (a, b) => a + b);
    final broke = affordable <= 0;
    return AlertDialog(
      title: Text('Bestechung ($spent / $treasury T)'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (broke)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Deine Schatzkammer ist leer — du kannst diesmal niemanden '
                  'bestechen. Bestätige ohne Geschenk.',
                ),
              ),
            for (final id in widget.electorIds)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.controller.state.persons[id]?.name ?? '?',
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: Slider(
                      value: _amounts[id]!.clamp(0, affordable).toDouble(),
                      max: broke ? 1 : affordable.toDouble(),
                      onChanged: broke
                          ? null
                          : (v) => setState(() => _amounts[id] = v.round()),
                    ),
                  ),
                  SizedBox(width: 56, child: Text('${_amounts[id]} T')),
                ],
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: spent > affordable
              ? null
              : () {
                  widget.onSubmit([
                    for (final e in _amounts.entries)
                      if (e.value > 0) {'electorId': e.key, 'amount': e.value},
                  ]);
                  Navigator.pop(context);
                },
          child: Text(broke ? 'Ohne Bestechung' : 'Fertig'),
        ),
      ],
    );
  }
}
