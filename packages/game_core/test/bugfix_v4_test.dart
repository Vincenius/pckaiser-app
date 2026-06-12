import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Regression tests for the 2026-06-11 bugfix round: the rules-v4 gates
/// (capture, stacked combat, assassination, merge-at-war, election
/// candidates) and the unversioned integrity fixes (dynasty-replacement
/// cleanup, decision purging, snapshot matching, recap baselines).
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

  /// War-ready state: human slot 1 vs AI slot 2, both with one 50-man
  /// unit, a shared border, year 1010 (mirrors war_test.dart's setup).
  /// Returns the state plus the granted border tile of slot 2.
  (GameState, (int, int)) warState() {
    var state = startGame(
            newGame(GameSetup(
              humans: [
                HumanPlayerSetup(
                    founderName: 'Anna',
                    gender: 1,
                    countrySlot: 1,
                    dorfName: 'A'),
                HumanPlayerSetup(
                    founderName: 'Berta',
                    gender: 1,
                    countrySlot: 2,
                    dorfName: 'B'),
              ],
              reformationYear: 1020,
              ottomanYear: 1040,
              seed: 2026,
            )),
            Rng(7))
        .state;
    state.year = 1010;
    state.dynasty(2).status = DynastyStatus.ai;
    state.dynasty(2).humanPlayer = null;
    for (final slot in [1, 2]) {
      final realm = state.realm(slot);
      realm.treasury = 10000;
      realm.towns.single.troopCapacity = 200;
      realm.troopCapacity = 200;
      state = applyAction(
              state,
              RecruitTroops(
                  slot: slot,
                  men: 50,
                  troopClass: TroopClass.infanterie,
                  name: 'Heer$slot'),
              Rng(state.rngSeed))
          .state;
    }
    final map = state.map;
    (int, int)? border;
    outer:
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) {
          continue;
        }
        for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
          if (map.inBounds(x + dx, y + dy) &&
              map.ownerAt(x + dx, y + dy) == 1) {
            map.owner[map.index(x, y)] = 2;
            state.realm(2).tileCount[Building.none]++;
            border = (x, y);
            break outer;
          }
        }
      }
    }
    expect(state.map.realmNeighbors(1), contains(2));
    return (state, border!);
  }

  group('foundReplacementDynasty integrity (unversioned fix)', () {
    test('bankruptcy of an aliased ruler leaves no dangling pointers', () {
      final state = freshState();
      state.year = 1010;
      final ruler1 = state.realm(1).rulerId!;
      // Ruler aliasing (§19): the slot-1 ruler also rules slot 2 and holds
      // the Kaiser crown plus a Kurfürst seat.
      state.realm(2).rulerId = ruler1;
      alignSlotControl(state, 2, ruler1);
      state.kaiserId = ruler1;
      state.kurfuerstenIds.add(ruler1);
      // Debt far past every §19.2 threshold → replacement dynasty.
      state.realm(1).treasury = -999999;
      state.currentPlayer = 1;

      final next = completeTurn(state, Rng(state.rngSeed)).state;

      expect(next.persons.containsKey(ruler1), isFalse,
          reason: 'the bankrupt dynasty vanished');
      for (final realm in next.realms) {
        if (realm.rulerId == null) continue;
        expect(next.persons, contains(realm.rulerId),
            reason: 'slot ${realm.slot} must not point at a deleted person');
      }
      expect(next.realm(2).rulerId, isNot(ruler1),
          reason: 'the aliased slot passed on (or went vacant)');
      expect(next.kaiserId, isNull,
          reason: 'a vanished Kaiser must vacate the throne');
      expect(next.kurfuerstenIds, isNot(contains(ruler1)));
      for (final person in next.persons.values) {
        expect(person.childrenIds, isNot(contains(ruler1)));
      }
      expect(checkWinCondition(next), isNull,
          reason: 'the win check must stay satisfiable (no phantom ruler)');
    });
  });

  group('rules v4: ruler capture', () {
    test('no capture on a capital tile the enemy no longer owns', () {
      final (state, border) = warState();
      final map = state.map;
      final defender = state.realm(2);
      // An earlier war took the capital tile; the seat never relocated.
      map.owner[map.index(defender.capitalX, defender.capitalY)] = 1;
      // Park the defender's unit on its border tile, the attacker's unit
      // on the defender's Dorf (always orthogonal to the capital, §5).
      defender.troops.single
        ..x = border.$1
        ..y = border.$2;
      final dorf = defender.towns.single;
      state.realm(1).troops.single
        ..x = dorf.x
        ..y = dorf.y;

      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      s = applyAction(
              s,
              WarMove(
                  slot: 1,
                  unitIndex: 0,
                  dx: defender.capitalX - dorf.x,
                  dy: defender.capitalY - dorf.y),
              Rng(s.rngSeed))
          .state;

      expect(s.activeWar, isNotNull,
          reason: 'stepping onto a tile the attacker owns is no capture');
      expect(s.realm(2).rulerId, isNot(s.realm(1).rulerId));
    });
  });

  group('rules v4: stacked combat', () {
    test('a mover never co-locates with surviving enemy units', () {
      final (state, border) = warState();
      final defender = state.realm(2);
      // Two defender units stacked on the Dorf; attacker on the adjacent
      // capital tile of the defender (combat, not capture — the move
      // targets the Dorf).
      defender.troops.add(Troop(
        name: 'Zweite',
        men: 50,
        troopClass: TroopClass.infanterie,
        quality: TroopQuality.soeldner,
        garrisonCounted: false,
        x: 0,
        y: 0,
      ));
      final dorf = defender.towns.single;
      for (final t in defender.troops) {
        t
          ..x = dorf.x
          ..y = dorf.y;
      }
      state.realm(1).troops.single
        ..x = defender.capitalX
        ..y = defender.capitalY;

      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      s = applyAction(
              s,
              WarMove(
                  slot: 1,
                  unitIndex: 0,
                  dx: dorf.x - defender.capitalX,
                  dy: dorf.y - defender.capitalY),
              Rng(s.rngSeed))
          .state;

      final attacker = s.realm(1).troops.singleOrNull;
      final defendersOnDorf =
          s.realm(2).troops.where((t) => t.x == dorf.x && t.y == dorf.y);
      final moverOnDorf =
          attacker != null && attacker.x == dorf.x && attacker.y == dorf.y;
      expect(moverOnDorf && defendersOnDorf.isNotEmpty, isFalse,
          reason: 'entering the tile means every defender was beaten');
    });
  });

  group('rules v4: assassinations', () {
    test('an attempt whose agents were all caught fails', () {
      // First draw of resolveAssassinations is nextInt(2×guard + 15);
      // any non-zero catches the single agent.
      var seed = 1;
      while (Rng(seed).nextInt(115) == 0) {
        seed++;
      }
      final state = freshState();
      state.realm(2).guardLevel = guardCap; // 50 → g + 15 = 115
      final victim = state.realm(2).rulerId!;
      queueAssassination(state, 1, 2, 1);
      final events = <GameEvent>[];
      resolveAssassinations(state, 2, Rng(seed), events);

      expect(events.single.type, 'assassinationFailed');
      expect(events.single.payload['caught'], 1,
          reason: 'the premise: the only agent was caught');
      expect(state.persons, contains(victim));
    });
  });

  group('rules v4: merging at war', () {
    test('MergeRealms is blocked while the realm fights the active war', () {
      final (built, _) = warState();
      var state = built;
      final ruler1 = state.realm(1).rulerId!;
      state.realm(3).rulerId = ruler1; // aliasing: also rules slot 3
      alignSlotControl(state, 3, ruler1);
      expect(mergeableSlots(state, 1), contains(3));

      state = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      expect(
        () => applyAction(
            state, MergeRealms(slot: 1, sourceSlot: 3), Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
      );
    });

    test('MergeRealms still works in peacetime and vacates the source seat',
        () {
      final (state, _) = warState();
      final ruler1 = state.realm(1).rulerId!;
      state.realm(3).rulerId = ruler1;
      alignSlotControl(state, 3, ruler1);

      final next = applyAction(
              state, MergeRealms(slot: 1, sourceSlot: 3), Rng(state.rngSeed))
          .state;
      expect(next.realm(3).isVacant, isTrue);
      expect(next.dynasty(3).status, DynastyStatus.ai,
          reason: 'a merged-away slot is no longer a human seat');
      expect(next.dynasty(3).humanPlayer, isNull);
    });
  });

  group('decision resolution (unversioned fixes)', () {
    test('unknown decision types resolve as a no-op instead of throwing', () {
      final state = freshState();
      state.pendingDecisions.add(PendingDecision(
        id: 'future-1',
        type: 'somethingFromTheFuture',
        decidingSlot: 1,
      ));
      final next = applyAction(
              state,
              ResolveDecision(
                  slot: 1, decisionId: 'future-1', choice: const {}),
              Rng(state.rngSeed))
          .state;
      expect(next.pendingDecisions.where((d) => d.id == 'future-1'), isEmpty);
    });

    test('marriage consent re-checks religion at resolution time', () {
      final state = freshState();
      final proposer = state.person(state.realm(3).rulerId)!;
      final target = state.person(state.realm(1).rulerId)!;
      state.pendingDecisions.add(PendingDecision(
        id: 'marriage-test',
        type: 'marriageConsent',
        decidingSlot: 1,
        payload: {'proposerId': proposer.id, 'targetId': target.id},
      ));
      // The proposer's dynasty converted after proposing (§14.4).
      state.dynasty(3).religion = Religion.moslemisch;

      final result = applyAction(
          state,
          ResolveDecision(
              slot: 1,
              decisionId: 'marriage-test',
              choice: const {'accept': true}),
          Rng(state.rngSeed));

      expect(result.events.any((e) => e.type == 'wedding'), isFalse);
      expect(result.state.person(proposer.id)!.spouseId, isNull);
      expect(result.state.person(target.id)!.spouseId, isNull);
    });

    test('decisions for AI/vacant slots are purged at round start', () {
      final state = freshState();
      state.pendingDecisions.add(PendingDecision(
        id: 'stale-1',
        type: 'childName',
        decidingSlot: 5, // an AI slot
        payload: const {'childId': 1},
      ));
      state.currentPlayer = 30; // completing slot 30 wraps the round
      final next = completeTurn(state, Rng(state.rngSeed)).state;
      expect(next.pendingDecisions.where((d) => d.id == 'stale-1'), isEmpty);
    });
  });

  group('rules v4: election candidates', () {
    test('a deposed Kurfürst without a realm is no Kaiser candidate', () {
      final state = freshState();
      state.year = 1010;
      // Pick a male ruler, then depose every ruler in favor of freshly
      // created female rulers — leaving the seated Kurfürst the only
      // would-be candidate.
      final deposed = state.realms
          .map((r) => state.person(r.rulerId)!)
          .firstWhere((p) => p.isMale)
          .id;
      for (final realm in state.realms) {
        final p = Person(
          id: state.nextPersonId++,
          name: 'Regentin ${realm.slot}',
          age: 30,
          dynasty: realm.slot,
          gender: 1,
        );
        state.persons[p.id] = p;
        state.dynasty(realm.slot).memberIds.add(p.id);
        realm.rulerId = p.id;
      }
      state.kurfuerstenIds
        ..clear()
        ..add(deposed);
      state.kaiserId = null;

      final events = <GameEvent>[];
      maybeStartElection(state, Office.kaiser, Rng(1), events);

      expect(state.kaiserId, isNull,
          reason: 'no acclamation for a candidate without a realm');
      expect(state.activeElection, isNull);
      expect(events.any((e) => e.type == 'interregnum'), isTrue);
    });
  });

  group('snapshot matching (unversioned fix)', () {
    test('duplicate-named units claim distinct snapshots in order', () {
      Troop unit(int x, int y) => Troop(
            name: 'Rekruten',
            men: 10,
            troopClass: TroopClass.infanterie,
            quality: TroopQuality.regular,
            garrisonCounted: false,
            x: x,
            y: y,
          );
      final troops = [unit(4, 4), unit(9, 9)];
      final snapshots = [
        UnitSnapshot(name: 'Rekruten', x: 1, y: 1),
        UnitSnapshot(name: 'Rekruten', x: 2, y: 2),
      ];
      final matched = matchedSnapshots(troops, snapshots);
      expect((matched[0]!.x, matched[0]!.y), (1, 1));
      expect((matched[1]!.x, matched[1]!.y), (2, 2));
      expect(matchedSnapshots(troops, const []), [null, null]);
    });

    test('post-war return puts same-named units on their own spots', () {
      final (state, border) = warState();
      // A second same-named unit for the attacker on another own tile.
      final first = state.realm(1).troops.single;
      state.realm(1).troops.add(Troop(
            name: first.name,
            men: 10,
            troopClass: TroopClass.infanterie,
            quality: TroopQuality.soeldner,
            garrisonCounted: false,
            x: state.realm(1).towns.single.x,
            y: state.realm(1).towns.single.y,
          ));
      final homes = [
        for (final t in state.realm(1).troops) (t.x, t.y),
      ];
      expect(homes[0], isNot(homes[1]));

      startWar(state, 1, 2, Rng(state.rngSeed));
      // Both units wander off, then the war ends in a draw.
      state.realm(1).troops[0]
        ..x = border.$1
        ..y = border.$2;
      state.realm(1).troops[1]
        ..x = state.realm(1).capitalX
        ..y = state.realm(1).capitalY;
      state.activeWar!
        ..attackerWantsPeace = true
        ..defenderWantsPeace = true;
      state.dynasty(2).status = DynastyStatus.human; // keep the wish as set
      final events = <GameEvent>[];
      endWarRound(state, Rng(state.rngSeed), events);

      expect(state.activeWar, isNull);
      // Rules v5 ends a mutual peace as a white peace ('peaceAgreed');
      // troops still return to their snapshots either way.
      expect(events.any((e) => e.type == 'peaceAgreed'), isTrue);
      final returned = [
        for (final t in state.realm(1).troops) (t.x, t.y),
      ];
      expect(returned, homes,
          reason: 'each unit returns to ITS OWN pre-war spot');
    });
  });

  group('recap baselines (unversioned fix)', () {
    test('round-trip through JSON and copy, redacted for other seats', () {
      final state = freshState();
      state.recapBaselines[1] = 42;
      expect(GameState.fromJson(state.toJson()).recapBaselines[1], 42);
      expect(state.copy().recapBaselines[1], 42);
      expect(visibleStateFor(state, 2).recapBaselines.containsKey(1), isFalse);
      expect(visibleStateFor(state, 1).recapBaselines[1], 42);
    });
  });
}
