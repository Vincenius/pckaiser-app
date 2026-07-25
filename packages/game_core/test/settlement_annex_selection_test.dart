import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Drag-select-to-annex ([planSettlementAnnexSelection]): plans a valid,
/// affordable, border-outward annex order from an arbitrary tile selection,
/// leaving unreachable / unaffordable tiles free. The planned list is
/// exactly what a `SettlementAnnexMany` of it annexes.
void main() {
  late GameState state;

  setUp(() {
    state = startGame(
            newGame(GameSetup(
              humans: [
                HumanPlayerSetup(
                    founderName: 'Hans', gender: 0, countrySlot: 1, dorfName: 'A'),
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
    // An army so DeclareWar is allowed (§11.1 needs troops to attack).
    final capital = state.realm(1);
    capital.troops.add(Troop(
      name: 'Heer',
      men: 500,
      troopClass: TroopClass.infanterie,
      quality: TroopQuality.regular,
      garrisonCounted: false,
      x: capital.capitalX,
      y: capital.capitalY,
    ));
    // Give slot 2 a tile bordering slot 1 (wars need a shared border).
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
  });

  /// Opens a settlement for winner slot 1 with slot 2 reduced to a straight
  /// 3-tile bare-land chain leading out of slot 1's border: c0 (bordering) —
  /// c1 — c2 (each only reachable through the previous). Returns the chain.
  List<(int, int)> settlementWithChain() {
    state = applyAction(state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
        .state;
    final war = state.activeWar!;
    war.phase = WarPhase.settlement;
    war.winnerSlot = 1;
    final map = state.map;
    for (var i = 0; i < map.terrain.length; i++) {
      if (map.owner[i] == 2) map.owner[i] = World.niemand;
    }
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
    state.realm(2).tileCount[Building.none] = 3;
    return chain;
  }

  int idx(int x, int y) => state.map.index(x, y);

  test('plans a valid border-outward order regardless of selection order', () {
    final chain = settlementWithChain();
    final [c0, c1, c2] = chain;
    state.activeWar!.remainingClaim = 1000;
    // Select the chain in REVERSE (farthest first) — the planner must still
    // return them nearest-first so each borders winner land at its turn.
    final plan = planSettlementAnnexSelection(state, [
      idx(c2.$1, c2.$2),
      idx(c1.$1, c1.$2),
      idx(c0.$1, c0.$2),
    ]);
    expect(plan, [
      (x: c0.$1, y: c0.$2),
      (x: c1.$1, y: c1.$2),
      (x: c2.$1, y: c2.$2),
    ]);

    // Dispatching a SettlementAnnexMany of the plan annexes exactly those.
    final result = applyAction(
        state,
        SettlementAnnexMany(slot: 1, tiles: plan),
        Rng(state.rngSeed));
    final map = result.state.map;
    expect(map.ownerAt(c0.$1, c0.$2), 1);
    expect(map.ownerAt(c1.$1, c1.$2), 1);
    expect(map.ownerAt(c2.$1, c2.$2), 1);
    expect(result.state.activeWar!.remainingClaim, 1000 - 300);
  });

  test('leaves unaffordable tiles (and everything behind them) out', () {
    final chain = settlementWithChain();
    final [c0, c1, c2] = chain;
    // 250 buys two bare tiles (100 each) — the third is unaffordable and,
    // being reachable only through c1, is dropped.
    state.activeWar!.remainingClaim = 250;
    final plan = planSettlementAnnexSelection(state, [
      idx(c0.$1, c0.$2),
      idx(c1.$1, c1.$2),
      idx(c2.$1, c2.$2),
    ]);
    expect(plan, [
      (x: c0.$1, y: c0.$2),
      (x: c1.$1, y: c1.$2),
    ]);
  });

  test('drops selected tiles not connected to the winner border', () {
    final chain = settlementWithChain();
    final [c0, c1, c2] = chain;
    state.activeWar!.remainingClaim = 1000;
    // Select only c1 and c2 — neither borders slot 1 without c0, so the
    // wave has no seed and nothing is planned.
    final plan = planSettlementAnnexSelection(state, [
      idx(c1.$1, c1.$2),
      idx(c2.$1, c2.$2),
    ]);
    expect(plan, isEmpty);
  });

  test('ignores non-loser tiles in the selection', () {
    final chain = settlementWithChain();
    final [c0, _, _] = chain;
    state.activeWar!.remainingClaim = 1000;
    final realm1 = state.realm(1);
    // Own capital + the border chain tile: only the enemy tile is planned.
    final plan = planSettlementAnnexSelection(state, [
      idx(realm1.capitalX, realm1.capitalY),
      idx(c0.$1, c0.$2),
    ]);
    expect(plan, [(x: c0.$1, y: c0.$2)]);
  });

  test('returns empty when not in a settlement', () {
    state = applyAction(state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
        .state;
    // Still in the rounds phase — no winner, no claim.
    expect(planSettlementAnnexSelection(state, [0, 1, 2]), isEmpty);
  });
}
