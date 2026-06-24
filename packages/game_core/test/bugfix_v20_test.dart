import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Regression tests for the 2026-06-23 codebase-review fixes:
///  - merging a realm carries its trade ships still at sea (otherwise the
///    staked Taler were silently lost),
///  - a high-value capital capture clamps the harvest share so the loser's
///    grain/cattle stock can never go negative.
void main() {
  GameState freshState() => startGame(
          newGame(GameSetup(
            humans: [
              HumanPlayerSetup(
                  founderName: 'Anna',
                  gender: 1,
                  countrySlot: 1,
                  dorfName: 'A'),
            ],
            reformationYear: 1020,
            ottomanYear: 1040,
            seed: 2026,
          )),
          Rng(7))
      .state;

  /// Makes slot 3 a same-ruler neighbour of slot 1, so the two can merge.
  GameState mergeableState() {
    final state = freshState();
    final ruler1 = state.realm(1).rulerId!;
    state.realm(3).rulerId = ruler1;
    alignSlotControl(state, 3, ruler1);
    final map = state.map;
    outer:
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != 1) continue;
        for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
          final nx = x + dx, ny = y + dy;
          if (!map.inBounds(nx, ny)) continue;
          if (map.ownerAt(nx, ny) == World.niemand && map.isLandAt(nx, ny)) {
            map.owner[map.index(nx, ny)] = 3;
            state.realm(3).tileCount[Building.none]++;
            break outer;
          }
        }
      }
    }
    return state;
  }

  test('merging carries the source realm trade ships still at sea', () {
    final state = mergeableState();
    // The acting realm (slot 1) is the SOURCE that gets vacated; slot 3 is
    // the target that absorbs it. A voyage staked from slot 1 must follow
    // the ruler to slot 3 instead of being orphaned on the dead slot.
    state.realm(1).pendingShipReturns.add(PendingShipReturn(
          invested: 500,
          returned: 800,
          returnYear: state.year + 1,
        ));

    final next = applyAction(
            state, MergeRealms(slot: 1, sourceSlot: 3), Rng(state.rngSeed))
        .state;

    expect(next.realm(1).pendingShipReturns, isEmpty,
        reason: 'the vacated source keeps no outstanding voyages');
    expect(next.realm(3).pendingShipReturns, hasLength(1));
    expect(next.realm(3).pendingShipReturns.single.returned, 800);
  });

  test('capturing a high-value capital never drives the loser harvest negative',
      () {
    final state = freshState();
    const loserSlot = 2;
    final loser = state.realm(loserSlot);
    final map = state.map;
    // Strip every weighted building off the loser except its capital, which
    // we make a Palast (heaviest harvest weight). With the capital the sole
    // weighted tile, its doubled capital share (factor 2) exceeds the whole
    // stock — the unclamped share would push the harvest negative.
    for (var i = 0; i < map.terrain.length; i++) {
      if (map.owner[i] != loserSlot) continue;
      map.building[i] = Building.none;
    }
    map.building[map.index(loser.capitalX, loser.capitalY)] = Building.palast;
    loser.towns
        .removeWhere((t) => t.x == loser.capitalX && t.y == loser.capitalY);
    loser.grainHarvest = 10;
    loser.livestockHarvest = 7;
    final winnerGrainBefore = state.realm(1).grainHarvest;
    final winnerCattleBefore = state.realm(1).livestockHarvest;

    final events = <GameEvent>[];
    transferTile(state, loser.capitalX, loser.capitalY, 1, events);

    expect(loser.grainHarvest, 0, reason: 'clamped to the available stock');
    expect(loser.livestockHarvest, 0);
    // The winner takes at most the loser's whole stock — never more.
    expect(state.realm(1).grainHarvest, winnerGrainBefore + 10);
    expect(state.realm(1).livestockHarvest, winnerCattleBefore + 7);
  });
}
