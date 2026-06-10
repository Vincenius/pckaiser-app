import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Builds a populated state exercising every entity type.
GameState sampleState() {
  final map = generateMap(Rng(7));

  final founder = Person(
    id: 1,
    name: 'Heinrich',
    age: 19,
    dynasty: 1,
    gender: 0,
  );
  final spouse = Person(
    id: 2,
    name: 'Mathilde',
    age: 18,
    dynasty: 1,
    gender: 1,
    spouseId: 1,
  );
  founder.spouseId = 2;
  final child = Person(
    id: 3,
    name: 'Otto',
    age: 0,
    dynasty: 1,
    gender: 0,
  );
  founder.childrenIds.add(3);

  final realms = [
    for (var slot = 1; slot <= World.realmCount; slot++) Realm(slot: slot),
  ];
  final dynasties = [
    for (var slot = 1; slot <= World.realmCount; slot++)
      Dynasty(
        index: slot,
        status: slot == 1 ? DynastyStatus.human : DynastyStatus.ai,
        humanPlayer: slot == 1 ? 0 : null,
        religion: Religion.katholisch,
      ),
  ];

  final realm1 = realms[0]
    ..titleClass = 1
    ..capitalX = 10
    ..capitalY = 10
    ..treasury = 1000
    ..rulerId = 1;
  realm1.towns.add(Town(
    name: 'Aachen',
    population: 100,
    troopCapacity: 25,
    garrison: 10,
    buildingType: Building.dorf,
    x: 11,
    y: 10,
  ));
  realm1.troops.add(Troop(
    name: 'Garde',
    men: 10,
    troopClass: TroopClass.infanterie,
    quality: TroopQuality.regular,
    garrisonCounted: true,
    x: 11,
    y: 10,
  ));
  realm1.intelReports.add(IntelReport(
    targetSlot: 2,
    year: 1003,
    values: {'treasury': 1234, 'armySize': 56},
  ));
  realm1.tileCount[Building.dorf] = 1;
  dynasties[0].memberIds.addAll([1, 2, 3]);

  return GameState(
    year: 1003,
    reformationYear: 1020,
    ottomanYear: 1040,
    grainPrice: 2.5,
    cattlePrice: 4.25,
    kaiserId: 1,
    kaiserPot: 321,
    kurfuerstenIds: [1, 2],
    kaiserChronicle: [
      ChronicleRecord(name: 'Heinrich', accessionYear: 1001),
    ],
    persons: {1: founder, 2: spouse, 3: child},
    nextPersonId: 4,
    assassinationOrders: [
      AssassinationOrder(sponsorSlot: 2, targetSlot: 1, count: 3),
    ],
    currentPlayer: 1,
    map: map,
    realms: realms,
    dynasties: dynasties,
    rngSeed: 987654321,
    pendingDecisions: [
      PendingDecision(
        id: 'pd-1',
        type: 'marriageConsent',
        decidingSlot: 2,
        payload: {'proposerId': 1, 'candidateId': 2},
      ),
    ],
    events: [
      GameEvent(
        year: 1003,
        slot: 1,
        type: 'intelGathered',
        visibility: EventVisibility.owner,
        payload: {'targetSlot': 2},
      ),
      GameEvent(
        year: 1003,
        slot: 1,
        type: 'warDeclared',
        visibility: EventVisibility.public,
        participants: [1, 2],
      ),
    ],
  );
}

void main() {
  group('GameState JSON', () {
    test('round-trips through encode/decode losslessly', () {
      final state = sampleState();
      final json1 = jsonEncode(state.toJson());
      final decoded = GameState.fromJson(
          (jsonDecode(json1) as Map).cast<String, dynamic>());
      final json2 = jsonEncode(decoded.toJson());
      expect(json2, json1);
    });

    test('tolerates missing optional fields (forward compatibility)', () {
      final minimal = {
        'year': 1000,
        'reformationYear': 1020,
        'ottomanYear': 1040,
        'map': WorldMap.water().toJson(),
        'realms': [
          for (var s = 1; s <= World.realmCount; s++) {'slot': s},
        ],
        'dynasties': [
          for (var s = 1; s <= World.realmCount; s++)
            {'index': s, 'status': 'ai', 'religion': 0},
        ],
        'rngSeed': 1,
      };
      final state = GameState.fromJson(minimal);
      expect(state.realm(1).popularity, 50);
      expect(state.realm(30).tileCount, hasLength(9));
      expect(state.pendingDecisions, isEmpty);
      expect(state.events, isEmpty);
      expect(state.kaiserId, isNull);
    });

    test('copy() is deep — mutating the copy leaves the original intact', () {
      final state = sampleState();
      final originalTerrain = state.map.terrain[0];
      final copy = state.copy();
      copy.realm(1).treasury = -500;
      copy.realm(1).towns.first.population = 9999;
      copy.persons[1]!.age = 99;
      copy.map.terrain[0] =
          originalTerrain == Terrain.berg ? Terrain.ebene : Terrain.berg;
      copy.dynasty(1).memberIds.removeLast();

      expect(state.realm(1).treasury, 1000);
      expect(state.realm(1).towns.first.population, 100);
      expect(state.persons[1]!.age, 19);
      expect(state.map.terrain[0], originalTerrain);
      expect(state.dynasty(1).memberIds, hasLength(3));
    });

    test('GameEvent.visibleTo respects visibility', () {
      final state = sampleState();
      final intel = state.events[0];
      final war = state.events[1];
      expect(intel.visibleTo(1), isTrue);
      expect(intel.visibleTo(2), isFalse);
      expect(war.visibleTo(30), isTrue);
      final secret = GameEvent(
        year: 1003,
        slot: 1,
        type: 'peaceOffer',
        visibility: EventVisibility.participants,
        participants: [1, 2],
      );
      expect(secret.visibleTo(2), isTrue);
      expect(secret.visibleTo(3), isFalse);
    });
  });
}
