import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// 2026-09-01, user request: an autopiloted ATTACK unit marches on the tile
/// its commander picked (`Troop.stanceTargetX/Y`) instead of the enemy
/// capital — the default whenever no tile was picked.
void main() {
  // Same two-realm setup the stance tests use: human slot 1 vs AI slot 2,
  // 50-man armies, a shared border. Returns the border tile (slot 2's, next
  // to slot 1) and the facing slot-1 tile via [out].
  GameState warReady(Map<String, int> out) {
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
    outer:
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) continue;
        for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
          if (map.inBounds(x + dx, y + dy) &&
              map.ownerAt(x + dx, y + dy) == 1) {
            map.owner[map.index(x, y)] = 2;
            state.realm(2).tileCount[Building.none]++;
            out['borderX'] = x;
            out['borderY'] = y;
            out['frontX'] = x + dx;
            out['frontY'] = y + dy;
            break outer;
          }
        }
      }
    }
    return state;
  }

  group('SetTroopStance march target', () {
    test('an attack order stores the picked tile and round-trips', () {
      final state = warReady({});
      final troop = state.realm(1).troops.single;
      expect(troop.stanceTargetX, isNull);

      final next = applyAction(
              state,
              SetTroopStance(
                  slot: 1,
                  unitIndex: 0,
                  stance: TroopStance.attack,
                  targetX: troop.x + 1,
                  targetY: troop.y),
              Rng(state.rngSeed))
          .state;
      final aimed = next.realm(1).troops.single;
      expect(aimed.stance, TroopStance.attack);
      expect(aimed.stanceTargetX, troop.x + 1);
      expect(aimed.stanceTargetY, troop.y);

      final restored = Troop.fromJson(aimed.toJson());
      expect(restored.stanceTargetX, troop.x + 1);
      expect(restored.stanceTargetY, troop.y);
    });

    test('holding position clears the target, as does an attack without one',
        () {
      var state = warReady({});
      final troop = state.realm(1).troops.single;
      SetTroopStance aim(int stance, {int? x, int? y}) => SetTroopStance(
          slot: 1, unitIndex: 0, stance: stance, targetX: x, targetY: y);

      state = applyAction(
              state,
              aim(TroopStance.attack, x: troop.x + 1, y: troop.y),
              Rng(state.rngSeed))
          .state;
      expect(state.realm(1).troops.single.stanceTargetX, isNotNull);

      state =
          applyAction(state, aim(TroopStance.holdPosition), Rng(state.rngSeed))
              .state;
      expect(state.realm(1).troops.single.stanceTargetX, isNull);
      expect(state.realm(1).troops.single.stanceTargetY, isNull);

      state = applyAction(
              state,
              aim(TroopStance.attack, x: troop.x + 1, y: troop.y),
              Rng(state.rngSeed))
          .state;
      state =
          applyAction(state, aim(TroopStance.attack), Rng(state.rngSeed)).state;
      expect(state.realm(1).troops.single.stanceTargetX, isNull,
          reason: 'an attack order without a tile restores the seat default');
    });

    test('a target off the map or on water is rejected', () {
      final state = warReady({});
      final map = state.map;
      expect(
        () => applyAction(
            state,
            SetTroopStance(
                slot: 1,
                unitIndex: 0,
                stance: TroopStance.attack,
                targetX: -1,
                targetY: 0),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
      );
      var water = -1;
      for (var i = 0; i < map.terrain.length; i++) {
        if (Terrain.isWater(map.terrain[i])) {
          water = i;
          break;
        }
      }
      expect(water, isNot(-1));
      expect(
        () => applyAction(
            state,
            SetTroopStance(
                slot: 1,
                unitIndex: 0,
                stance: TroopStance.attack,
                targetX: water % map.width,
                targetY: water ~/ map.width),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
      );
    });

    test('an old save without the fields marches on the enemy capital', () {
      final troop = Troop.fromJson({
        'name': 'Heer',
        'men': 50,
        'troopClass': 0,
        'quality': 1,
        'garrisonCounted': true,
        'x': 3,
        'y': 4,
        'stance': TroopStance.attack,
      });
      expect(troop.stanceTargetX, isNull);
      expect(troop.stanceTargetY, isNull);
    });
  });

  group('the autopilot marches an attack unit to its picked tile', () {
    // AI slot 2 attacks human slot 1; slot 2's capital sits on the border
    // tile, so "toward the enemy capital" is one step onto (borderX, borderY)
    // — any other destination proves the picked target won.
    GameState attackedAtFront(Map<String, int> out) {
      var state = warReady(out);
      state = applyAction(
              state, DeclareWar(slot: 2, targetSlot: 1), Rng(state.rngSeed))
          .state;
      state.realm(2)
        ..capitalX = out['borderX']!
        ..capitalY = out['borderY']!;
      state.realm(1).troops.single
        ..x = out['frontX']!
        ..y = out['frontY']!;
      state.activeWar!.movesLeft[1] = [3];
      return state;
    }

    test('without a target it still heads for the enemy capital', () {
      final out = <String, int>{};
      final state = attackedAtFront(out);
      state.realm(1).troops.single.stance = TroopStance.attack;
      runAiWarMovement(state, 1, Rng(state.rngSeed), <GameEvent>[]);
      final troop = state.realm(1).troops.single;
      expect(troop.x, out['borderX']);
      expect(troop.y, out['borderY']);
    });

    test('with a target it marches there instead', () {
      final out = <String, int>{};
      final state = attackedAtFront(out);
      final map = state.map;
      final troop = state.realm(1).troops.single;
      // A land tile of the unit's own realm, away from the enemy capital.
      int? tx, ty;
      for (var i = 0; i < map.terrain.length && tx == null; i++) {
        final x = i % map.width;
        final y = i ~/ map.width;
        if (map.owner[i] != 1 || !map.isLandAt(x, y)) continue;
        if (x == out['borderX'] && y == out['borderY']) continue;
        if (x == troop.x && y == troop.y) continue;
        tx = x;
        ty = y;
      }
      expect(tx, isNotNull);
      troop
        ..stance = TroopStance.attack
        ..stanceTargetX = tx
        ..stanceTargetY = ty;
      runAiWarMovement(state, 1, Rng(state.rngSeed), <GameEvent>[]);
      final moved = state.realm(1).troops.single;
      expect(moved.x == out['borderX'] && moved.y == out['borderY'], isFalse,
          reason: 'the picked target overrides the enemy capital');
      // It closed in on the picked tile (or stands on it already).
      final before =
          (out['frontX']! - tx!).abs() + (out['frontY']! - ty!).abs();
      final after = (moved.x - tx).abs() + (moved.y - ty).abs();
      expect(after, lessThan(before));
    });
  });
}
