import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/labels.dart';
import '../l10n/strings.dart';
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
      title: tr('dec.roundReport'),
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
    case 'troopTransfer':
      final troop = gc.Troop.fromJson(
        (p['sourceTroop'] as Map).cast<String, dynamic>(),
      );
      final map = state.map;
      final candidateIndices = <int>{};
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) == decision.decidingSlot) {
            candidateIndices.add(map.index(x, y));
          }
        }
      }
      // Announce the gift first, then let the player tap its station on the
      // map — a realm owns hundreds of tiles by mid-game, far more than any
      // coordinate list can usefully offer. Skipping the pick (or owning no
      // tile at all) stations the unit at the capital, as the engine's
      // fallback does.
      await _info(
        context,
        tr('dec.troopTransferTitle'),
        tr('dec.troopTransferBody', {
          'source': realmName(p['sourceSlot'] as int),
          'name': troop.name,
          'men': troop.men,
        }),
      );
      final pick = candidateIndices.isEmpty
          ? null
          : await controller.pickSeatOnMap(
              hint: tr('dec.troopTransferMapHint'),
              candidates: candidateIndices,
            );
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        if (pick != null) 'x': pick.$1,
        if (pick != null) 'y': pick.$2,
      });

    case 'marriageConsent':
      final proposer = state.persons[p['proposerId'] as int];
      final target = state.persons[p['targetId'] as int];
      // Name the proposer's land and age: a marriage is the main peaceful
      // path to inheriting realms (§14), so the target must know which
      // realm they are tying their line to before accepting.
      final proposerLine = proposer == null
          ? '?'
          : tr('dec.proposerLine', {
              'name': proposer.name,
              'realm': realmName(proposer.dynasty),
              'age': proposer.age,
            });
      final accept = await _yesNo(
        context,
        tr('dec.marriageProposalTitle'),
        tr('dec.marriageProposalBody', {
          'proposer': proposerLine,
          'target': target?.name ?? '?',
        }),
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
          title: Text(tr('dec.heirChoiceTitle', {'name': p['deceasedName']})),
          children: [
            for (final id in candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, id),
                child: Text(
                  tr('dec.personWithAge', {
                    'name': state.persons[id]!.name,
                    'age': state.persons[id]!.age,
                  }),
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
      final opponent = realmName(
        (attackerRole ? p['defenderSlot'] : p['attackerSlot']) as int? ?? 0,
      );
      final live = await _yesNo(
        context,
        attackerRole
            ? tr('dec.warDeclaredTitle')
            : tr('dec.warDeclarationTitle'),
        tr('dec.warPlanBody', {
          'declaration': attackerRole
              ? tr('dec.warPlanYouDeclared', {'realm': opponent})
              : tr('dec.warPlanEnemyDeclared', {'realm': opponent}),
        }),
      );
      // Online duel scheduling: a live commander proposes start times.
      // Local hot-seat skips this — both players sit at the device, the
      // war starts as soon as both have chosen.
      List<int>? slots;
      if (live && controller.isOnline && context.mounted) {
        // The opponent may have answered first — show which hours suit them
        // so the second answer can actually match one (user request
        // 2026-08-09). Both sides' proposals live in the shared war state.
        final enemySlot = war.opponentOf(decision.decidingSlot);
        slots = await askWarStartSlots(
          context,
          controller.turnTimeoutHours,
          opponentSlots: war.planSlots[enemySlot] ?? const [],
          opponentAnswered: war.planAnsweredSlots.contains(enemySlot),
        );
      }
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'auto': !live,
        if (slots != null && slots.isNotEmpty) 'slots': slots,
      });
      // Online: confirm the outcome in-app. Whoever answers second (usually
      // the defender) learns the matched appointment right away; the first
      // to answer sees their choice was saved while the opponent still owes
      // theirs. A no-overlap result reads the same as "still waiting" from
      // here (the opponent's pending answer is hidden) — the wording covers
      // both, and the server's push carries the final "fixed" word.
      if (live && controller.isOnline && context.mounted) {
        final agreedMs = controller.state.activeWar?.scheduledStartMs;
        await _info(
          context,
          tr('dec.warStartTitle'),
          agreedMs != null && agreedMs > 0
              ? tr('dec.warStartConfirmed', {
                  'time': formatWarStartTime(agreedMs),
                })
              : tr('dec.warStartSaved'),
        );
      }

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
      final attacker = realmName(p['attackerSlot'] as int? ?? 0);
      final defend = await _yesNo(
        context,
        tr('dec.warDeclarationTitle'),
        tr('dec.warDefenseBody', {'realm': attacker}),
      );
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'defend': defend,
      });

    case 'childName':
      final child = state.persons[p['childId'] as int];
      final isBoy = child == null || child.isMale;
      final name = await _askText(
        context,
        isBoy ? tr('dec.childBornBoy') : tr('dec.childBornGirl'),
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
          title: Text(tr('dec.electionVoteTitle')),
          children: [
            for (final id in finalists)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, id),
                child: Text(
                  tr('dec.electionCandidate', {
                    'name': state.persons[id]?.name ?? '?',
                    'amount': bribes['$id'] ?? 0,
                  }),
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
      // Full-sentence keys per option: the verb phrase sits at the end in
      // German but mid-sentence in English, so a shared template won't do.
      final params = {'name': captured?.name ?? '?', 'option': p['option']};
      final question = switch (p['option']) {
        'convertOrDie' => tr('dec.coerceConvertOrDie', params),
        'forcedMarriage' => tr('dec.coerceForcedMarriage', params),
        'abdication' => tr('dec.coerceAbdication', params),
        'stripSeat' => tr('dec.coerceStripSeat', params),
        _ => tr('dec.coerceOther', params),
      };
      final apply = await _yesNo(context, tr('dec.coercionTitle'), question);
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'apply': apply,
      });

    case 'convertOrDie':
      final accept = await _yesNo(
        context,
        tr('dec.convertOrDieTitle'),
        tr('dec.convertOrDieBody'),
      );
      await controller.resolveDecision(decision.id, decision.decidingSlot, {
        'accept': accept,
      });

    case 'relocateCapital':
      // The seat was lost (war, earthquake, bankruptcy) — the player must
      // pick a new one. Free, and not dismissible: leaving the realm
      // seatless is not an option.
      final map = state.map;
      final candidates = <(int, int, int)>[];
      final candidateIndices = <int>{};
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          final building = map.buildingAt(x, y);
          // The engine's seat rule (§6.2): Stadt, Burg or Palast.
          if (map.ownerAt(x, y) == decision.decidingSlot &&
              gc.Building.isSeat(building)) {
            candidates.add((x, y, building));
            candidateIndices.add(map.index(x, y));
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
      // Map-based pick: highlight the eligible tiles, let the player tap
      // one on the map instead of selecting from a coordinate list.
      final pick = await controller.pickSeatOnMap(
        hint: tr('dec.relocateSeatMapHint'),
        candidates: candidateIndices,
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

const _weekdayKeys = [
  'dec.weekdayMon',
  'dec.weekdayTue',
  'dec.weekdayWed',
  'dec.weekdayThu',
  'dec.weekdayFri',
  'dec.weekdaySat',
  'dec.weekdaySun',
];

/// A duel start instant (epoch ms UTC) in the device's local time —
/// "Heute 18:00", "Morgen 03:00", else "Mi 14:00".
///
/// An instant that has PASSED reads "jeden Moment" instead of a clock
/// time (`[FIX 2026-08-08]`, user report): the first offered slot is
/// "sofort" = the top of the answering side's CURRENT hour, so an
/// agreement on it is by construction already in the past — the panel
/// then announced "Krieg startet um 20:00" at 20:40, which reads like a
/// missed appointment instead of "the server fires it on its next sweep".
String formatWarStartTime(int epochMs) {
  final local = DateTime.fromMillisecondsSinceEpoch(
    epochMs,
    isUtc: true,
  ).toLocal();
  final now = DateTime.now();
  if (!local.isAfter(now)) return tr('dec.warStartImminent');
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final dayLabel = day == today
      ? tr('dec.today')
      : day == today.add(const Duration(days: 1))
      ? tr('dec.tomorrow')
      : tr(_weekdayKeys[local.weekday - 1]);
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return tr('dec.warStartTime', {'day': dayLabel, 'time': '$hh:$mm'});
}

/// Online duel scheduling: the live commander ticks the times that suit
/// them — "sofort" (the top of the CURRENT hour) plus the following full
/// hours, hourly over the turn timer window (capped at 24 entries; no timer
/// offers 24 h). Full UTC hours, so both players' proposals land on
/// identical instants and can match; shown in local time. Because "sofort"
/// is pinned to the current hour, two sides only agree on it when both
/// answer within the same hour — a late answer can no longer start the duel
/// at an arbitrary future instant. Returns epoch ms; an empty selection
/// proposes nothing — the fallback deadline governs. Null = cancelled (the
/// re-scheduling path from the war panel leaves the stored offer alone).
///
/// `[DESIGNED 2026-08-09, user request]` Re-openable during the whole
/// preparation window (war panel → "Zeiten anpassen"): [initial] pre-ticks
/// this side's current offer, and [opponentSlots] marks the times the
/// OPPONENT already accepted — without that hint two players who missed
/// each other had to guess blindly which hour to add.
Future<List<int>?> askWarStartSlots(
  BuildContext context,
  int? turnTimeoutHours, {
  Iterable<int> initial = const [],
  Iterable<int> opponentSlots = const [],
  bool opponentAnswered = false,
  bool cancellable = false,
}) async {
  final now = DateTime.now().toUtc();
  final currentHour = DateTime.utc(now.year, now.month, now.day, now.hour);
  final nowMs = currentHour.millisecondsSinceEpoch;
  final count = turnTimeoutHours == null ? 24 : turnTimeoutHours.clamp(1, 24);
  final offered = [
    for (var i = 0; i < count; i++)
      currentHour.add(Duration(hours: i)).millisecondsSinceEpoch,
  ];
  final enemy = opponentSlots.toSet();
  // A previously offered hour that has since rolled out of the window can
  // no longer be re-ticked — keep only what is still offerable.
  final picked = initial.where(offered.contains).toSet();
  final result = await showDialog<List<int>>(
    context: context,
    barrierDismissible: cancellable,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr('dec.warStartTitle')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(tr('dec.warStartHint')),
              ),
              // What the opponent offered, stated up front: "they have not
              // chosen yet" vs. "these hours suit them" — the ticks below
              // carry the same information per row.
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  !opponentAnswered
                      ? tr('dec.warStartEnemyPending')
                      : enemy.isEmpty
                      ? tr('dec.warStartEnemyNoTimes')
                      : tr('dec.warStartEnemyTimes'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              for (final ms in offered)
                CheckboxListTile(
                  dense: true,
                  value: picked.contains(ms),
                  title: Text(
                    ms == nowMs
                        ? tr('dec.warStartNow')
                        : formatWarStartTime(ms),
                  ),
                  // The opponent's accepted hours are flagged per row, so a
                  // matching pick is one glance away.
                  secondary: enemy.contains(ms)
                      ? Tooltip(
                          message: tr('dec.warStartEnemyFits'),
                          // A check mark — `dec.warStartEnemyTimes` above
                          // tells the player to look for exactly that.
                          child: const Icon(Icons.check, size: 20),
                        )
                      : null,
                  onChanged: (v) => setState(
                    () => v == true ? picked.add(ms) : picked.remove(ms),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (cancellable)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('dec.cancel')),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, picked.toList()..sort()),
            child: Text(
              picked.isEmpty ? tr('dec.warStartNoProposal') : tr('dec.confirm'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
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
          child: Text(tr('dec.no')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(tr('dec.yes')),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// A single-button information dialog (acknowledge only).
Future<void> _info(BuildContext context, String title, String message) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('dec.ok')),
          ),
        ],
      ),
    );

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
      title: Text(tr('dec.bribeTitle')),
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
                    ? tr('dec.bribeBroke')
                    : tr('dec.bribeBudget', {
                        'spent': spent,
                        'remaining': remaining,
                      }),
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
          child: Text(
            broke || spent == 0 ? tr('dec.bribeNone') : tr('dec.confirm'),
          ),
        ),
      ],
    );
  }
}
