import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// "Steuern + zusammenlegen über eigene Erben": a realm ruled by a DIFFERENT
/// heir of your own dynasty (peaceful inheritance, §15.4) is both
/// controllable — control follows the dynasty via `alignSlotControl` — and
/// mergeable with your home realm (§6.2), even though the two slots have
/// different rulers. The old `mergeableSlots` gate required the *same ruler*
/// and so locked an heir's realm out of the Handel "Reiche zusammenlegen".
/// (The file counter is just a label; rules are not versioned.)
void main() {
  // Hand slot 3 a land tile bordering slot 1 so the two can merge.
  void borderSlot3ToSlot1(GameState state) {
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
  }

  // Human player 0 (founder Otto, dynasty 1, home slot 1). A second member of
  // that same dynasty — a brother — inherits realm 3 (its home dynasty was
  // AI). Slot 3 ends up ruled by a different person than slot 1.
  GameState withHeirRuledNeighbour() {
    var state = startGame(
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

    final heir = Person(
      id: state.nextPersonId++,
      name: 'Konrad',
      age: 30,
      dynasty: 1, // the player's own dynasty (family 1)
      gender: 0,
    );
    state.persons[heir.id] = heir;
    state.dynasty(1).memberIds.add(heir.id);

    // Control follows the dynasty on every ruler overwrite (succession,
    // inheritance, conquest) — alignSlotControl is what the engine runs.
    state.realm(3).rulerId = heir.id;
    alignSlotControl(state, 3, heir.id);

    borderSlot3ToSlot1(state);
    return state;
  }

  test('a realm ruled by your own heir becomes yours to control', () {
    final state = withHeirRuledNeighbour();
    expect(state.realm(1).rulerId, isNot(state.realm(3).rulerId),
        reason: 'home and inherited realm have different rulers');
    expect(state.dynasty(3).status, DynastyStatus.human,
        reason: 'inherited by a member of the human dynasty');
    expect(state.dynasty(3).humanPlayer, 0,
        reason: 'controlled by the same player as the home realm');
  });

  test('your home realm can merge with an heir-ruled realm (different ruler)',
      () {
    final state = withHeirRuledNeighbour();
    // The candidacy is symmetric — either slot lists the other.
    expect(mergeableSlots(state, 1), contains(3));
    expect(mergeableSlots(state, 3), contains(1));

    final otto = state.realm(1).rulerId;
    // Vacate the heir's slot 3 into the founder's home slot 1.
    final next = applyAction(
            state, MergeRealms(slot: 3, sourceSlot: 1), Rng(state.rngSeed))
        .state;
    expect(next.realm(1).rulerId, otto,
        reason: 'the consolidated seat stays with the founder');
    expect(next.realm(3).rulerId, isNull,
        reason: 'the merged-away slot is vacated');
    expect(next.dynasty(3).status, DynastyStatus.ai,
        reason: 'a vacated slot is no longer a human seat');
  });

  test('still refuses to merge realms held by a DIFFERENT player', () {
    final state = withHeirRuledNeighbour();
    // Flip realm 3 to a rival human player; same dynasty membership is no
    // longer enough — control (humanPlayer) must match.
    state.dynasty(3).humanPlayer = 1;
    expect(mergeableSlots(state, 1), isNot(contains(3)));
  });
}
