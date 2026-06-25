import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// "Reiche zusammenlegen" requires a shared border, exactly as the original
/// did: the merge handler builds its candidate list from the same neighbour
/// helper as war declaration (verified in the disassembly — both reject with a
/// "Nachbarn" message when the list is empty). Adjacency is plain orthogonal
/// tile-touch on the ownership grid. An owned Hafen sits on a water tile the
/// realm owns, so it counts in adjacency like any owned tile and CAN bridge a
/// one-tile strait — but a harbour does NOT reach across an open-water gap.
///
/// Reported case: two own realms "next to each other, only via a harbour".
/// These tests pin down both halves so the rule can't silently drift:
///   • a Hafen tile that touches the other realm → neighbours → mergeable;
///   • realms separated by open water (harbour does not reach) → NOT mergeable.
/// (The file counter is just a label; rules are not versioned.)
void main() {
  // A cleared map with two same-player realms on row [y], separated by one
  // water tile. With [bridge] the gap tile becomes realm 1's Hafen (owned),
  // so realm 1 orthogonally touches realm 2; without it the gap stays open
  // water and the two realms never touch.
  GameState scenario({required bool bridge}) {
    final state = startGame(
      newGame(GameSetup(
        humans: [
          HumanPlayerSetup(
              founderName: 'Otto', gender: 0, countrySlot: 1, dorfName: 'A'),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 2026,
      )),
      Rng(7),
    ).state;
    state.year = 1010;

    final map = state.map;
    // Wipe to open water so only the tiles we place below exist.
    for (var i = 0; i < map.terrain.length; i++) {
      map.terrain[i] = Terrain.water;
      map.owner[i] = World.niemand;
      map.building[i] = Building.none;
    }
    for (final slot in [1, 2]) {
      final r = state.realm(slot);
      for (var b = 0; b < r.tileCount.length; b++) {
        r.tileCount[b] = 0;
      }
    }

    const y = 20, x0 = 10;
    void put(int x, int slot, int terrain, int building) {
      final i = map.index(x, y);
      map.terrain[i] = terrain;
      map.owner[i] = slot;
      map.building[i] = building;
    }

    // [1 land][1 Dorf] [water gap] [2 Dorf][2 land]
    put(x0, 1, Terrain.ebene, Building.none);
    put(x0 + 1, 1, Terrain.ebene, Building.dorf);
    put(x0 + 3, 2, Terrain.ebene, Building.dorf);
    put(x0 + 4, 2, Terrain.ebene, Building.none);
    state.realm(1).tileCount[Building.none] += 1;
    state.realm(1).tileCount[Building.dorf] += 1;
    state.realm(2).tileCount[Building.dorf] += 1;
    state.realm(2).tileCount[Building.none] += 1;

    if (bridge) {
      // Realm 1's Hafen on the gap water tile: owned by 1, now touches realm 2.
      put(x0 + 2, 1, Terrain.water, Building.hafen);
      state.realm(1).tileCount[Building.hafen] += 1;
    }

    // Both realms held by the same human player (aliasing/inheritance).
    final ruler1 = state.realm(1).rulerId!;
    state.realm(2).rulerId = ruler1;
    alignSlotControl(state, 2, ruler1);
    return state;
  }

  test('open-water gap: the harbour does not reach — NOT mergeable (faithful)',
      () {
    final state = scenario(bridge: false);
    expect(state.map.realmNeighbors(1), isNot(contains(2)),
        reason: 'an open-water tile separates the two coasts');
    expect(mergeableSlots(state, 1), isNot(contains(2)),
        reason: 'the original blocks merge across a sea gap ("keine Nachbarn")');
  });

  test('a Hafen tile that touches the other realm bridges adjacency → mergeable',
      () {
    final state = scenario(bridge: true);
    expect(state.map.realmNeighbors(1), contains(2),
        reason: "realm 1's owned Hafen water tile orthogonally touches realm 2");
    expect(mergeableSlots(state, 1), contains(2));

    final otto = state.realm(1).rulerId;
    final next = applyAction(
            state, MergeRealms(slot: 2, sourceSlot: 1), Rng(state.rngSeed))
        .state;
    expect(next.realm(1).rulerId, otto, reason: 'realm 1 absorbs realm 2');
    expect(next.realm(2).rulerId, isNull, reason: 'the merged-away slot vacates');
  });
}
