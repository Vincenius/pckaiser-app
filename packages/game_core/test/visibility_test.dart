import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  late GameState state;

  setUp(() {
    state = newGame(GameSetup(
      humans: [
        HumanPlayerSetup(
            founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'Berlin'),
        HumanPlayerSetup(
            founderName: 'Berta',
            gender: 1,
            countrySlot: 2,
            dorfName: 'Kassel'),
      ],
      reformationYear: 1020,
      ottomanYear: 1040,
      seed: 5,
    ));
    state.realm(2).guardLevel = 30;
    state
        .realm(1)
        .intelReports
        .add(IntelReport(targetSlot: 2, year: 1002, values: {'treasury': 990}));
    state.pendingDecisions.add(
        PendingDecision(id: 'd1', type: 'marriageConsent', decidingSlot: 2));
    state.assassinationOrders
        .add(AssassinationOrder(sponsorSlot: 2, targetSlot: 1, count: 1));
    state.events.addAll([
      GameEvent(
          year: 1000,
          slot: 2,
          type: 'intelGathered',
          visibility: EventVisibility.owner),
      GameEvent(
          year: 1000,
          slot: 2,
          type: 'warDeclared',
          visibility: EventVisibility.public),
    ]);
  });

  group('visibleStateFor', () {
    test('keeps the viewer\'s own realm complete', () {
      final view = visibleStateFor(state, 1);
      final own = view.realm(1);
      expect(own.treasury, 1000);
      expect(own.popularity, 50);
      expect(own.population, state.realm(1).population);
      expect(own.intelReports, hasLength(1));
    });

    test(
        'hides foreign troop markers on the map '
        '(visible again in a war the viewer fights)', () {
      // Give both realms a troop standing on their own capital.
      for (final slot in [1, 2]) {
        final realm = state.realm(slot);
        realm.troops.add(Troop(
            name: 'Heer$slot',
            men: 10,
            troopClass: TroopClass.infanterie,
            quality: TroopQuality.regular,
            garrisonCounted: false,
            x: realm.capitalX,
            y: realm.capitalY));
        state.map.troopMarker[state.map.index(realm.capitalX, realm.capitalY)] =
            1;
      }
      final map = state.map;
      int markerOf(GameState s, int slot) => s.map.troopMarker[
          map.index(s.realm(slot).capitalX, s.realm(slot).capitalY)];

      final view1 = visibleStateFor(state, 1);
      expect(markerOf(view1, 1), 1,
          reason: 'own troops stay visible (marker = owner slot)');
      expect(markerOf(view1, 2), 0, reason: 'foreign troops are hidden');

      // At war with each other: both sides' troops become visible, with
      // the owner slot encoded in the marker (attacker/defender icons).
      state.activeWar = ActiveWar(attackerSlot: 2, defenderSlot: 1);
      final atWar = visibleStateFor(state, 1);
      expect(markerOf(atWar, 2), 2,
          reason: 'enemy troops show once the war starts');
      // An uninvolved third party still sees neither.
      final third = visibleStateFor(state, 3);
      expect(markerOf(third, 1), 0);
      expect(markerOf(third, 2), 0);
    });

    test('reveals the opponent troop list to a combatant during war', () {
      for (final slot in [1, 2]) {
        final realm = state.realm(slot);
        realm.troops.add(Troop(
            name: 'Heer$slot',
            men: 42,
            troopClass: TroopClass.infanterie,
            quality: TroopQuality.regular,
            garrisonCounted: false,
            x: realm.capitalX,
            y: realm.capitalY));
        realm.armySize = 42;
      }

      // Peacetime: the enemy army is hidden.
      expect(visibleStateFor(state, 1).realm(2).troops, isEmpty);

      // At war: realm 1 sees realm 2's units (and vice versa), but a
      // bystander still sees nothing.
      state.activeWar = ActiveWar(attackerSlot: 2, defenderSlot: 1);
      final atWar = visibleStateFor(state, 1).realm(2);
      expect(atWar.troops.single.men, 42);
      expect(atWar.troops.single.name, 'Heer2');
      expect(atWar.armySize, 42);
      expect(visibleStateFor(state, 3).realm(2).troops, isEmpty,
          reason: 'an uninvolved third party still cannot see the army');
    });

    test('hides foreign economy, military and intel', () {
      final view = visibleStateFor(state, 1);
      final foreign = view.realm(2);
      expect(foreign.treasury, 0);
      expect(foreign.guardLevel, 0);
      expect(foreign.popularity, 0);
      expect(foreign.population, 0);
      expect(foreign.grainHarvest, 0);
      expect(foreign.armySize, 0);
      expect(foreign.troops, isEmpty);
      expect(foreign.intelReports, isEmpty);
      expect(foreign.movementPoints, 0);
      expect(foreign.towns.single.population, 0);
      expect(foreign.towns.single.garrison, 0);
    });

    test('keeps foreign public identity: title, capital, towns, ruler', () {
      final view = visibleStateFor(state, 1);
      final foreign = view.realm(2);
      expect(foreign.rulerId, state.realm(2).rulerId);
      expect(foreign.titleClass, state.realm(2).titleClass);
      expect(foreign.capitalX, state.realm(2).capitalX);
      expect(foreign.towns.single.name, 'Kassel');
      expect(foreign.towns.single.buildingType, Building.dorf);
      expect(foreign.tileCount, state.realm(2).tileCount);
      // Map ownership is public.
      expect(view.map.owner, state.map.owner);
      expect(view.persons.length, state.persons.length);
    });

    test('hides election bribes and votes from every viewer', () {
      state.activeElection = ActiveElection(
        office: Office.kaiser,
        finalistIds: [1, 2],
        electorIds: [3],
      )..addBribe(3, 1, 500);
      state.activeElection!.votes[3] = 1;
      final view = visibleStateFor(state, 1);
      expect(view.activeElection, isNotNull,
          reason: 'the running election itself is public');
      expect(view.activeElection!.bribes, isEmpty);
      expect(view.activeElection!.votes, isEmpty);
      expect(state.activeElection!.bribes, isNotEmpty,
          reason: 'the master state keeps them');
    });

    test('hides war snapshots and movement budgets from non-participants', () {
      state.activeWar = ActiveWar(attackerSlot: 2, defenderSlot: 1)
        ..snapshots[2] = [UnitSnapshot(name: 'Heer', x: 3, y: 4)]
        ..movesLeft[2] = [5];
      final participant = visibleStateFor(state, 1);
      expect(participant.activeWar!.snapshots, isNotEmpty);
      expect(participant.activeWar!.movesLeft, isNotEmpty);
      final bystander = visibleStateFor(state, 3);
      expect(bystander.activeWar, isNotNull,
          reason: 'that a war rages is public');
      expect(bystander.activeWar!.snapshots, isEmpty);
      expect(bystander.activeWar!.movesLeft, isEmpty);
    });

    test('never leaks the RNG seed', () {
      expect(visibleStateFor(state, 1).rngSeed, 0);
      expect(state.rngSeed, isNot(0));
    });

    test('filters pending decisions, assassination orders and events', () {
      final view1 = visibleStateFor(state, 1);
      expect(view1.pendingDecisions, isEmpty);
      expect(view1.assassinationOrders, isEmpty);
      expect(view1.events.map((e) => e.type), ['warDeclared']);

      final view2 = visibleStateFor(state, 2);
      expect(view2.pendingDecisions.single.id, 'd1');
      expect(view2.assassinationOrders, hasLength(1));
      expect(view2.events.map((e) => e.type), ['intelGathered', 'warDeclared']);
    });

    test('does not mutate the source state', () {
      final before = state.toJson();
      visibleStateFor(state, 1);
      expect(state.toJson(), before);
    });
  });
}
