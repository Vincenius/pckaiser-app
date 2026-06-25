import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

GameState freshGame({int seed = 2026, List<int> humanSlots = const [1]}) =>
    newGame(GameSetup(
      humans: [
        for (var i = 0; i < humanSlots.length; i++)
          HumanPlayerSetup(
            founderName: 'Mensch$i',
            gender: 0,
            countrySlot: humanSlots[i],
            dorfName: 'Stadt$i',
          ),
      ],
      reformationYear: 1020,
      ottomanYear: 1040,
      seed: seed,
    ));

void main() {
  group('births (§15.3)', () {
    test('no children without marriage — phantom births are removed', () {
      for (var seed = 0; seed < 50; seed++) {
        final state = startGame(freshGame(seed: 2026), Rng(1)).state;
        // Leave slot 1's unmarried founder alone in the world: no
        // marriage candidate can exist, so no birth may ever fire.
        final founderId = state.dynasty(1).memberIds.single;
        state.persons.removeWhere((id, _) => id != founderId);
        final events = <GameEvent>[];
        runDynastyPhase(state, 1, Rng(seed), events);
        expect(events.where((e) => e.type == 'birth'), isEmpty,
            reason: 'seed $seed produced a child without parents');
        expect(state.persons[founderId]!.spouseId, isNull);
      }
    });
  });

  group('marriage fallback (§14.3): AI weds a commoner when no royal partner', () {
    test('an isolated AI member weds a commoner so the line survives', () {
      // All-AI game: slot 1's founder is computer-controlled, not the player.
      final state = startGame(freshGame(humanSlots: const []), Rng(1)).state;
      expect(state.dynasty(1).status, DynastyStatus.ai);
      // Strip every other person so findMarriageCandidate can never succeed —
      // the only path left to continue the line is the commoner fallback.
      final founderId = state.dynasty(1).memberIds.single;
      state.persons.removeWhere((id, _) => id != founderId);
      final founder = state.persons[founderId]!;
      expect(founder.spouseId, isNull);

      // Year stays in the 1000–1009 protection window so nobody dies before
      // the throttled (~25%/turn) marriage roll lands.
      final rng = Rng(7);
      for (var i = 0; i < 60 && founder.spouseId == null; i++) {
        runDynastyPhase(state, 1, rng, <GameEvent>[]);
      }

      expect(founder.spouseId, isNotNull,
          reason: 'an AI member with no royal partner should wed a commoner');
      final spouse = state.persons[founder.spouseId!]!;
      expect(spouse.dynasty, 1, reason: 'the commoner joins the dynasty');
      expect(spouse.gender, isNot(founder.gender));
      expect(state.dynasty(1).memberIds, contains(spouse.id));
      expect(spouse.age, greaterThanOrEqualTo(14));
      expect((spouse.age - founder.age).abs(), lessThan(10),
          reason: '§14.1 age gap holds for the commoner too');
    });

    test('a human member is NOT auto-wed to a commoner (the player chooses)',
        () {
      final state = startGame(freshGame(humanSlots: const [1]), Rng(1)).state;
      expect(state.dynasty(1).status, DynastyStatus.human);
      final founderId = state.dynasty(1).memberIds.single;
      state.persons.removeWhere((id, _) => id != founderId);

      final rng = Rng(7);
      for (var i = 0; i < 60; i++) {
        runDynastyPhase(state, 1, rng, <GameEvent>[]);
      }
      expect(state.persons[founderId]!.spouseId, isNull,
          reason: 'humans keep the explicit "Bürgerlich heiraten" choice');
      expect(state.dynasty(1).memberIds, [founderId],
          reason: 'no commoner was injected into the human line');
    });
  });

  group('aging & death (§15.1)', () {
    test('protection window suppresses death rolls but not aging', () {
      final state = startGame(freshGame(), Rng(1)).state;
      expect(state.year, 1000);
      for (final realm in state.realms) {
        final ruler = state.person(realm.rulerId)!;
        ruler.age = 89; // would be certain death without protection
      }
      final events = <GameEvent>[];
      runDynastyPhase(state, 1, Rng(5), events);
      expect(state.realm(1).rulerId, isNotNull);
      expect(state.person(state.realm(1).rulerId)!.age, 90);
      expect(events.where((e) => e.type == 'personDied'), isEmpty);
    });

    test('after the window, the elderly certainly die and heirs succeed', () {
      final state = startGame(freshGame(), Rng(1)).state;
      state.year = 1010;
      final dynasty = state.dynasty(1);
      final ruler = state.person(state.realm(1).rulerId)!;
      ruler.age = 89;
      final son = Person(
          id: state.nextPersonId++,
          name: 'Erbprinz',
          age: 20,
          dynasty: 1,
          gender: 0);
      state.persons[son.id] = son;
      dynasty.memberIds.add(son.id);
      ruler.childrenIds.add(son.id);

      final events = <GameEvent>[];
      runDynastyPhase(state, 1, Rng(5), events);

      expect(state.persons.containsKey(ruler.id), isFalse);
      expect(state.realm(1).rulerId, son.id,
          reason: 'first male child inherits');
      expect(events.any((e) => e.type == 'personDied'), isTrue);
      expect(events.any((e) => e.type == 'succession'), isTrue);
      // Human dynasty with >1 member would offer a menu — only one member
      // remains here, so no decision is queued.
      expect(
          state.pendingDecisions.where((d) => d.type == 'heirChoice'), isEmpty);
    });
  });

  group('succession priority (§15.4)', () {
    test('spouse from another dynasty inherits when no members remain', () {
      final state = startGame(freshGame(), Rng(1)).state;
      state.year = 1010;
      final ruler = state.person(state.realm(1).rulerId)!;
      final foreignSpouse = state.person(state.realm(2).rulerId)!;
      ruler.spouseId = foreignSpouse.id;
      foreignSpouse.spouseId = ruler.id;

      final events = <GameEvent>[];
      handleDeath(state, ruler, Rng(5), events);

      expect(state.realm(1).rulerId, foreignSpouse.id,
          reason: 'peaceful inheritance path across dynasties');
      // D1: control follows the inheriting ruler — slot 1 was human, the
      // spouse's dynasty (slot 2) is AI, so slot 1 is now AI-dispatched.
      expect(state.dynasty(1).status, state.dynasty(2).status);
      expect(state.dynasty(1).humanPlayer, state.dynasty(2).humanPlayer);
      // The gaining house is told prominently (client popup).
      final inherited = events.singleWhere((e) => e.type == 'realmInherited');
      expect(inherited.slot, 2);
      expect((inherited.payload['slots'] as List).cast<int>(), [1]);
    });

    test('ruler aliasing: the heir takes ALL the deceased\'s slots', () {
      final state = startGame(freshGame(), Rng(1)).state;
      state.year = 1010;
      final ruler = state.person(state.realm(1).rulerId)!;
      state.realm(5).rulerId = ruler.id; // conquered earlier
      state.realm(9).rulerId = ruler.id;
      final son = Person(
          id: state.nextPersonId++,
          name: 'Erbe',
          age: 18,
          dynasty: 1,
          gender: 0);
      state.persons[son.id] = son;
      state.dynasty(1).memberIds.add(son.id);
      ruler.childrenIds.add(son.id);

      handleDeath(state, ruler, Rng(5), []);

      expect(state.realm(1).rulerId, son.id);
      expect(state.realm(5).rulerId, son.id);
      expect(state.realm(9).rulerId, son.id);
    });

    test('extinct AI dynasty passes everything to a random living ruler', () {
      final state = startGame(freshGame(), Rng(1)).state;
      state.year = 1010;
      final ruler = state.person(state.realm(2).rulerId)!;
      final events = <GameEvent>[];
      handleDeath(state, ruler, Rng(5), events);
      final newRuler = state.realm(2).rulerId;
      expect(newRuler, isNotNull);
      expect(newRuler, isNot(ruler.id));
      expect(state.persons.containsKey(newRuler), isTrue);
      // The inheriting house is told prominently (client popup).
      final inherited = events.singleWhere((e) => e.type == 'realmInherited');
      expect(inherited.slot, state.persons[newRuler]!.dynasty);
      expect((inherited.payload['slots'] as List).cast<int>(), [2]);
    });

    test('Islamic succession crisis flips a human dynasty to AI (§15.5)', () {
      final state = startGame(freshGame(), Rng(1)).state;
      state.year = 1041;
      final dynasty = state.dynasty(1);
      dynasty.religion = Religion.moslemisch;
      final ruler = state.person(state.realm(1).rulerId)!;
      final daughter = Person(
          id: state.nextPersonId++,
          name: 'Fatima',
          age: 16,
          dynasty: 1,
          gender: 1);
      state.persons[daughter.id] = daughter;
      dynasty.memberIds.add(daughter.id);
      ruler.childrenIds.add(daughter.id);

      final events = <GameEvent>[];
      handleDeath(state, ruler, Rng(5), events);

      expect(dynasty.status, DynastyStatus.ai);
      expect(dynasty.humanPlayer, isNull);
      expect(state.realm(1).rulerId, daughter.id);
      expect(events.any((e) => e.type == 'islamicSuccessionCrisis'), isTrue);
    });
  });

  group('marriage (§14)', () {
    test(
        'proposal to a human dynasty queues a consent decision; accepting '
        'marries the couple and merges children into the husband', () {
      final state = startGame(freshGame(humanSlots: [1, 2]), Rng(1)).state;
      final groom = state.person(state.realm(2).rulerId)!;
      final bride = Person(
          id: state.nextPersonId++,
          name: 'Braut',
          age: groom.age,
          dynasty: 1,
          gender: 1);
      state.persons[bride.id] = bride;
      state.dynasty(1).memberIds.add(bride.id);
      final brideChild = Person(
          id: state.nextPersonId++,
          name: 'Kind',
          age: 1,
          dynasty: 1,
          gender: 0);
      state.persons[brideChild.id] = brideChild;
      state.dynasty(1).memberIds.add(brideChild.id);
      bride.childrenIds.add(brideChild.id);

      var result = applyAction(
          state,
          ProposeMarriage(slot: 2, proposerId: groom.id, targetId: bride.id),
          Rng(state.rngSeed));
      final decision = result.state.pendingDecisions
          .singleWhere((d) => d.type == 'marriageConsent');
      expect(decision.decidingSlot, 1);

      result = applyAction(
          result.state,
          ResolveDecision(
              slot: 1, decisionId: decision.id, choice: {'accept': true}),
          Rng(result.state.rngSeed));

      final marriedGroom = result.state.persons[groom.id]!;
      final marriedBride = result.state.persons[bride.id]!;
      expect(marriedGroom.spouseId, bride.id);
      expect(marriedBride.spouseId, groom.id);
      expect(marriedGroom.childrenIds, contains(brideChild.id),
          reason: 'children merge into the husband');
      expect(marriedBride.childrenIds, isEmpty);
      expect(result.events.any((e) => e.type == 'wedding'), isTrue);
    });

    test('rejects ineligible proposals (same religion rule etc.)', () {
      final state = startGame(freshGame(), Rng(1)).state;
      final a = state.person(state.realm(1).rulerId)!;
      final b = state.person(state.realm(2).rulerId)!;
      // Same gender (both founders could be any gender — force it).
      expect(
        () => applyAction(
            state,
            ProposeMarriage(
                slot: 1,
                proposerId: a.id,
                targetId: a.gender == b.gender
                    ? b.id
                    : a.id), // same person → same gender
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
      );
    });

    test('religious conversion divorces incompatible couples (§14.4)', () {
      final state = startGame(freshGame(), Rng(1)).state;
      state.year = 1021;
      final a = state.person(state.realm(1).rulerId)!;
      final b = state.person(state.realm(2).rulerId)!;
      a.spouseId = b.id;
      b.spouseId = a.id;
      final result = applyAction(
          state,
          ChangeReligion(slot: 1, religion: Religion.evangelisch),
          Rng(state.rngSeed));
      expect(result.state.persons[a.id]!.spouseId, isNull);
      expect(result.state.persons[b.id]!.spouseId, isNull);
      expect(result.events.any((e) => e.type == 'divorce'), isTrue);
    });

    test('births add children and queue a naming decision for humans', () {
      final state = startGame(freshGame(), Rng(1)).state;
      final husband = state.person(state.realm(1).rulerId)!;
      final wife = Person(
          id: state.nextPersonId++,
          name: 'Gemahlin',
          age: husband.age,
          dynasty: 1,
          gender: 1);
      state.persons[wife.id] = wife;
      state.dynasty(1).memberIds.add(wife.id);
      husband.spouseId = wife.id;
      wife.spouseId = husband.id;

      // The birth throttle is random(4) == 0 — try seeds until it fires.
      // A human dynasty defers the public 'birth' event until the child is
      // named, so detect the birth via the queued childName decision.
      var born = false;
      for (var seed = 0; seed < 40 && !born; seed++) {
        final trial = state.copy();
        final events = <GameEvent>[];
        runDynastyPhase(trial, 1, Rng(seed), events);
        if (trial.pendingDecisions.any((d) => d.type == 'childName')) {
          born = true;
          final child =
              trial.persons[trial.persons[husband.id]!.childrenIds.single]!;
          expect(child.age, 0, reason: 'original age bug fixed');
          expect(child.dynasty, 1);
          expect(trial.persons[wife.id]!.childrenIds, contains(child.id));
          expect(events.any((e) => e.type == 'birth'), isFalse,
              reason: 'human births announce only after naming');
        }
      }
      expect(born, isTrue, reason: 'birth should fire within 40 seeds');
    });
  });

  group('titles (§16.2)', () {
    test('prestige score formula and promotion thresholds', () {
      final state = startGame(freshGame(), Rng(1)).state;
      final realm = state.realm(1);
      // Starting realm: 1 Burg → 10,000 + treasury + pop + 10×popularity.
      expect(
          prestigeScore(realm),
          realm.population +
              realm.treasury +
              10 * realm.popularity +
              10000 +
              1000 * realm.tileCount[Building.hafen]);

      realm.treasury = 100000;
      final events = <GameEvent>[];
      checkTitlePromotion(state, realm, events);
      expect(realm.titleClass, 8, reason: 'straight to König');
      expect(events.single.type, 'titlePromoted');

      // Never demote.
      realm.treasury = 0;
      checkTitlePromotion(state, realm, events);
      expect(realm.titleClass, 8);
    });

    test('Muslim ladder uses its own thresholds', () {
      final state = startGame(freshGame(), Rng(1)).state;
      final realm = state.realm(2);
      state.dynasty(2).religion = Religion.moslemisch;
      realm.titleClass = 9;
      realm.treasury = 60000; // ≥ 50k → Emir, < 80k Kalif
      checkTitlePromotion(state, realm, []);
      expect(realm.titleClass, 11);
    });
  });

  group('heirChoice resilience', () {
    test(
        'a human ruler death offers the heir menu, and the chosen heir '
        'is crowned', () {
      final state = startGame(freshGame(), Rng(1)).state;
      state.year = 1010;
      final dynasty = state.dynasty(1);
      final ruler = state.person(state.realm(1).rulerId)!;
      final son = Person(
          id: state.nextPersonId++,
          name: 'Sohn',
          age: 20,
          dynasty: 1,
          gender: 0);
      final daughter = Person(
          id: state.nextPersonId++,
          name: 'Tochter',
          age: 18,
          dynasty: 1,
          gender: 1);
      for (final p in [son, daughter]) {
        state.persons[p.id] = p;
        dynasty.memberIds.add(p.id);
        ruler.childrenIds.add(p.id);
      }

      final events = <GameEvent>[];
      handleDeath(state, ruler, Rng(5), events);

      // The §15.4 priority heir is crowned provisionally right away…
      expect(state.realm(1).rulerId, son.id);
      // …and the human player gets the menu with every member.
      final decision =
          state.pendingDecisions.singleWhere((d) => d.type == 'heirChoice');
      expect(decision.decidingSlot, 1);
      expect((decision.payload['candidateIds'] as List).cast<int>(),
          containsAll([son.id, daughter.id]));

      // The player picks the daughter instead — she is re-crowned.
      final result = applyAction(
          state,
          ResolveDecision(
              slot: 1,
              decisionId: decision.id,
              choice: {'heirId': daughter.id}),
          Rng(state.rngSeed));
      expect(result.state.realm(1).rulerId, daughter.id);
      expect(result.state.pendingDecisions, isEmpty);
    });

    test(
        'choosing an heir who died in the meantime keeps the provisional '
        'heir without throwing', () {
      final state = startGame(freshGame(), Rng(1)).state;
      final provisional = state.realm(1).rulerId!;
      state.pendingDecisions.add(PendingDecision(
        id: 'heir-test',
        type: 'heirChoice',
        decidingSlot: 1,
        payload: {
          'deceasedName': 'Tot',
          'candidateIds': [99999],
          'provisionalHeirId': provisional,
          'slots': [1],
        },
      ));
      final result = applyAction(
          state,
          ResolveDecision(
              slot: 1, decisionId: 'heir-test', choice: {'heirId': 99999}),
          Rng(state.rngSeed));
      expect(result.state.pendingDecisions, isEmpty,
          reason: 'consumed without throwing');
      expect(result.state.realm(1).rulerId, provisional);
    });
  });
}
