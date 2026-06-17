import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Regression tests for the 2026-06-11 original-fidelity round (rules
/// v10): multi-option coercion (§12), coerced-conversion side effects
/// (§14.4/§16.1), earthquake/disease garrison sync, and the unversioned
/// merge bookkeeping fix (ships + intel).
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

  group('rules v10: §12 coercion fires every applicable option', () {
    /// Same religion, marriage made inapplicable via the age gap — the
    /// applicable options are exactly abdication + seat strip.
    (GameState, Person) coercionState({required int victorSlot}) {
      final state = freshState();
      final victor = state.person(state.realm(victorSlot).rulerId)!;
      final captured = state.person(state.realm(3).rulerId)!;
      victor.age = 20;
      captured.age = 80; // gap ≥ 10 → no forced marriage
      state.kaiserId = captured.id;
      state.kurfuerstenIds.add(captured.id);
      return (state, captured);
    }

    test('an AI victor executes abdication AND the seat strip', () {
      final (state, captured) = coercionState(victorSlot: 2);
      final events = <GameEvent>[];
      runCoercion(state, 2, captured, Rng(1), events);

      expect(events.any((e) => e.type == 'forcedAbdication'), isTrue);
      expect(events.any((e) => e.type == 'kurfuerstStripped'), isTrue);
      expect(state.kaiserId, isNull);
      expect(state.kurfuerstenIds, isNot(contains(captured.id)));
    });

    test('a human victor gets one decision per applicable option', () {
      final (state, captured) = coercionState(victorSlot: 1);
      runCoercion(state, 1, captured, Rng(1), <GameEvent>[]);

      final options = [
        for (final d in state.pendingDecisions)
          if (d.type == 'coercion') d.payload['option'],
      ];
      expect(options, containsAll(['abdication', 'stripSeat']));
      expect(options.toSet().length, options.length,
          reason: 'distinct decisions, one per option');
    });
  });

  group('rules v10: coerced conversion side effects', () {
    test('accepting convert-or-die switches the ladder and divorces', () {
      final state = freshState();
      final captured = state.person(state.realm(3).rulerId)!;
      final spouse = state.person(state.realm(4).rulerId)!;
      captured.spouseId = spouse.id;
      spouse.spouseId = captured.id;
      state.realm(3).titleClass = 5; // Großfürst, Christian ladder

      final events = <GameEvent>[];
      applyConvertOrDie(
          state, captured, Religion.moslemisch, true, Rng(1), events);

      expect(state.dynasty(3).religion, Religion.moslemisch);
      expect(state.realm(3).titleClass, 9,
          reason: 'a Muslim dynasty starts on the Muslim ladder (Scheich)');
      expect(captured.spouseId, isNull,
          reason: '§14.4: incompatible marriages dissolve');
      expect(spouse.spouseId, isNull);
      expect(events.any((e) => e.type == 'divorce'), isTrue);
      expect(events.any((e) => e.type == 'dynastyConverted'), isTrue);
    });

    test('an aliased realm keeps its own ladder on coerced conversion', () {
      final state = freshState();
      final captured = state.person(state.realm(3).rulerId)!;
      // The captured ruler also rules slot 4 (aliasing) — slot 4's own
      // dynasty does NOT convert, so its Christian title must survive.
      state.realm(4).rulerId = captured.id;
      alignSlotControl(state, 4, captured.id);
      state.realm(3).titleClass = 5;
      state.realm(4).titleClass = 5;

      applyConvertOrDie(
          state, captured, Religion.moslemisch, true, Rng(1), <GameEvent>[]);

      expect(state.realm(3).titleClass, 9,
          reason: 'the home realm switches to the Muslim ladder');
      expect(state.realm(4).titleClass, 5,
          reason: 'slot 4\'s dynasty is still Christian — its ladder, and '
              'with it the §16.2 promotion check, must keep working');
    });

    test('a stale abdication never deposes a successor Kaiser', () {
      final state = freshState();
      final captured = state.person(state.realm(3).rulerId)!;
      final victor = state.person(state.realm(2).rulerId)!;
      final successor = state.person(state.realm(5).rulerId)!;
      state.kaiserId = successor.id; // someone else was crowned meanwhile

      applyCoercion(
          state, 'abdication', victor, captured, Rng(1), <GameEvent>[]);

      expect(state.kaiserId, successor.id,
          reason: 'only the captured ruler\'s own crown is forfeit');
    });

    test('menu conversion to Islam strips every member\'s Kurfürst seat', () {
      final state = freshState();
      state.year = 1050; // past the Ottoman year — Islam available
      final realm = state.realm(3);
      realm.treasury = 5000;
      // A second dynasty member rules an inherited slot and holds a seat.
      final member = Person(
        id: state.nextPersonId++,
        name: 'Vetter',
        age: 30,
        dynasty: 3,
        gender: 0,
      );
      state.persons[member.id] = member;
      state.dynasty(3).memberIds.add(member.id);
      state.realm(6).rulerId = member.id;
      state.kurfuerstenIds.addAll([realm.rulerId!, member.id]);

      final next = applyAction(
              state,
              ChangeReligion(slot: 3, religion: Religion.moslemisch),
              Rng(state.rngSeed))
          .state;

      expect(next.kurfuerstenIds, isNot(contains(realm.rulerId)));
      expect(next.kurfuerstenIds, isNot(contains(member.id)),
          reason: 'the whole dynasty converted — no member may keep a '
              'Kurfürst seat (§17.2 keys on the home-dynasty religion)');
    });
  });

  group('rules v10: epidemic damage keeps units in sync', () {
    test('disease garrison losses are cut from garrison-counted units', () {
      final state = freshState();
      state.year = 1010; // outside the protect-new-players window
      final realm = state.realm(1);
      realm.treasury = 10000;
      realm.towns.single.troopCapacity = 200;
      realm.troopCapacity = 200;
      var s = applyAction(
              state,
              RecruitTroops(
                  slot: 1,
                  men: 150,
                  troopClass: TroopClass.infanterie,
                  name: 'Heer'),
              Rng(state.rngSeed))
          .state;
      // Force the unconditional disease trigger (> 250 persons).
      for (var i = 0; i < 260; i++) {
        final p = Person(
          id: s.nextPersonId++,
          name: 'Bauer $i',
          age: 20,
          dynasty: 5,
          gender: i % 2,
        );
        s.persons[p.id] = p;
        s.dynasty(5).memberIds.add(p.id);
      }

      final events = <GameEvent>[];
      runWorldEvents(s, Rng(99), events);
      expect(events.any((e) => e.type == 'disease'), isTrue);

      for (final r in s.realms) {
        final unitMen = r.troops
            .where((t) => t.garrisonCounted)
            .fold(0, (sum, t) => sum + t.men);
        final garrisons = r.towns.fold(0, (sum, t) => sum + t.garrison);
        expect(unitMen, r.armySize,
            reason: 'slot ${r.slot}: unit men must match armySize');
        expect(garrisons, r.armySize,
            reason: 'slot ${r.slot}: town garrisons must match armySize');
      }
    });
  });

  group('realm merge bookkeeping (unversioned fix)', () {
    test('merging moves colony ships and intel reports', () {
      final state = freshState();
      final ruler1 = state.realm(1).rulerId!;
      state.realm(3).rulerId = ruler1; // aliasing: also rules slot 3
      alignSlotControl(state, 3, ruler1);
      // Ensure slot 3 borders slot 1 (required since merging needs shared border).
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
      state.realm(3).ships.add(Ship(x: 5, y: 5));
      state.realm(3).intelReports.add(IntelReport(
            targetSlot: 7,
            year: state.year,
            values: const {'treasury': 1234},
          ));

      final next = applyAction(
              state, MergeRealms(slot: 1, sourceSlot: 3), Rng(state.rngSeed))
          .state;

      // slot 3 is the target (sourceSlot absorbs the acting slot 1).
      // slot 3 already had the ship and intel — they stay in slot 3.
      expect(next.realm(3).ships, hasLength(1));
      expect(next.realm(1).ships, isEmpty);
      expect(next.realm(3).intelReports, hasLength(1));
      expect(next.realm(3).intelReports.single.targetSlot, 7);
      expect(next.realm(1).intelReports, isEmpty);
    });
  });
}
