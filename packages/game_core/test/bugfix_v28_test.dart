import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Regression tests for the 0.1.13 features (user feedback 2026-07):
/// escalating war-declaration popularity penalty with the lower war floor
/// and its peace-year decay, the cumulative war tally + end-of-war
/// summary, the human-vs-human `warDefense` delegation, and the
/// `suggestChildNames` game option.
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

/// Gives [slot] a standing army and marks [a]/[b] as border neighbors by
/// bridging tiles if needed — war declarations require troops + a shared
/// border.
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
  // Claim a free tile next to a's land for b to create a shared border.
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

/// Answers both warPlan decisions (live control) and runs the start rules
/// — the hot-seat path, where a both-live war begins immediately.
void _completePrep(GameState state) {
  for (final d in [
    ...state.pendingDecisions.where((d) => d.type == 'warPlan')
  ]) {
    applyActionInPlace(
        state,
        ResolveDecision(
            slot: d.decidingSlot, decisionId: d.id, choice: {'auto': false}),
        Rng(1));
  }
  resolveWarPreparation(state, Rng(1), <GameEvent>[]);
}

void main() {
  group('escalating war-declaration penalty (0.1.13)', () {
    test('successive wars cost −5, −10, −15 and can cross the strife line', () {
      var state = _game();
      _prepareWar(state, 1, 2);
      state.realm(1).popularity = 50;

      int declare(GameState s, int target) {
        s = applyAction(s, DeclareWar(slot: 1, targetSlot: target), Rng(1))
            .state;
        // End the fresh war immediately (white peace) so the next
        // declaration is legal again.
        s.activeWar = null;
        s.realm(1).warThisYear = false;
        s.realm(target).warThisYear = false;
        state = s;
        return s.realm(1).popularity;
      }

      _prepareWar(state, 1, 2);
      expect(declare(state, 2), 45, reason: '1st war: −5');
      _prepareWar(state, 1, 2);
      expect(declare(state, 2), 35, reason: '2nd war: −10');
      _prepareWar(state, 1, 2);
      expect(declare(state, 2), 20, reason: '3rd war: −15');
      _prepareWar(state, 1, 2);
      expect(declare(state, 2), 10,
          reason: '4th war: −20 floored at the war floor (10) — '
              'below the §19.1 strife line');
    });

    test('war weariness decays by one per war-free year', () {
      final state = _game(humanSlots: const []);
      state.realm(1).recentWars = 2;
      state.realm(1).warThisYear = false;
      // Complete the LAST slot's turn so control wraps and the year rolls.
      state.currentPlayer = World.realmCount;
      final next = completeTurn(state, Rng(3)).state;
      expect(next.year, state.year + 1);
      expect(next.realm(1).recentWars, 1);
    });
  });

  group('war tally & end-of-war summary (0.1.13)', () {
    test('battles feed the tally; peace carries the summary payload', () {
      // Two humans: the AI-peace pass in endWarRound would overwrite an AI
      // side's wantsPeace flag and dodge the mutual-peace ending.
      final state = _game(humanSlots: const [1, 2]);
      _prepareWar(state, 1, 2);
      final war = startWar(state, 1, 2, Rng(1));
      _completePrep(state);

      final a = state.realm(1).troops.first;
      final b = state.realm(2).troops.first;
      resolveCombat(state, 1, a, 2, b, Rng(5));

      expect(war.battles, 1);
      expect(war.attackerMenLost + war.defenderMenLost, greaterThan(0));

      // Mutual peace ends the war — the event must carry the tally,
      // because the war state (and with it the numbers) is cleared.
      war.attackerWantsPeace = true;
      war.defenderWantsPeace = true;
      final events = <GameEvent>[];
      endWarRound(state, Rng(5), events);
      final peace = events.singleWhere((e) => e.type == 'peaceAgreed');
      final summary = (peace.payload['summary'] as Map).cast<String, dynamic>();
      expect(summary['battles'], 1);
      expect(summary['attackerSlot'], 1);
      expect(state.activeWar, isNull);
    });
  });

  group('war preparation & delegation (0.1.13)', () {
    PendingDecision planOf(GameState state, int slot) => state.pendingDecisions
        .singleWhere((d) => d.type == 'warPlan' && d.decidingSlot == slot);

    test('a human-vs-human war opens the preparation window for both sides',
        () {
      final state = _game(humanSlots: const [1, 2]);
      _prepareWar(state, 1, 2);
      final war = startWar(state, 1, 2, Rng(1));

      expect(war.phase, WarPhase.preparation);
      expect(warActingSlot(state), 1,
          reason: 'the attacker owes the first warPlan answer');

      // Attacker plays live — still waiting for the defender's answer.
      applyActionInPlace(
          state,
          ResolveDecision(
              slot: 1,
              decisionId: planOf(state, 1).id,
              choice: {'auto': false}),
          Rng(1));
      resolveWarPreparation(state, Rng(1), <GameEvent>[]);
      expect(war.phase, WarPhase.preparation);
      expect(warActingSlot(state), 2);

      // Defender lines up each unit INDIVIDUALLY during the preparation
      // (user rule 2026-07-13 — the bulk 'stance' answer is gone), then
      // delegates: exactly one live side — the war starts at once, the
      // delegated side is autopiloted.
      for (var i = 0; i < state.realm(2).troops.length; i++) {
        applyActionInPlace(state,
            SetTroopStance(slot: 2, unitIndex: i, stance: TroopStance.attack),
            Rng(1));
      }
      applyActionInPlace(
          state,
          ResolveDecision(
              slot: 2, decisionId: planOf(state, 2).id, choice: {'auto': true}),
          Rng(1));
      resolveWarPreparation(state, Rng(1), <GameEvent>[]);
      expect(war.phase, WarPhase.rounds);
      expect(war.autoSlots, contains(2));
      expect(state.realm(2).troops.every((t) => t.stance == TroopStance.attack),
          isTrue,
          reason: 'per-unit stance orders set in the preparation survive');
      expect(warActingSlot(state), 1);
      expect(handWarRoundOver(state, 1), isFalse,
          reason: 'a delegated defender takes no handover');
      final round = war.round;
      endWarRoundFor(state, 1, Rng(5), <GameEvent>[]);
      expect(state.activeWar!.round, round + 1,
          reason: 'the attacker\'s round end autopilots the defender');
    });

    test('both live: the online rule waits for the deadline (force)', () {
      final state = _game(humanSlots: const [1, 2]);
      _prepareWar(state, 1, 2);
      final war = startWar(state, 1, 2, Rng(1));
      for (final slot in [1, 2]) {
        applyActionInPlace(
            state,
            ResolveDecision(
                slot: slot,
                decisionId: planOf(state, slot).id,
                choice: {'auto': false}),
            Rng(1));
      }
      // Online (turn timer set): a both-live duel waits for the deadline.
      resolveWarPreparation(state, Rng(1), <GameEvent>[],
          waitWhenAllManual: true);
      expect(war.phase, WarPhase.preparation);
      // The deadline (sweep) forces the fair, simultaneous start.
      resolveWarPreparation(state, Rng(1), <GameEvent>[], force: true);
      expect(war.phase, WarPhase.rounds);
      expect(war.autoSlots, isEmpty);
    });

    test('both delegated (or unanswered at the deadline): fast-forward', () {
      final state = _game(humanSlots: const [1, 2]);
      _prepareWar(state, 1, 2);
      startWar(state, 1, 2, Rng(1));
      // Nobody answers; the deadline defaults both to the autopilot and
      // the whole war plays out like an AI-vs-AI war.
      final events = <GameEvent>[];
      resolveWarPreparation(state, Rng(1), events, force: true);
      expect(state.activeWar, isNull,
          reason: 'a fully delegated war fast-forwards to its end');
      expect(
          events.any((e) =>
              e.type == 'warWon' ||
              e.type == 'warDraw' ||
              e.type == 'peaceAgreed' ||
              e.type == 'winterEndsWar'),
          isTrue);
    });

    test('no preparation window against an AI side', () {
      final state = _game(humanSlots: const [1]);
      _prepareWar(state, 1, 2);
      final war = startWar(state, 1, 2, Rng(1));
      expect(war.phase, WarPhase.rounds);
      expect(state.pendingDecisions.where((d) => d.type == 'warPlan'), isEmpty);
    });
  });

  group('pending marriage consent protects the couple (0.1.13)', () {
    test('neither side of a pending consent is auto-matched or re-proposed',
        () {
      final state = _game(humanSlots: const [1, 2]);
      final proposer = state.person(state.realm(1).rulerId)!;
      final target = state.person(state.realm(2).rulerId)!;
      proposer.age = 20;
      target.age = 20;
      state.pendingDecisions.add(PendingDecision(
        id: 'marriage-test',
        type: 'marriageConsent',
        decidingSlot: 2,
        payload: {'proposerId': proposer.id, 'targetId': target.id},
      ));

      expect(awaitingMarriageConsent(state, proposer.id), isTrue);
      expect(awaitingMarriageConsent(state, target.id), isTrue);
      // The annual loop must never marry them off in the meantime (the
      // online "accepted but rejected" bug).
      for (var i = 0; i < 40; i++) {
        runDynastyPhase(state, 1, Rng(i), <GameEvent>[]);
        runDynastyPhase(state, 2, Rng(i), <GameEvent>[]);
      }
      expect(state.persons[proposer.id]!.spouseId, isNull);
      expect(state.persons[target.id]!.spouseId, isNull);

      // No commoner sidestep and no second proposal while the answer is
      // out.
      expect(
          () => applyAction(
              state, MarryCommoner(slot: 1, personId: proposer.id), Rng(1)),
          throwsA(isA<ActionException>()));

      // Accepting still works and marries the couple.
      final result = applyAction(
          state,
          ResolveDecision(
              slot: 2, decisionId: 'marriage-test', choice: {'accept': true}),
          Rng(1));
      expect(result.state.persons[proposer.id]!.spouseId, target.id);
    });

    test('an accepted-but-decayed consent reports "invalid", not "declined"',
        () {
      final state = _game(humanSlots: const [1, 2]);
      final proposer = state.person(state.realm(1).rulerId)!;
      final target = state.person(state.realm(2).rulerId)!;
      state.pendingDecisions.add(PendingDecision(
        id: 'marriage-stale',
        type: 'marriageConsent',
        decidingSlot: 2,
        payload: {'proposerId': proposer.id, 'targetId': target.id},
      ));
      // The proposer married someone else in the meantime.
      proposer.spouseId = 999;

      final result = applyAction(
          state,
          ResolveDecision(
              slot: 2, decisionId: 'marriage-stale', choice: {'accept': true}),
          Rng(1));
      final rejected =
          result.events.singleWhere((e) => e.type == 'marriageRejected');
      expect(rejected.payload['reason'], 'invalid');
    });
  });

  group('manual crown-pot collection (0.1.13)', () {
    test('the pot stays until CollectTribute; only the office holder may', () {
      final state = _game();
      state.kaiserId = state.realm(1).rulerId;
      state.kaiserPot = 700;

      // Upkeep no longer pays it out.
      runEconomy(state, state.realm(1), Rng(1));
      expect(state.kaiserPot, 700);

      expect(() => applyAction(state, CollectTribute(slot: 2), Rng(1)),
          throwsA(isA<ActionException>()));

      final before = state.realm(1).treasury;
      final result = applyAction(state, CollectTribute(slot: 1), Rng(1));
      expect(result.state.realm(1).treasury, before + 700);
      expect(result.state.kaiserPot, 0);
    });
  });

  group('batched settlement annex (0.1.13)', () {
    test('SettlementAnnexMany annexes the tiles atomically', () {
      final state = _game(humanSlots: const [1, 2]);
      _prepareWar(state, 1, 2);
      final war = startWar(state, 1, 2, Rng(1));
      war.phase = WarPhase.settlement;
      war.winnerSlot = 1;
      war.remainingClaim = 10000;
      war.actingSlot = 1;

      // Loser tiles bordering the winner's land, in sweep order.
      final map = state.map;
      final tiles = <({int x, int y})>[];
      for (var y = 0; y < map.height && tiles.length < 2; y++) {
        for (var x = 0; x < map.width && tiles.length < 2; x++) {
          if (map.ownerAt(x, y) != 2) continue;
          for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
            if (map.inBounds(x + dx, y + dy) &&
                map.ownerAt(x + dx, y + dy) == 1) {
              tiles.add((x: x, y: y));
              break;
            }
          }
        }
      }
      expect(tiles, isNotEmpty);

      final result = applyAction(
          state, SettlementAnnexMany(slot: 1, tiles: tiles), Rng(1));
      for (final t in tiles) {
        expect(result.state.map.ownerAt(t.x, t.y), 1);
      }
      expect(result.state.activeWar!.remainingClaim, lessThan(10000));

      // Atomic: a batch with an invalid tile changes nothing.
      expect(
          () => applyAction(
              state,
              SettlementAnnexMany(slot: 1, tiles: [
                ...tiles,
                (x: state.realm(1).capitalX, y: state.realm(1).capitalY),
              ]),
              Rng(1)),
          throwsA(isA<ActionException>()));
      expect(state.map.ownerAt(tiles.first.x, tiles.first.y), 2,
          reason: 'the original state is untouched');
    });
  });

  group('suggestChildNames option (0.1.13)', () {
    test('round-trips through JSON and defaults to true for old saves', () {
      final state = _game();
      expect(state.suggestChildNames, isTrue);
      final json = state.toJson()..remove('suggestChildNames');
      expect(GameState.fromJson(json).suggestChildNames, isTrue,
          reason: 'old saves keep the prefilled suggestion');

      final off = newGame(GameSetup(
        humans: const [],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 1,
        suggestChildNames: false,
      ));
      expect(GameState.fromJson(off.toJson()).suggestChildNames, isFalse);
    });
  });
}
