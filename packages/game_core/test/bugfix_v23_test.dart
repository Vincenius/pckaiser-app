import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// A human slot 1 next to an AI slot 2, sharing a border — mirrors the
/// war_test setUp. Both have a 50-man infantry unit and 10,000 T.
GameState warReadyGame() {
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
  // Hand slot 2 a land tile right next to slot 1's territory (shared border).
  final map = state.map;
  outer:
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) continue;
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        if (map.inBounds(x + dx, y + dy) && map.ownerAt(x + dx, y + dy) == 1) {
          map.owner[map.index(x, y)] = 2;
          state.realm(2).tileCount[Building.none]++;
          break outer;
        }
      }
    }
  }
  return state;
}

/// Strips slot 2 down to a SINGLE Hafen tile bordering slot 1 (its Burg and
/// every other tile gone), and stands slot 1's unit on that Hafen so the
/// limited-victory war score points at slot 1. Returns the Hafen's coords.
(int, int) reduceLoserToLoneHafen(GameState state) {
  final map = state.map;
  // The tile slot 2 owns that borders slot 1 (the one warReadyGame added).
  int hx = -1, hy = -1;
  outer:
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.ownerAt(x, y) != 2) continue;
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        if (map.inBounds(x + dx, y + dy) && map.ownerAt(x + dx, y + dy) == 1) {
          hx = x;
          hy = y;
          break outer;
        }
      }
    }
  }
  expect(hx, greaterThanOrEqualTo(0));
  // Drop every other slot-2 tile, then leave only the lone Hafen.
  for (var i = 0; i < map.owner.length; i++) {
    if (map.owner[i] == 2) {
      map.owner[i] = World.niemand;
      map.building[i] = Building.none;
    }
  }
  final loser = state.realm(2);
  map.owner[map.index(hx, hy)] = 2;
  map.building[map.index(hx, hy)] = Building.hafen;
  for (var b = 0; b < loser.tileCount.length; b++) {
    loser.tileCount[b] = 0;
  }
  loser.tileCount[Building.hafen] = 1;
  loser.towns.clear();
  loser.troops.clear();
  // Slot 1's unit occupies the Hafen — its only foothold on enemy soil.
  state.realm(1).troops.first
    ..x = hx
    ..y = hy;
  state.rebuildTroopMarkers();
  return (hx, hy);
}

/// Strips slot 2 down to a small rump worth less than a Burg: a Markt (2,500)
/// bordering slot 1 plus an adjacent Hafen (700) — 3,200 < 5,000 total. Slot
/// 1's unit stands on the Markt. Returns (Markt, Hafen) coords.
((int, int), (int, int)) reduceLoserToSmallRump(GameState state) {
  final map = state.map;
  int mx = -1, my = -1;
  outer:
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.ownerAt(x, y) != 2) continue;
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        if (map.inBounds(x + dx, y + dy) && map.ownerAt(x + dx, y + dy) == 1) {
          mx = x;
          my = y;
          break outer;
        }
      }
    }
  }
  expect(mx, greaterThanOrEqualTo(0));
  // A free land tile next to the Markt becomes the Hafen (reachable once the
  // Markt is annexed).
  int hx = -1, hy = -1;
  for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
    final nx = mx + dx, ny = my + dy;
    if (map.inBounds(nx, ny) &&
        !map.isWaterAt(nx, ny) &&
        map.ownerAt(nx, ny) == World.niemand) {
      hx = nx;
      hy = ny;
      break;
    }
  }
  expect(hx, greaterThanOrEqualTo(0), reason: 'a free tile borders the Markt');
  for (var i = 0; i < map.owner.length; i++) {
    if (map.owner[i] == 2) {
      map.owner[i] = World.niemand;
      map.building[i] = Building.none;
    }
  }
  final loser = state.realm(2);
  map.owner[map.index(mx, my)] = 2;
  map.building[map.index(mx, my)] = Building.markt;
  map.owner[map.index(hx, hy)] = 2;
  map.building[map.index(hx, hy)] = Building.hafen;
  for (var b = 0; b < loser.tileCount.length; b++) {
    loser.tileCount[b] = 0;
  }
  loser.tileCount[Building.markt] = 1;
  loser.tileCount[Building.hafen] = 1;
  loser.towns.clear();
  loser.troops.clear();
  state.realm(1).troops.first
    ..x = mx
    ..y = my;
  state.rebuildTroopMarkers();
  return ((mx, my), (hx, hy));
}

void main() {
  group('war claim floor (rules v15)', () {
    test(
        'a winner can always claim the cheapest remaining loser tile — '
        'a lone Hafen after the Burg is gone', () {
      var s = warReadyGame();
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      final (hx, hy) = reduceLoserToLoneHafen(s);
      final hafenValue = settlementTileValue(s, Building.hafen);
      expect(hafenValue, 700);

      // Winter forces the end: slot 1 leads on score and wins.
      final events = <GameEvent>[];
      resolveWarEnd(s, Rng(s.rngSeed), events);

      expect(s.activeWar!.winnerSlot, 1);
      expect(s.activeWar!.phase, WarPhase.settlement);
      // Without the floor the cap (50–80 % of a 700-value realm = 350–560)
      // would fall below the Hafen's 700 cost and the winner could take
      // nothing. The floor guarantees the single cheapest bordering tile.
      expect(s.activeWar!.remainingClaim, greaterThanOrEqualTo(hafenValue),
          reason: 'the floor lifts the claim to the lone Hafen\'s cost');

      // The winner can now actually take the Hafen.
      s = applyAction(s, SettlementAnnex(slot: 1, x: hx, y: hy), Rng(s.rngSeed))
          .state;
      expect(s.map.ownerAt(hx, hy), 1,
          reason: 'the remaining part is finally claimable');
    });

    test('a realm worth less than a Burg (5,000) is taken whole', () {
      var s = warReadyGame();
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      final ((mx, my), (hx, hy)) = reduceLoserToSmallRump(s);
      final total = settlementTileValue(s, Building.markt) +
          settlementTileValue(s, Building.hafen);
      expect(total, 3200);

      final events = <GameEvent>[];
      resolveWarEnd(s, Rng(s.rngSeed), events);
      expect(s.activeWar!.winnerSlot, 1);
      // Below 5,000 the cap is lifted entirely: the claim covers the whole
      // rump (the 50–80 % cap would have left the 2,500 Markt out of reach).
      expect(s.activeWar!.remainingClaim, total,
          reason: 'a sub-Burg realm can be taken whole');

      s = applyAction(s, SettlementTakeAll(slot: 1), Rng(s.rngSeed)).state;
      expect(s.map.ownerAt(mx, my), 1);
      expect(s.map.ownerAt(hx, hy), 1, reason: 'nothing of the rump is left');
    });
  });

  group('landless realm vacate (rules v15)', () {
    test('a realm with no tiles is vacated and unblocks the sole-ruler win',
        () {
      var s = warReadyGame();
      for (final realm in s.realms) {
        if (realm.slot != 1 && realm.slot != 2) realm.rulerId = null;
      }
      // Slot 2 loses all land to a non-war cause (e.g. an earthquake) but
      // keeps its ruler — exactly the "zombie" that blocked the win.
      final map = s.map;
      for (var i = 0; i < map.owner.length; i++) {
        if (map.owner[i] == 2) {
          map.owner[i] = World.niemand;
          map.building[i] = Building.none;
        }
      }
      final loser = s.realm(2);
      for (var b = 0; b < loser.tileCount.length; b++) {
        loser.tileCount[b] = 0;
      }
      expect(checkWinCondition(s), isNull,
          reason: 'a landless ruler still counts — the win is blocked');

      // Every land-loss cause (earthquake, bankruptcy, war teardown) calls
      // checkLandLoss inline — the old once-per-round sweep is gone.
      final events = <GameEvent>[];
      checkLandLoss(s, s.realm(2), events);

      expect(s.realm(2).isVacant, isTrue);
      expect(events.any((e) => e.type == 'realmOverrun'), isTrue);
      expect(checkWinCondition(s), 1,
          reason: 'with the zombie gone, slot 1 owns everything');
    });
  });

  group('sole-ruler victory (rules v15)', () {
    test(
        'overrunning the last rival emits gameWon immediately — not only at '
        'the winner\'s next end of turn', () {
      var s = warReadyGame();
      // Make slot 1 vs slot 2 the only living realms.
      for (final realm in s.realms) {
        if (realm.slot != 1 && realm.slot != 2) realm.rulerId = null;
      }
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      final (hx, hy) = reduceLoserToLoneHafen(s);

      final events = <GameEvent>[];
      resolveWarEnd(s, Rng(s.rngSeed), events);
      expect(s.activeWar!.winnerSlot, 1);

      // Take the loser's last tile: slot 2 is overrun and slot 1 stands
      // alone — the victory must surface right here.
      final result = applyAction(s, SettlementTakeAll(slot: 1), Rng(s.rngSeed));
      s = result.state;

      expect(s.map.ownerAt(hx, hy), 1);
      expect(s.realm(2).rulerId, isNull, reason: 'the last rival is overrun');
      expect(checkWinCondition(s), 1);
      expect(result.events.any((e) => e.type == 'gameWon'), isTrue,
          reason: 'gameWon is emitted the instant the last rival loses land');
      expect(s.events.last.type, 'gameWon',
          reason: 'the client shows the victory popup off the last event');
    });

    test('an AI-vs-AI conquest does NOT emit a mid-turn gameWon', () {
      var s = warReadyGame();
      s.dynasty(1).status = DynastyStatus.ai; // both sides AI now
      s.dynasty(1).humanPlayer = null;
      for (final realm in s.realms) {
        if (realm.slot != 1 && realm.slot != 2) realm.rulerId = null;
      }
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      reduceLoserToLoneHafen(s);

      final events = <GameEvent>[];
      resolveWarEnd(s, Rng(s.rngSeed), events);
      // AI winner auto-settles inside resolveWarEnd; the win is left to the
      // normal end-of-turn check, so no gameWon leaks out mid-turn.
      expect(events.any((e) => e.type == 'gameWon'), isFalse);
    });
  });
}
