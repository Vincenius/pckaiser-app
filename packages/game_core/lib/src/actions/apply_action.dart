import '../l10n/messages.dart';
import '../rng/rng.dart';
import '../rules/costs.dart';
import '../rules/dynasty.dart';
import '../rules/offices.dart';
import '../rules/realm_merge.dart';
import '../rules/titles.dart' show regenderTitle, switchTitleLadder;
import '../rules/victory.dart';
import '../rules/war.dart' as war_rules;
import '../state/constants.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/pending_ship_return.dart';
import '../state/realm.dart';
import '../state/ship.dart';
import '../state/town.dart';
import '../state/war.dart' show WarPhase;
import '../state/world_map.dart';
import 'apply_military.dart';
import 'player_action.dart';

/// Result of applying an action: the new state plus the events it emitted.
class ActionResult {
  ActionResult(this.state, this.events);

  final GameState state;
  final List<GameEvent> events;
}

/// Key API (ARCHITECTURE.md): validates and applies a player action.
/// Pure: the input state is never mutated; throws [ActionException] with a
/// player-facing message when the action is not allowed.
///
/// The RNG is injected for actions with random outcomes (e.g. founding a
/// Dorf rolls its starting population); `state.rngSeed` is updated so the
/// save stays replayable.
ActionResult applyAction(GameState state, PlayerAction action, Rng rng) {
  final next = state.copy();
  final events = applyActionInPlace(next, action, rng);
  next.rngSeed = rng.seed;
  next.events.addAll(events);
  return ActionResult(next, events);
}

/// In-place variant for callers that already own a working copy — the AI
/// turn script and the turn pipeline. Mutates [state], returns the events
/// WITHOUT appending them to `state.events` (the caller does both).
List<GameEvent> applyActionInPlace(
    GameState state, PlayerAction action, Rng rng) {
  if (action.slot < 1 || action.slot > state.realmCount) {
    throw ActionException(coreMessage('invalidRealm', {'slot': action.slot}));
  }
  final realm = state.realm(action.slot);
  if (realm.isVacant) {
    throw ActionException(coreMessage('realmVacant'));
  }

  return switch (action) {
    ClaimTile() => _claimTile(state, realm, action),
    BuyShip() => _buyShip(state, realm, action),
    MoveShip() => _moveShip(state, realm, action),
    ColonizeShip() => _colonizeShip(state, realm, action, rng),
    Build() => _build(state, realm, action, rng),
    BuildFields() => _buildFields(state, realm, action),
    Demolish() => _demolish(state, realm, action),
    ChangeReligion() => _changeReligion(state, realm, action),
    CollectTribute() => _collectTribute(state, realm, action),
    SellGood() => _sellGood(state, realm, action),
    InvestShips() => _investShips(state, realm, action, rng),
    SendMoney() => _sendMoney(state, realm, action),
    RelocateCapital() => _relocateCapital(state, realm, action),
    ProposeMarriage() => _proposeMarriage(state, realm, action, rng),
    MarryCommoner() => _marryCommoner(state, realm, action, rng),
    ResolveDecision() => _resolveDecision(state, realm, action, rng),
    MergeRealms() => _mergeRealms(state, realm, action, rng),
    TransferRealm() => _transferRealm(state, realm, action, rng),
    RecruitTroops() => applyRecruitTroops(state, realm, action, rng),
    HireSoeldner() => applyHireSoeldner(state, realm, action),
    ReinforceTroop() => applyReinforceTroop(state, realm, action, rng),
    TrainTroop() => applyTrainTroop(state, realm, action),
    DrillTroop() => applyDrillTroop(state, realm, action),
    RenameTroop() => applyRenameTroop(state, realm, action),
    SetTroopStance() => applySetTroopStance(state, realm, action),
    MergeTroops() => applyMergeTroops(state, realm, action),
    DisbandTroop() => applyDisbandTroop(state, realm, action),
    MoveTroop() => applyMoveTroop(state, realm, action),
    DeclareWar() => applyDeclareWar(state, realm, action, rng),
    WarMove() => applyWarMove(state, realm, action, rng),
    WarMarch() => applyWarMarch(state, realm, action, rng),
    WarNavalTransport() => applyWarNavalTransport(state, realm, action, rng),
    WarPlunder() => applyWarPlunder(state, realm, action, rng),
    WarPeaceWish() => applyWarPeaceWish(state, realm, action),
    WarEndRound() => applyWarEndRound(state, realm, action, rng),
    WarPrepPlan() => applyWarPrepPlan(state, realm, action),
    SettlementAnnex() => applySettlementAnnex(state, realm, action, rng),
    SettlementAnnexMany() =>
      applySettlementAnnexMany(state, realm, action, rng),
    SettlementTakeAll() => applySettlementTakeAll(state, realm, action, rng),
    SettlementFinish() => applySettlementFinish(state, realm, action, rng),
    SpyMission() => applySpyMission(state, realm, action, rng),
    OrderAssassination() => applyOrderAssassination(state, realm, action),
    AdjustGuards() => applyAdjustGuards(state, realm, action),
  };
}

void _requireMovementPoint(Realm realm) {
  if (realm.movementPoints < 1) {
    throw ActionException(coreMessage('noMovesLeft'));
  }
}

void _requireFunds(Realm realm, int cost) {
  if (realm.treasury < cost) {
    throw ActionException(coreMessage('notEnoughTaler', {'cost': cost}));
  }
}

void _requireOnMap(WorldMap map, int x, int y) {
  if (!map.inBounds(x, y)) {
    throw ActionException(coreMessage('tileOffMap'));
  }
}

/// Claiming an adjacent unowned land tile costs 1 movement point (§4).
List<GameEvent> _claimTile(GameState state, Realm realm, ClaimTile action) {
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if (map.isWaterAt(action.x, action.y)) {
    throw ActionException(coreMessage('cannotClaimWater'));
  }
  if (map.ownerAt(action.x, action.y) != World.niemand) {
    throw ActionException(coreMessage('tileAlreadyOwned'));
  }
  if (!map.bordersSlot(action.x, action.y, realm.slot)) {
    throw ActionException(coreMessage('tileNotAdjacent'));
  }
  _requireMovementPoint(realm);

  realm.movementPoints--;
  map.owner[map.index(action.x, action.y)] = realm.slot;
  realm.tileCount[Building.none]++;

  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'tileClaimed',
      visibility: EventVisibility.public,
      payload: {'x': action.x, 'y': action.y},
    ),
  ];
}

Ship _shipAt(Realm realm, int index) {
  if (index < 0 || index >= realm.ships.length) {
    throw ActionException(coreMessage('noSuchShip'));
  }
  return realm.ships[index];
}

/// Buy a colony ship at an own Hafen: 700 T + 1 Zug; the ship
/// spawns on the harbor's water tile and is steered manually from there.
List<GameEvent> _buyShip(GameState state, Realm realm, BuyShip action) {
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if (map.ownerAt(action.x, action.y) != realm.slot ||
      map.buildingAt(action.x, action.y) != Building.hafen) {
    throw ActionException(coreMessage('buyShipAtOwnHarbor'));
  }
  _requireMovementPoint(realm);
  _requireFunds(realm, Building.shipCost);

  realm.movementPoints--;
  realm.treasury -= Building.shipCost;
  realm.ships.add(Ship(x: action.x, y: action.y));

  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'shipBought',
      visibility: EventVisibility.owner,
      payload: {'x': action.x, 'y': action.y},
    ),
  ];
}

/// Sail a ship to a water tile: shortest all-water route,
/// 1 Zug per water tile — the original's "(S)chiff steuern" cost. A
/// voyage longer than the remaining Züge must wait for the next turn
/// (or stop at a nearer tile).
List<GameEvent> _moveShip(GameState state, Realm realm, MoveShip action) {
  final ship = _shipAt(realm, action.shipIndex);
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if (!map.isWaterAt(action.x, action.y)) {
    throw ActionException(coreMessage('shipsOnlyOnWater'));
  }
  final distance = map.waterPathLength(ship.x, ship.y, action.x, action.y);
  if (distance < 0) {
    throw ActionException(coreMessage('notReachableBySea'));
  }
  if (distance == 0) {
    throw ActionException(coreMessage('shipAlreadyThere'));
  }
  if (realm.movementPoints < distance) {
    throw ActionException(coreMessage('shipTooFar', {'distance': distance}));
  }

  realm.movementPoints -= distance;
  ship.x = action.x;
  ship.y = action.y;
  return const [];
}

/// Colonize with a ship: a free land tile orthogonally next to
/// the ship becomes the realm's, with a freshly founded Dorf on it — the
/// ship is consumed (its settlers stay). Costs 1 Zug; the ship's 700 T
/// already covered the colony.
List<GameEvent> _colonizeShip(
    GameState state, Realm realm, ColonizeShip action, Rng rng) {
  final ship = _shipAt(realm, action.shipIndex);
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if ((ship.x - action.x).abs() + (ship.y - action.y).abs() != 1) {
    throw ActionException(coreMessage('shipMustBeAdjacent'));
  }
  if (map.isWaterAt(action.x, action.y)) {
    throw ActionException(coreMessage('colonizeFreeLandOnly'));
  }
  if (map.ownerAt(action.x, action.y) != World.niemand ||
      map.buildingAt(action.x, action.y) != Building.none) {
    throw ActionException(coreMessage('tileAlreadyOwned'));
  }
  if (action.townName.trim().isEmpty) {
    throw ActionException(coreMessage('villageNeedsName'));
  }
  _requireMovementPoint(realm);

  realm.movementPoints--;
  realm.ships.remove(ship);
  map.owner[map.index(action.x, action.y)] = realm.slot;
  map.building[map.index(action.x, action.y)] = Building.dorf;
  realm.tileCount[Building.dorf]++;

  final town = Town(
    name: clampName(action.townName),
    population: 75 + rng.nextInt(50),
    troopCapacity: 25,
    garrison: 0,
    buildingType: Building.dorf,
    x: action.x,
    y: action.y,
  );
  realm.towns.add(town);
  realm.population += town.population;
  realm.troopCapacity += town.troopCapacity;

  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'shipColonized',
      visibility: EventVisibility.public,
      payload: {'x': action.x, 'y': action.y},
    ),
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'townFounded',
      visibility: EventVisibility.public,
      payload: {'name': town.name, 'x': action.x, 'y': action.y},
    ),
  ];
}

/// Build menu (§4): Kornfeld on Ebene, Weide on Ebene/Berg, Dorf on land,
/// Burg/Palast on land, Hafen on the coast. Markt/Stadt never built.
/// Costs 1 movement point + the building's Taler cost.
///
/// Building on an unowned land tile adjacent to own territory claims the
/// tile as part of the build — the separate claim step was dropped from
/// the player UX [DEVIATION]; `ClaimTile` remains for the AI script.
List<GameEvent> _build(GameState state, Realm realm, Build action, Rng rng) {
  final map = state.map;
  _requireOnMap(map, action.x, action.y);

  final building = action.building;
  final cost = building >= 0 && building < Building.cost.length
      ? Building.cost[building]
      : null;
  if (cost == null) {
    throw ActionException(coreMessage('cannotBuildThat'));
  }
  final owner = map.ownerAt(action.x, action.y);
  final terrain = map.terrainAt(action.x, action.y);
  // A Hafen goes on a coastal water tile (§4/§5): water cannot be claimed,
  // so building on unowned water next to your land takes ownership as part
  // of the build — matching the starting-cross harbors. It must touch own
  // LAND: an own Hafen on water must not count, or harbors could chain
  // along the coast with no land contact at all.
  final hafenOnCoast = building == Building.hafen &&
      owner == World.niemand &&
      map.bordersSlotLand(action.x, action.y, realm.slot);
  final claimOnBuild = building != Building.hafen &&
      owner == World.niemand &&
      Terrain.isLand(terrain) &&
      map.bordersSlot(action.x, action.y, realm.slot);
  if (owner != realm.slot && !hafenOnCoast && !claimOnBuild) {
    throw ActionException(coreMessage('tileNotYours'));
  }
  if (map.buildingAt(action.x, action.y) != Building.none) {
    throw ActionException(coreMessage('tileAlreadyBuilt'));
  }

  final terrainOk = switch (building) {
    Building.kornfeld => terrain == Terrain.ebene,
    // [DEVIATION] Weide on Ebene too — original restricts it to Berg.
    Building.weide => terrain == Terrain.berg || terrain == Terrain.ebene,
    Building.dorf ||
    Building.burg ||
    Building.palast =>
      Terrain.isLand(terrain),
    Building.hafen => Terrain.isWater(terrain),
    _ => false,
  };
  if (!terrainOk) {
    throw ActionException(coreMessage('wrongTerrain'));
  }
  if (building == Building.dorf &&
      (action.townName == null || action.townName!.trim().isEmpty)) {
    throw ActionException(coreMessage('villageNeedsName'));
  }

  _requireMovementPoint(realm);
  _requireFunds(realm, cost);

  realm.movementPoints--;
  realm.treasury -= cost;
  map.building[map.index(action.x, action.y)] = building;
  if (hafenOnCoast || claimOnBuild) {
    map.owner[map.index(action.x, action.y)] = realm.slot;
  } else {
    realm.tileCount[Building.none]--;
  }
  realm.tileCount[building]++;

  final events = <GameEvent>[
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'buildingBuilt',
      visibility: EventVisibility.public,
      payload: {'x': action.x, 'y': action.y, 'building': building},
    ),
  ];

  if (building == Building.dorf) {
    final town = Town(
      name: clampName(action.townName!),
      population: 75 + rng.nextInt(50),
      troopCapacity: 25,
      garrison: 0,
      buildingType: Building.dorf,
      x: action.x,
      y: action.y,
    );
    realm.towns.add(town);
    realm.population += town.population;
    realm.troopCapacity += town.troopCapacity;
    events.add(GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'townFounded',
      visibility: EventVisibility.public,
      payload: {'name': town.name, 'x': action.x, 'y': action.y},
    ));
  }

  return events;
}

/// Drag-select batch cultivation ([BuildFields]): lay a Kornfeld or Weide
/// on every listed tile that can take it, best-effort. Wrong-terrain tiles
/// (Kornfeld off Ebene) and tiles the treasury / remaining Züge can no
/// longer pay for are silently skipped — the client offers the batch
/// pre-filtered, this is the authoritative re-check. Each built field
/// costs 1 Zug + the field's Taler, exactly like a single [Build].
List<GameEvent> _buildFields(GameState state, Realm realm, BuildFields action) {
  final building = action.building;
  // A fields-only batch: Dorf/Burg/Hafen/… go through the single Build.
  if (building != Building.kornfeld && building != Building.weide) {
    throw ActionException(coreMessage('cannotBuildThat'));
  }
  final events = <GameEvent>[];
  for (final t in action.tiles) {
    if (_tryBuildField(state, realm, t.x, t.y, building)) {
      events.add(GameEvent(
        year: state.year,
        slot: realm.slot,
        type: 'buildingBuilt',
        visibility: EventVisibility.public,
        payload: {'x': t.x, 'y': t.y, 'building': building},
      ));
    }
  }
  // Nothing built at all: surface the most likely cause so the tap isn't a
  // silent no-op (the client normally guarantees ≥1 affordable valid tile).
  if (events.isEmpty) {
    if (realm.movementPoints < 1) {
      throw ActionException(coreMessage('noMovesLeft'));
    }
    final cost = Building.cost[building]!;
    if (realm.treasury < cost) {
      throw ActionException(coreMessage('notEnoughTaler', {'cost': cost}));
    }
    throw ActionException(coreMessage('cannotBuildThat'));
  }
  return events;
}

/// Tries to lay [building] (Kornfeld/Weide only) on ([x],[y]) for [realm].
/// Returns true and mutates the map on success; false — leaving everything
/// untouched — when the tile is off-map, not owned/claimable, already
/// built, the wrong terrain, or unaffordable. Mirrors the per-tile rules
/// of [_build] so a batch and a single build never diverge.
bool _tryBuildField(GameState state, Realm realm, int x, int y, int building) {
  final map = state.map;
  if (!map.inBounds(x, y)) return false;
  final owner = map.ownerAt(x, y);
  final terrain = map.terrainAt(x, y);
  // Same claim-on-build rule as _build: an unowned land tile bordering own
  // territory is claimed as part of the cultivation.
  final claimOnBuild = owner == World.niemand &&
      Terrain.isLand(terrain) &&
      map.bordersSlot(x, y, realm.slot);
  if (owner != realm.slot && !claimOnBuild) return false;
  if (map.buildingAt(x, y) != Building.none) return false;
  final terrainOk = switch (building) {
    Building.kornfeld => terrain == Terrain.ebene,
    Building.weide => terrain == Terrain.berg || terrain == Terrain.ebene,
    _ => false,
  };
  if (!terrainOk) return false;
  final cost = Building.cost[building]!;
  if (realm.movementPoints < 1 || realm.treasury < cost) return false;

  realm.movementPoints--;
  realm.treasury -= cost;
  final idx = map.index(x, y);
  map.building[idx] = building;
  if (claimOnBuild) {
    map.owner[idx] = realm.slot;
  } else {
    realm.tileCount[Building.none]--;
  }
  realm.tileCount[building]++;
  return true;
}

/// Plans which of [selected] tiles (indices `y * width + x`) a
/// [BuildFields] of [building] would cultivate for [slot], as a DRY RUN
/// (state never mutated). Returns the tiles in a valid build ORDER: claim
/// chains resolve outward — building on an unowned border tile claims it,
/// which lets the wave reach the next unowned tile behind it — so a
/// selection stretching several tiles into free land builds completely.
/// Bounded by terrain (Kornfeld only on Ebene), the treasury and the
/// remaining Züge, exactly per [_tryBuildField]: dispatching the returned
/// list as a [BuildFields] builds every tile of it. Selected tiles that
/// are unreachable (connected only through non-selected or wrong-terrain
/// tiles) or beyond the budget are left out. Drives the client's
/// drag-select preview counts and the batch it submits.
List<({int x, int y})> planFieldCultivation(
    GameState state, int slot, Iterable<int> selected, int building) {
  if (building != Building.kornfeld && building != Building.weide) {
    return const [];
  }
  final map = state.map;
  final realm = state.realm(slot);
  final cost = Building.cost[building]!;
  bool terrainOk(int t) => building == Building.kornfeld
      ? t == Terrain.ebene
      : t == Terrain.berg || t == Terrain.ebene;
  // Candidates: empty tiles of a valid terrain that are own or claimable
  // (unowned land) — everything else can never build and never carries a
  // claim chain either.
  final sel = <int>{
    for (final i in selected)
      if (i >= 0 &&
          i < map.terrain.length &&
          map.building[i] == Building.none &&
          terrainOk(map.terrain[i]) &&
          (map.owner[i] == slot || map.owner[i] == World.niemand))
        i,
  };
  if (sel.isEmpty) return const [];

  var moves = realm.movementPoints;
  var treasury = realm.treasury;
  final planned = <({int x, int y})>[];
  final queued = <int>{};
  final queue = <int>[];
  // Seeds: own tiles and unowned tiles already bordering own territory,
  // in reading order (deterministic across client and server).
  for (final i in sel.toList()..sort()) {
    if (map.owner[i] == slot ||
        map.bordersSlot(i % map.width, i ~/ map.width, slot)) {
      queued.add(i);
      queue.add(i);
    }
  }
  for (var head = 0; head < queue.length; head++) {
    // Every field costs the same — once one is unaffordable, all are.
    if (moves < 1 || treasury < cost) break;
    final i = queue[head];
    moves--;
    treasury -= cost;
    planned.add((x: i % map.width, y: i ~/ map.width));
    // The built (and, if unowned, claimed) tile carries the wave to its
    // selected neighbors — enqueued only now, so at their turn they
    // border own territory just as _tryBuildField will see it.
    for (final (nx, ny) in map.neighborsOf(i % map.width, i ~/ map.width)) {
      final ni = map.index(nx, ny);
      if (sel.contains(ni) && queued.add(ni)) queue.add(ni);
    }
  }
  return planned;
}

/// "(A)breißen" — 100 T, clears the building (§4). Towns cannot be
/// demolished this way (the original demolishes *fields*).
List<GameEvent> _demolish(GameState state, Realm realm, Demolish action) {
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if (map.ownerAt(action.x, action.y) != realm.slot) {
    throw ActionException(coreMessage('tileNotYours'));
  }
  final building = map.buildingAt(action.x, action.y);
  if (building == Building.none) {
    throw ActionException(coreMessage('nothingHere'));
  }
  if (Building.isTown(building)) {
    throw ActionException(coreMessage('cannotDemolishTowns'));
  }
  const cost = demolishCost;
  _requireMovementPoint(realm);
  _requireFunds(realm, cost);

  realm.movementPoints--;
  realm.treasury -= cost;
  final idx = map.index(action.x, action.y);
  map.building[idx] = Building.none;
  map.owner[idx] = World.niemand;
  // Clearing the tile also lifts any lingering war devastation — a field
  // built fresh here later must not inherit the razed field's fallow timer
  // (a rebuilt Kornfeld/Weide would otherwise yield nothing for years).
  map.devastatedUntil[idx] = 0;
  realm.tileCount[building]--;

  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'buildingDemolished',
      visibility: EventVisibility.public,
      payload: {'x': action.x, 'y': action.y, 'building': building},
    ),
  ];
}

/// "Reiche zusammenlegen" (§6.2).
/// [DESIGNED] The acting slot (realm.slot) is the SOURCE — it gets vacated
/// and its everything moves to action.sourceSlot (the target). This means
/// the player "joins" their current realm to the selected one, which then
/// becomes the consolidated seat going forward.
List<GameEvent> _mergeRealms(
    GameState state, Realm realm, MergeRealms action, Rng rng) {
  // No merging while either realm fights the active war — the merged-in
  // troops would bypass the no-reinforcement-at-war gate and desync the
  // war's movesLeft/snapshot bookkeeping.
  final war = state.activeWar;
  if (war != null &&
      (war.isParticipant(realm.slot) || war.isParticipant(action.sourceSlot))) {
    throw ActionException(coreMessage('notDuringWar'));
  }
  if (!mergeableSlots(state, realm.slot).contains(action.sourceSlot)) {
    throw ActionException(coreMessage('cannotMergeRealms'));
  }
  final events = <GameEvent>[];
  // action.sourceSlot is the target (absorbs); realm.slot is the source (vacated).
  mergeRealms(state, action.sourceSlot, realm.slot, rng, events);
  return events;
}

/// "Reich übertragen" [DESIGNED, deviation]: hand the whole realm to a
/// FOREIGN ruler. Same war gate as the merge (transferred troops would
/// bypass the no-reinforcement-at-war rule); the acting slot is always the
/// source and gets vacated.
List<GameEvent> _transferRealm(
    GameState state, Realm realm, TransferRealm action, Rng rng) {
  final war = state.activeWar;
  if (war != null &&
      (war.isParticipant(realm.slot) || war.isParticipant(action.targetSlot))) {
    throw ActionException(coreMessage('notDuringWar'));
  }
  if (!transferableSlots(state, realm.slot).contains(action.targetSlot)) {
    throw ActionException(coreMessage('cannotTransferRealm'));
  }
  final events = <GameEvent>[];
  transferRealm(state, action.targetSlot, realm.slot, rng, events);

  // A voluntary handover can eliminate the last distinct ruler just like a
  // conquest. Emit the end-of-game event as part of the action result so the
  // receiving player sees the victory immediately, rather than only when the
  // former owner's turn is completed.
  final winner = checkWinCondition(state);
  if (winner != null) {
    events.add(GameEvent(
      year: state.year,
      slot: winner,
      type: 'gameWon',
      visibility: EventVisibility.public,
      payload: {'sourceSlot': realm.slot},
    ));
  }
  return events;
}

/// Market sale (§9.1): once per good per turn, at the global year price.
/// "Das geht nicht !!!" on a bad amount; selling reduces the food stock —
/// what you sell, your people don't eat.
List<GameEvent> _sellGood(GameState state, Realm realm, SellGood action) {
  final grain = action.good == MarketGood.grain;
  if (grain ? realm.soldGrainThisTurn : realm.soldCattleThisTurn) {
    throw ActionException(coreMessage('alreadySoldThisTurn'));
  }
  final stock = grain ? realm.grainHarvest : realm.livestockHarvest;
  // amount ≥ 1: selling 0 would still burn the once-per-turn flag.
  if (action.amount < 1 || action.amount > stock) {
    throw ActionException(coreMessage('notPossible'));
  }

  final price = grain ? state.grainPrice : state.cattlePrice;
  final proceeds = (action.amount * price).round();
  if (grain) {
    realm.grainHarvest -= action.amount;
    realm.soldGrainThisTurn = true;
  } else {
    realm.livestockHarvest -= action.amount;
    realm.soldCattleThisTurn = true;
  }
  realm.treasury += proceeds;

  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'goodsSold',
      visibility: EventVisibility.owner,
      payload: {
        'good': action.good.name,
        'amount': action.amount,
        'proceeds': proceeds,
      },
    ),
  ];
}

/// Trade-ship investment (§9.2): once per turn, capped at 600 T × harbors;
/// 50/50 profit up to 2× or loss down to (almost) zero. The stake leaves
/// the treasury now; the ships return at the START of this realm's next
/// turn (`_resolveShipReturns` in the turn pipeline) with a notice of
/// their haul. The outcome is rolled here so the save stays replayable,
/// but it stays hidden until they come home.
List<GameEvent> _investShips(
    GameState state, Realm realm, InvestShips action, Rng rng) {
  if (realm.investedThisTurn) {
    throw ActionException(coreMessage('alreadyInvestedThisTurn'));
  }
  final maxInvestment = shipInvestmentCap(realm);
  if (action.amount <= 0 ||
      action.amount > realm.treasury ||
      action.amount > maxInvestment) {
    throw ActionException(coreMessage('notPossible'));
  }

  realm.treasury -= action.amount;
  final int returned;
  if (rng.nextInt(2) == 0) {
    returned = action.amount + rng.nextInt(action.amount) + 1; // profit
  } else {
    returned = action.amount - (rng.nextInt(action.amount) + 1); // loss
  }
  realm.investedThisTurn = true;
  realm.pendingShipReturns.add(PendingShipReturn(
    invested: action.amount,
    returned: returned,
    returnYear: state.year + 1,
  ));

  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'shipsSent',
      visibility: EventVisibility.owner,
      payload: {'invested': action.amount},
    ),
  ];
}

/// "Geld schicken" (§6.2): transfer Taler to another living realm.
List<GameEvent> _sendMoney(GameState state, Realm realm, SendMoney action) {
  if (action.targetSlot < 1 ||
      action.targetSlot > state.realmCount ||
      action.targetSlot == realm.slot) {
    throw ActionException(coreMessage('invalidTargetRealm'));
  }
  final target = state.realm(action.targetSlot);
  if (target.isVacant) {
    throw ActionException(coreMessage('realmVacant'));
  }
  if (action.amount < 1) throw ActionException(coreMessage('notPossible'));
  _requireFunds(realm, action.amount);

  realm.treasury -= action.amount;
  target.treasury += action.amount;

  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'moneySent',
      visibility: EventVisibility.participants,
      participants: [realm.slot, action.targetSlot],
      payload: {'targetSlot': action.targetSlot, 'amount': action.amount},
    ),
  ];
}

/// "Sitz verlegen" (§6.2): valid target = own tile with Stadt/Burg/Palast.
/// `[DESIGNED]` Allowed at ANY time, not only when the seat is lost. A
/// voluntary move costs 5,000 T; re-seating a LOST capital (its tile is no
/// longer owned, e.g. after a war or earthquake) is free — the realm is
/// forced to pick a new seat anyway (see [reseatLostCapitals]). Also free
/// when the current seat sits on a makeshift tile without Stadt/Burg/
/// Palast (the forced no-eligible-tile fallback seat): moving onto a
/// proper seat building is the completion of that forced move.
List<GameEvent> _relocateCapital(
    GameState state, Realm realm, RelocateCapital action) {
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if (action.x == realm.capitalX && action.y == realm.capitalY) {
    throw ActionException(coreMessage('alreadyYourSeat'));
  }
  if (map.ownerAt(action.x, action.y) != realm.slot) {
    throw ActionException(coreMessage('seatOnOwnTerritory'));
  }
  final building = map.buildingAt(action.x, action.y);
  if (!Building.isSeat(building)) {
    throw ActionException(coreMessage('seatNeedsSeatBuilding'));
  }
  final lost = map.ownerAt(realm.capitalX, realm.capitalY) != realm.slot ||
      !Building.isSeat(map.buildingAt(realm.capitalX, realm.capitalY));
  if (!lost) {
    _requireFunds(realm, relocateCapitalCost);
    realm.treasury -= relocateCapitalCost;
  }
  realm.capitalX = action.x;
  realm.capitalY = action.y;
  // A forced re-seat decision (if any) is now satisfied.
  state.pendingDecisions.removeWhere(
      (d) => d.type == 'relocateCapital' && d.decidingSlot == realm.slot);

  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'capitalRelocated',
      visibility: EventVisibility.public,
      payload: {'x': action.x, 'y': action.y},
    ),
  ];
}

/// "Staatskasse plündern" (§17.5): the office holder empties the crown pot
/// into their treasury. Free (no Zug) — the original collected it as part
/// of the turn; making it a button is the deliberate part `[DESIGNED
/// 2026-07-06, user request]`. AI office holders trigger it at turn start
/// (§20.3 step 3), so pots never rot on an AI throne.
List<GameEvent> _collectTribute(
    GameState state, Realm realm, CollectTribute action) {
  final isKaiser = state.kaiserId != null && realm.rulerId == state.kaiserId;
  final isSultan = state.sultanId != null && realm.rulerId == state.sultanId;
  if (!isKaiser && !isSultan) {
    throw ActionException(coreMessage('onlyKaiserOrSultan'));
  }
  // Every pot the ruler is entitled to: a Kaiser whose dynasty converted
  // to Islam keeps the crown and may win the Sultan election too — a
  // dual-office holder must be able to empty both (picking only the
  // Kaiser pot stranded the Sultan pot forever and crashed the AI's
  // turn-start collection when the Kaiser pot happened to be empty).
  final events = <GameEvent>[];
  void collect(String office, int amount, void Function() clear) {
    if (amount <= 0) return;
    realm.treasury += amount;
    clear();
    events.add(GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'tributeCollected',
      // The pot totals are public information (visibleStateFor keeps
      // them), so the collection is too.
      visibility: EventVisibility.public,
      payload: {'amount': amount, 'office': office},
    ));
  }

  if (isKaiser) collect('kaiser', state.kaiserPot, () => state.kaiserPot = 0);
  if (isSultan) collect('sultan', state.sultanPot, () => state.sultanPot = 0);
  if (events.isEmpty) {
    throw ActionException(coreMessage('stateTreasuryEmpty'));
  }
  return events;
}

/// "H(e)irat vorschlagen" (§14.1): validates eligibility, then either the
/// AI 25% roll or a pending decision for a human target. The modern UX cap
/// is one proposal per PERSON per turn (the original had none at all) —
/// every marriageable member may propose each round.
List<GameEvent> _proposeMarriage(
    GameState state, Realm realm, ProposeMarriage action, Rng rng) {
  if (realm.proposedThisTurnIds.contains(action.proposerId)) {
    throw ActionException(coreMessage('alreadyProposedThisTurn'));
  }
  final proposer = state.persons[action.proposerId];
  final target = state.persons[action.targetId];
  if (proposer == null || target == null) {
    throw ActionException(coreMessage('personNotFound'));
  }
  // The ruler's home dynasty counts too: after a cross-dynasty inheritance
  // (§15.4) the ruling house differs from the slot, but its player must
  // still be able to marry from this slot's turn.
  if (!memberOfRulingHouse(state, realm, proposer)) {
    throw ActionException(coreMessage('notYourDynasty'));
  }
  // Neither side may already sit on an unanswered proposal — marrying in
  // the meantime would invalidate that pending consent.
  if (awaitingMarriageConsent(state, proposer.id) ||
      awaitingMarriageConsent(state, target.id)) {
    throw ActionException(coreMessage('awaitingAnswer'));
  }
  if (!marriageEligible(state, proposer, target)) {
    throw ActionException(coreMessage('noSuitablePartner'));
  }
  final events = <GameEvent>[];
  proposeMarriage(state, proposer, target, rng, events);
  realm.proposedThisTurnIds.add(proposer.id);
  return events;
}

/// "(B)ürgerlich heiraten" (§14.1): marry [MarryCommoner.personId] to a
/// freshly created commoner. [DEVIATION] A commoner always accepts (the
/// original rolled the 25% like any proposal); the spouse joins the
/// dynasty so the §14.3 birth loop applies to the couple.
/// always available — it neither checks nor consumes the one royal
/// proposal per turn.
List<GameEvent> _marryCommoner(
    GameState state, Realm realm, MarryCommoner action, Rng rng) {
  final person = state.persons[action.personId];
  if (person == null || !memberOfRulingHouse(state, realm, person)) {
    throw ActionException(coreMessage('notYourDynasty'));
  }
  if (person.spouseId != null || person.age < 14) {
    throw ActionException(coreMessage('noSuitablePartner'));
  }
  // No commoner sidestep while a royal answer is pending (see
  // _proposeMarriage) — it would invalidate the pending consent.
  if (awaitingMarriageConsent(state, person.id)) {
    throw ActionException(coreMessage('awaitingAnswer'));
  }
  final events = <GameEvent>[];
  // Shared with the AI annual fallback (§14.3) so both stay in lock-step.
  marry(state, person, createCommonerSpouse(state, person, rng),
      events); // "Angenommen !"
  return events;
}

/// Resolves a pending decision addressed to this slot.
List<GameEvent> _resolveDecision(
    GameState state, Realm realm, ResolveDecision action, Rng rng) {
  final index =
      state.pendingDecisions.indexWhere((d) => d.id == action.decisionId);
  if (index < 0) {
    throw ActionException(coreMessage('decisionNotFound'));
  }
  final decision = state.pendingDecisions[index];
  if (decision.decidingSlot != action.slot) {
    throw ActionException(coreMessage('decisionNotYours'));
  }

  // Validate-then-commit: the decision is consumed AFTER its case ran (see
  // the removal at the end). A case that rejects the submission
  // (electionBribe over-spend, electorVote without a finalist) throws
  // before any mutation — the working copy is discarded and the decision
  // structurally stays pending for a corrected answer. A STALE decision
  // (election over, war gone, heir dead) resolves as an explicit no-op
  // (`break`) and is still consumed.
  final events = <GameEvent>[];
  final payload = decision.payload;
  final choice = action.choice;

  switch (decision.type) {
    case 'marriageConsent':
      final proposer = state.persons[payload['proposerId'] as int];
      final target = state.persons[payload['targetId'] as int];
      // Eligibility can decay between proposal and consent: a death, a
      // marriage, a religion change (§14.4) or a merge collapsing the two
      // dynasties into one — re-check what can have changed.
      final stillValid = proposer != null &&
          target != null &&
          proposer.spouseId == null &&
          target.spouseId == null &&
          proposer.dynasty != target.dynasty &&
          state.dynasty(proposer.dynasty).religion ==
              state.dynasty(target.dynasty).religion;
      if (choice['accept'] == true && stillValid) {
        marry(state, proposer, target, events);
      } else {
        events.add(GameEvent(
          year: state.year,
          slot: decision.decidingSlot,
          type: 'marriageRejected',
          visibility: EventVisibility.participants,
          participants: [
            decision.decidingSlot,
            if (proposer != null) proposer.dynasty,
          ],
          payload: {
            ...payload,
            // An ACCEPTED proposal that decayed in the meantime is not a
            // rejection — tell the players the truth ("nicht mehr
            // möglich" instead of "abgelehnt").
            'reason': choice['accept'] == true ? 'invalid' : 'declined',
          },
        ));
      }

    case 'heirChoice':
      final heirId = choice['heirId'] as int?;
      final candidates = (payload['candidateIds'] as List).cast<int>();
      final provisional = payload['provisionalHeirId'] as int;
      if (heirId == null ||
          !candidates.contains(heirId) ||
          state.persons[heirId] == null) {
        // The chosen heir died in the meantime (disease, assassination):
        // the provisional heir simply stays crowned — a no-op consumes the
        // decision (throwing would keep re-prompting an unanswerable one).
        break;
      }
      // Re-crown only slots still held by the provisional heir — conquest
      // in between must not be undone. No honors can have accrued to the
      // placeholder in the meantime: a provisional heir is office-
      // ineligible until this choice resolves (`rulesOnlyProvisionally`,
      // the "Kaiser ohne Reich" root fix).
      for (final slot in (payload['slots'] as List).cast<int>()) {
        if (state.realm(slot).rulerId == provisional) {
          state.realm(slot).rulerId = heirId;
          regenderTitle(state, state.realm(slot));
        }
      }
      events.add(GameEvent(
        year: state.year,
        slot: decision.decidingSlot,
        type: 'succession',
        visibility: EventVisibility.public,
        payload: {
          'deceased': payload['deceasedName'],
          'heir': state.persons[heirId]!.name,
          'chosen': true,
        },
      ));

    case 'warPlan':
      // War-start preparation (user-designed mechanic): the combatant
      // chooses live control (`auto: false`) or the stance autopilot —
      // any NON-explicit answer (incl. the empty timeout default)
      // delegates, so an absent player is protected, never steamrolled.
      // Troop stances are NOT part of the answer: each unit is set
      // individually via `SetTroopStance` during the preparation window
      // (user rule 2026-07-13, replacing the old all-troops choice). The
      // caller layer (local session / server) runs the start rules via
      // `resolveWarPreparation` afterwards. Stale decision → no-op.
      final war = state.activeWar;
      if (war == null ||
          war.phase != WarPhase.preparation ||
          !war.isParticipant(decision.decidingSlot)) {
        break;
      }
      // `[DESIGNED 2026-07-08]` Online duel scheduling: a LIVE side may
      // propose start times ('slots': epoch ms UTC on full hours). The
      // first slot is "sofort" — the top of THIS side's current hour — so
      // two sides only agree on it when both answer within the same hour.
      // Recording the plan (and re-deriving the agreed start from both
      // sides' proposals) is shared with the revising `WarPrepPlan` action
      // — ONE definition in war_rules.setWarPrepPlan.
      war_rules.setWarPrepPlan(
        state,
        war,
        decision.decidingSlot,
        auto: choice['auto'] != false,
        slots: (choice['slots'] as List?)?.cast<int>() ?? const [],
      );

    case 'warDefense':
      // Legacy (pre-preparation dev builds): `defend == false` hands THIS
      // war to the stance autopilot; any other answer keeps human control.
      final legacyWar = state.activeWar;
      if (choice['defend'] == false &&
          legacyWar != null &&
          legacyWar.attackerSlot == payload['attackerSlot'] &&
          legacyWar.defenderSlot == decision.decidingSlot) {
        legacyWar.autoSlots.add(decision.decidingSlot);
        if (legacyWar.actingSlot == decision.decidingSlot) {
          legacyWar.actingSlot = legacyWar.attackerSlot;
        }
      }

    case 'childName':
      final child = state.persons[payload['childId'] as int];
      final name = clampName((choice['name'] as String?) ?? '');
      if (child != null && name.isNotEmpty) {
        child.name = name;
      }
      // Announce the birth now (deferred from `_birth` for human dynasties):
      // with the final name, in the round the child is named — so other
      // players see the real name, a round after the birth, never both the
      // provisional name and a same-round notice.
      if (child != null && payload.containsKey('parent')) {
        events.add(GameEvent(
          year: state.year,
          slot: decision.decidingSlot,
          type: 'birth',
          visibility: EventVisibility.public,
          payload: {
            'parent': payload['parent'],
            'partner': payload['partner'],
            'child': child.name,
            'gender': payload['gender'],
          },
        ));
      }

    case 'relocateCapital':
      // Forced re-seat after a lost capital — free. An invalid/stale pick
      // is a no-op that consumes the decision; `reseatLostCapitals`
      // re-prompts next round if the seat is still lost.
      final x = choice['x'] as int?;
      final y = choice['y'] as int?;
      final building = (x != null && y != null && state.map.inBounds(x, y))
          ? state.map.buildingAt(x, y)
          : Building.none;
      if (x != null &&
          y != null &&
          state.map.ownerAt(x, y) == decision.decidingSlot &&
          Building.isSeat(building)) {
        realm.capitalX = x;
        realm.capitalY = y;
        events.add(GameEvent(
          year: state.year,
          slot: decision.decidingSlot,
          type: 'capitalRelocated',
          visibility: EventVisibility.public,
          payload: {'x': x, 'y': y},
        ));
      }

    case 'electionBribe':
      final election = state.activeElection;
      final finalistId = payload['finalistId'] as int;
      if (election == null ||
          election.office.name != payload['office'] ||
          election.bribesDone.contains(finalistId)) {
        // The election moved on without this decision (e.g. the finalist
        // died) — a stale answer is a no-op that consumes the decision.
        break;
      }
      // Validate exactly the gifts that will be applied — summing raw
      // amounts would let negative entries offset an over-spend.
      final gifts = <(int, int)>[];
      var total = 0;
      for (final gift in (choice['gifts'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        final electorId = gift['electorId'] as int;
        final amount = gift['amount'] as int;
        if (amount <= 0 || !election.electorIds.contains(electorId)) {
          continue;
        }
        gifts.add((electorId, amount));
        total += amount;
      }
      // A negative treasury (e.g. after a lost war's reparations) must still
      // accept the empty "no bribe" submission — only reject spending more
      // than is actually available, never the zero case, or the finalist is
      // soft-locked in the bribe prompt with no way to confirm.
      final affordable = realm.treasury > 0 ? realm.treasury : 0;
      if (total > affordable) {
        throw ActionException(coreMessage('notEnoughTalerBribe'));
      }
      for (final (electorId, amount) in gifts) {
        realm.treasury -= amount;
        realmRuledBy(state, electorId)?.treasury += amount;
        election.addBribe(electorId, finalistId, amount);
      }
      election.bribesDone.add(finalistId);
      advanceElection(state, rng, events);

    case 'coercion':
      final victor = state.persons[payload['victorId'] as int];
      final captured = state.persons[payload['capturedRulerId'] as int];
      if (victor != null && captured != null && choice['apply'] != false) {
        war_rules.applyCoercion(
            state, payload['option'] as String, victor, captured, rng, events);
      }

    case 'convertOrDie':
      final captured = state.persons[payload['capturedRulerId'] as int];
      if (captured != null) {
        war_rules.applyConvertOrDie(state, captured, payload['religion'] as int,
            choice['accept'] == true, rng, events);
      }

    case 'electorVote':
      final election = state.activeElection;
      final electorId = payload['electorId'] as int;
      final finalistId = choice['finalistId'] as int?;
      if (election == null || election.office.name != payload['office']) {
        break; // election already over — stale decision, no-op
      }
      if (finalistId == null || !election.finalistIds.contains(finalistId)) {
        throw ActionException(coreMessage('voteForCandidate'));
      }
      election.votes[electorId] = finalistId;
      advanceElection(state, rng, events);

    default:
      // A decision type this build does not know — written by a newer app
      // version (decision types are additive schema changes). Consuming it
      // resolves to the rules' default; throwing would leave it pending
      // and re-prompted forever.
      break;
  }

  // Commit: the answer was accepted (or the decision was stale) — consume
  // it. Rejections threw above, so the decision is still pending then.
  state.pendingDecisions.remove(decision);
  return events;
}

/// Religion change (§4): katholisch free, evangelisch 500 T, moslemisch
/// 1,000 T. Availability follows §15.2 (Reformation/Ottoman gates).
/// Any conversion costs a floored popularity hit
/// ([religionChangePopularityCost]) on every slot the ruler holds;
/// converting to Islam forfeits any Kurfürst seat and switches the title
/// ladder (§16.1, §17.2).
List<GameEvent> _changeReligion(
    GameState state, Realm realm, ChangeReligion action) {
  final dynasty = state.dynasty(realm.slot);
  final religion = action.religion;
  if (religion < Religion.katholisch || religion > Religion.moslemisch) {
    throw ActionException(coreMessage('unknownReligion'));
  }
  if (religion == dynasty.religion) {
    throw ActionException(coreMessage('alreadyYourReligion'));
  }
  // Availability is inclusive of the event year itself (see
  // [religionAvailable]) — blocking the announcement year read as a bug
  // (user report 2026-07-10).
  if (!religionAvailable(state, religion)) {
    throw ActionException(coreMessage(religion == Religion.evangelisch
        ? 'reformationNotYet'
        : 'islamNotYet'));
  }

  final cost = religionChangeCost(religion);
  _requireFunds(realm, cost);
  realm.treasury -= cost;
  dynasty.religion = religion;

  // Popularity hit on every slot this ruler holds (ruler aliasing, §19).
  // [DEVIATION] A reduced, floored cost (see religionChangePopularityCost)
  // instead of the original's flat −70: a conversion shakes the realm but
  // can never on its own tip it into a §19.1 strife collapse. The actual
  // loss is reported so the UI can tell the player exactly why their
  // popularity dropped (it never exceeds religionChangePopularityCost).
  var popularityLost = 0;
  for (final r in state.realms) {
    if (r.rulerId == realm.rulerId) {
      final lost = militarismPopularityCost(r, religionChangePopularityCost);
      if (lost > popularityLost) popularityLost = lost;
    }
  }

  if (religion == Religion.moslemisch) {
    // The whole dynasty converts (religion is a dynasty property), so
    // every member's Kurfürst seat is forfeit — exactly as in the
    // coerced conversion (§12.1); seat eligibility (§17.2) keys on the
    // member's HOME-dynasty religion. A cross-dynasty ruler (§15.4) whose
    // own house did not convert keeps his seat — no blanket rulerId strip.
    state.kurfuerstenIds
        .removeWhere((id) => state.persons[id]?.dynasty == realm.slot);
  }

  // §14.4: religiously incompatible marriages dissolve.
  final events = <GameEvent>[];
  divorceIncompatibleCouples(state, realm.slot, events);

  // Switch the title ladder (§16.1). The exact class mapping is not in the
  // spec; we reset to the ladder's floor (Scheich/Ritter) and let the
  // per-turn promotion check (§16.2, Phase 3) climb back by prestige.
  switchTitleLadder(realm, religion);

  events.add(GameEvent(
    year: state.year,
    slot: realm.slot,
    type: 'religionChanged',
    visibility: EventVisibility.public,
    payload: {'religion': religion, 'popularityLost': popularityLost},
  ));
  return events;
}
