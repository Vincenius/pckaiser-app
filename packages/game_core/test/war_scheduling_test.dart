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

  test('the "sofort" sentinel (0) starts the duel with the second answer',
      () {
    final state = _game(humanSlots: const [1, 2]);
    _prepareWar(state, 1, 2);
    final war = startWar(state, 1, 2, Rng(1));

    answer(state, 1, {
      'auto': false,
      'slots': [0, 5000],
    });
    answer(state, 2, {
      'auto': false,
      'slots': [0],
    });
    expect(war.scheduledStartMs, 0,
        reason: '0 sorts before any real instant — "sofort" wins');

    // Even under the online wait rule the duel begins at once: both
    // declared themselves ready right now.
    resolveWarPreparation(state, Rng(1), <GameEvent>[],
        waitWhenAllManual: true);
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
      ..remove('actedSlots');
    final legacy = ActiveWar.fromJson(legacyJson);
    expect(legacy.planSlots, isEmpty);
    expect(legacy.scheduledStartMs, isNull);
    expect(legacy.actedSlots, isEmpty);
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
      realm.armySize += 100;
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
