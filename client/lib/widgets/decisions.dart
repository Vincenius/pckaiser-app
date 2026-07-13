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
  final inWar =
      war != null &&
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
///
/// A player can control several slots (cross-dynasty inheritance, §15.4);
/// their turns come in slot order. Decisions raised for ANY of their slots
/// surface at the player's FIRST handoff — otherwise a death at the home
/// slot would let them rule the inherited realms for whole turns before
/// hearing of it or choosing the heir.
Future<void> promptDecisionsFor(
  BuildContext context,
  GameController controller,
  int slot,
) async {
  while (true) {
    if (!context.mounted) return;
    final decisions = controller.state.pendingDecisions
        .where(
          (d) =>
              d.decidingSlot == slot ||
              _sameHumanPlayer(controller.state, d.decidingSlot, slot),
        )
        .toList();
    if (decisions.isEmpty) return;
    await _promptDecision(context, controller, decisions.first);
  }
}

bool _sameHumanPlayer(gc.GameState state, int a, int b) {
  final da = state.dynasty(a);
  final db = state.dynasty(b);
  return da.status == gc.DynastyStatus.human &&
      db.status == gc.DynastyStatus.human &&
      da.humanPlayer != null &&
      da.humanPlayer == db.humanPlayer;
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
      // Name the proposer's land and age: a marriage is the main peaceful
      // path to inheriting realms (§14), so the target must know which
      // realm they are tying their line to before accepting.
      final proposerLine = proposer == null
          ? '?'
          : '${proposer.name} von ${gc.countryNames[proposer.dynasty]} '
                '(${proposer.age})';
      final accept = await _yesNo(
        context,
        'Heiratsantrag',
        '$proposerLine hält um die Hand von '
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
          // Doubles as the death notice: this dialog is the first thing the
          // player sees after the loss, possibly while seated at another of
          // their slots.
          title: Text('${p['deceasedName']} ist gestorben ! Wähle den Erben:'),
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

    case 'warPlan':
      final war = state.activeWar;
      if (war == null ||
          war.phase != gc.WarPhase.preparation ||
          !war.isParticipant(decision.decidingSlot)) {
        // The war is gone (or already running) — clear the stale choice.
        await controller.resolveDecision(
          decision.id,
          decision.decidingSlot,
          const {},
        );
        return;
      }
      final attackerRole = p['role'] == 'attacker';
      final opponent =
          gc.countryNames[(attackerRole ? p['defenderSlot'] : p['attackerSlot'])
                  as int? ??
              0];
      final live = await _yesNo(
        context,
        attackerRole ? 'Krieg erklärt !' : 'Kriegserklärung !',
        '${attackerRole ? 'Du hast $opponent den Krieg erklärt.' : '$opponent hat dir den Krieg erklärt !'} '
        'Willst du deine Truppen selbst befehligen?\n\n'
        'Bei „Nein" übernimmt der Computer diesen Krieg: deine Truppen '
        'folgen ihrer Haltung. Bis zum Kriegsbeginn kannst du jede Truppe '
        'einzeln auf der Karte einstellen (Stellung halten oder '
        'angreifen) — im Kriegsvorbereitungs-Menü über der Karte. Der '
        'Krieg beginnt, sobald beide Seiten gewählt haben — wollen beide '
        'selbst steuern, online zum vereinbarten Zeitpunkt oder nach '
        'Ablauf der Vorbereitungsfrist.',
      );
      // Online duel scheduling: a live commander proposes start times.
      // Local hot-seat skips this — both players sit at the device, the
      // war starts as soon as both have chosen.
      List<int>? slots;
      if (live && controller.isOnline && context.mounted) {
        slots = await _askWarStartSlots(context, controller.turnTimeoutHours);
      }
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'auto': !live,
        if (slots != null && slots.isNotEmpty) 'slots': slots,
      });

    case 'warDefense':
      final war = state.activeWar;
      if (war == null || war.defenderSlot != decision.decidingSlot) {
        // The war ended before the choice was made — clear it silently.
        await controller.resolveDecision(
          decision.id,
          decision.decidingSlot,
          const {},
        );
        return;
      }
      final attacker = gc.countryNames[p['attackerSlot'] as int? ?? 0];
      final defend = await _yesNo(
        context,
        'Kriegserklärung !',
        '$attacker hat dir den Krieg erklärt ! Willst du deine Truppen '
            'selbst befehligen?\n\nBei „Nein" übernimmt der Computer '
            'diesen Krieg: deine Truppen folgen ihrer eingestellten '
            'Haltung (halten / greifen an), und du spielst erst nach '
            'Kriegsende wieder selbst.',
      );
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'defend': defend,
      });

    case 'childName':
      final child = state.persons[p['childId'] as int];
      final isBoy = child == null || child.isMale;
      final name = await _askText(
        context,
        'Ein ${isBoy ? 'Junge' : 'Mädchen'} ist geboren ! '
        'Wie soll ${isBoy ? 'er' : 'sie'} heißen?',
        // Per-game setup option: an empty field instead of the suggestion.
        state.suggestChildNames ? p['suggestedName'] as String? ?? '' : '',
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
          decision.id,
          decision.decidingSlot,
          const {},
        );
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
                child: Text('${buildingNames[building]} (${x + 1}, ${y + 1})'),
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

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// A duel start instant (epoch ms UTC) in the device's local time —
/// "Heute 18:00", "Morgen 03:00", else "Mi 14:00".
String formatWarStartTime(int epochMs) {
  final local = DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true)
      .toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final dayLabel = day == today
      ? 'Heute'
      : day == today.add(const Duration(days: 1))
          ? 'Morgen'
          : _weekdays[local.weekday - 1];
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$dayLabel $hh:$mm Uhr';
}

/// Online duel scheduling: the live commander ticks the times that suit
/// them — "sofort" (the 0 sentinel) plus the next full hours, hourly over
/// the turn timer window (capped at 24 entries; no timer offers 24 h).
/// Full UTC hours, so both players' proposals land on identical instants
/// and can match; shown in local time. Returns epoch ms (0 = sofort);
/// an empty selection proposes nothing — the fallback deadline governs.
Future<List<int>> _askWarStartSlots(
  BuildContext context,
  int? turnTimeoutHours,
) async {
  final now = DateTime.now().toUtc();
  final firstHour = DateTime.utc(now.year, now.month, now.day, now.hour)
      .add(const Duration(hours: 1));
  final count =
      turnTimeoutHours == null ? 24 : turnTimeoutHours.clamp(1, 24);
  final offered = [
    0,
    for (var i = 0; i < count; i++)
      firstHour.add(Duration(hours: i)).millisecondsSinceEpoch,
  ];
  final picked = <int>{};
  final result = await showDialog<List<int>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Wann soll der Krieg beginnen?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Wähle die Zeitpunkte, die dir passen. Passt einer auch '
                  'deinem Gegner, beginnt der Krieg zum frühesten '
                  'gemeinsamen Zeitpunkt — sonst nach Ablauf der '
                  'Vorbereitungsfrist. Ohne Auswahl gilt die Frist.',
                ),
              ),
              for (final ms in offered)
                CheckboxListTile(
                  dense: true,
                  value: picked.contains(ms),
                  title: Text(
                    ms == 0
                        ? 'Sofort — sobald beide gewählt haben'
                        : formatWarStartTime(ms),
                  ),
                  onChanged: (v) => setState(
                    () => v == true ? picked.add(ms) : picked.remove(ms),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, picked.toList()..sort()),
            child: Text(picked.isEmpty ? 'Ohne Terminvorschlag' : 'Bestätigen'),
          ),
        ],
      ),
    ),
  );
  return result ?? const [];
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
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: gc.maxNameLength,
      ),
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
    final theme = Theme.of(context);
    final treasury = widget.controller.state.realm(widget.slot).treasury;
    // You can only ever spend what you actually have — a treasury in the red
    // (e.g. after a lost war's reparations) affords no bribe, but the dialog
    // must stay confirmable (with zero) so the election can proceed instead
    // of soft-locking the finalist with a permanently disabled button.
    final affordable = treasury > 0 ? treasury : 0;
    final spent = _amounts.values.fold(0, (a, b) => a + b);
    final remaining = affordable - spent;
    final broke = affordable <= 0;
    return AlertDialog(
      title: const Text('Bestechung der Kurfürsten'),
      // A per-elector slider stacked over its own row so nothing is crammed
      // side by side (long names + six-digit amounts used to overflow narrow
      // phones); the amount can never exceed the budget, so the confirm button
      // is always enabled.
      // One scrolling ListView (the budget line is its first item): a single
      // viewport keeps the layout bounded on any screen and scrolls when many
      // electors don't fit.
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                broke
                    ? 'Deine Schatzkammer ist leer — du kannst diesmal niemanden '
                          'bestechen. Bestätige ohne Geschenk.'
                    : 'Ausgegeben: $spent T   ·   Verbleibend: $remaining T',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            for (final id in widget.electorIds)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.controller.state.persons[id]?.name ?? '?',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_amounts[id]} T',
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                    Slider(
                      value: _amounts[id]!.clamp(0, affordable).toDouble(),
                      // Cap this elector at whatever is still unspent, so the
                      // total can never exceed the treasury.
                      max: broke
                          ? 1
                          : (_amounts[id]! + remaining)
                                .clamp(1, affordable)
                                .toDouble(),
                      onChanged: broke
                          ? null
                          : (v) => setState(
                              () => _amounts[id] = v
                                  .round()
                                  // Never exceed this elector's share of the
                                  // remaining budget (guards the max=1 floor
                                  // when the treasury is fully committed).
                                  .clamp(0, _amounts[id]! + remaining),
                            ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            widget.onSubmit([
              for (final e in _amounts.entries)
                if (e.value > 0) {'electorId': e.key, 'amount': e.value},
            ]);
            Navigator.pop(context);
          },
          child: Text(broke || spent == 0 ? 'Ohne Bestechung' : 'Bestätigen'),
        ),
      ],
    );
  }
}
