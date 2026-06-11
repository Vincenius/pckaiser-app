import '../data/tables.dart';
import '../rng/rng.dart';
import '../rules/dynasty.dart';
import '../rules/offices.dart';
import '../rules/realm_merge.dart';
import '../rules/titles.dart' show switchTitleLadder;
import '../rules/war.dart' as war_rules;
import '../state/constants.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/person.dart';
import '../state/realm.dart';
import '../state/ship.dart';
import '../state/town.dart';
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
  if (action.slot < 1 || action.slot > World.realmCount) {
    throw ActionException('Ungültiges Reich ${action.slot} !');
  }
  final realm = state.realm(action.slot);
  if (realm.isVacant) {
    throw ActionException('Das Reich ist verwaist !');
  }

  return switch (action) {
    ClaimTile() => _claimTile(state, realm, action),
    SendShip() => _sendShip(state, realm, action),
    BuyShip() => _buyShip(state, realm, action),
    MoveShip() => _moveShip(state, realm, action),
    ColonizeShip() => _colonizeShip(state, realm, action, rng),
    Build() => _build(state, realm, action, rng),
    Demolish() => _demolish(state, realm, action),
    ChangeReligion() => _changeReligion(state, realm, action),
    SellGood() => _sellGood(state, realm, action),
    InvestShips() => _investShips(state, realm, action, rng),
    SendMoney() => _sendMoney(state, realm, action),
    RelocateCapital() => _relocateCapital(state, realm, action),
    ProposeMarriage() => _proposeMarriage(state, realm, action, rng),
    MarryCommoner() => _marryCommoner(state, realm, action, rng),
    ResolveDecision() => _resolveDecision(state, realm, action, rng),
    MergeRealms() => _mergeRealms(state, realm, action, rng),
    RecruitTroops() => applyRecruitTroops(state, realm, action, rng),
    HireSoeldner() => applyHireSoeldner(state, realm, action),
    ReinforceTroop() => applyReinforceTroop(state, realm, action, rng),
    TrainTroop() => applyTrainTroop(state, realm, action),
    DrillTroop() => applyDrillTroop(state, realm, action),
    RenameTroop() => applyRenameTroop(state, realm, action),
    MergeTroops() => applyMergeTroops(state, realm, action),
    DisbandTroop() => applyDisbandTroop(state, realm, action),
    MoveTroop() => applyMoveTroop(state, realm, action),
    DeclareWar() => applyDeclareWar(state, realm, action, rng),
    WarMove() => applyWarMove(state, realm, action, rng),
    WarPlunder() => applyWarPlunder(state, realm, action, rng),
    WarPeaceWish() => applyWarPeaceWish(state, realm, action),
    WarEndRound() => applyWarEndRound(state, realm, action, rng),
    SettlementAnnex() => applySettlementAnnex(state, realm, action),
    SettlementFinish() => applySettlementFinish(state, realm, action),
    SpyMission() => applySpyMission(state, realm, action, rng),
    OrderAssassination() => applyOrderAssassination(state, realm, action),
    AdjustGuards() => applyAdjustGuards(state, realm, action),
  };
}

void _requireMovementPoint(Realm realm) {
  if (realm.movementPoints < 1) {
    throw ActionException('Du hast keine Züge mehr !');
  }
}

void _requireFunds(Realm realm, int cost) {
  if (realm.treasury < cost) {
    throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
  }
}

void _requireOnMap(WorldMap map, int x, int y) {
  if (!map.inBounds(x, y)) {
    throw ActionException('Das Feld liegt außerhalb der Karte !');
  }
}

bool _adjacentToOwn(WorldMap map, int slot, int x, int y) {
  for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
    if (map.inBounds(x + dx, y + dy) &&
        map.ownerAt(x + dx, y + dy) == slot) {
      return true;
    }
  }
  return false;
}

/// Like [_adjacentToOwn], but only own LAND tiles count — an own Hafen on
/// a water tile must not anchor further coastal builds.
bool _adjacentToOwnLand(WorldMap map, int slot, int x, int y) {
  for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
    if (map.inBounds(x + dx, y + dy) &&
        map.ownerAt(x + dx, y + dy) == slot &&
        Terrain.isLand(map.terrainAt(x + dx, y + dy))) {
      return true;
    }
  }
  return false;
}

/// Claiming an adjacent unowned land tile costs 1 movement point (§4).
List<GameEvent> _claimTile(GameState state, Realm realm, ClaimTile action) {
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if (map.isWaterAt(action.x, action.y)) {
    throw ActionException('Wasser kann nicht beansprucht werden !');
  }
  if (map.ownerAt(action.x, action.y) != World.niemand) {
    throw ActionException('Das Feld hat bereits einen Besitzer !');
  }
  if (!_adjacentToOwn(map, realm.slot, action.x, action.y)) {
    throw ActionException('Das Feld grenzt nicht an dein Territorium !');
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

/// "(S)chiff" colony ship, rules v6–v8 (manual: "man kann von [Häfen] aus
/// auch Schiffe ausschicken, um z.B. unbewohnte Inseln zu kolonisieren";
/// proc_005D2B): claims a free land tile reachable over water from an own
/// Hafen for a flat 700 T — the ship is consumed at its build cost.
/// Rules v9 retired this tap-target voyage in favor of manually steered
/// ships ([_buyShip]/[_moveShip]/[_colonizeShip]).
List<GameEvent> _sendShip(GameState state, Realm realm, SendShip action) {
  if (state.rulesVersion < 6) {
    throw ActionException('Das geht in diesem Spielstand noch nicht !');
  }
  if (state.rulesVersion >= 9) {
    throw ActionException(
        'Schiffe werden jetzt im Hafen gekauft und selbst gesteuert !');
  }
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if (map.isWaterAt(action.x, action.y)) {
    throw ActionException('Das Schiff muß ein freies Landfeld ansteuern !');
  }
  if (map.ownerAt(action.x, action.y) != World.niemand) {
    throw ActionException('Das Feld hat bereits einen Besitzer !');
  }
  if (realm.tileCount[Building.hafen] < 1) {
    throw ActionException('Du brauchst zuerst einen Hafen !');
  }
  if (!map.shipReachable(realm.slot, action.x, action.y)) {
    throw ActionException('Dieses Feld ist über See nicht erreichbar !');
  }
  const cost = Building.shipCost;
  _requireMovementPoint(realm);
  _requireFunds(realm, cost);

  realm.movementPoints--;
  realm.treasury -= cost;
  map.owner[map.index(action.x, action.y)] = realm.slot;
  realm.tileCount[Building.none]++;

  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'shipColonized',
      visibility: EventVisibility.public,
      payload: {'x': action.x, 'y': action.y},
    ),
  ];
}

void _requireManualShips(GameState state) {
  if (state.rulesVersion < 9) {
    throw ActionException('Das geht in diesem Spielstand noch nicht !');
  }
}

Ship _shipAt(Realm realm, int index) {
  if (index < 0 || index >= realm.ships.length) {
    throw ActionException('Dieses Schiff gibt es nicht !');
  }
  return realm.ships[index];
}

/// Buy a colony ship at an own Hafen (rules v9): 700 T + 1 Zug; the ship
/// spawns on the harbor's water tile and is steered manually from there.
List<GameEvent> _buyShip(GameState state, Realm realm, BuyShip action) {
  _requireManualShips(state);
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if (map.ownerAt(action.x, action.y) != realm.slot ||
      map.buildingAt(action.x, action.y) != Building.hafen) {
    throw ActionException('Schiffe werden in einem eigenen Hafen gekauft !');
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

/// Sail a ship to a water tile (rules v9): shortest all-water route,
/// 1 Zug per water tile — the original's "(S)chiff steuern" cost. A
/// voyage longer than the remaining Züge must wait for the next turn
/// (or stop at a nearer tile).
List<GameEvent> _moveShip(GameState state, Realm realm, MoveShip action) {
  _requireManualShips(state);
  final ship = _shipAt(realm, action.shipIndex);
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if (!map.isWaterAt(action.x, action.y)) {
    throw ActionException('Schiffe fahren nur auf dem Wasser !');
  }
  final distance =
      map.waterPathLength(ship.x, ship.y, action.x, action.y);
  if (distance < 0) {
    throw ActionException('Dieses Feld ist über See nicht erreichbar !');
  }
  if (distance == 0) {
    throw ActionException('Da liegt das Schiff doch schon !');
  }
  if (realm.movementPoints < distance) {
    throw ActionException(
        'So weit kommt das Schiff nicht mehr — die Fahrt kostet '
        '$distance Züge !');
  }

  realm.movementPoints -= distance;
  ship.x = action.x;
  ship.y = action.y;
  return const [];
}

/// Colonize with a ship (rules v9): a free land tile orthogonally next to
/// the ship becomes the realm's, with a freshly founded Dorf on it — the
/// ship is consumed (its settlers stay). Costs 1 Zug; the ship's 700 T
/// already covered the colony.
List<GameEvent> _colonizeShip(
    GameState state, Realm realm, ColonizeShip action, Rng rng) {
  _requireManualShips(state);
  final ship = _shipAt(realm, action.shipIndex);
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if ((ship.x - action.x).abs() + (ship.y - action.y).abs() != 1) {
    throw ActionException('Das Schiff muß direkt neben dem Feld liegen !');
  }
  if (map.isWaterAt(action.x, action.y)) {
    throw ActionException('Kolonisiert wird ein freies Landfeld !');
  }
  if (map.ownerAt(action.x, action.y) != World.niemand ||
      map.buildingAt(action.x, action.y) != Building.none) {
    throw ActionException('Das Feld hat bereits einen Besitzer !');
  }
  if (action.townName.trim().isEmpty) {
    throw ActionException('Das Dorf braucht einen Namen !');
  }
  _requireMovementPoint(realm);

  realm.movementPoints--;
  realm.ships.remove(ship);
  map.owner[map.index(action.x, action.y)] = realm.slot;
  map.building[map.index(action.x, action.y)] = Building.dorf;
  realm.tileCount[Building.dorf]++;

  final town = Town(
    name: action.townName.trim(),
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
List<GameEvent> _build(
    GameState state, Realm realm, Build action, Rng rng) {
  final map = state.map;
  _requireOnMap(map, action.x, action.y);

  final building = action.building;
  final cost = building >= 0 && building < Building.cost.length
      ? Building.cost[building]
      : null;
  if (cost == null) {
    throw ActionException('Das kann nicht gebaut werden !');
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
      _adjacentToOwnLand(map, realm.slot, action.x, action.y);
  final claimOnBuild = building != Building.hafen &&
      owner == World.niemand &&
      Terrain.isLand(terrain) &&
      _adjacentToOwn(map, realm.slot, action.x, action.y);
  if (owner != realm.slot && !hafenOnCoast && !claimOnBuild) {
    throw ActionException('Das Feld gehört dir nicht !');
  }
  if (map.buildingAt(action.x, action.y) != Building.none) {
    throw ActionException('Das Feld ist bereits bebaut !');
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
    throw ActionException('Falsches Gelände für dieses Bauwerk !');
  }
  if (building == Building.dorf &&
      (action.townName == null || action.townName!.trim().isEmpty)) {
    throw ActionException('Das Dorf braucht einen Namen !');
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
      name: action.townName!.trim(),
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

/// "(A)breißen" — 100 T, clears the building (§4). Towns cannot be
/// demolished this way (the original demolishes *fields*).
List<GameEvent> _demolish(GameState state, Realm realm, Demolish action) {
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if (map.ownerAt(action.x, action.y) != realm.slot) {
    throw ActionException('Das Feld gehört dir nicht !');
  }
  final building = map.buildingAt(action.x, action.y);
  if (building == Building.none) {
    throw ActionException('Hier steht doch gar nichts !');
  }
  if (building == Building.dorf ||
      building == Building.markt ||
      building == Building.stadt) {
    throw ActionException('Orte können nicht abgerissen werden !');
  }
  const cost = 100;
  _requireMovementPoint(realm);
  _requireFunds(realm, cost);

  realm.movementPoints--;
  realm.treasury -= cost;
  map.building[map.index(action.x, action.y)] = Building.none;
  realm.tileCount[building]--;
  realm.tileCount[Building.none]++;

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
List<GameEvent> _mergeRealms(
    GameState state, Realm realm, MergeRealms action, Rng rng) {
  // Rules v4: no merging while either realm fights the active war — the
  // merged-in troops would bypass the v2 no-reinforcement-at-war gate and
  // desync the war's movesLeft/snapshot bookkeeping.
  final war = state.activeWar;
  if (state.rulesVersion >= 4 &&
      war != null &&
      (war.isParticipant(realm.slot) ||
          war.isParticipant(action.sourceSlot))) {
    throw ActionException('Nicht mitten im Krieg !');
  }
  if (!mergeableSlots(state, realm.slot).contains(action.sourceSlot)) {
    throw ActionException('Diese Reiche können nicht zusammengelegt werden !');
  }
  final events = <GameEvent>[];
  mergeRealms(state, realm.slot, action.sourceSlot, rng, events);
  return events;
}

/// Market sale (§9.1): once per good per turn, at the global year price.
/// "Das geht nicht !!!" on a bad amount; selling reduces the food stock —
/// what you sell, your people don't eat.
List<GameEvent> _sellGood(GameState state, Realm realm, SellGood action) {
  final grain = action.good == MarketGood.grain;
  if (grain ? realm.soldGrainThisTurn : realm.soldCattleThisTurn) {
    throw ActionException('Du hast diese Runde schon verkauft !!!');
  }
  final stock = grain ? realm.grainHarvest : realm.livestockHarvest;
  // amount ≥ 1: selling 0 would still burn the once-per-turn flag.
  if (action.amount < 1 || action.amount > stock) {
    throw ActionException('Das geht nicht !!!');
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
/// 50/50 profit up to 2× or loss down to (almost) zero.
List<GameEvent> _investShips(
    GameState state, Realm realm, InvestShips action, Rng rng) {
  if (realm.investedThisTurn) {
    throw ActionException('Du hast diese Runde schon investiert !');
  }
  final maxInvestment = realm.tileCount[Building.hafen] * 600;
  if (action.amount <= 0 ||
      action.amount > realm.treasury ||
      action.amount > maxInvestment) {
    throw ActionException('Das geht nicht !!!');
  }

  realm.treasury -= action.amount;
  final int returned;
  if (rng.nextInt(2) == 0) {
    returned = action.amount + rng.nextInt(action.amount) + 1; // profit
  } else {
    returned = action.amount - (rng.nextInt(action.amount) + 1); // loss
  }
  realm.treasury += returned;
  realm.investedThisTurn = true;

  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'shipsReturned',
      visibility: EventVisibility.owner,
      payload: {'invested': action.amount, 'returned': returned},
    ),
  ];
}

/// "Geld schicken" (§6.2): transfer Taler to another living realm.
List<GameEvent> _sendMoney(GameState state, Realm realm, SendMoney action) {
  if (action.targetSlot < 1 ||
      action.targetSlot > World.realmCount ||
      action.targetSlot == realm.slot) {
    throw ActionException('Ungültiges Zielreich !');
  }
  final target = state.realm(action.targetSlot);
  if (target.isVacant) {
    throw ActionException('Das Reich ist verwaist !');
  }
  if (action.amount < 1) throw ActionException('Das geht nicht !!!');
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

/// "Sitz verlegen" (§6.2): 5,000 T; valid target = own tile with
/// Stadt/Burg/Palast; only when the capital is unset or lost.
List<GameEvent> _relocateCapital(
    GameState state, Realm realm, RelocateCapital action) {
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if (map.ownerAt(realm.capitalX, realm.capitalY) == realm.slot) {
    throw ActionException('Dein Sitz ist nicht verloren !');
  }
  if (map.ownerAt(action.x, action.y) != realm.slot) {
    throw ActionException('Der neue Sitz muss auf deinem Territorium liegen !');
  }
  final building = map.buildingAt(action.x, action.y);
  if (building != Building.stadt &&
      building != Building.burg &&
      building != Building.palast) {
    throw ActionException('Der neue Sitz braucht eine Stadt, Burg oder einen Palast !');
  }
  _requireFunds(realm, 5000);

  realm.treasury -= 5000;
  realm.capitalX = action.x;
  realm.capitalY = action.y;

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

/// "H(e)irat vorschlagen" (§14.1): validates eligibility, then either the
/// AI 25% roll or a pending decision for a human target.
List<GameEvent> _proposeMarriage(
    GameState state, Realm realm, ProposeMarriage action, Rng rng) {
  if (realm.proposedMarriageThisTurn) {
    throw ActionException('Nur ein Heiratsantrag pro Zug !');
  }
  final proposer = state.persons[action.proposerId];
  final target = state.persons[action.targetId];
  if (proposer == null || target == null) {
    throw ActionException('Person nicht gefunden !');
  }
  if (proposer.dynasty != realm.slot) {
    throw ActionException('Diese Person gehört nicht zu deiner Dynastie !');
  }
  final eligible = proposer.spouseId == null &&
      target.spouseId == null &&
      proposer.gender != target.gender &&
      proposer.age >= 14 &&
      target.age >= 14 &&
      (proposer.age - target.age).abs() < 10 &&
      proposer.dynasty != target.dynasty &&
      state.dynasty(proposer.dynasty).religion ==
          state.dynasty(target.dynasty).religion;
  if (!eligible) {
    throw ActionException('Es gibt zur Zeit keinen passenden Partner !');
  }
  final events = <GameEvent>[];
  proposeMarriage(state, proposer, target, rng, events);
  realm.proposedMarriageThisTurn = true;
  return events;
}

/// "(B)ürgerlich heiraten" (§14.1): marry [MarryCommoner.personId] to a
/// freshly created commoner. [DEVIATION] A commoner always accepts (the
/// original rolled the 25% like any proposal); the spouse joins the
/// dynasty so the §14.3 birth loop applies to the couple. Rules v5+:
/// always available — it neither checks nor consumes the one royal
/// proposal per turn.
List<GameEvent> _marryCommoner(
    GameState state, Realm realm, MarryCommoner action, Rng rng) {
  if (state.rulesVersion < 5 && realm.proposedMarriageThisTurn) {
    throw ActionException('Nur ein Heiratsantrag pro Zug !');
  }
  final person = state.persons[action.personId];
  if (person == null || person.dynasty != realm.slot) {
    throw ActionException('Diese Person gehört nicht zu deiner Dynastie !');
  }
  if (person.spouseId != null || person.age < 14) {
    throw ActionException('Es gibt zur Zeit keinen passenden Partner !');
  }
  if (state.rulesVersion < 5) realm.proposedMarriageThisTurn = true;

  final events = <GameEvent>[];
  final dynasty = state.dynasty(realm.slot);
  final gender = 1 - person.gender;
  final names = dynasty.religion == Religion.moslemisch
      ? (gender == 0 ? ottomanMaleNames : ottomanFemaleNames)
      : (gender == 0 ? europeanMaleNames : europeanFemaleNames);
  // Age gap < 10 like every §14.1 match, but never below 14.
  var age = person.age - 9 + rng.nextInt(19);
  if (age < 14) age = 14;
  final spouse = Person(
    id: state.nextPersonId++,
    name: names[rng.nextInt(names.length)],
    age: age,
    dynasty: realm.slot,
    gender: gender,
  );
  state.persons[spouse.id] = spouse;
  dynasty.memberIds.add(spouse.id);
  marry(state, person, spouse, events); // "Angenommen !"
  return events;
}

/// Resolves a pending decision addressed to this slot.
List<GameEvent> _resolveDecision(
    GameState state, Realm realm, ResolveDecision action, Rng rng) {
  final index =
      state.pendingDecisions.indexWhere((d) => d.id == action.decisionId);
  if (index < 0) {
    throw ActionException('Entscheidung nicht gefunden !');
  }
  final decision = state.pendingDecisions[index];
  if (decision.decidingSlot != action.slot) {
    throw ActionException('Diese Entscheidung steht dir nicht zu !');
  }
  state.pendingDecisions.removeAt(index);

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
          payload: payload,
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
        // the provisional heir simply stays crowned — never throw, or the
        // decision would be re-prompted with no resolvable answer.
        break;
      }
      // Re-crown only slots still held by the provisional heir — conquest
      // in between must not be undone.
      for (final slot in (payload['slots'] as List).cast<int>()) {
        if (state.realm(slot).rulerId == provisional) {
          state.realm(slot).rulerId = heirId;
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

    case 'childName':
      final child = state.persons[payload['childId'] as int];
      final name = (choice['name'] as String?)?.trim() ?? '';
      if (child != null && name.isNotEmpty) {
        child.name = name;
      }

    case 'electionBribe':
      final election = state.activeElection;
      final finalistId = payload['finalistId'] as int;
      if (election == null ||
          election.office.name != payload['office'] ||
          election.bribesDone.contains(finalistId)) {
        // The election moved on without this decision (e.g. the finalist
        // died) — resolving must not throw, or the now-removed decision
        // would be restored with the discarded state copy and re-prompted
        // forever. Stale phase: the resolution is simply a no-op.
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
      if (total > realm.treasury) {
        throw ActionException('Du hast nicht genügend Taler für diese Bestechung !');
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
        war_rules.applyCoercion(state, payload['option'] as String, victor,
            captured, rng, events);
      }

    case 'convertOrDie':
      final captured = state.persons[payload['capturedRulerId'] as int];
      if (captured != null) {
        war_rules.applyConvertOrDie(state, captured,
            payload['religion'] as int, choice['accept'] == true, rng,
            events);
      }

    case 'electorVote':
      final election = state.activeElection;
      final electorId = payload['electorId'] as int;
      final finalistId = choice['finalistId'] as int?;
      if (election == null || election.office.name != payload['office']) {
        break; // election already over — stale decision, no-op
      }
      if (finalistId == null ||
          !election.finalistIds.contains(finalistId)) {
        throw ActionException('Stimme für einen der Kandidaten !');
      }
      election.votes[electorId] = finalistId;
      advanceElection(state, rng, events);

    default:
      // A decision type this build does not know — written by a newer app
      // version (decision types are additive schema changes). Throwing
      // would restore the decision with the discarded state copy and
      // re-prompt it forever; dropping it resolves to the rules' default.
      break;
  }

  return events;
}

/// Religion change (§4): katholisch free, evangelisch 500 T, moslemisch
/// 1,000 T. Availability follows §15.2 (Reformation/Ottoman gates).
/// Any conversion costs −70 popularity (clamped ≥ 0) on every slot the
/// ruler holds; converting to Islam forfeits any Kurfürst seat and switches
/// the title ladder (§16.1, §17.2).
List<GameEvent> _changeReligion(
    GameState state, Realm realm, ChangeReligion action) {
  final dynasty = state.dynasty(realm.slot);
  final religion = action.religion;
  if (religion < Religion.katholisch || religion > Religion.moslemisch) {
    throw ActionException('Unbekannte Religion !');
  }
  if (religion == dynasty.religion) {
    throw ActionException('Das ist bereits deine Religion !');
  }
  if (religion == Religion.evangelisch && state.year <= state.reformationYear) {
    throw ActionException('Die Reformation hat noch nicht stattgefunden !');
  }
  if (religion == Religion.moslemisch && state.year <= state.ottomanYear) {
    throw ActionException('Der Islam ist noch nicht verfügbar !');
  }

  final cost = switch (religion) {
    Religion.evangelisch => 500,
    Religion.moslemisch => 1000,
    _ => 0,
  };
  _requireFunds(realm, cost);
  realm.treasury -= cost;
  dynasty.religion = religion;

  // −70 popularity on every slot this ruler holds (ruler aliasing, §19).
  // Clamped 0–100 like every other popularity write (Realm.popularity).
  for (final r in state.realms) {
    if (r.rulerId == realm.rulerId) {
      r.popularity = (r.popularity - 70).clamp(0, 100);
    }
  }

  if (religion == Religion.moslemisch) {
    state.kurfuerstenIds.remove(realm.rulerId);
    // Rules v10: the whole dynasty converts (religion is a dynasty
    // property), so every member's Kurfürst seat is forfeit — exactly as
    // in the coerced conversion (§12.1); seat eligibility (§17.2) keys
    // on the member's home-dynasty religion.
    if (state.rulesVersion >= 10) {
      state.kurfuerstenIds
          .removeWhere((id) => state.persons[id]?.dynasty == realm.slot);
    }
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
    payload: {'religion': religion},
  ));
  return events;
}
