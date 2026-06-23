import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Multiplayer/UX fixes: a human birth's PUBLIC announcement is deferred to
/// the naming decision (so rivals see the chosen name, a round later, not the
/// provisional one), and a religion change costs a smaller, floored
/// popularity hit (no more opaque −70 swings).
/// (18th bugfix iteration — the file counter is independent of
/// `currentRulesVersion`.)
void main() {
  GameState fresh() => startGame(
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

  group('deferred birth announcement (human dynasties)', () {
    test('childName resolution emits the public birth with the chosen name',
        () {
      final state = fresh();
      final child = Person(
          id: state.nextPersonId++,
          name: 'Platzhalter',
          age: 0,
          dynasty: 1,
          gender: 0);
      state.persons[child.id] = child;
      state.dynasty(1).memberIds.add(child.id);
      state.pendingDecisions.add(PendingDecision(
        id: 'childname-${child.id}',
        type: 'childName',
        decidingSlot: 1,
        payload: {
          'childId': child.id,
          'suggestedName': 'Platzhalter',
          'parent': 'Otto',
          'partner': 'Mathilde',
          'gender': 0,
        },
      ));

      final result = applyAction(
        state,
        ResolveDecision(slot: 1, decisionId: 'childname-${child.id}',
            choice: {'name': 'Heinrich'}),
        Rng(state.rngSeed),
      );

      expect(result.state.persons[child.id]!.name, 'Heinrich');
      final birth =
          result.events.where((e) => e.type == 'birth').toList();
      expect(birth, hasLength(1), reason: 'announced now, once');
      expect(birth.single.visibility, EventVisibility.public,
          reason: 'rivals see it');
      expect(birth.single.payload['child'], 'Heinrich',
          reason: 'the chosen name, not the placeholder');
    });

    test('a childName decision without birth context renames silently', () {
      // The plain naming decision (e.g. legacy payload) must not emit a
      // spurious birth event.
      final state = fresh();
      final child = Person(
          id: state.nextPersonId++,
          name: 'X',
          age: 0,
          dynasty: 1,
          gender: 0);
      state.persons[child.id] = child;
      state.dynasty(1).memberIds.add(child.id);
      state.pendingDecisions.add(PendingDecision(
          id: 'cn', type: 'childName', decidingSlot: 1,
          payload: {'childId': child.id}));

      final result = applyAction(
        state,
        ResolveDecision(slot: 1, decisionId: 'cn', choice: {'name': 'Karl'}),
        Rng(state.rngSeed),
      );
      expect(result.state.persons[child.id]!.name, 'Karl');
      expect(result.events.where((e) => e.type == 'birth'), isEmpty);
    });
  });

  group('religion change popularity (floored, reported)', () {
    test('a conversion costs at most religionChangePopularityCost, floored',
        () {
      final state = fresh();
      state.year = 1021; // after the Reformation
      state.realm(1).popularity = 80;
      state.realm(1).treasury = 5000;

      final result = applyAction(
        state,
        ChangeReligion(slot: 1, religion: Religion.evangelisch),
        Rng(state.rngSeed),
      );
      expect(result.state.realm(1).popularity, 80 - religionChangePopularityCost);
      final event =
          result.events.firstWhere((e) => e.type == 'religionChanged');
      expect(event.payload['popularityLost'], religionChangePopularityCost);
    });

    test('the floor keeps a conversion from tipping a realm into strife', () {
      final state = fresh();
      state.year = 1021;
      state.realm(1).popularity = 30; // 30 − 25 = 5 would be below the floor
      state.realm(1).treasury = 5000;

      final result = applyAction(
        state,
        ChangeReligion(slot: 1, religion: Religion.evangelisch),
        Rng(state.rngSeed),
      );
      expect(result.state.realm(1).popularity, militarismPopularityFloor,
          reason: 'never pushed below the floor');
    });
  });
}
