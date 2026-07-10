import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// A fresh all-AI world at the given difficulty. War is gated far in the
/// future so the assassination/military probes below never collide with a
/// spontaneous war declaration.
GameState aiGame(AiDifficulty difficulty, {int seed = 2026}) => startGame(
        newGame(GameSetup(
          humans: const [],
          reformationYear: 1020,
          ottomanYear: 1040,
          warStartYear: 2000,
          aiDifficulty: difficulty,
          seed: seed,
        )),
        Rng(seed))
    .state;

void main() {
  group('AiDifficulty option plumbing', () {
    test('flows from GameSetup into the state and serializes', () {
      final state = aiGame(AiDifficulty.schwer);
      expect(state.aiDifficulty, AiDifficulty.schwer);
      final json = state.toJson();
      expect(json['aiDifficulty'], 'schwer');
      expect(GameState.fromJson(json).aiDifficulty, AiDifficulty.schwer);
    });

    test('old saves without the field default to mittel', () {
      final json = aiGame(AiDifficulty.leicht).toJson()..remove('aiDifficulty');
      expect(GameState.fromJson(json).aiDifficulty, AiDifficulty.mittel);
      expect(AiDifficulty.fromName('nightmare'), AiDifficulty.mittel,
          reason: 'unknown values from a future build must not crash');
    });

    test('mittel tuning reproduces the pre-difficulty script constants', () {
      final tuning = aiTuningFor(AiDifficulty.mittel);
      expect(tuning.grainSellMin, 1.6);
      expect(tuning.cattleSellMin, 2.2);
      expect(tuning.foodFactor, 1.0);
      expect(tuning.burgChance, 20);
      expect(tuning.reinforceDivisor, 1);
      expect(tuning.capacityTarget, 0, reason: 'no planned recruiting');
      expect(tuning.kavallerieTreasury, 0);
      expect(tuning.drillMaxQuality, TroopQuality.regular);
      expect(tuning.warChance, 20);
      expect(tuning.warStrengthAdvantage, 0, reason: 'original target pick');
      expect(tuning.assassinChance, 40);
      // Pins the mittel TURN ORDER, not just a knob: flipping this moves
      // the assassination RNG draw before the build loop and silently
      // changes every old save's replay determinism.
      expect(tuning.assassinateEarly, isFalse);
      expect(tuning.smartAssassinTarget, isFalse);
      expect(tuning.assassinTreasuryDivisor, 4);
      expect(tuning.assassinMaxAgents, 20);
    });
  });

  group('leicht', () {
    test('never assassinates, however rich and however the dice fall', () {
      final base = aiGame(AiDifficulty.leicht);
      base.year = 1011; // past the protection window
      base.realm(1).treasury = 20000;
      _makeNeighbor(base, 1); // give it a target so the test isn't vacuous
      for (var seed = 0; seed < 80; seed++) {
        final result = runAiTurn(base, 1, Rng(seed));
        expect(result.events.where((e) => e.type == 'assassinsDispatched'),
            isEmpty,
            reason: 'seed $seed');
      }
    });

    test('still raises a first unit at free capacity 1', () {
      // Regression: the halving divisor made (rng.nextInt(1) + 1) ~/ 2
      // deterministically 0 — a troopless leicht realm with one free
      // quarter could never arm at all.
      final state = aiGame(AiDifficulty.leicht);
      final realm = state.realm(1);
      realm.treasury = 5000;
      realm.towns.single.troopCapacity = 1;
      realm.troopCapacity = 1;
      final result = runAiTurn(state, 1, Rng(7));
      expect(result.state.realm(1).troops, isNotEmpty,
          reason: 'the first unit must always be raisable');
    });

    test('sells harvests even at rock-bottom prices', () {
      final state = aiGame(AiDifficulty.leicht);
      state.grainPrice = 1.0; // below every mittel threshold
      state.cattlePrice = 1.5;
      state.realm(1).grainHarvest = 500;
      final result = runAiTurn(state, 1, Rng(state.rngSeed));
      expect(result.events.any((e) => e.type == 'goodsSold'), isTrue);
      expect(result.state.realm(1).grainHarvest, 0);
    });
  });

  group('schwer', () {
    test('assassinates rivals over enough turns', () {
      final base = aiGame(AiDifficulty.schwer);
      base.year = 1011;
      base.realm(1).treasury = 20000;
      _makeNeighbor(base, 1); // a fresh realm has no bordering rivals yet
      var dispatched = false;
      for (var seed = 0; seed < 80 && !dispatched; seed++) {
        final result = runAiTurn(base, 1, Rng(seed));
        dispatched =
            result.events.any((e) => e.type == 'assassinsDispatched');
      }
      // P(miss in 80 turns) = (14/15)^80 ≈ 0.4% — a failure here means the
      // schwer assassination path broke, not bad luck.
      expect(dispatched, isTrue);
    });

    test('fills the army toward 80% capacity, raises Kavallerie and drills',
        () {
      final state = aiGame(AiDifficulty.schwer);
      final realm = state.realm(1);
      realm.treasury = 30000;
      realm.towns.single.troopCapacity = 100;
      realm.troopCapacity = 100;
      final result = runAiTurn(state, 1, Rng(state.rngSeed));
      final after = result.state.realm(1);
      expect(after.armySize,
          greaterThanOrEqualTo((after.troopCapacity * 0.8).floor()),
          reason: 'planned recruiting fills toward the capacity target');
      expect(after.troops.any((t) => t.troopClass == TroopClass.kavallerie),
          isTrue,
          reason: 'a rich schwer AI raises Kavallerie');
      expect(after.troops.any((t) => t.quality > TroopQuality.regular), isTrue,
          reason: 'schwer drills its regulars');
      expect(after.treasury, greaterThan(0),
          reason: 'the war chest must never be fully spent');
      expect(after.troops.where((t) => t.garrisonCounted).length,
          greaterThanOrEqualTo(2),
          reason: 'the army is split so a war home guard can stay behind');
      final names = [for (final t in after.troops) t.name];
      expect(names.toSet().length, names.length,
          reason: 'unique unit names — war snapshots pair units by name');
    });

    test('only declares war on a clearly weaker neighbour', () {
      final state = aiGame(AiDifficulty.schwer, seed: 9);
      state.year = 2001; // past the (deferred) war gate
      final realm = state.realm(1);
      realm.treasury = 30000;
      realm.towns.single.troopCapacity = 300;
      realm.troopCapacity = 300;
      _makeNeighbor(state, 1);
      // Arm every neighbour beyond our reach: no war may be declared.
      for (final n in state.map.realmNeighbors(1)) {
        final other = state.realm(n);
        if (other.isVacant) continue;
        other.troops.add(Troop(
          name: 'Übermacht',
          men: 5000,
          troopClass: TroopClass.artillerie,
          quality: 10,
          garrisonCounted: false,
          x: other.capitalX,
          y: other.capitalY,
        ));
      }
      for (var seed = 0; seed < 40; seed++) {
        final result = runAiTurn(state, 1, Rng(seed));
        expect(result.state.activeWar, isNull, reason: 'seed $seed');
        expect(result.events.where((e) => e.type == 'warDeclared'), isEmpty,
            reason: 'schwer must not attack a stronger neighbour (seed $seed)');
      }
    });
  });
}

/// Gives another living realm one tile orthogonally touching [slot]'s
/// territory, so target picks (assassination, war) have a neighbour.
void _makeNeighbor(GameState state, int slot) {
  if (state.map.realmNeighbors(slot).isNotEmpty) return;
  final map = state.map;
  final other =
      state.realms.firstWhere((r) => r.slot != slot && !r.isVacant).slot;
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) {
        continue;
      }
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        if (map.inBounds(x + dx, y + dy) &&
            map.ownerAt(x + dx, y + dy) == slot) {
          map.owner[map.index(x, y)] = other;
          state.realm(other).tileCount[Building.none]++;
          return;
        }
      }
    }
  }
  fail('no free tile bordering slot $slot');
}
