import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Regression tests for the 0.1.13 fixes (user bug reports 2026-07):
/// a ruler who inherited realms across dynasties (§15.4 spouse path, e.g.
/// a widow after a successful assassination) can still marry from those
/// slots, inherited realms re-gender their title to the new ruler, and
/// pending decisions follow the player across all their slots.
GameState _game({List<int> humanSlots = const [1]}) => startGame(
      newGame(GameSetup(
        humans: [
          for (var i = 0; i < humanSlots.length; i++)
            HumanPlayerSetup(
                founderName: 'Mensch$i',
                gender: 1, // female founders — the reported scenario
                countrySlot: humanSlots[i],
                dorfName: 'Stadt$i'),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 2026,
      )),
      Rng(7),
    ).state;

void main() {
  group('cross-dynasty inheritance (§15.4 spouse path)', () {
    late GameState state;
    late Person anna;

    setUp(() {
      state = _game();
      state.year = 1010;
      anna = state.person(state.realm(1).rulerId)!;
      anna.age = 25;
      final victim = state.person(state.realm(2).rulerId)!;
      // The victim is the last member of their house, married to Anna —
      // her spouse-path inheritance is the only succession candidate.
      victim.childrenIds.clear();
      state.dynasty(2).memberIds.retainWhere((id) => id == victim.id);
      state.realm(2).titleClass = 1; // male form, lowest rank (Ritter)
      anna.spouseId = victim.id;
      victim.spouseId = anna.id;
      handleDeath(state, victim, Rng(5), <GameEvent>[]);
    });

    test('the widow rules the inherited slot but keeps her home dynasty', () {
      expect(state.realm(2).rulerId, anna.id);
      expect(anna.dynasty, 1,
          reason: 'inheritance does not move her into house 2');
      expect(state.dynasty(2).status, DynastyStatus.human);
      expect(memberOfRulingHouse(state, state.realm(2), anna), isTrue);
    });

    test('the inherited realm re-genders its title to the new ruler', () {
      expect(state.realm(2).titleClass, 13,
          reason: 'female form of rank 1 (Burgherrin) — the rank itself '
              'stays the realm\'s, only the form follows the ruler');
    });

    test('she may propose a royal marriage from the inherited slot', () {
      final groom = Person(
          id: state.nextPersonId++,
          name: 'Ludwig',
          age: anna.age,
          dynasty: 3,
          gender: 0);
      state.persons[groom.id] = groom;
      state.dynasty(3).memberIds.add(groom.id);
      state.dynasty(3).religion = state.dynasty(1).religion;

      // Used to throw "Diese Person gehört nicht zu deiner Dynastie !"
      // because anna.dynasty (1) != realm.slot (2).
      final result = applyAction(
          state,
          ProposeMarriage(slot: 2, proposerId: anna.id, targetId: groom.id),
          Rng(1));
      expect(result.state.realm(2).proposedMarriageThisTurn, isTrue);
    });

    test('she may marry a commoner from the inherited slot', () {
      final result =
          applyAction(state, MarryCommoner(slot: 2, personId: anna.id), Rng(1));
      expect(result.state.persons[anna.id]!.spouseId, isNotNull);
    });

    test('members of the slot\'s own house stay marriageable too', () {
      final localPrince = Person(
          id: state.nextPersonId++,
          name: 'Lokalprinz',
          age: 20,
          dynasty: 2,
          gender: 0);
      state.persons[localPrince.id] = localPrince;
      state.dynasty(2).memberIds.add(localPrince.id);

      final result = applyAction(
          state, MarryCommoner(slot: 2, personId: localPrince.id), Rng(1));
      expect(result.state.persons[localPrince.id]!.spouseId, isNotNull);
    });
  });

  group('pending decisions follow the player across their slots', () {
    test('visibleStateFor keeps same-player decisions, drops foreign ones', () {
      final state = _game(humanSlots: const [1, 2]);
      // Player 1 also controls slot 3 (cross-dynasty inheritance).
      state.dynasty(3).status = DynastyStatus.human;
      state.dynasty(3).humanPlayer = state.dynasty(1).humanPlayer;
      state.pendingDecisions.addAll([
        PendingDecision(id: 'own-home', type: 'heirChoice', decidingSlot: 1),
        PendingDecision(id: 'other-player', type: 'childName', decidingSlot: 2),
      ]);

      final viewFromInherited = visibleStateFor(state, 3);
      expect(viewFromInherited.pendingDecisions.map((d) => d.id), ['own-home'],
          reason: "player 1's decision surfaces at their inherited slot; "
              "player 2's stays hidden");

      final viewPlayer2 = visibleStateFor(state, 2);
      expect(viewPlayer2.pendingDecisions.map((d) => d.id), ['other-player']);
    });
  });
}
