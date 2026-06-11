import 'dart:math' as math;

import '../actions/apply_action.dart';
import '../actions/player_action.dart';
import '../data/tables.dart';
import '../rng/rng.dart';
import '../rules/espionage.dart';
import '../rules/realm_merge.dart';
import '../rules/troops.dart' show troopStrength;
import '../rules/war.dart';
import '../state/constants.dart';
import '../state/dynasty.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/realm.dart';
import '../state/troop.dart';
import '../state/war.dart';
import '../state/world_map.dart';
import '../turn/turn_pipeline.dart';

/// AI action phase for [slot] (ORIGINAL_GAME.md §20): "Die `<name>` zieht."
/// Uses the same action primitives as humans via [applyActionInPlace].
/// Pure: returns a new state plus the emitted events.
///
/// Defensive guard: the AI script must never act for a human-controlled
/// dynasty — a caller bug here would silently play the player's realm.
TurnResult runAiTurn(GameState state, int slot, Rng rng) {
  if (state.dynasty(slot).status == DynastyStatus.human) {
    return TurnResult(state, const []);
  }
  final next = state.copy();
  final events = <GameEvent>[];
  _runAiTurnInPlace(next, slot, rng, events);
  next.rngSeed = rng.seed;
  next.events.addAll(events);
  return TurnResult(next, events);
}

void _act(GameState state, PlayerAction action, Rng rng,
    List<GameEvent> events) {
  events.addAll(applyActionInPlace(state, action, rng));
}

void _runAiTurnInPlace(
    GameState state, int slot, Rng rng, List<GameEvent> events) {
  final realm = state.realm(slot);
  if (realm.isVacant) return;

  // §20.2 Sell harvests at the upper ~40% of each price range; never
  // stockpiles. (§20.3 pot collection already happens in upkeep.)
  if (state.grainPrice > 1.6 && realm.grainHarvest > 0) {
    _act(state,
        SellGood(slot: slot, good: MarketGood.grain, amount: realm.grainHarvest),
        rng, events);
  }
  if (state.cattlePrice > 2.2 && realm.livestockHarvest > 0) {
    _act(
        state,
        SellGood(
            slot: slot,
            good: MarketGood.cattle,
            amount: realm.livestockHarvest),
        rng,
        events);
  }

  // §20.4 Build loop.
  var warFlag = false;
  while (realm.movementPoints > 0) {
    final action = _pickBuildAction(state, realm, rng);
    if (action == null) {
      warFlag = true; // boxed in (§20.4)
      break;
    }
    try {
      _act(state, action, rng, events);
    } on ActionException {
      break; // defensive: a stale target pick must not kill the AI turn
    }
  }

  // §20.5 Reinforce, guards, ships.
  _reinforce(state, realm, rng, events);
  _adjustGuardsTowardTarget(state, realm, rng, events);
  _investInShips(state, realm, rng, events);

  // (§20.6 marriage/heir upkeep runs in the shared dynasty phase.)

  // §20.7 Merge one randomly-chosen other slot ruled by the same ruler.
  final mergeable = mergeableSlots(state, slot);
  if (mergeable.isNotEmpty) {
    _act(
        state,
        MergeRealms(
            slot: slot,
            sourceSlot: mergeable[rng.nextInt(mergeable.length)]),
        rng,
        events);
  }

  // §20.8 War.
  if ((warFlag || rng.nextInt(20) == 0) &&
      rng.nextInt(7) == 0 &&
      state.year > 1009 &&
      !realm.warThisYear &&
      state.activeWar == null &&
      realm.troops.any((t) => t.men > 0)) {
    final target = _pickWarTarget(state, slot, rng);
    if (target != null) {
      try {
        _act(state, DeclareWar(slot: slot, targetSlot: target), rng, events);
      } on ActionException {
        return; // defensive: an invalid pick must not kill the AI turn
      }
      _fastForwardAiWar(state, rng, events);
    }
  }
}

/// §20.4 build-loop target selection: first matching tile in a map scan.
PlayerAction? _pickBuildAction(GameState state, Realm realm, Rng rng) {
  final map = state.map;
  final slot = realm.slot;

  (int, int)? findOwned(bool Function(int x, int y, int building) test) {
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != slot) continue;
        if (test(x, y, map.buildingAt(x, y))) return (x, y);
      }
    }
    return null;
  }

  (int, int)? findClaimable() {
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) {
          continue;
        }
        for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
          if (map.inBounds(x + dx, y + dy) &&
              map.ownerAt(x + dx, y + dy) == slot) {
            return (x, y);
          }
        }
      }
    }
    return null;
  }

  // Keep food up: tileCount[Kornfeld] × 9 ≳ population.
  if (realm.tileCount[Building.kornfeld] * 9 < realm.population) {
    final field = findOwned((x, y, b) =>
        b == Building.none &&
        (map.terrainAt(x, y) == Terrain.ebene && realm.treasury >= 100 ||
            map.terrainAt(x, y) == Terrain.berg && realm.treasury >= 150));
    if (field != null) {
      final (x, y) = field;
      final berg = map.terrainAt(x, y) == Terrain.berg;
      return Build(
          slot: slot,
          x: x,
          y: y,
          building: berg ? Building.weide : Building.kornfeld);
    }
    final claim = findClaimable();
    if (claim != null) {
      return ClaimTile(slot: slot, x: claim.$1, y: claim.$2);
    }
  }

  // Found a Dorf.
  if (realm.treasury >= 1000) {
    final spot = findOwned((x, y, b) => b == Building.none);
    if (spot != null) {
      return Build(
          slot: slot,
          x: spot.$1,
          y: spot.$2,
          building: Building.dorf,
          townName: placeNames[rng.nextInt(placeNames.length)]);
    }
  }

  // Hafen on a qualifying coastal water tile.
  if (realm.treasury >= 700) {
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (!map.isWaterAt(x, y) ||
            map.ownerAt(x, y) != World.niemand ||
            map.buildingAt(x, y) != Building.none) {
          continue;
        }
        for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
          // Own LAND adjacency, like the engine's hafenOnCoast rule — an
          // own Hafen on water must not anchor the pick (the engine would
          // reject the build and end the AI's build loop early).
          if (map.inBounds(x + dx, y + dy) &&
              map.ownerAt(x + dx, y + dy) == slot &&
              Terrain.isLand(map.terrainAt(x + dx, y + dy))) {
            return Build(
                slot: slot, x: x, y: y, building: Building.hafen);
          }
        }
      }
    }
  }

  // Burg / Palast at ≈ 1/20 per turn.
  if (realm.treasury >= 5000 && rng.nextInt(20) == 0) {
    final spot = findOwned((x, y, b) => b == Building.none);
    if (spot != null) {
      return Build(slot: slot, x: spot.$1, y: spot.$2, building: Building.burg);
    }
  }
  if (realm.treasury >= 10000 && rng.nextInt(20) == 0) {
    final spot = findOwned((x, y, b) => b == Building.none);
    if (spot != null) {
      return Build(
          slot: slot, x: spot.$1, y: spot.$2, building: Building.palast);
    }
  }

  // Otherwise expand.
  final claim = findClaimable();
  if (claim != null) {
    return ClaimTile(slot: slot, x: claim.$1, y: claim.$2);
  }
  return null; // boxed in → war flag
}

/// Default names for AI units. The original named every AI unit
/// "Rekruten" (it has no troop-name table); a small period-flavor pool
/// keeps battle reports readable when several AI units fight.
const aiTroopNames = [
  'Heerbann', 'Landwehr', 'Reisige', 'Stadtwache', 'Aufgebot',
  'Bogenschützen', 'Pikeniere', 'Reiterei',
];

/// §20.5: each unit gets `random(freeCapacity) + 1` recruits; a realm
/// without units raises one first [INTERPRETATION — the original AI must
/// create units to be able to declare war].
void _reinforce(
    GameState state, Realm realm, Rng rng, List<GameEvent> events) {
  final free = realm.troopCapacity - realm.armySize;
  if (realm.troops.isEmpty) {
    if (free > 0 && realm.treasury >= 5 * 10) {
      final men = math.min(
          rng.nextInt(free) + 1, math.min(free, realm.treasury ~/ 5));
      if (men > 0) {
        _act(
            state,
            RecruitTroops(
                slot: realm.slot,
                men: men,
                troopClass: TroopClass.infanterie,
                name: aiTroopNames[(realm.slot + realm.troops.length) %
                    aiTroopNames.length]),
            rng,
            events);
      }
    }
    return;
  }
  for (var i = 0; i < realm.troops.length; i++) {
    final freeNow = realm.troopCapacity - realm.armySize;
    if (freeNow <= 0) break;
    if (!realm.troops[i].garrisonCounted) continue;
    final wanted = rng.nextInt(freeNow) + 1;
    final men =
        math.min(wanted, math.min(freeNow, realm.treasury ~/ 5));
    if (men <= 0) continue;
    _act(state, ReinforceTroop(slot: realm.slot, unitIndex: i, men: men),
        rng, events);
  }
}

/// §20.5: keep the guard level near `random(treasury / 200)`.
void _adjustGuardsTowardTarget(
    GameState state, Realm realm, Rng rng, List<GameEvent> events) {
  if (realm.treasury < 200) return;
  final target =
      math.min(guardCap, rng.nextInt(realm.treasury ~/ 200));
  var delta = target - realm.guardLevel;
  if (delta > 0) {
    delta = math.min(delta, realm.treasury ~/ guardCost);
  }
  if (delta == 0) return;
  _act(state, AdjustGuards(slot: realm.slot, delta: delta), rng, events);
}

/// §20.5: buy ships up to 600 T × harbors.
void _investInShips(
    GameState state, Realm realm, Rng rng, List<GameEvent> events) {
  if (realm.investedThisTurn) return;
  final cap = realm.tileCount[Building.hafen] * 600;
  final amount = math.min(cap, realm.treasury ~/ 2);
  if (amount <= 0) return;
  _act(state, InvestShips(slot: realm.slot, amount: amount), rng, events);
}

/// §20.8: a random adjacent realm of a different religion, falling back
/// to any adjacent realm. Adjacency = any tile of A orthogonally touching
/// a tile of B.
int? _pickWarTarget(GameState state, int slot, Rng rng) {
  final map = state.map;
  final adjacent = <int>{};
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.ownerAt(x, y) != slot) continue;
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        if (!map.inBounds(x + dx, y + dy)) continue;
        final other = map.ownerAt(x + dx, y + dy);
        // A slot the AI's own ruler already holds (aliasing, §19) is no
        // war target — DeclareWar rejects it; merging is the path.
        if (other != World.niemand &&
            other != slot &&
            !state.realm(other).isVacant &&
            state.realm(other).rulerId != state.realm(slot).rulerId) {
          adjacent.add(other);
        }
      }
    }
  }
  if (adjacent.isEmpty) return null;
  final religion = state.dynasty(slot).religion;
  final infidels = [
    for (final s in adjacent)
      if (state.dynasty(s).religion != religion) s,
  ];
  final pool = infidels.isNotEmpty ? infidels : adjacent.toList();
  return pool[rng.nextInt(pool.length)];
}

/// AI war-round movement (§11.2): the attacker's units march toward the
/// enemy capital; the defender's units walk back to their snapshots.
/// Returns when the side is out of moves (or the war ended).
///
/// Rules v7 `[DESIGNED]`: the defender fights back — units intercept
/// enemy units standing on own territory, and once the enemy army is
/// wiped out or clearly outmatched they counter-march on the enemy
/// capital (occupying tiles for war score, capturing the ruler if they
/// reach it). Both sides also path around water with a BFS instead of
/// the greedy axis step (which strands units on lake shores). Pre-v7
/// the defender sat at home for the whole war — even with the enemy
/// army annihilated.
void runAiWarMovement(GameState state, int slot, Rng rng,
    List<GameEvent> events) {
  final war = state.activeWar;
  if (war == null || war.phase != WarPhase.rounds) return;
  final realm = state.realm(slot);

  for (var i = 0; i < realm.troops.length; i++) {
    var guard = 0;
    while (identical(state.activeWar, war) &&
        war.phase == WarPhase.rounds &&
        i < realm.troops.length &&
        (war.movesLeft[slot]?[i] ?? 0) > 0 &&
        guard++ < 30) {
      final troop = realm.troops[i];
      // Recomputed every step: kills and deaths reshape the troop list
      // and can change the nearest-intruder pick.
      final target = _warTarget(state, war, slot, i, troop);
      if (target == null) break;
      final (tx, ty) = target;
      if (troop.x == tx && troop.y == ty) break;

      final step = state.rulesVersion >= 7
          ? _bfsStep(state.map, troop.x, troop.y, tx, ty) ??
              _stepToward(state, troop.x, troop.y, tx, ty)
          : _stepToward(state, troop.x, troop.y, tx, ty);
      if (step == null) break;
      try {
        events.addAll(applyActionInPlace(
            state,
            WarMove(slot: slot, unitIndex: i, dx: step.$1, dy: step.$2),
            rng));
      } on ActionException {
        break; // blocked — give up on this unit for this round
      }
    }
    if (state.activeWar == null) return; // capture ended the war
  }
}

/// Where an AI war unit wants to go this step (see [runAiWarMovement]).
(int, int)? _warTarget(
    GameState state, ActiveWar war, int slot, int index, Troop troop) {
  final realm = state.realm(slot);
  final enemy = state.realm(war.opponentOf(slot));

  if (slot == war.attackerSlot) {
    return (enemy.capitalX, enemy.capitalY);
  }

  if (state.rulesVersion >= 7) {
    // Intercept the nearest intruder on own soil.
    (int, int)? nearest;
    var best = 1 << 30;
    for (final e in enemy.troops) {
      if (state.map.ownerAt(e.x, e.y) != slot) continue;
      final d = (e.x - troop.x).abs() + (e.y - troop.y).abs();
      if (d < best) {
        best = d;
        nearest = (e.x, e.y);
      }
    }
    if (nearest != null) return nearest;

    // Counter-offensive once the enemy army is gone or clearly weaker.
    final own = realm.troops.fold(0.0, (a, t) => a + troopStrength(t));
    final theirs = enemy.troops.fold(0.0, (a, t) => a + troopStrength(t));
    if (enemy.troops.isEmpty || own > 1.5 * theirs) {
      return (enemy.capitalX, enemy.capitalY);
    }
  }

  // Walk back home. Distinct snapshot per unit — recomputed because
  // deaths reshape the troop list (matchedSnapshots pairs by list order).
  final home =
      matchedSnapshots(realm.troops, war.snapshots[slot] ?? const [])[index];
  return home == null ? null : (home.x, home.y);
}

/// First step of a shortest land path from ([x],[y]) to ([tx],[ty]);
/// null when the target is start itself or unreachable over land.
(int, int)? _bfsStep(WorldMap map, int x, int y, int tx, int ty) {
  final start = map.index(x, y);
  final goal = map.index(tx, ty);
  if (start == goal) return null;
  final prev = List<int>.filled(map.terrain.length, -1);
  prev[start] = start;
  final queue = <int>[start];
  for (var head = 0; head < queue.length; head++) {
    final cur = queue[head];
    if (cur == goal) break;
    final cx = cur % map.width;
    final cy = cur ~/ map.width;
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = cx + dx;
      final ny = cy + dy;
      if (!map.inBounds(nx, ny) || map.isWaterAt(nx, ny)) continue;
      final ni = map.index(nx, ny);
      if (prev[ni] != -1) continue;
      prev[ni] = cur;
      queue.add(ni);
    }
  }
  if (prev[goal] == -1) return null; // unreachable (island capital etc.)
  var cur = goal;
  while (prev[cur] != start) {
    cur = prev[cur];
  }
  return (cur % map.width - x, cur ~/ map.width - y);
}

(int, int)? _stepToward(GameState state, int x, int y, int tx, int ty) {
  final map = state.map;
  final candidates = <(int, int)>[];
  if (tx > x) candidates.add((1, 0));
  if (tx < x) candidates.add((-1, 0));
  if (ty > y) candidates.add((0, 1));
  if (ty < y) candidates.add((0, -1));
  // Detours when the direct axes are blocked by water.
  candidates.addAll(const [(0, 1), (0, -1), (1, 0), (-1, 0)]);
  for (final (dx, dy) in candidates) {
    if (map.inBounds(x + dx, y + dy) && !map.isWaterAt(x + dx, y + dy)) {
      return (dx, dy);
    }
  }
  return null;
}

/// Ends a war round: the AI sides move first (their response to the
/// driving side's moves this round), then the round advances — capture,
/// peace and winter checks included. ONE entry point for the local client
/// ("Runde beenden") and the V2 server (an awaited war-round input, see
/// ARCHITECTURE.md "Human-vs-human wars online") so the orchestration
/// never lives in UI code. Attacker before defender, as in the original.
void endWarRoundWithAi(GameState state, Rng rng, List<GameEvent> events) {
  final war = state.activeWar;
  if (war == null || war.phase != WarPhase.rounds) return;
  for (final slot in [war.attackerSlot, war.defenderSlot]) {
    if (state.dynasty(slot).status != DynastyStatus.human) {
      runAiWarMovement(state, slot, rng, events);
    }
  }
  // A pre-v9 AI move can capture mid-march and end the war right here.
  if (state.activeWar != null &&
      state.activeWar!.phase == WarPhase.rounds) {
    endWarRound(state, rng, events);
  }
}

/// Runs a whole AI-vs-AI war to completion in silent "fast mode" (§11.3).
void _fastForwardAiWar(GameState state, Rng rng, List<GameEvent> events) {
  var guard = 0;
  while (state.activeWar != null && guard++ < 30) {
    final war = state.activeWar!;
    if (war.phase == WarPhase.settlement) {
      // Only a human winner leaves the settlement open.
      return;
    }
    for (final slot in [war.attackerSlot, war.defenderSlot]) {
      if (state.dynasty(slot).status == DynastyStatus.human) {
        return; // a human participant drives their own war rounds
      }
    }
    endWarRoundWithAi(state, rng, events);
  }
}

/// Driver for local mode and the server (ARCHITECTURE.md "Turn Flow"):
/// after a human ends their turn, run AI action phases and advance the
/// pipeline until a human's action phase is reached (with all pending
/// decisions for AIs already auto-resolved), or the game is over.
///
/// When NO human seat remains (every human dynasty lost control through
/// strife, capture, succession crisis or extinction), the game ends right
/// there with a public `humansDefeated` event. Without this stop the loop
/// would silently simulate the AI-only world for up to 2,000 turns —
/// centuries of play — and then drop the player into whichever realm
/// happened to be current (or an AI "victory"), long after they were out.
TurnResult advanceUntilHuman(GameState state, Rng rng) {
  var current = state;
  final events = <GameEvent>[];
  var guard = 0;

  bool humanSeated(GameState s) => s.realms.any((r) =>
      !r.isVacant && s.dynasty(r.slot).status == DynastyStatus.human);

  while (guard++ < 2000) {
    if (current.events.isNotEmpty &&
        (current.events.last.type == 'gameWon' ||
            current.events.last.type == 'gameDraw')) {
      break;
    }
    if (!humanSeated(current)) {
      final defeat = GameEvent(
        year: current.year,
        slot: 0,
        type: 'humansDefeated',
        visibility: EventVisibility.public,
      );
      current = current.copy();
      current.events.add(defeat);
      events.add(defeat);
      break;
    }
    final slot = current.currentPlayer;
    final dynasty = current.dynasty(slot);
    final realm = current.realm(slot);
    if (dynasty.status == DynastyStatus.human && !realm.isVacant) break;

    if (dynasty.status == DynastyStatus.ai && !realm.isVacant) {
      final aiResult = runAiTurn(current, slot, rng);
      current = aiResult.state;
      events.addAll(aiResult.events);
      if (current.activeWar != null) break; // a human defender must act
    }
    final turnResult = completeTurn(current, rng);
    current = turnResult.state;
    events.addAll(turnResult.events);
  }
  return TurnResult(current, events);
}
