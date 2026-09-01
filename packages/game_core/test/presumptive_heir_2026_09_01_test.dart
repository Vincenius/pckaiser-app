import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// [presumptiveHeir] — the display query behind the Stammbaum's
/// "Thronfolger" badge (2026-09-01). It walks the §15.4 priority chain with
/// the ruler still ALIVE, so it must never crown the ruler themself and
/// must never invent an heir where the engine would roll dice.
GameState _game({bool genderEqualSuccession = false}) => startGame(
      newGame(GameSetup(
        humans: [
          HumanPlayerSetup(
            founderName: 'Otto',
            gender: 0,
            countrySlot: 1,
            dorfName: 'Burg',
          ),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 2026,
        genderEqualSuccession: genderEqualSuccession,
      )),
      Rng(1),
    ).state;

/// Adds a child of [parent] into [parent]'s house.
Person _child(GameState state, Person parent, String name, int gender, int age) {
  final child = Person(
    id: state.nextPersonId++,
    name: name,
    age: age,
    dynasty: parent.dynasty,
    gender: gender,
  );
  state.persons[child.id] = child;
  state.dynasty(parent.dynasty).memberIds.add(child.id);
  parent.childrenIds.add(child.id);
  return child;
}

void main() {
  group('presumptiveHeir (§15.4 as a display query)', () {
    test('names the first son, never the living ruler', () {
      final state = _game();
      final ruler = state.persons[state.realm(1).rulerId]!;
      // Insertion order is the succession order: the daughter is older but
      // the faithful chain takes the first MALE child.
      final daughter = _child(state, ruler, 'Adelheid', 1, 20);
      final son = _child(state, ruler, 'Heinrich', 0, 12);

      expect(presumptiveHeir(state, 1)?.id, son.id);
      expect(presumptiveHeir(state, 1)?.id, isNot(ruler.id));
      expect(daughter.id, isNot(son.id));
    });

    test('gender-equal succession takes the first child of any gender', () {
      final state = _game(genderEqualSuccession: true);
      final ruler = state.persons[state.realm(1).rulerId]!;
      final daughter = _child(state, ruler, 'Adelheid', 1, 20);
      _child(state, ruler, 'Heinrich', 0, 12);

      expect(presumptiveHeir(state, 1)?.id, daughter.id);
    });

    test('falls through to a childless ruler\'s spouse', () {
      final state = _game();
      final ruler = state.persons[state.realm(1).rulerId]!;
      final foreign = state.persons[state.realm(2).rulerId]!;
      expect(foreign.dynasty, isNot(ruler.dynasty));
      marry(state, ruler, foreign, <GameEvent>[]);

      // No child, no other member of the house — §15.4 rank 3 is the spouse.
      expect(state.dynasty(1).memberIds, [ruler.id]);
      expect(presumptiveHeir(state, 1)?.id, foreign.id);
    });

    test('reports no heir instead of the engine\'s random fallback', () {
      final state = _game();
      final ruler = state.persons[state.realm(1).rulerId]!;
      expect(ruler.spouseId, isNull);
      expect(state.dynasty(1).memberIds, [ruler.id]);

      expect(presumptiveHeir(state, 1), isNull);
    });

    test('a slot whose ruler is gone has no heir', () {
      final state = _game();
      state.realm(1).rulerId = -1;
      expect(presumptiveHeir(state, 1), isNull);
    });
  });
}
