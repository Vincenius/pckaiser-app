import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Online duel scheduling (2026-07-08, user-designed): live sides of a
/// human-vs-human war may propose start times in their `warPlan` answer
/// ('slots': epoch ms UTC; 0 = "as soon as both answered"). The earliest
/// common proposal becomes `war.scheduledStartMs`; no overlap keeps the
/// online fallback (half the turn timer — the server arms the deadline).
void main() {
  PendingDecision planOf(GameState state, int slot) => state.pendingDecisions
      .singleWhere((d) => d.type == 'warPlan' && d.decidingSlot == slot);

  void answer(GameState state, int slot, Map<String, dynamic> choice) =>
      applyActionInPlace(
          state,
          ResolveDecision(
              slot: slot, decisionId: planOf(state, slot).id, choice: choice),
          Rng(1));

  /// Revises an already-given plan (2026-08-09) — the same payload, but as
  /// an action instead of a decision answer.
  void plan(GameState state, int slot, {required bool auto, List<int>? slots}) =>
      applyActionInPlace(
          state, WarPrepPlan(slot: slot, auto: auto, slots: slots), Rng(1));

  test('the earliest common slot becomes the agreed start', () {
    final state = _game(humanSlots: const [1, 2]);
    _prepareWar(state, 1, 2);
    final war = startWar(state, 1, 2, Rng(1));

    answer(state, 1, {
      'auto': false,
      'slots': [3000, 1000, 2000],
    });
    expect(war.scheduledStartMs, isNull,
        reason: 'no agreement before both sides answered');

    answer(state, 2, {
      'auto': false,
      'slots': [2000, 4000],
    });
    expect(war.scheduledStartMs, 2000,
        reason: 'earliest common proposal wins');

    // A scheduled (non-zero) agreement still WAITS online — the server
    // arms the deadline at the agreed instant and the sweep starts it.
    resolveWarPreparation(state, Rng(1), <GameEvent>[],
        waitWhenAllManual: true);
    expect(war.phase, WarPhase.preparation);
    resolveWarPreparation(state, Rng(1), <GameEvent>[], force: true);
    expect(war.phase, WarPhase.rounds);
    expect(war.autoSlots, isEmpty);
  });

  test('a "sofort" agreement (a current-hour instant) still waits online',
      () {
    final state = _game(humanSlots: const [1, 2]);
    _prepareWar(state, 1, 2);
    final war = startWar(state, 1, 2, Rng(1));

    // "sofort" is the top of the answering side's current hour — a concrete
    // instant, not a sentinel. Both propose it; it becomes the agreed start.
    const sofort = 1000;
    answer(state, 1, {
      'auto': false,
      'slots': [sofort, 5000],
    });
    answer(state, 2, {
      'auto': false,
      'slots': [sofort],
    });
    expect(war.scheduledStartMs, sofort,
        reason: 'the earliest common instant wins — no special 0 sentinel');

    // Online (both live): the duel no longer starts in this request. The
    // server arms the deadline at the (already-past "sofort") instant and
    // the sweep fires it — there is no immediate-start sentinel anymore.
    resolveWarPreparation(state, Rng(1), <GameEvent>[],
        waitWhenAllManual: true);
    expect(war.phase, WarPhase.preparation);
    resolveWarPreparation(state, Rng(1), <GameEvent>[], force: true);
    expect(war.phase, WarPhase.rounds);
    expect(war.autoSlots, isEmpty);
  });

  test('no overlap (or one-sided proposals) leaves the fallback in charge',
      () {
    final state = _game(humanSlots: const [1, 2]);
    _prepareWar(state, 1, 2);
    final war = startWar(state, 1, 2, Rng(1));

    answer(state, 1, {
      'auto': false,
      'slots': [1000, 2000],
    });
    answer(state, 2, {'auto': false}); // proposes nothing
    expect(war.scheduledStartMs, isNull);

    resolveWarPreparation(state, Rng(1), <GameEvent>[],
        waitWhenAllManual: true);
    expect(war.phase, WarPhase.preparation,
        reason: 'no agreement → wait for the fallback deadline');
    resolveWarPreparation(state, Rng(1), <GameEvent>[], force: true);
    expect(war.phase, WarPhase.rounds);
  });

  test('a delegating side never schedules — one live side starts at once',
      () {
    final state = _game(humanSlots: const [1, 2]);
    _prepareWar(state, 1, 2);
    final war = startWar(state, 1, 2, Rng(1));

    answer(state, 1, {
      'auto': false,
      'slots': [1000],
    });
    // The defender delegates; their (nonsensical) slots are ignored.
    answer(state, 2, {
      'auto': true,
      'slots': [1000],
    });
    expect(war.planSlots.containsKey(2), isFalse);
    expect(war.scheduledStartMs, isNull,
        reason: 'scheduling only matters for a BOTH-live duel');

    resolveWarPreparation(state, Rng(1), <GameEvent>[],
        waitWhenAllManual: true);
    expect(war.phase, WarPhase.rounds,
        reason: 'exactly one live side → early start, as before');
  });

  test('scheduling fields survive the JSON roundtrip; old saves default',
      () {
    final state = _game(humanSlots: const [1, 2]);
    _prepareWar(state, 1, 2);
    final war = startWar(state, 1, 2, Rng(1));
    war.planSlots[1] = [1000, 2000];
    war.scheduledStartMs = 2000;
    war.actedSlots.add(1);

    final revived = ActiveWar.fromJson(war.toJson());
    expect(revived.planSlots, {
      1: [1000, 2000],
    });
    expect(revived.scheduledStartMs, 2000);
    expect(revived.actedSlots, {1});

    // A pre-scheduling save (no such keys) loads with empty defaults.
    final legacyJson = war.toJson()
      ..remove('planSlots')
      ..remove('scheduledStartMs')
      ..remove('actedSlots')
      ..remove('planAnsweredSlots');
    final legacy = ActiveWar.fromJson(legacyJson);
    expect(legacy.planSlots, isEmpty);
    expect(legacy.scheduledStartMs, isNull);
    expect(legacy.actedSlots, isEmpty);
    expect(legacy.planAnsweredSlots, isEmpty);

    // planAnsweredSlots (2026-08-09) is DERIVED for a save from a build
    // that predates it: a side that had proposed times (or delegated)
    // obviously answered its warPlan.
    final midLegacy =
        ActiveWar.fromJson(war.toJson()..remove('planAnsweredSlots'));
    expect(midLegacy.planAnsweredSlots, {1});
  });

  // `[DESIGNED 2026-08-09, user request]` The plan stays REVISABLE for the
  // whole preparation window (`WarPrepPlan`): switch between live command
  // and autopilot, and widen/narrow the offered times until they overlap.
  group('revising the plan during the preparation window', () {
    test('both sides widen their offers until a time matches', () {
      final state = _game(humanSlots: const [1, 2]);
      _prepareWar(state, 1, 2);
      final war = startWar(state, 1, 2, Rng(1));

      answer(state, 1, {
        'auto': false,
        'slots': [1000],
      });
      answer(state, 2, {
        'auto': false,
        'slots': [2000],
      });
      expect(war.scheduledStartMs, isNull, reason: 'no common time yet');
      // Both answered, both live: online the duel waits for the fallback.
      resolveWarPreparation(state, Rng(1), <GameEvent>[],
          waitWhenAllManual: true);
      expect(war.phase, WarPhase.preparation);

      // The defender adds the attacker's time — now they agree.
      plan(state, 2, auto: false, slots: [2000, 1000]);
      expect(war.scheduledStartMs, 1000);

      // ...and the attacker withdraws it again: back to the fallback.
      plan(state, 1, auto: false, slots: const []);
      expect(war.scheduledStartMs, isNull);
    });

    test('a delegated side may take the field again before the war starts',
        () {
      final state = _game(humanSlots: const [1, 2]);
      _prepareWar(state, 1, 2);
      final war = startWar(state, 1, 2, Rng(1));

      answer(state, 1, {'auto': true}); // attacker delegates
      expect(war.autoSlots, {1});
      // Second thoughts: command live after all, with a time proposal.
      plan(state, 1, auto: false, slots: [1000]);
      expect(war.autoSlots, isEmpty);
      expect(war.planSlots[1], [1000]);

      answer(state, 2, {
        'auto': false,
        'slots': [1000],
      });
      expect(war.scheduledStartMs, 1000,
          reason: 'the revised side counts as live and schedules');
      resolveWarPreparation(state, Rng(1), <GameEvent>[],
          waitWhenAllManual: true);
      expect(war.phase, WarPhase.preparation,
          reason: 'a both-live duel waits for its appointment');
    });

    test('delegating after an appointment was fixed keeps the start time',
        () {
      final state = _game(humanSlots: const [1, 2]);
      _prepareWar(state, 1, 2);
      final war = startWar(state, 1, 2, Rng(1));

      answer(state, 1, {
        'auto': false,
        'slots': [1000],
      });
      answer(state, 2, {
        'auto': false,
        'slots': [1000],
      });
      expect(war.scheduledStartMs, 1000);

      // The defender hands the war to the autopilot after the fact. The
      // appointment must SURVIVE: the live attacker planned for it and
      // would otherwise miss a duel started "right now".
      plan(state, 2, auto: true);
      expect(war.autoSlots, {2});
      expect(war.scheduledStartMs, 1000);
      expect(war.planSlots.containsKey(2), isFalse);
      resolveWarPreparation(state, Rng(1), <GameEvent>[],
          waitWhenAllManual: true);
      expect(war.phase, WarPhase.preparation,
          reason: 'the agreed start outranks the one-live-side early start');
      resolveWarPreparation(state, Rng(1), <GameEvent>[], force: true);
      expect(war.phase, WarPhase.rounds);
    });

    test('both sides see who has already chosen', () {
      final state = _game(humanSlots: const [1, 2]);
      _prepareWar(state, 1, 2);
      final war = startWar(state, 1, 2, Rng(1));

      expect(war.planAnsweredSlots, isEmpty);
      answer(state, 1, {'auto': false});
      expect(war.planAnsweredSlots, {1});
      // The flag lives in the shared war state, so it survives the
      // hidden-information filter for the OPPONENT's view too (their
      // pending decision itself is filtered out).
      final asDefender = visibleStateFor(state, 2);
      expect(asDefender.activeWar!.planAnsweredSlots, {1});
      expect(asDefender.pendingDecisions.map((d) => d.decidingSlot), [2]);
    });

    test('a revision is rejected once the war rounds run', () {
      final state = _game(humanSlots: const [1, 2]);
      _prepareWar(state, 1, 2);
      final war = startWar(state, 1, 2, Rng(1));
      answer(state, 1, {'auto': false});
      answer(state, 2, {'auto': false});
      resolveWarPreparation(state, Rng(1), <GameEvent>[]);
      expect(war.phase, WarPhase.rounds);

      expect(
          () => applyActionInPlace(
              state, WarPrepPlan(slot: 1, auto: true), Rng(1)),
          throwsA(isA<ActionException>()));
    });

    test('the opponent\'s proposed times are visible to both sides', () {
      final state = _game(humanSlots: const [1, 2]);
      _prepareWar(state, 1, 2);
      startWar(state, 1, 2, Rng(1));
      answer(state, 1, {
        'auto': false,
        'slots': [1000, 2000],
      });

      // The defender's filtered view carries the attacker's offer, so the
      // time picker can highlight the times the enemy already accepted.
      final asDefender = visibleStateFor(state, 2);
      expect(asDefender.activeWar!.planSlots[1], [1000, 2000]);
    });
  });
}

GameState _game({List<int> humanSlots = const [1]}) => startGame(
      newGame(GameSetup(
        humans: [
          for (var i = 0; i < humanSlots.length; i++)
            HumanPlayerSetup(
                founderName: 'Mensch$i',
                gender: 0,
                countrySlot: humanSlots[i],
                dorfName: 'Stadt$i'),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 2026,
      )),
      Rng(7),
    ).state;

/// Gives both slots a standing army and a shared border — war
/// declarations require troops + neighborship (same fixture as
/// bugfix_v28_test.dart).
void _prepareWar(GameState state, int a, int b) {
  state.year = 1010;
  for (final slot in [a, b]) {
    final realm = state.realm(slot);
    if (realm.troops.isEmpty) {
      realm.troops.add(Troop(
          name: 'Heer$slot',
          men: 100,
          troopClass: TroopClass.infanterie,
          quality: TroopQuality.regular,
          garrisonCounted: false,
          x: realm.capitalX,
          y: realm.capitalY));
    }
  }
  if (state.map.realmNeighbors(a).contains(b)) return;
  final map = state.map;
  outer:
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) {
        continue;
      }
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        if (map.inBounds(x + dx, y + dy) && map.ownerAt(x + dx, y + dy) == a) {
          map.owner[map.index(x, y)] = b;
          state.realm(b).tileCount[Building.none]++;
          break outer;
        }
      }
    }
  }
  expect(state.map.realmNeighbors(a), contains(b));
}
