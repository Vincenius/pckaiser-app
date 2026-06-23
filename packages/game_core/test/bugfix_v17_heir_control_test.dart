import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Bugfix: "play the land yourself whenever your own heir is in power".
///
/// Reported case: a human is couped on their home realm (the slot flips to
/// AI under a rival branch — say a daughter). The human still controls a
/// second realm with another of their dynasty's rulers. They send assassins
/// from the second realm and kill the usurper; succession crowns their old
/// ruler on the couped realm, so BOTH realms now share the same ruler — yet
/// the couped realm stayed locked to AI control. After the fix,
/// `alignSlotControl` restores human control: a realm whose ruler already
/// plays another slot as a human is played by that same human.
/// (17th bugfix iteration — the file counter is just a label; rules are not
/// versioned, every game plays the latest.)
void main() {
  test('a retaken home realm follows its human ruler, not the couped AI flag',
      () {
    var state = startGame(
      newGame(GameSetup(
        humans: [
          // Founder is male so he is the first-priority male heir.
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

    final ruler = state.person(state.realm(1).rulerId)!; // Otto, dynasty 1

    // The human also plays realm 2, ruled by Otto (cross-dynasty aliasing).
    state.realm(2).rulerId = ruler.id;
    state.dynasty(2).status = DynastyStatus.human;
    state.dynasty(2).humanPlayer = 0;

    // The coup: realm 1 (Otto's home dynasty) flipped to AI under a daughter.
    final daughter = Person(
      id: state.nextPersonId++,
      name: 'Adelheid',
      age: 25,
      dynasty: 1,
      gender: 1,
    );
    state.persons[daughter.id] = daughter;
    state.dynasty(1).memberIds.add(daughter.id);
    state.realm(1).rulerId = daughter.id;
    state.dynasty(1).status = DynastyStatus.ai;
    state.dynasty(1).humanPlayer = null;

    // Sanity: the couped realm is AI before the assassination resolves.
    expect(state.dynasty(1).status, DynastyStatus.ai);

    // Assassinate the usurper — succession crowns Otto (first male member).
    final events = <GameEvent>[];
    handleDeath(state, daughter, Rng(1), events);

    expect(state.realm(1).rulerId, ruler.id,
        reason: 'Otto re-crowned on his home realm');
    expect(state.dynasty(1).status, DynastyStatus.human,
        reason: 'the realm follows its human ruler');
    expect(state.dynasty(1).humanPlayer, 0,
        reason: 'controlled by the same player who holds realm 2');
  });
}
