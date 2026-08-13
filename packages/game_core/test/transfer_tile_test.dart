import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// "Felder übertragen" [DESIGNED, deviation]: voluntarily hand a single
/// map tile to a FOREIGN ruler. Tests cover the full validation chain,
/// the state mutation (ownership, tileCount, town transfer), and the event.
void main() {
  GameState freshGame() {
    final state = startGame(
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
    state.year = 1010;
    return state;
  }

  /// Find an edge tile owned by [slot] (not the capital) for testing.
  (int x, int y) findEdgeTile(GameState state, int slot) {
    final realm = state.realm(slot);
    final map = state.map;
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != slot) continue;
        if (x == realm.capitalX && y == realm.capitalY) continue;
        return (x, y);
      }
    }
    throw StateError('no edge tile found for slot $slot');
  }

  /// Matches an [ActionException] carrying exactly the engine message
  /// [key] (locale-independent: both sides call [coreMessage]).
  Matcher throwsMessage(String key) => throwsA(
        isA<ActionException>().having((e) => e.message, 'message', coreMessage(key)),
      );

  group('basic transfer', () {
    test('transfers ownership, adjusts tileCount, keeps building', () {
      final state = freshGame();
      final target = transferableSlots(state, 1).first;
      final (x, y) = findEdgeTile(state, 1);
      final building = state.map.buildingAt(x, y);
      final sourceBefore = state.realm(1);
      final targetBefore = state.realm(target);
      final sourceTileCount = List<int>.from(sourceBefore.tileCount);
      final targetTileCount = List<int>.from(targetBefore.tileCount);
      final sourceTreasury = sourceBefore.treasury;
      final sourceGrain = sourceBefore.grainHarvest;
      final sourceLivestock = sourceBefore.livestockHarvest;

      final result = applyAction(
        state,
        TransferTile(slot: 1, targetSlot: target, x: x, y: y),
        Rng(state.rngSeed),
      );
      final next = result.state;

      // Ownership changed.
      expect(next.map.ownerAt(x, y), target);
      // tileCount adjusted on both sides.
      expect(next.realm(1).tileCount[building], sourceTileCount[building] - 1);
      expect(
          next.realm(target).tileCount[building], targetTileCount[building] + 1);
      // Building on the tile unchanged.
      expect(next.map.buildingAt(x, y), building);
      // Treasury/harvests NOT transferred.
      expect(next.realm(1).treasury, sourceTreasury);
      expect(next.realm(1).grainHarvest, sourceGrain);
      expect(next.realm(1).livestockHarvest, sourceLivestock);
    });

    test('town transfer: town moves with population/troopCapacity, garrison cut',
        () {
      final state = freshGame();
      final target = transferableSlots(state, 1).first;
      final source = state.realm(1);

      // Pick a town that is NOT the capital.
      final town = source.towns.firstWhere(
        (t) => !(t.x == source.capitalX && t.y == source.capitalY),
        orElse: () => throw StateError('no non-capital town found'),
      );
      final townPop = town.population;
      final townCap = town.troopCapacity;

      final result = applyAction(
        state,
        TransferTile(slot: 1, targetSlot: target, x: town.x, y: town.y),
        Rng(state.rngSeed),
      );
      final next = result.state;

      // Town moved to target.
      expect(next.realm(target).towns.any((t) => t.x == town.x && t.y == town.y),
          isTrue);
      expect(next.realm(1).towns.any((t) => t.x == town.x && t.y == town.y),
          isFalse);

      // Population and troopCapacity moved.
      expect(next.realm(1).population, state.realm(1).population - townPop);
      expect(next.realm(target).population, state.realm(target).population + townPop);
      expect(next.realm(1).troopCapacity, state.realm(1).troopCapacity - townCap);
      expect(next.realm(target).troopCapacity,
          state.realm(target).troopCapacity + townCap);

      // Garrison cut at source, town.garrison == 0 at target.
      final targetTown = next.realm(target).towns
          .firstWhere((t) => t.x == town.x && t.y == town.y);
      expect(targetTown.garrison, 0);
    });
  });

  group('validation', () {
    test('capital transfer forbidden — cannotTransferCapital', () {
      final state = freshGame();
      final target = transferableSlots(state, 1).first;
      final capital = state.realm(1);
      expect(
        () => applyAction(
          state,
          TransferTile(
              slot: 1, targetSlot: target, x: capital.capitalX, y: capital.capitalY),
          Rng(state.rngSeed),
        ),
        throwsMessage('cannotTransferCapital'),
      );
      // State unchanged (atomicity via copy in applyAction).
      expect(state.map.ownerAt(capital.capitalX, capital.capitalY), 1);
    });

    test('foreign tile forbidden — tileNotYours', () {
      final state = freshGame();
      final target = transferableSlots(state, 1).first;
      // Pick a tile owned by the target.
      final targetRealm = state.realm(target);
      expect(
        () => applyAction(
          state,
          TransferTile(
              slot: 1,
              targetSlot: target,
              x: targetRealm.capitalX,
              y: targetRealm.capitalY),
          Rng(state.rngSeed),
        ),
        throwsMessage('tileNotYours'),
      );
    });

    test('self target — cannotTransferTile', () {
      final state = freshGame();
      // An own, non-capital tile transferred to SELF (slot 1 -> slot 1) is
      // not in transferableSlots, so the target gate must reject it.
      final (x, y) = findEdgeTile(state, 1);
      expect(
        () => applyAction(
          state,
          TransferTile(slot: 1, targetSlot: 1, x: x, y: y),
          Rng(state.rngSeed),
        ),
        throwsMessage('cannotTransferTile'),
      );
    });

    test('mid-war (source participant) — notDuringWar', () {
      final state = freshGame();
      final target = transferableSlots(state, 1).first;
      final (x, y) = findEdgeTile(state, 1);

      state.activeWar = ActiveWar(
        attackerSlot: 1,
        defenderSlot: target,
        phase: WarPhase.rounds,
      );

      expect(
        () => applyAction(
          state,
          TransferTile(slot: 1, targetSlot: target, x: x, y: y),
          Rng(state.rngSeed),
        ),
        throwsMessage('notDuringWar'),
      );
    });

    test('mid-war (target participant only) — notDuringWar', () {
      final state = freshGame();
      final target = transferableSlots(state, 1).first;
      final third = transferableSlots(state, 1).firstWhere((s) => s != target);
      final (x, y) = findEdgeTile(state, 1);

      // Source (slot 1) is neutral; the TARGET fights a third party.
      state.activeWar = ActiveWar(
        attackerSlot: target,
        defenderSlot: third,
        phase: WarPhase.rounds,
      );

      expect(
        () => applyAction(
          state,
          TransferTile(slot: 1, targetSlot: target, x: x, y: y),
          Rng(state.rngSeed),
        ),
        throwsMessage('notDuringWar'),
      );
    });

    test('troops on tile — tileHasTroops', () {
      final state = freshGame();
      final target = transferableSlots(state, 1).first;
      final (x, y) = findEdgeTile(state, 1);

      // Place a troop on a NON-capital own tile.
      state.realm(1).troops.add(Troop(
            name: 'Test',
            men: 100,
            troopClass: TroopClass.infanterie,
            quality: TroopQuality.regular,
            garrisonCounted: false,
            x: x,
            y: y,
          ));

      expect(
        () => applyAction(
          state,
          TransferTile(slot: 1, targetSlot: target, x: x, y: y),
          Rng(state.rngSeed),
        ),
        throwsMessage('tileHasTroops'),
      );
    });

    test('ship on tile — tileHasShips', () {
      final state = freshGame();
      final target = transferableSlots(state, 1).first;
      final (x, y) = findEdgeTile(state, 1);

      state.realm(1).ships.add(Ship(x: x, y: y));

      expect(
        () => applyAction(
          state,
          TransferTile(slot: 1, targetSlot: target, x: x, y: y),
          Rng(state.rngSeed),
        ),
        throwsMessage('tileHasShips'),
      );
    });
  });

  group('event', () {
    test('emits tileTransferred with correct payload', () {
      final state = freshGame();
      final target = transferableSlots(state, 1).first;
      final (x, y) = findEdgeTile(state, 1);

      final result = applyAction(
        state,
        TransferTile(slot: 1, targetSlot: target, x: x, y: y),
        Rng(state.rngSeed),
      );

      final event =
          result.events.singleWhere((e) => e.type == 'tileTransferred');
      expect(event.slot, target);
      expect(event.visibility, EventVisibility.public);
      expect(event.payload['x'], x);
      expect(event.payload['y'], y);
      expect(event.payload['from'], 1);
      // visibleTo for other slots should be true (public).
      expect(event.visibleTo(3), isTrue);
    });
  });

  group('JSON roundtrip', () {
    test('TransferTile.fromJson(toJson()) roundtrips correctly', () {
      final action = TransferTile(slot: 5, targetSlot: 12, x: 30, y: 20);
      final json = action.toJson();
      expect(json['type'], 'transferTile');
      expect(json['slot'], 5);
      expect(json['targetSlot'], 12);
      expect(json['x'], 30);
      expect(json['y'], 20);

      final decoded = PlayerAction.fromJson(json);
      expect(decoded, isA<TransferTile>());
      final tile = decoded as TransferTile;
      expect(tile.slot, 5);
      expect(tile.targetSlot, 12);
      expect(tile.x, 30);
      expect(tile.y, 20);
    });
  });
}
