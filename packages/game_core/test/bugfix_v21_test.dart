import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// 2026-06-24: online wars against the AI are fought interactively (the
/// server change lives in the backend tests); the engine gains a per-unit
/// war STANCE that steers an unattended (autopiloted) war round, and AI
/// sides keep a home guard on their base.
void main() {
  // A war-eligible two-realm state: human slot 1 vs AI slot 2, 50-man
  // armies, a shared border. The border tile (slot 2, touching slot 1) and
  // the facing slot-1 tile are returned via [out] as borderX/Y, frontX/Y.
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
    // Wars need a shared border: hand slot 2 a land tile next to slot 1.
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

  group('SetTroopStance', () {
    test('defaults to holding position and round-trips through JSON', () {
      final state = warReady({});
      final troop = state.realm(1).troops.single;
      expect(troop.stance, TroopStance.holdPosition);

      final next = applyAction(
              state,
              SetTroopStance(slot: 1, unitIndex: 0, stance: TroopStance.attack),
              Rng(state.rngSeed))
          .state;
      expect(next.realm(1).troops.single.stance, TroopStance.attack);

      final restored = Troop.fromJson(next.realm(1).troops.single.toJson());
      expect(restored.stance, TroopStance.attack);
    });

    test('an old save without a stance field defaults to holdPosition', () {
      final troop = Troop.fromJson({
        'name': 'Heer',
        'men': 50,
        'troopClass': 0,
        'quality': 1,
        'garrisonCounted': true,
        'x': 3,
        'y': 4,
      });
      expect(troop.stance, TroopStance.holdPosition);
    });

    test('rejects an unknown stance value', () {
      final state = warReady({});
      expect(
        () => applyAction(
            state,
            SetTroopStance(slot: 1, unitIndex: 0, stance: 7),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
      );
    });

    test('the stance can still be set during a war', () {
      final out = <String, int>{};
      var state = warReady(out);
      state = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      expect(state.activeWar, isNotNull);
      // Unlike recruit/move/drill, SetTroopStance is allowed mid-war.
      state = applyAction(
              state,
              SetTroopStance(slot: 1, unitIndex: 0, stance: TroopStance.attack),
              Rng(state.rngSeed))
          .state;
      expect(state.realm(1).troops.single.stance, TroopStance.attack);
    });
  });

  group('autopiloted human war side follows each unit stance', () {
    // Sets up: AI slot 2 attacks human slot 1; slot 2's capital is the border
    // tile, slot 1's lone unit stands on the facing tile with 3 war moves.
    GameState attackedAtFront(Map<String, int> out) {
      var state = warReady(out);
      state = applyAction(
              state, DeclareWar(slot: 2, targetSlot: 1), Rng(state.rngSeed))
          .state;
      final war = state.activeWar!;
      // Put the enemy "capital" right on the border so "toward the enemy" is
      // a single, well-defined step onto (borderX, borderY).
      state.realm(2)
        ..capitalX = out['borderX']!
        ..capitalY = out['borderY']!;
      // Slot 1's unit stands on the tile facing the border (its snapshot home
      // stays the original capital, captured at war start).
      state.realm(1).troops.single
        ..x = out['frontX']!
        ..y = out['frontY']!;
      war.movesLeft[1] = [3];
      return state;
    }

    test('holdPosition does NOT advance onto the enemy while it has troops',
        () {
      final out = <String, int>{};
      final state = attackedAtFront(out);
      // Default stance is holdPosition.
      runAiWarMovement(state, 1, Rng(state.rngSeed), <GameEvent>[]);
      final troop = state.realm(1).troops.single;
      expect(troop.x == out['borderX'] && troop.y == out['borderY'], isFalse,
          reason: 'a holding unit walks home, never onto the enemy capital');
    });

    test('attack advances onto the enemy capital', () {
      final out = <String, int>{};
      final state = attackedAtFront(out);
      state.realm(1).troops.single.stance = TroopStance.attack;
      runAiWarMovement(state, 1, Rng(state.rngSeed), <GameEvent>[]);
      final troop = state.realm(1).troops.single;
      expect(troop.x == out['borderX'] && troop.y == out['borderY'], isTrue);
    });

    test('holdPosition advances once the enemy has no troops left', () {
      final out = <String, int>{};
      final state = attackedAtFront(out);
      state.realm(2).troops.clear(); // enemy army wiped
      runAiWarMovement(state, 1, Rng(state.rngSeed), <GameEvent>[]);
      final troop = state.realm(1).troops.single;
      expect(troop.x == out['borderX'] && troop.y == out['borderY'], isTrue,
          reason: 'a holding unit marches only when the enemy is gone');
    });
  });

  test('an AI side keeps a home guard on its base during war', () {
    final out = <String, int>{};
    var state = warReady(out);
    // Give the AI a second unit so it can both guard and field an army.
    state = applyAction(
            state,
            RecruitTroops(
                slot: 2,
                men: 50,
                troopClass: TroopClass.infanterie,
                name: 'Wache'),
            Rng(state.rngSeed))
        .state;
    state = applyAction(
            state, DeclareWar(slot: 2, targetSlot: 1), Rng(state.rngSeed))
        .state;
    final war = state.activeWar!;
    // Park both AI units on the (relocated) capital = the border tile, so the
    // non-guard unit has a clear step toward slot 1.
    final bx = out['borderX']!;
    final by = out['borderY']!;
    state.realm(2)
      ..capitalX = bx
      ..capitalY = by;
    for (final t in state.realm(2).troops) {
      t
        ..x = bx
        ..y = by;
    }
    war.movesLeft[2] = [3, 3];
    final guard = state.realm(2).troops.first;
    // Clear the march path of defenders: this test pins the guard/march
    // split, not combat outcomes — a marcher charging a fortified equal
    // defender twice can (realistically) be annihilated en route.
    state.realm(1).troops.clear();

    runAiWarMovement(state, 2, Rng(state.rngSeed), <GameEvent>[]);

    expect(guard.x == bx && guard.y == by, isTrue,
        reason: 'the reserved home guard never marches out');
    expect(state.realm(2).troops.any((t) => t.x == bx && t.y == by), isTrue,
        reason: 'the base is never left wholly undefended');
    expect(state.realm(2).troops.any((t) => !(t.x == bx && t.y == by)), isTrue,
        reason: 'the other unit does march on the enemy');
  });
}
