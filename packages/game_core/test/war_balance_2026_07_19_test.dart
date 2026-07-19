import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// 2026-07-19 war-balancing round (docs/HISTORY.md), user-designed:
///  3. war score is OCCUPATION-based (tile values + won battles), no
///     strength multiplier — "you get what you hold";
///  4. round initiative alternates (attacker opens even rounds, defender
///     odd ones) — tested in war_test.dart's HvH group;
///  6. plunder scales with the acting unit's strength (min strength,
///     loot/kill caps);
///  7. plundered fields are DEVASTATED (fallow for 3 years), not erased.
void main() {
  late GameState state;

  setUp(() {
    state = startGame(
            newGame(GameSetup(
              humans: [
                HumanPlayerSetup(
                    founderName: 'Hans',
                    gender: 0,
                    countrySlot: 1,
                    dorfName: 'A'),
              ],
              reformationYear: 1020,
              ottomanYear: 1040,
              seed: 2026,
            )),
            Rng(7))
        .state;
    state.year = 1010;
    state.realm(1).treasury = 50000;
    state.dynasty(2).status = DynastyStatus.ai;
    state.dynasty(2).humanPlayer = null;
    final realm = state.realm(1);
    realm.towns.single.troopCapacity = 2000;
    realm.troopCapacity = 2000;
    realm.population = 20000; // levy headroom for a big unit
    state = applyAction(
            state,
            RecruitTroops(
                slot: 1,
                men: 1000,
                troopClass: TroopClass.infanterie,
                name: 'Heer'),
            Rng(state.rngSeed))
        .state;
    // Wars need a shared border: hand slot 2 a tile next to slot 1.
    final map = state.map;
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
            break outer;
          }
        }
      }
    }
  });

  GameState declareWar() =>
      applyAction(state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;

  /// First enemy Kornfeld/Weide tile of slot 2, or null.
  (int, int)? enemyField(GameState s) {
    final map = s.map;
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != 2) continue;
        final b = map.buildingAt(x, y);
        if (b == Building.kornfeld || b == Building.weide) return (x, y);
      }
    }
    return null;
  }

  group('war score is occupation-based (point 3)', () {
    test('a stack counts its tile once, and strength does not multiply', () {
      final s = declareWar();
      final town = s.realm(2).towns.single;
      final troop = s.realm(1).troops.single;
      troop.x = town.x;
      troop.y = town.y;
      final tileValue = Building.value[s.map.buildingAt(town.x, town.y)];
      expect(warScore(s, 1), tileValue,
          reason: 'score = occupied tile worth, no strength factor');

      // A second unit on the SAME tile adds nothing.
      s.realm(1).troops.add(Troop(
            name: 'Zweite',
            men: 500,
            troopClass: TroopClass.infanterie,
            quality: TroopQuality.regular,
            garrisonCounted: false,
            x: town.x,
            y: town.y,
          ));
      expect(warScore(s, 1), tileValue,
          reason: 'stacking a tile must not double its worth');
    });

    test('won battles add their bonus to the score', () {
      final s = declareWar();
      s.activeWar!.attackerBattlesWon = 4;
      expect(warScore(s, 1), 4 * warScoreBattleBonus);
      expect(warScore(s, 2), 0);
    });

    test('resolveCombat credits the winner\'s battle tally', () {
      final s = declareWar();
      final attacker = s.realm(1).troops.single;
      final weak = Troop(
        name: 'Häuflein',
        men: 10,
        troopClass: TroopClass.infanterie,
        quality: TroopQuality.regular,
        garrisonCounted: false,
        x: attacker.x,
        y: attacker.y,
      );
      s.realm(2).troops.add(weak);
      resolveCombat(s, 1, attacker, 2, weak, Rng(1));
      expect(s.activeWar!.attackerBattlesWon, 1,
          reason: '1000 vs 10 men: the attacker wins and is credited');
      expect(s.activeWar!.defenderBattlesWon, 0);
    });
  });

  group('plunder scales with unit strength (point 6)', () {
    test('a 1-man splinter is too weak to plunder', () {
      final s = declareWar();
      final town = s.realm(2).towns.single;
      s.realm(1).troops.add(Troop(
            name: 'Splitter',
            men: 5, // strength 0.5 < minPlunderStrength
            troopClass: TroopClass.infanterie,
            quality: TroopQuality.regular,
            garrisonCounted: false,
            x: town.x,
            y: town.y,
          ));
      expect(
        () => applyAction(
            s, WarPlunder(slot: 1, x: town.x, y: town.y), Rng(1)),
        throwsA(isA<ActionException>()),
        reason: 'below the minimum plunder strength',
      );
    });

    test('loot and kills are capped by the unit\'s strength', () {
      final s = declareWar();
      final town = s.realm(2).towns.single;
      town.population = 100000; // a huge prize the cap must bound
      s.realm(2).population = 100000;
      // A 100-man regular unit: strength 10 → loot ≤ 100 T, kills ≤ 50.
      final unit = Troop(
        name: 'Räuber',
        men: 100,
        troopClass: TroopClass.infanterie,
        quality: TroopQuality.regular,
        garrisonCounted: false,
        x: town.x,
        y: town.y,
      );
      // Replace the big army so the small unit carries the plunder.
      s.realm(1).troops
        ..clear()
        ..add(unit);
      for (var seed = 0; seed < 30; seed++) {
        for (final t in s.realm(1).troops) {
          t.plunderedThisRound = false;
        }
        final events =
            applyAction(s, WarPlunder(slot: 1, x: town.x, y: town.y),
                    Rng(seed))
                .events;
        final p = events.singleWhere((e) => e.type == 'plunder').payload;
        expect(p['loot'], lessThanOrEqualTo(10 * plunderLootPerStrength),
            reason: 'loot ≤ strength × $plunderLootPerStrength (seed $seed)');
        expect(p['killed'], lessThanOrEqualTo(10 * plunderKillsPerStrength),
            reason: 'kills ≤ strength × $plunderKillsPerStrength '
                '(seed $seed)');
      }
    });

    test('the strongest unspent unit on the tile carries the plunder', () {
      final s = declareWar();
      final town = s.realm(2).towns.single;
      town.population = 100000;
      s.realm(2).population = 100000;
      final big = s.realm(1).troops.single; // 1000 men, strength 100
      big.x = town.x;
      big.y = town.y;
      s.realm(1).troops.insert(
          0,
          Troop(
            name: 'Splitter',
            men: 10, // strength 1 — plunder-capable, but weaker
            troopClass: TroopClass.infanterie,
            quality: TroopQuality.regular,
            garrisonCounted: false,
            x: town.x,
            y: town.y,
          ));
      applyAction(s, WarPlunder(slot: 1, x: town.x, y: town.y), Rng(1));
      // applyAction works on a copy — re-run in place semantics via the
      // returned state instead.
      final after =
          applyAction(s, WarPlunder(slot: 1, x: town.x, y: town.y), Rng(1))
              .state;
      expect(after.realm(1).troops[1].plunderedThisRound, isTrue,
          reason: 'the 1000-man army carried the plunder');
      expect(after.realm(1).troops[0].plunderedThisRound, isFalse,
          reason: 'the splinter keeps its own plunder for later');
    });
  });

  group('auto-annex wave from the border (user request 2026-07-19)', () {
    /// Puts the declared war into an open settlement for winner slot 1
    /// and reduces slot 2's land to a bare 3-tile chain leading straight
    /// away from slot 1's border: c0 (on the border) — c1 — c2, where c1
    /// and c2 do NOT touch slot 1 directly and are only reachable through
    /// the chain. Returns (state, chain tiles).
    (GameState, List<(int, int)>) settlementWithChain() {
      final s = declareWar();
      final war = s.activeWar!;
      war.phase = WarPhase.settlement;
      war.winnerSlot = 1;
      final map = s.map;
      // Strip slot 2's land — the chain must be the ONLY annexable area,
      // or natural border tiles elsewhere would soak up the claim first.
      for (var i = 0; i < map.terrain.length; i++) {
        if (map.owner[i] == 2) map.owner[i] = World.niemand;
      }
      // A straight 3-tile run of free land leading out of slot 1's border.
      List<(int, int)>? chain;
      outer:
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) != 1) continue;
          for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            final candidate = <(int, int)>[];
            var ok = true;
            for (var k = 1; k <= 3; k++) {
              final nx = x + dx * k;
              final ny = y + dy * k;
              if (!map.inBounds(nx, ny) ||
                  !map.isLandAt(nx, ny) ||
                  map.ownerAt(nx, ny) == 1 ||
                  (k > 1 && map.bordersSlot(nx, ny, 1))) {
                ok = false;
                break;
              }
              candidate.add((nx, ny));
            }
            if (ok) {
              chain = candidate;
              break outer;
            }
          }
        }
      }
      expect(chain, isNotNull, reason: 'the map has a straight border run');
      for (final (cx, cy) in chain!) {
        map.owner[map.index(cx, cy)] = 2;
        map.building[map.index(cx, cy)] = Building.none;
      }
      s.realm(2).tileCount[Building.none] = 3;
      return (s, chain);
    }

    test('a partial claim grows a compact wave, nearest tiles first', () {
      final (s, chain) = settlementWithChain();
      final [c0, c1, c2] = chain;
      // 250 buys two bare tiles (100 each) — the wave must take the two
      // NEAREST chain tiles and stop before the third.
      s.activeWar!.remainingClaim = 250;
      final events = <GameEvent>[];
      annexAffordableTiles(s, events);
      expect(s.map.ownerAt(c0.$1, c0.$2), 1, reason: 'border tile annexed');
      expect(s.map.ownerAt(c1.$1, c1.$2), 1, reason: 'wave advances inward');
      expect(s.map.ownerAt(c2.$1, c2.$2), 2,
          reason: 'the claim is spent — the farthest tile stays');
      expect(s.activeWar!.remainingClaim, 50);
      expect(events.where((e) => e.type == 'tileConquered').length, 2);
    });

    test('an unaffordable border tile stops the wave locally', () {
      final (s, chain) = settlementWithChain();
      final [c0, c1, c2] = chain;
      // The border tile is a Burg (5,000) the claim cannot afford — the
      // cheap tiles BEHIND it are unreachable (annexes must border the
      // winner's land), so nothing is taken at all.
      s.map.building[s.map.index(c0.$1, c0.$2)] = Building.burg;
      s.realm(2).tileCount[Building.none] = 2;
      s.realm(2).tileCount[Building.burg] = 1;
      s.activeWar!.remainingClaim = 250;
      final events = <GameEvent>[];
      annexAffordableTiles(s, events);
      expect(s.map.ownerAt(c0.$1, c0.$2), 2);
      expect(s.map.ownerAt(c1.$1, c1.$2), 2);
      expect(s.map.ownerAt(c2.$1, c2.$2), 2);
      expect(s.activeWar!.remainingClaim, 250);
      expect(events, isEmpty);
    });
  });

  group('fields are devastated, not erased (point 7)', () {
    test('plunder keeps owner and building, sets the recovery year', () {
      final s = declareWar();
      final field = enemyField(s);
      expect(field, isNotNull, reason: 'slot 2 starts with fields');
      final (fx, fy) = field!;
      final troop = s.realm(1).troops.single;
      troop.x = fx;
      troop.y = fy;

      final result =
          applyAction(s, WarPlunder(slot: 1, x: fx, y: fy), Rng(1));
      final after = result.state;
      final building = after.map.buildingAt(fx, fy);
      expect(after.map.ownerAt(fx, fy), 2,
          reason: 'the field is NOT struck from the loser\'s land');
      expect(building == Building.kornfeld || building == Building.weide,
          isTrue,
          reason: 'the building survives the plunder');
      expect(after.map.isDevastatedAt(fx, fy, after.year), isTrue);
      expect(after.map.devastatedUntil[after.map.index(fx, fy)],
          after.year + fieldDevastationYears);
      final p =
          result.events.singleWhere((e) => e.type == 'plunder').payload;
      expect(p['destroyed'], isTrue);
      expect(p['recoversIn'], fieldDevastationYears);

      // Recovery: once the year reaches the mark, the field works again.
      after.year += fieldDevastationYears;
      expect(after.map.isDevastatedAt(fx, fy, after.year), isFalse);
    });

    test('a devastated field yields nothing until it recovers', () {
      final realm = state.realm(1);
      final map = state.map;
      // Devastate EVERY field slot 1 owns.
      for (var i = 0; i < map.terrain.length; i++) {
        if (map.owner[i] != 1) continue;
        if (map.building[i] == Building.kornfeld ||
            map.building[i] == Building.weide) {
          map.devastatedUntil[i] = state.year + fieldDevastationYears;
        }
      }
      final report =
          runFoodAndPopulation(state, realm, Rng(1), <GameEvent>[]);
      expect(report.grainYield, 0,
          reason: 'fallow fields produce no grain');
      expect(report.livestockYield, 0,
          reason: 'fallow pastures produce no livestock');

      // After recovery the same fields yield again.
      state.year += fieldDevastationYears;
      final recovered =
          runFoodAndPopulation(state, realm, Rng(1), <GameEvent>[]);
      expect(recovered.grainYield, greaterThan(0));
    });
  });
}
