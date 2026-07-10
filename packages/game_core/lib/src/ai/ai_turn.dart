import 'dart:math' as math;

import '../actions/apply_action.dart';
import '../actions/player_action.dart';
import '../data/tables.dart';
import '../rng/rng.dart';
import '../rules/espionage.dart';
import '../rules/realm_merge.dart';
import '../rules/troops.dart' show classSurcharge, troopStrength;
import '../rules/war.dart';
import 'ai_tuning.dart';
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

void _act(
    GameState state, PlayerAction action, Rng rng, List<GameEvent> events) {
  events.addAll(applyActionInPlace(state, action, rng));
}

void _runAiTurnInPlace(
    GameState state, int slot, Rng rng, List<GameEvent> events) {
  final realm = state.realm(slot);
  if (realm.isVacant) return;

  // How strongly this AI plays — per-game setup choice, see ai_tuning.dart.
  // Mittel is the faithful pre-difficulty script.
  final tuning = aiTuningFor(state.aiDifficulty);

  // §20.3 Collect the crown pot when this realm's ruler holds the office —
  // a deliberate action since 0.1.13 ("Staatskasse plündern"), no longer
  // part of the upkeep, so the AI presses the button itself.
  final holdsKaiser = state.kaiserId != null && realm.rulerId == state.kaiserId;
  final holdsSultan = state.sultanId != null && realm.rulerId == state.sultanId;
  if ((holdsKaiser && state.kaiserPot > 0) ||
      (holdsSultan && state.sultanPot > 0)) {
    _act(state, CollectTribute(slot: slot), rng, events);
  }

  // §20.2 Sell harvests once the price clears the tuning threshold
  // (mittel: the upper ~40% of each range); never stockpiles.
  if (state.grainPrice > tuning.grainSellMin && realm.grainHarvest > 0) {
    _act(
        state,
        SellGood(
            slot: slot, good: MarketGood.grain, amount: realm.grainHarvest),
        rng,
        events);
  }
  if (state.cattlePrice > tuning.cattleSellMin && realm.livestockHarvest > 0) {
    _act(
        state,
        SellGood(
            slot: slot,
            good: MarketGood.cattle,
            amount: realm.livestockHarvest),
        rng,
        events);
  }

  // Schwer budgets the daggers BEFORE the builders: after the turn's
  // spending (build loop, planned levies, drill, ships) the §13.3 reserve
  // gate would almost never hold for an AI that plans its economy
  // aggressively. Mittel keeps the original late check below.
  if (tuning.assassinateEarly) {
    _maybeAssassinate(state, realm, rng, events, tuning);
  }

  // §20.4 Build loop.
  var warFlag = false;
  while (realm.movementPoints > 0) {
    final action = _pickBuildAction(state, realm, rng, tuning);
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

  // §20.5 Reinforce, drill (schwer only), guards, ships.
  _reinforce(state, realm, rng, events, tuning);
  _drillTroops(state, realm, rng, events, tuning);
  _adjustGuardsTowardTarget(state, realm, rng, events);
  _investInShips(state, realm, rng, events);

  // `[DESIGNED]` Peacetime manoeuvres: the original AI never moved its
  // units in peace, so armies sat frozen on their muster tile for
  // centuries. Now they drift between the frontier and the rear each turn,
  // so the map shows them maneuvering (relocation is free, §6.3).
  _repositionTroops(state, realm, rng, events);

  // (§20.6 marriage/heir upkeep runs in the shared dynasty phase.)

  // §20.7 Merge one randomly-chosen other slot ruled by the same ruler.
  final mergeable = mergeableSlots(state, slot);
  if (mergeable.isNotEmpty) {
    _act(
        state,
        MergeRealms(
            slot: slot, sourceSlot: mergeable[rng.nextInt(mergeable.length)]),
        rng,
        events);
  }

  // §13.3 `[DESIGNED]` cloak-and-dagger: a content, solvent AI occasionally
  // sends assassins at a bordering rival's ruler. The original AI never used
  // its spies offensively, so rulers were immune to the dagger unless a
  // human paid for it. (Schwer already ran this before the spending —
  // see assassinateEarly above.)
  if (!tuning.assassinateEarly) {
    _maybeAssassinate(state, realm, rng, events, tuning);
  }

  // §20.8 War. Declaring war costs the aggressor popularity, so a
  // sensible AI ruler only wars while the people are content — without
  // this guard, war-hit realms drifted into §19.1 strife collapses
  // several times as often in the 200-year sim. `[DESIGNED]` The spontaneous
  // war chance was raised (~2–3×) so the map sees a bit more conflict
  // without the AI warring constantly.
  // The declaration penalty escalates with war weariness (−5 × (recentWars
  // + 1), floored below the strife line) — demand a matching mood cushion
  // so a serial-warring AI never talks itself into a §19.1 revolt.
  final warMoodOk = realm.popularity >= 50 + 5 * realm.recentWars;
  if ((warFlag ||
          tuning.warChance > 0 && rng.nextInt(tuning.warChance) == 0) &&
      rng.nextInt(3) == 0 &&
      warMoodOk &&
      state.year >= state.warStartYear &&
      !realm.warThisYear &&
      state.activeWar == null &&
      realm.troops.any((t) => t.men > 0)) {
    // A boxed-in AI (warFlag) wars to break out even without a clear
    // strength edge — otherwise a schwer realm with only strong
    // neighbours would idle forever (§20.4's escape valve).
    final target =
        _pickWarTarget(state, slot, rng, tuning, desperate: warFlag);
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

/// §20.4 build-loop target selection: a RANDOM matching tile.
/// `[DEVIATION]` The original scanned the map row by row and took the
/// first hit, so AI realms always built and expanded toward the top-left
/// corner — visibly predictable. Picking uniformly among all candidates
/// keeps the same build priorities but spreads growth in every direction.
PlayerAction? _pickBuildAction(
    GameState state, Realm realm, Rng rng, AiTuning tuning) {
  final map = state.map;
  final slot = realm.slot;

  (int, int)? pickRandom(List<(int, int)> candidates) =>
      candidates.isEmpty ? null : candidates[rng.nextInt(candidates.length)];

  (int, int)? findOwned(bool Function(int x, int y, int building) test) {
    final candidates = <(int, int)>[];
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != slot) continue;
        if (test(x, y, map.buildingAt(x, y))) candidates.add((x, y));
      }
    }
    return pickRandom(candidates);
  }

  (int, int)? findClaimable() {
    final candidates = <(int, int)>[];
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) {
          continue;
        }
        for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
          if (map.inBounds(x + dx, y + dy) &&
              map.ownerAt(x + dx, y + dy) == slot) {
            candidates.add((x, y));
            break;
          }
        }
      }
    }
    return pickRandom(candidates);
  }

  // Keep food up: tileCount[Kornfeld] × 9 ≳ population × foodFactor
  // (schwer keeps a buffer, leicht reacts only to acute shortage).
  if (realm.tileCount[Building.kornfeld] * 9 <
      realm.population * tuning.foodFactor) {
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
    final coast = <(int, int)>[];
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
            coast.add((x, y));
            break;
          }
        }
      }
    }
    final spot = pickRandom(coast);
    if (spot != null) {
      return Build(
          slot: slot, x: spot.$1, y: spot.$2, building: Building.hafen);
    }
  }

  // Burg / Palast at ≈ 1/burgChance per loop pass (mittel: the original
  // 1/20; schwer checks far more often, leicht barely ever).
  if (realm.treasury >= 5000 && rng.nextInt(tuning.burgChance) == 0) {
    final spot = findOwned((x, y, b) => b == Building.none);
    if (spot != null) {
      return Build(slot: slot, x: spot.$1, y: spot.$2, building: Building.burg);
    }
  }
  if (realm.treasury >= 10000 && rng.nextInt(tuning.burgChance) == 0) {
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
  'Heerbann',
  'Landwehr',
  'Reisige',
  'Stadtwache',
  'Aufgebot',
  'Bogenschützen',
  'Pikeniere',
  'Reiterei',
];

/// A troop name no unit of [realm] carries yet. Uniqueness matters: the
/// war snapshots pair units BY NAME (`matchedSnapshots`), so two units
/// sharing a name would swap positions after a war. Starts at the classic
/// `(slot + count) % n` pick (identical to the old behaviour while names
/// are free), then walks the pool, then numbers the fallback.
String _newTroopName(Realm realm) {
  final used = {for (final troop in realm.troops) troop.name};
  for (var i = 0; i < aiTroopNames.length; i++) {
    final name = aiTroopNames[
        (realm.slot + realm.troops.length + i) % aiTroopNames.length];
    if (!used.contains(name)) return name;
  }
  final base = aiTroopNames[realm.slot % aiTroopNames.length];
  var n = 2;
  while (used.contains('$base $n')) {
    n++;
  }
  return '$base $n';
}

/// §20.5: each unit gets `random(freeCapacity) + 1` recruits; a realm
/// without units raises one first [INTERPRETATION — the original AI must
/// create units to be able to declare war]. Leicht halves every levy
/// (reinforceDivisor); schwer skips the random levy entirely and recruits
/// planfully ([_reinforcePlanned]).
void _reinforce(GameState state, Realm realm, Rng rng, List<GameEvent> events,
    AiTuning tuning) {
  if (tuning.capacityTarget > 0) {
    _reinforcePlanned(state, realm, rng, events, tuning);
    return;
  }
  final free = realm.troopCapacity - realm.armySize;
  if (realm.troops.isEmpty) {
    if (free > 0 && realm.treasury >= 5 * 10) {
      // Floored at 1 man: the first unit must always be raisable — with a
      // halving divisor and free capacity 1 the levy would otherwise be
      // deterministically 0 and the realm could never arm at all.
      final men = math.min(
          math.max(1, (rng.nextInt(free) + 1) ~/ tuning.reinforceDivisor),
          math.min(free, realm.treasury ~/ 5));
      if (men > 0) {
        _act(
            state,
            RecruitTroops(
                slot: realm.slot,
                men: men,
                troopClass: TroopClass.infanterie,
                name: _newTroopName(realm)),
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
    final wanted = (rng.nextInt(freeNow) + 1) ~/ tuning.reinforceDivisor;
    final men = math.min(wanted, math.min(freeNow, realm.treasury ~/ 5));
    if (men <= 0) continue;
    _act(state, ReinforceTroop(slot: realm.slot, unitIndex: i, men: men), rng,
        events);
  }
}

/// `[DESIGNED]` Schwer recruiting: instead of the original's random levy
/// the AI fills its army toward `capacityTarget × troopCapacity`, spending
/// at most half the treasury per turn (the rest stays as a war chest). Up
/// to three regular units are founded, each capped near a third of the
/// target so the army really is SPLIT (one lump unit could never leave a
/// home guard behind, see [runAiWarMovement]) — Kavallerie once the
/// treasury clears [AiTuning.kavallerieTreasury] and the unit is worth the
/// surcharge — then existing units are reinforced, smallest first.
void _reinforcePlanned(GameState state, Realm realm, Rng rng,
    List<GameEvent> events, AiTuning tuning) {
  var budget = realm.treasury ~/ 2;
  // Clamped to the capacity so a tuning target > 1.0 can never oversize
  // the deficit past the free quarters.
  final target = math.min(
      (realm.troopCapacity * tuning.capacityTarget).floor(),
      realm.troopCapacity);
  // Founding cap per new unit: ~a third of the target, at least 10 men.
  final unitCap = math.max(10, (target / 3).ceil());
  var guard = 0;
  while (guard++ < 10) {
    final deficit = target - realm.armySize;
    if (deficit <= 0 || budget < 5) return;
    final regulars = [
      for (var i = 0; i < realm.troops.length; i++)
        if (realm.troops[i].garrisonCounted) i,
    ];
    if (regulars.length < 3) {
      // Found a new unit. The Kavallerie surcharge only pays off for a
      // real unit — never buy it for a token squad.
      final kavSurcharge = classSurcharge(TroopClass.kavallerie);
      final kavMen = math.min(
          math.min(deficit, unitCap), (budget - kavSurcharge) ~/ 5);
      final kav = tuning.kavallerieTreasury > 0 &&
          realm.treasury >= tuning.kavallerieTreasury &&
          kavMen >= 10;
      final surcharge = kav ? kavSurcharge : 0;
      final men =
          kav ? kavMen : math.min(math.min(deficit, unitCap), budget ~/ 5);
      if (men <= 0) return;
      try {
        _act(
            state,
            RecruitTroops(
                slot: realm.slot,
                men: men,
                troopClass: kav ? TroopClass.kavallerie : TroopClass.infanterie,
                name: _newTroopName(realm)),
            rng,
            events);
      } on ActionException {
        return; // defensive: never kill the AI turn over a levy
      }
      budget -= surcharge + 5 * men;
    } else {
      // Reinforce the smallest regular unit toward the target.
      var index = regulars.first;
      for (final i in regulars) {
        if (realm.troops[i].men < realm.troops[index].men) index = i;
      }
      final men = math.min(deficit, budget ~/ 5);
      if (men <= 0) return;
      try {
        _act(state, ReinforceTroop(slot: realm.slot, unitIndex: index, men: men),
            rng, events);
      } on ActionException {
        return;
      }
      budget -= 5 * men;
    }
  }
}

/// `[DESIGNED]` Schwer drills its regulars toward
/// [AiTuning.drillMaxQuality] (the original AI never drilled), spending at
/// most a quarter of the treasury per turn — cheapest drill first, so
/// quality rises evenly across the army. Runs AFTER reinforcing: new
/// recruits dilute quality, so the drill works on the final roster.
void _drillTroops(GameState state, Realm realm, Rng rng,
    List<GameEvent> events, AiTuning tuning) {
  if (tuning.drillMaxQuality <= TroopQuality.regular) return;
  var budget = realm.treasury ~/ 4;
  var guard = 0;
  while (guard++ < 30) {
    var index = -1;
    var bestCost = 1 << 30;
    for (var i = 0; i < realm.troops.length; i++) {
      final troop = realm.troops[i];
      if (!troop.garrisonCounted) continue;
      if (troop.quality >= tuning.drillMaxQuality ||
          troop.quality >= Troop.drillCap) {
        continue;
      }
      final cost = 5 * troop.men * troop.quality;
      if (cost < bestCost) {
        bestCost = cost;
        index = i;
      }
    }
    // budget ≤ treasury holds throughout: both start with budget =
    // treasury/4 and each drill decrements both by the same cost.
    if (index < 0 || bestCost > budget) return;
    try {
      _act(state, DrillTroop(slot: realm.slot, unitIndex: index), rng, events);
    } on ActionException {
      return; // defensive: never kill the AI turn over a drill
    }
    budget -= bestCost;
  }
}

/// §20.5: keep the guard level near `random(treasury / 200)`.
void _adjustGuardsTowardTarget(
    GameState state, Realm realm, Rng rng, List<GameEvent> events) {
  if (realm.treasury < 200) return;
  final target = math.min(guardCap, rng.nextInt(realm.treasury ~/ 200 + 1));
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
/// a tile of B. With [AiTuning.warStrengthAdvantage] > 0 (schwer) the pick
/// is the WEAKEST adjacent realm instead — and only when the own army
/// holds that strength edge over it, so a schwer AI never CHOOSES a war it
/// is likely to lose; [desperate] (boxed in, §20.4) drops the edge
/// requirement but keeps the weakest-target pick.
int? _pickWarTarget(GameState state, int slot, Rng rng, AiTuning tuning,
    {bool desperate = false}) {
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
  if (tuning.warStrengthAdvantage > 0) {
    final own = _armyStrength(state.realm(slot));
    int? weakest;
    var weakestStrength = double.infinity;
    for (final s in adjacent) {
      final strength = _armyStrength(state.realm(s));
      if (strength < weakestStrength) {
        weakestStrength = strength;
        weakest = s;
      }
    }
    if (weakest == null) return null;
    if (!desperate && own < tuning.warStrengthAdvantage * weakestStrength) {
      return null; // no beatable neighbour — keep the peace
    }
    return weakest;
  }
  final religion = state.dynasty(slot).religion;
  final infidels = [
    for (final s in adjacent)
      if (state.dynasty(s).religion != religion) s,
  ];
  final pool = infidels.isNotEmpty ? infidels : adjacent.toList();
  return pool[rng.nextInt(pool.length)];
}

/// `[DESIGNED]` Peacetime troop manoeuvres. Relocation is free (§6.3), so
/// each turn most units redeploy to a random own destination — a frontier
/// tile (own land touching another realm or unclaimed land) or a rear base
/// (a town / the capital). Over several turns armies visibly shift around
/// the realm instead of standing frozen on their muster tile, and they tend
/// to mass near the borders where they may soon be needed. ~1/3 of the
/// units hold position each turn so a realm is never left wholly undefended.
void _repositionTroops(
    GameState state, Realm realm, Rng rng, List<GameEvent> events) {
  if (realm.troops.isEmpty) return;
  final map = state.map;
  final slot = realm.slot;

  final frontier = <(int, int)>[];
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.ownerAt(x, y) != slot) continue;
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
        final nx = x + dx;
        final ny = y + dy;
        if (!map.inBounds(nx, ny) || map.isWaterAt(nx, ny)) continue;
        if (map.ownerAt(nx, ny) != slot) {
          frontier.add((x, y));
          break;
        }
      }
    }
  }

  final rear = <(int, int)>[
    for (final town in realm.towns) (town.x, town.y),
    (realm.capitalX, realm.capitalY),
  ];
  // Weight toward the frontier when one exists, but keep some rear options
  // so units don't all crowd a single edge.
  final destinations = <(int, int)>[...frontier, ...frontier, ...rear];
  if (destinations.isEmpty) return;

  for (var i = 0; i < realm.troops.length; i++) {
    if (rng.nextInt(3) == 0) continue; // hold position
    final (dx, dy) = destinations[rng.nextInt(destinations.length)];
    final troop = realm.troops[i];
    if (troop.x == dx && troop.y == dy) continue;
    try {
      _act(state, MoveTroop(slot: slot, unitIndex: i, x: dx, y: dy), rng,
          events);
    } on ActionException {
      // Defensive: a stale destination must not kill the AI turn.
    }
  }

  // `[DESIGNED]` Always leave a home guard on the capital — never strip the
  // base of its last defender (mirrors the war-time home guard). If the
  // reposition above left the capital empty, send the nearest unit back.
  if (!realm.troops
      .any((t) => t.x == realm.capitalX && t.y == realm.capitalY)) {
    final guard = _nearestToCapital(realm);
    if (guard != null) {
      try {
        _act(
            state,
            MoveTroop(
                slot: slot,
                unitIndex: realm.troops.indexOf(guard),
                x: realm.capitalX,
                y: realm.capitalY),
            rng,
            events);
      } on ActionException {
        // Defensive: the capital is always own land, so this should not throw.
      }
    }
  }
}

/// Total army strength of a realm — the yardstick for smart war and
/// assassination target picks.
double _armyStrength(Realm realm) =>
    realm.troops.fold(0.0, (a, t) => a + troopStrength(t));

/// The unit nearest the realm's capital (Manhattan distance), or null when
/// the realm has no troops. Used to pick the home guard.
Troop? _nearestToCapital(Realm realm) {
  Troop? best;
  var bestD = 1 << 30;
  for (final troop in realm.troops) {
    final d =
        (troop.x - realm.capitalX).abs() + (troop.y - realm.capitalY).abs();
    if (d < bestD) {
      bestD = d;
      best = troop;
    }
  }
  return best;
}

/// §13.3 `[DESIGNED]` AI assassination. A content, solvent AI occasionally
/// dispatches a squad of agents at a bordering rival ruler. Rare by design
/// (the map should not drown in daggers), gated to the war years so the
/// protected first decade stays safe, and never spends the whole treasury.
/// The frequency, squad size and target pick scale with the difficulty
/// (leicht never assassinates; schwer strikes the strongest rival).
void _maybeAssassinate(GameState state, Realm realm, Rng rng,
    List<GameEvent> events, AiTuning tuning) {
  // Deliberately the FIXED protect-new-players decade (years 1000–1009),
  // NOT the configurable warStartYear — daggers stay gated even when the
  // host defers wars far beyond 1010 (and vice versa).
  if (state.year < 1010) return;
  if (state.activeWar != null) return;
  if (tuning.assassinChance <= 0) return; // leicht: never
  if (rng.nextInt(tuning.assassinChance) != 0) return; // rare
  // Keep a war chest — only act with comfortable reserves.
  if (realm.treasury < 12 * assassinCost) return;

  final targets = <int>[
    for (final other in state.map.realmNeighbors(realm.slot))
      if (!state.realm(other).isVacant &&
          state.realm(other).rulerId != null &&
          // Not a slot the AI's own ruler already holds (aliasing, §19).
          state.realm(other).rulerId != realm.rulerId)
        other,
  ];
  if (targets.isEmpty) return;
  int target;
  if (tuning.smartAssassinTarget) {
    // The strongest bordering rival — the biggest long-term threat.
    target = targets.first;
    var best = -1.0;
    for (final s in targets) {
      final strength = _armyStrength(state.realm(s));
      if (strength > best) {
        best = strength;
        target = s;
      }
    }
  } else {
    target = targets[rng.nextInt(targets.length)];
  }

  // A squad scaled to a share of the war chest (mittel: a quarter, 3–20
  // agents; schwer sends a third). The bound is pinned into [3, 30]: below
  // 3 `clamp` would throw (min > max), above 30 the action rejects the
  // order — either way a bad tuning row must not kill the AI turn.
  final maxAgents = math.min(math.max(tuning.assassinMaxAgents, 3), 30);
  final agents = ((realm.treasury ~/ tuning.assassinTreasuryDivisor) ~/
          assassinCost)
      .clamp(3, maxAgents);
  if (realm.treasury < agents * assassinCost) return;
  try {
    _act(
        state,
        OrderAssassination(
            slot: realm.slot, targetSlot: target, agents: agents),
        rng,
        events);
  } on ActionException {
    // Defensive: an invalid target pick must not kill the AI turn.
  }
}

/// AI war-round movement (§11.2): the attacker's units march toward the
/// enemy capital; the defender's units walk back to their snapshots.
/// Returns when the side is out of moves (or the war ended).
///
/// `[DESIGNED]`: the AI defender fights back — units intercept
/// enemy units standing on own territory, and once the enemy army is
/// wiped out or clearly outmatched they counter-march on the enemy
/// capital (occupying tiles for war score, capturing the ruler if they
/// reach it). Both sides also path around water with a BFS instead of
/// the greedy axis step (which strands units on lake shores). Pre-v7
/// the defender sat at home for the whole war — even with the enemy
/// army annihilated.
void runAiWarMovement(
    GameState state, int slot, Rng rng, List<GameEvent> events) {
  final war = state.activeWar;
  if (war == null || war.phase != WarPhase.rounds) return;
  final realm = state.realm(slot);

  // `[DESIGNED]` A real AI side always keeps a HOME GUARD on its base: the
  // unit nearest the capital is reserved and never marched out, so the realm
  // is never left wholly undefended (the player always has a defender to
  // fight at the AI's base). Held by reference so it survives the troop-list
  // reshaping as units die. Not applied to an autopiloted human side (its
  // per-unit stance already governs defence), nor to a one-unit realm (it
  // cannot both guard the base and field an army).
  final Troop? homeGuard =
      state.dynasty(slot).status == DynastyStatus.ai && realm.troops.length >= 2
          ? _nearestToCapital(realm)
          : null;

  for (var i = 0; i < realm.troops.length; i++) {
    var guard = 0;
    while (identical(state.activeWar, war) &&
        war.phase == WarPhase.rounds &&
        i < realm.troops.length &&
        (war.movesLeft[slot]?[i] ?? 0) > 0 &&
        guard++ < 30) {
      final troop = realm.troops[i];
      if (identical(troop, homeGuard)) break; // the home guard holds the base
      // Recomputed every step: kills and deaths reshape the troop list
      // and can change the nearest-intruder pick.
      final target = _warTarget(state, war, slot, i, troop);
      if (target == null) break;
      final (tx, ty) = target;
      if (troop.x == tx && troop.y == ty) break;

      // Own land, the enemy's, and neutral unowned tiles are passable in
      // war (mirrors [applyWarMove]); only third realms block the march.
      final warOwners = {slot, war.opponentOf(slot), World.niemand};
      final step = _bfsStep(state.map, troop.x, troop.y, tx, ty,
              allowedOwners: warOwners) ??
          _stepToward(state, troop.x, troop.y, tx, ty,
              allowedOwners: warOwners);
      if (step == null) break;
      try {
        events.addAll(applyActionInPlace(state,
            WarMove(slot: slot, unitIndex: i, dx: step.$1, dy: step.$2), rng));
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

  // The unit's snapshotted pre-war position (its base). Recomputed because
  // deaths reshape the troop list (matchedSnapshots pairs by list order).
  (int, int)? homeSnapshot() {
    final home =
        matchedSnapshots(realm.troops, war.snapshots[slot] ?? const [])[index];
    return home == null ? null : (home.x, home.y);
  }

  // An idle human's side is fought on AUTOPILOT, per unit, by its stance
  // ([TroopStance]) — the online war clock ran out before the player acted
  // (or they left the match). A holdPosition unit returns to its base and
  // defends; it only marches on the enemy capital once the enemy has no
  // troops left. An attack unit advances straight away.
  if (state.dynasty(slot).status == DynastyStatus.human) {
    if (troop.stance == TroopStance.attack || enemy.troops.isEmpty) {
      return (enemy.capitalX, enemy.capitalY);
    }
    return homeSnapshot();
  }

  if (slot == war.attackerSlot) {
    return (enemy.capitalX, enemy.capitalY);
  }

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
  final own = _armyStrength(realm);
  final theirs = _armyStrength(enemy);
  if (enemy.troops.isEmpty || own > 1.5 * theirs) {
    return (enemy.capitalX, enemy.capitalY);
  }

  // Walk back home.
  return homeSnapshot();
}

/// First step of a shortest land path from ([x],[y]) to ([tx],[ty]);
/// null when the target is start itself or unreachable over land.
/// If [allowedOwners] is non-null, only tiles whose owner is in the set
/// (or the start tile itself) are traversed — used during war to prevent
/// routing through uninvolved realms.
(int, int)? _bfsStep(WorldMap map, int x, int y, int tx, int ty,
    {Set<int>? allowedOwners}) {
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
      if (allowedOwners != null && !allowedOwners.contains(map.owner[ni])) {
        continue;
      }
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

(int, int)? _stepToward(GameState state, int x, int y, int tx, int ty,
    {Set<int>? allowedOwners}) {
  final map = state.map;
  final candidates = <(int, int)>[];
  if (tx > x) candidates.add((1, 0));
  if (tx < x) candidates.add((-1, 0));
  if (ty > y) candidates.add((0, 1));
  if (ty < y) candidates.add((0, -1));
  // Detours when the direct axes are blocked by water.
  candidates.addAll(const [(0, 1), (0, -1), (1, 0), (-1, 0)]);
  for (final (dx, dy) in candidates) {
    final nx = x + dx;
    final ny = y + dy;
    if (!map.inBounds(nx, ny) || map.isWaterAt(nx, ny)) continue;
    if (allowedOwners != null &&
        !allowedOwners.contains(map.owner[map.index(nx, ny)])) {
      continue;
    }
    return (dx, dy);
  }
  return null;
}

/// Awaited war-round input from [slot] ("Runde beenden"): in a
/// human-vs-human war the ATTACKER's round end only hands the input to
/// the human defender ([handWarRoundOver]) — the defender's round end
/// advances the round for real via [endWarRoundWithAi]. ONE entry point
/// for the local client and the V2 server (ARCHITECTURE.md
/// "Human-vs-human wars online") so the orchestration never lives in UI
/// code.
void endWarRoundFor(
    GameState state, int slot, Rng rng, List<GameEvent> events) {
  if (handWarRoundOver(state, slot)) {
    _skipTrooplessWarSides(state, rng, events);
    return;
  }
  endWarRoundWithAi(state, rng, events);
  _skipTrooplessWarSides(state, rng, events);
}

/// A war side with no troops left can take no action — auto-resolve its
/// round so the war never stalls waiting for a defenceless human to act
/// (online a troopless seat would otherwise block the whole match until its
/// turn timer expires every single round). Loops because skipping one side
/// can hand the round to a second defenceless side; the guard sits well
/// above the 20-round winter cap, which ends any war between two empty
/// armies on its own.
void _skipTrooplessWarSides(GameState state, Rng rng, List<GameEvent> events) {
  var guard = 0;
  while (guard++ < 60) {
    final war = state.activeWar;
    if (war == null || war.phase != WarPhase.rounds) return;
    final acting = warActingSlot(state);
    // No human is awaited (a pure-AI war advances itself; a settlement is
    // not a round) — nothing to skip.
    if (acting == null) return;
    if (state.realm(acting).troops.isNotEmpty) return;
    // The awaited human side is defenceless: end its round on its behalf —
    // an attacker hands over to the defender, anyone else advances the round
    // (which also runs any AI side's movement first).
    if (handWarRoundOver(state, acting)) continue;
    endWarRoundWithAi(state, rng, events);
  }
}

/// Ends a war round: the AI sides move first (their response to the
/// driving side's moves this round), then the round advances — capture,
/// peace and winter checks included. Attacker before defender, as in
/// the original.
void endWarRoundWithAi(GameState state, Rng rng, List<GameEvent> events) {
  final war = state.activeWar;
  if (war == null || war.phase != WarPhase.rounds) return;
  for (final slot in [war.attackerSlot, war.defenderSlot]) {
    // Delegated human sides (war.autoSlots) are autopiloted like AI sides.
    if (!warSideIsHuman(state, war, slot)) {
      runAiWarMovement(state, slot, rng, events);
    }
  }
  // Defensive: should a war end mid-move, stop issuing orders.
  if (state.activeWar != null && state.activeWar!.phase == WarPhase.rounds) {
    endWarRound(state, rng, events);
  }
}

/// Runs a whole AI-vs-AI war to completion in silent "fast mode" (§11.3).
void _fastForwardAiWar(GameState state, Rng rng, List<GameEvent> events) {
  var guard = 0;
  while (state.activeWar != null && guard++ < 30) {
    final war = state.activeWar!;
    if (war.phase == WarPhase.settlement) {
      // Only a live human winner leaves the settlement open.
      return;
    }
    for (final slot in [war.attackerSlot, war.defenderSlot]) {
      // Delegated human sides (autoSlots) fast-forward like AI sides.
      if (warSideIsHuman(state, war, slot)) {
        return; // a live human participant drives their own war rounds
      }
    }
    endWarRoundWithAi(state, rng, events);
  }
}

/// After a `warPlan` answer (or the online preparation deadline): begins
/// the war rounds per the user-designed start rules (2026-07-06):
///  - all answered, exactly ONE side plays live → start at once (the live
///    player declared themself ready, the other delegated),
///  - all answered, NOBODY plays live → begin and fast-forward the whole
///    war like an AI-vs-AI war (both sides on the stance autopilot),
///  - all answered, BOTH play live → start only when [waitWhenAllManual]
///    is false (hot-seat / no online timer: both are present), when both
///    agreed on the "immediately" slot (`war.scheduledStartMs == 0`, the
///    online duel scheduling), or on [force] (the online deadline — the
///    agreed start time if the sides found a common slot, otherwise half
///    the turn timer — keeps the duel start fair).
/// [force] (deadline expiry) also defaults every unanswered side to the
/// autopilot — an absent player is protected, never steamrolled.
void resolveWarPreparation(GameState state, Rng rng, List<GameEvent> events,
    {bool force = false, bool waitWhenAllManual = false}) {
  final war = state.activeWar;
  if (war == null || war.phase != WarPhase.preparation) return;
  final sides = [war.attackerSlot, war.defenderSlot];
  bool unanswered(int slot) => state.pendingDecisions
      .any((d) => d.type == 'warPlan' && d.decidingSlot == slot);
  if (force) {
    for (final slot in sides.where(unanswered)) {
      war.autoSlots.add(slot);
    }
    state.pendingDecisions.removeWhere((d) => d.type == 'warPlan');
  } else if (sides.any(unanswered)) {
    return;
  }
  final liveSides = sides.where((s) => warSideIsHuman(state, war, s)).length;
  if (!force &&
      waitWhenAllManual &&
      liveSides == 2 &&
      war.scheduledStartMs != 0) {
    return;
  }
  beginWarRounds(state, rng);
  if (liveSides == 0) _fastForwardAiWar(state, rng, events);
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

  bool humanSeated(GameState s) => s.realms.any(
      (r) => !r.isVacant && s.dynasty(r.slot).status == DynastyStatus.human);

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
        // Surface WHY the last human dynasty lost the throne instead of a
        // bare "no human dynasty". The cause is recorded on the state at the
        // exact moment each human seat falls (`noteHumanSeatLost`), so it
        // reflects the PLAYER's own loss — not a stray AI-vs-AI event that
        // merely happens to be the most recent in the shared log (which an
        // earlier "scan the log backwards" approach mislabelled, e.g.
        // showing "ruler captured in war" for a peaceful inheritance). The
        // client renders a sentence.
        payload: {'reason': current.humanLossReason ?? 'unknown'},
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

    // `aiTurnActed` skips a phase that already ran: a war against a human
    // defender interrupts the loop AFTER the AI acted, and that state can
    // be auto-saved — re-entering here (e.g. resuming such a save) must
    // complete the parked turn without a second action phase.
    if (dynasty.status == DynastyStatus.ai &&
        !realm.isVacant &&
        !current.aiTurnActed) {
      final aiResult = runAiTurn(current, slot, rng);
      current = aiResult.state;
      current.aiTurnActed = true;
      events.addAll(aiResult.events);
      if (current.activeWar != null) break; // a human defender must act
    }
    final turnResult = completeTurn(current, rng);
    current = turnResult.state;
    events.addAll(turnResult.events);
  }
  return TurnResult(current, events);
}
