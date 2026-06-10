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
  group('Kurfürsten (§17.2)', () {
    test('seven seats fill with eligible rulers, highest title first', () {
      final state = startGame(freshGame(), Rng(1)).state;
      state.kurfuerstenIds.clear(); // startGame already filled the seats
      state.realm(5).titleClass = 8; // a König among Ritter
      final events = <GameEvent>[];
      refillKurfuersten(state, Rng(2), events);
      expect(state.kurfuerstenIds, hasLength(7));
      expect(state.kurfuerstenIds.first, state.realm(5).rulerId,
          reason: 'highest titleClass takes the first seat');
      expect(events.where((e) => e.type == 'newKurfuerst'), hasLength(7));
      // No duplicates.
      expect(state.kurfuerstenIds.toSet(), hasLength(7));
    });

    test('female and Muslim rulers are not eligible', () {
      final state = startGame(freshGame(), Rng(1)).state;
      state.kurfuerstenIds.clear();
      // Make everyone ineligible except two slots.
      for (var slot = 3; slot <= 30; slot++) {
        state.realm(slot).rulerId = null;
      }
      state.persons[state.realm(1).rulerId]!; // male, stays eligible
      state.dynasty(2).religion = Religion.moslemisch;
      refillKurfuersten(state, Rng(2), []);
      expect(state.kurfuerstenIds, [state.realm(1).rulerId]);
    });
  });

  group('Kaiser election (§17.3)', () {
    test('an all-AI election crowns a Kaiser with chronicle record', () {
      var state = startGame(freshGame(), Rng(1)).state;
      // Convert the only human realm to AI so the election self-resolves.
      state.dynasty(1).status = DynastyStatus.ai;
      state.dynasty(1).humanPlayer = null;
      state.year = 1009; // next wrap = 1010, the first election year

      // Play a full round so the world phase runs at the wrap.
      for (var i = 0; i < 30; i++) {
        state = completeTurn(state, Rng(state.rngSeed)).state;
      }
      expect(state.year, 1010);
      expect(state.kaiserId, isNotNull, reason: 'Kaiser elected at wrap');
      expect(state.kaiserChronicle, hasLength(1));
      expect(state.kaiserChronicle.single.accessionYear, 1010);
      expect(state.kaiserChronicle.single.deathYear, isNull);
      expect(state.activeElection, isNull);
      expect(
          state.events.any((e) => e.type == 'crowned'), isTrue);
    });

    test('human finalist bribes and human elector votes via decisions', () {
      final state = startGame(freshGame(), Rng(1)).state;
      state.year = 1010;
      // Slot 1 (human) gets a König title → guaranteed finalist.
      state.realm(1).titleClass = 8;
      state.realm(1).treasury = 5000;
      refillKurfuersten(state, Rng(3), []);
      final events = <GameEvent>[];
      maybeStartElection(state, Office.kaiser, Rng(3), events);
      expect(state.activeElection, isNotNull);
      advanceElection(state, Rng(3), events);

      // The human finalist owes a bribery decision.
      final bribe = state.pendingDecisions
          .singleWhere((d) => d.type == 'electionBribe');
      expect(bribe.decidingSlot, 1);
      final finalistId = bribe.payload['finalistId'] as int;
      final electorIds = (bribe.payload['electorIds'] as List).cast<int>();
      final targetElector =
          electorIds.firstWhere((e) => e != finalistId);

      var result = applyAction(
          state,
          ResolveDecision(slot: 1, decisionId: bribe.id, choice: {
            'gifts': [
              {'electorId': targetElector, 'amount': 1000},
            ],
          }),
          Rng(state.rngSeed));
      // 1,000 T spent on bribes; the AI finalist's counter-bribes may
      // land in slot 1's treasury (its ruler is an elector).
      expect(result.state.realm(1).treasury, greaterThanOrEqualTo(4000));

      // Election finishes (AI finalist bribes + all-AI electors vote,
      // except the human finalist who votes for themself automatically).
      final s = result.state;
      expect(s.activeElection, isNull);
      expect(s.kaiserId, isNotNull);
    });

    test('the election waits while a human elector has not voted', () {
      final state = startGame(freshGame(humanSlots: [1, 2]), Rng(1)).state;
      state.year = 1010;
      state.realm(3).titleClass = 8; // two AI finalists
      state.realm(4).titleClass = 8;
      // Deterministic college: both human rulers hold seats.
      state.kurfuerstenIds
        ..clear()
        ..addAll([
          state.realm(1).rulerId!,
          state.realm(2).rulerId!,
          state.realm(3).rulerId!,
          state.realm(4).rulerId!,
        ]);

      final events = <GameEvent>[];
      maybeStartElection(state, Office.kaiser, Rng(3), events);
      advanceElection(state, Rng(3), events);

      // AI finalists bribed instantly; human electors (slots 1 & 2) hold
      // the result open.
      expect(state.kaiserId, isNull);
      final votes = state.pendingDecisions
          .where((d) => d.type == 'electorVote')
          .toList();
      expect(votes, hasLength(2));
      expect(state.activeElection, isNotNull);

      var s = state;
      for (final vote in votes) {
        final finalists =
            (vote.payload['finalistIds'] as List).cast<int>();
        s = applyAction(
                s,
                ResolveDecision(
                    slot: vote.decidingSlot,
                    decisionId: vote.id,
                    choice: {'finalistId': finalists.first}),
                Rng(s.rngSeed))
            .state;
      }
      expect(s.activeElection, isNull);
      expect(s.kaiserId, isNotNull);
    });
  });

  group('chronicle & epithets (§17.5)', () {
    test('a Kaiser dying in office closes the record, maybe with epithet',
        () {
      final state = startGame(freshGame(), Rng(1)).state;
      state.year = 1010;
      final kaiser = state.person(state.realm(2).rulerId)!;
      state.kaiserId = kaiser.id;
      state.kaiserChronicle.add(
          ChronicleRecord(name: kaiser.name, accessionYear: 1005));

      handleDeath(state, kaiser, Rng(4), []);

      expect(state.kaiserId, isNull);
      final record = state.kaiserChronicle.single;
      expect(record.deathYear, 1010);
      // Epithet is a 50% roll — whichever way, it must come from a pool.
      if (record.epithet != null) {
        expect(
            epithetPools.any((p) => p.contains(record.epithet)), isTrue);
      }
    });

    test('epithet pool selection follows the reign × weight matrix', () {
      // Find a seed where the epithet fires for a long, popular reign.
      for (var seed = 0; seed < 20; seed++) {
        final state = startGame(freshGame(), Rng(1)).state;
        state.year = 1030;
        final kaiser = state.person(state.realm(2).rulerId)!;
        state.kaiserId = kaiser.id;
        state.realm(2).popularity = 90;
        state.kaiserChronicle.add(
            ChronicleRecord(name: kaiser.name, accessionYear: 1010));
        closeChronicleIfOfficeHolder(state, kaiser, Rng(seed), []);
        final epithet = state.kaiserChronicle.single.epithet;
        if (epithet != null) {
          expect(epithetPools[0], contains(epithet),
              reason: 'reign 20 y × weight 90 → pool 1');
          return;
        }
      }
      fail('epithet never fired in 20 seeds');
    });
  });

  group('pending decisions hygiene', () {
    test('resolving a foreign decision is rejected', () {
      final state = startGame(freshGame(humanSlots: [1, 2]), Rng(1)).state;
      state.pendingDecisions.add(PendingDecision(
          id: 'd1', type: 'childName', decidingSlot: 2, payload: const {}));
      expect(
        () => applyAction(
            state,
            ResolveDecision(slot: 1, decisionId: 'd1'),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
      );
    });

    test('childName renames the child', () {
      final state = startGame(freshGame(), Rng(1)).state;
      final child = Person(
          id: state.nextPersonId++,
          name: 'Platzhalter',
          age: 0,
          dynasty: 1,
          gender: 0);
      state.persons[child.id] = child;
      state.dynasty(1).memberIds.add(child.id);
      state.pendingDecisions.add(PendingDecision(
          id: 'cn1',
          type: 'childName',
          decidingSlot: 1,
          payload: {'childId': child.id}));
      final result = applyAction(
          state,
          ResolveDecision(
              slot: 1, decisionId: 'cn1', choice: {'name': ' Otto '}),
          Rng(state.rngSeed));
      expect(result.state.persons[child.id]!.name, 'Otto');
    });
  });

  group('election state JSON', () {
    test('ActiveElection round-trips through the save format', () {
      final election = ActiveElection(
        office: Office.kaiser,
        finalistIds: [3, 9],
        electorIds: [3, 9, 12],
        bribesDone: {3},
        votes: {3: 3},
      )..addBribe(12, 3, 500);
      final restored = ActiveElection.fromJson(election.toJson());
      expect(restored.toJson(), election.toJson());
      expect(restored.bribeFor(12, 3), 500);
    });
  });
}
