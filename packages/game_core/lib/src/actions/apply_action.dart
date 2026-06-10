import '../rng/rng.dart';
import '../rules/dynasty.dart';
import '../rules/offices.dart';
import '../rules/war.dart' as war_rules;
import '../state/constants.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/realm.dart';
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
  if (action.slot < 1 || action.slot > World.realmCount) {
    throw ActionException('invalid realm slot ${action.slot}');
  }
  final next = state.copy();
  final realm = next.realm(action.slot);
  if (realm.isVacant) {
    throw ActionException('realm ${action.slot} is vacant');
  }

  final events = switch (action) {
    ClaimTile() => _claimTile(next, realm, action),
    Build() => _build(next, realm, action, rng),
    Demolish() => _demolish(next, realm, action),
    ChangeReligion() => _changeReligion(next, realm, action),
    SellGood() => _sellGood(next, realm, action),
    InvestShips() => _investShips(next, realm, action, rng),
    ProposeMarriage() => _proposeMarriage(next, realm, action, rng),
    ResolveDecision() => _resolveDecision(next, realm, action, rng),
    RecruitTroops() => applyRecruitTroops(next, realm, action, rng),
    HireSoeldner() => applyHireSoeldner(next, realm, action),
    ReinforceTroop() => applyReinforceTroop(next, realm, action, rng),
    MergeTroops() => applyMergeTroops(next, realm, action),
    DisbandTroop() => applyDisbandTroop(next, realm, action),
    MoveTroop() => applyMoveTroop(next, realm, action),
    DeclareWar() => applyDeclareWar(next, realm, action, rng),
    WarMove() => applyWarMove(next, realm, action, rng),
    WarPlunder() => applyWarPlunder(next, realm, action, rng),
    WarPeaceWish() => applyWarPeaceWish(next, realm, action),
    WarEndRound() => applyWarEndRound(next, realm, action, rng),
    SettlementAnnex() => applySettlementAnnex(next, realm, action),
    SettlementFinish() => applySettlementFinish(next, realm, action),
    SpyMission() => applySpyMission(next, realm, action, rng),
    OrderAssassination() => applyOrderAssassination(next, realm, action),
    AdjustGuards() => applyAdjustGuards(next, realm, action),
  };

  next.rngSeed = rng.seed;
  next.events.addAll(events);
  return ActionResult(next, events);
}

void _requireMovementPoint(Realm realm) {
  if (realm.movementPoints < 1) {
    throw ActionException('no movement points left');
  }
}

void _requireFunds(Realm realm, int cost) {
  if (realm.treasury < cost) {
    throw ActionException('not enough Taler (need $cost)');
  }
}

void _requireOnMap(WorldMap map, int x, int y) {
  if (!map.inBounds(x, y)) {
    throw ActionException('tile ($x, $y) is outside the map');
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

/// Claiming an adjacent unowned land tile costs 1 movement point (§4).
List<GameEvent> _claimTile(GameState state, Realm realm, ClaimTile action) {
  final map = state.map;
  _requireOnMap(map, action.x, action.y);
  if (map.isWaterAt(action.x, action.y)) {
    throw ActionException('water cannot be claimed');
  }
  if (map.ownerAt(action.x, action.y) != World.niemand) {
    throw ActionException('tile already has an owner');
  }
  if (!_adjacentToOwn(map, realm.slot, action.x, action.y)) {
    throw ActionException('tile is not adjacent to your territory');
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

/// Build menu (§4): Kornfeld on Ebene, Weide on Berg, Dorf on land,
/// Burg/Palast on land, Hafen on the coast. Markt/Stadt never built.
/// Costs 1 movement point + the building's Taler cost.
List<GameEvent> _build(
    GameState state, Realm realm, Build action, Rng rng) {
  final map = state.map;
  _requireOnMap(map, action.x, action.y);

  final building = action.building;
  final cost = building >= 0 && building < Building.cost.length
      ? Building.cost[building]
      : null;
  if (cost == null) {
    throw ActionException('this cannot be built');
  }
  if (map.ownerAt(action.x, action.y) != realm.slot) {
    throw ActionException('you do not own this tile');
  }
  if (map.buildingAt(action.x, action.y) != Building.none) {
    throw ActionException('the tile is already built on');
  }

  final terrain = map.terrainAt(action.x, action.y);
  final terrainOk = switch (building) {
    Building.kornfeld => terrain == Terrain.ebene,
    Building.weide => terrain == Terrain.berg,
    Building.dorf ||
    Building.burg ||
    Building.palast =>
      Terrain.isLand(terrain),
    // The starting cross puts the Hafen on an owned water tile (§5);
    // explicit builds follow the same convention ("Hafen on the coast"):
    // an owned water tile next to your land.
    Building.hafen => Terrain.isWater(terrain) &&
        _adjacentToOwn(map, realm.slot, action.x, action.y),
    _ => false,
  };
  if (!terrainOk) {
    throw ActionException('wrong terrain for this building');
  }
  if (building == Building.dorf &&
      (action.townName == null || action.townName!.trim().isEmpty)) {
    throw ActionException('the Dorf needs a name');
  }

  _requireMovementPoint(realm);
  _requireFunds(realm, cost);

  realm.movementPoints--;
  realm.treasury -= cost;
  map.building[map.index(action.x, action.y)] = building;
  realm.tileCount[Building.none]--;
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
    throw ActionException('you do not own this tile');
  }
  final building = map.buildingAt(action.x, action.y);
  if (building == Building.none) {
    throw ActionException('nothing to demolish here');
  }
  if (building == Building.dorf ||
      building == Building.markt ||
      building == Building.stadt) {
    throw ActionException('towns cannot be demolished');
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

/// Market sale (§9.1): once per good per turn, at the global year price.
/// "Das geht nicht !!!" on a bad amount; selling reduces the food stock —
/// what you sell, your people don't eat.
List<GameEvent> _sellGood(GameState state, Realm realm, SellGood action) {
  final grain = action.good == MarketGood.grain;
  if (grain ? realm.soldGrainThisTurn : realm.soldCattleThisTurn) {
    throw ActionException('Sie haben diese Runde schon verkauft !!!');
  }
  final stock = grain ? realm.grainHarvest : realm.livestockHarvest;
  if (action.amount < 0 || action.amount > stock) {
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
    throw ActionException('you already invested this turn');
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

/// "H(e)irat vorschlagen" (§14.1): validates eligibility, then either the
/// AI 25% roll or a pending decision for a human target.
List<GameEvent> _proposeMarriage(
    GameState state, Realm realm, ProposeMarriage action, Rng rng) {
  final proposer = state.persons[action.proposerId];
  final target = state.persons[action.targetId];
  if (proposer == null || target == null) {
    throw ActionException('person not found');
  }
  if (proposer.dynasty != realm.slot) {
    throw ActionException('the proposer is not in your dynasty');
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
  return events;
}

/// Resolves a pending decision addressed to this slot.
List<GameEvent> _resolveDecision(
    GameState state, Realm realm, ResolveDecision action, Rng rng) {
  final index =
      state.pendingDecisions.indexWhere((d) => d.id == action.decisionId);
  if (index < 0) {
    throw ActionException('decision ${action.decisionId} not found');
  }
  final decision = state.pendingDecisions[index];
  if (decision.decidingSlot != action.slot) {
    throw ActionException('this decision is not yours to make');
  }
  state.pendingDecisions.removeAt(index);

  final events = <GameEvent>[];
  final payload = decision.payload;
  final choice = action.choice;

  switch (decision.type) {
    case 'marriageConsent':
      final proposer = state.persons[payload['proposerId'] as int];
      final target = state.persons[payload['targetId'] as int];
      final stillValid = proposer != null &&
          target != null &&
          proposer.spouseId == null &&
          target.spouseId == null;
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
        throw ActionException('invalid heir choice');
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
        throw ActionException('this election phase is over');
      }
      var total = 0;
      final gifts = (choice['gifts'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final gift in gifts) {
        total += gift['amount'] as int;
      }
      if (total < 0 || total > realm.treasury) {
        throw ActionException('not enough Taler for these bribes');
      }
      for (final gift in gifts) {
        final electorId = gift['electorId'] as int;
        final amount = gift['amount'] as int;
        if (amount <= 0 || !election.electorIds.contains(electorId)) {
          continue;
        }
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
        throw ActionException('this election is over');
      }
      if (finalistId == null ||
          !election.finalistIds.contains(finalistId)) {
        throw ActionException('vote for one of the finalists');
      }
      election.votes[electorId] = finalistId;
      advanceElection(state, rng, events);

    default:
      throw ActionException('unknown decision type ${decision.type}');
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
    throw ActionException('unknown religion');
  }
  if (religion == dynasty.religion) {
    throw ActionException('that is already your religion');
  }
  if (religion == Religion.evangelisch && state.year <= state.reformationYear) {
    throw ActionException('the Reformation has not happened yet');
  }
  if (religion == Religion.moslemisch && state.year <= state.ottomanYear) {
    throw ActionException('Islam is not available yet');
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
  for (final r in state.realms) {
    if (r.rulerId == realm.rulerId) {
      r.popularity = (r.popularity - 70).clamp(0, 150);
    }
  }

  if (religion == Religion.moslemisch) {
    state.kurfuerstenIds.remove(realm.rulerId);
  }

  // §14.4: religiously incompatible marriages dissolve.
  final events = <GameEvent>[];
  divorceIncompatibleCouples(state, realm.slot, events);

  // Switch the title ladder (§16.1). The exact class mapping is not in the
  // spec; we reset to the ladder's floor (Scheich/Ritter) and let the
  // per-turn promotion check (§16.2, Phase 3) climb back by prestige.
  final female = realm.titleClass > 12;
  final baseClass = religion == Religion.moslemisch
      ? 9
      : (realm.titleClass > (female ? 20 : 8) ? 1 : null);
  if (baseClass != null) {
    realm.titleClass = baseClass + (female ? 12 : 0);
  }

  events.add(GameEvent(
    year: state.year,
    slot: realm.slot,
    type: 'religionChanged',
    visibility: EventVisibility.public,
    payload: {'religion': religion},
  ));
  return events;
}
