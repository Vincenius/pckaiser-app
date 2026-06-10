/// Handlers for the §10–§13 actions, called from `applyAction`'s
/// dispatcher. Same contract: mutate the (already copied) state, throw
/// [ActionException] on invalid input, return the emitted events.
library;

import '../rng/rng.dart';
import '../rules/espionage.dart';
import '../rules/protection.dart';
import '../rules/troops.dart';
import '../rules/war.dart';
import '../state/constants.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/realm.dart';
import '../state/troop.dart';
import '../state/war.dart';
import 'player_action.dart';

Troop unitAt(Realm realm, int index) {
  if (index < 0 || index >= realm.troops.length) {
    throw ActionException('no such troop unit');
  }
  return realm.troops[index];
}

List<GameEvent> applyRecruitTroops(
    GameState state, Realm realm, RecruitTroops action, Rng rng) {
  if (action.men <= 0) throw ActionException('Das geht nicht !!!');
  if (action.troopClass < TroopClass.infanterie ||
      action.troopClass > TroopClass.artillerie) {
    throw ActionException('unknown troop class');
  }
  if (realm.armySize + action.men > realm.troopCapacity) {
    throw ActionException('not enough garrison capacity');
  }
  final cost = 5 * action.men + classSurcharge(action.troopClass);
  if (realm.treasury < cost) {
    throw ActionException('not enough Taler (need $cost)');
  }
  realm.treasury -= cost;
  quarterRecruits(realm, action.men, rng);
  realm.troops.add(Troop(
    name: action.name.trim().isEmpty ? 'Rekruten' : action.name.trim(),
    men: action.men,
    troopClass: action.troopClass,
    quality: TroopQuality.regular,
    garrisonCounted: true,
    x: realm.capitalX,
    y: realm.capitalY,
  ));
  state.map.troopMarker[
      state.map.index(realm.capitalX, realm.capitalY)] = 1;
  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'troopsRecruited',
      visibility: EventVisibility.owner,
      payload: {'men': action.men, 'troopClass': action.troopClass},
    ),
  ];
}

List<GameEvent> applyHireSoeldner(
    GameState state, Realm realm, HireSoeldner action) {
  if (action.men <= 0) throw ActionException('Das geht nicht !!!');
  final cost = 50 * action.men;
  if (realm.treasury < cost) {
    throw ActionException('not enough Taler (need $cost)');
  }
  realm.treasury -= cost;
  realm.troops.add(Troop(
    name: action.name.trim().isEmpty ? 'Söldner' : action.name.trim(),
    men: action.men,
    troopClass: TroopClass.infanterie,
    quality: TroopQuality.soeldner,
    garrisonCounted: false,
    x: realm.capitalX,
    y: realm.capitalY,
  ));
  state.map.troopMarker[
      state.map.index(realm.capitalX, realm.capitalY)] = 1;
  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'soeldnerHired',
      visibility: EventVisibility.owner,
      payload: {'men': action.men},
    ),
  ];
}

List<GameEvent> applyReinforceTroop(
    GameState state, Realm realm, ReinforceTroop action, Rng rng) {
  final troop = unitAt(realm, action.unitIndex);
  if (action.men <= 0) throw ActionException('Das geht nicht !!!');
  final int cost;
  if (troop.quality == TroopQuality.soeldner) {
    cost = 50 * action.men;
  } else {
    if (realm.armySize + action.men > realm.troopCapacity) {
      throw ActionException('not enough garrison capacity');
    }
    cost = 5 * action.men;
  }
  if (realm.treasury < cost) {
    throw ActionException('not enough Taler (need $cost)');
  }
  realm.treasury -= cost;
  if (troop.garrisonCounted) quarterRecruits(realm, action.men, rng);
  troop.men += action.men;
  return const [];
}

List<GameEvent> applyMergeTroops(
    GameState state, Realm realm, MergeTroops action) {
  if (action.fromIndex == action.toIndex) {
    throw ActionException('pick two different units');
  }
  final from = unitAt(realm, action.fromIndex);
  final to = unitAt(realm, action.toIndex);
  if (from.troopClass != to.troopClass || from.quality != to.quality) {
    throw ActionException('only units of the same kind can merge');
  }
  to.men += from.men;
  realm.troops.remove(from);
  return const [];
}

List<GameEvent> applyDisbandTroop(
    GameState state, Realm realm, DisbandTroop action) {
  final troop = unitAt(realm, action.unitIndex);
  if (troop.garrisonCounted) releaseGarrison(realm, troop.men);
  realm.troops.remove(troop);
  return const [];
}

List<GameEvent> applyMoveTroop(
    GameState state, Realm realm, MoveTroop action) {
  final troop = unitAt(realm, action.unitIndex);
  final map = state.map;
  if (!map.inBounds(action.x, action.y) ||
      map.ownerAt(action.x, action.y) != realm.slot) {
    // "Sie müssen Ihre Truppen auf Ihrem Territorium stationieren!"
    throw ActionException(
        'troops must be stationed on your own territory');
  }
  if (realm.movementPoints < 1) {
    throw ActionException('no movement points left');
  }
  realm.movementPoints--;
  map.troopMarker[map.index(troop.x, troop.y)] = 0;
  troop.x = action.x;
  troop.y = action.y;
  map.troopMarker[map.index(action.x, action.y)] = 1;
  return const [];
}

List<GameEvent> applyDeclareWar(
    GameState state, Realm realm, DeclareWar action, Rng rng) {
  if (state.year < firstWarYear) {
    throw ActionException('Kriege sind erst ab dem Jahr 1010 erlaubt !');
  }
  if (realm.warThisYear) {
    throw ActionException(
        'Sie haben dieses Jahr schon einmal Krieg geführt !');
  }
  if (realm.troops.where((t) => t.men > 0).isEmpty) {
    throw ActionException('Sie haben nicht genug Truppen !');
  }
  if (state.activeWar != null) {
    throw ActionException('another war is already raging');
  }
  if (action.targetSlot == realm.slot ||
      action.targetSlot < 1 ||
      action.targetSlot > World.realmCount ||
      state.realm(action.targetSlot).isVacant) {
    throw ActionException('invalid war target');
  }
  startWar(state, realm.slot, action.targetSlot, rng);
  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'warDeclared',
      visibility: EventVisibility.public,
      participants: [realm.slot, action.targetSlot],
      payload: {'targetSlot': action.targetSlot},
    ),
  ];
}

ActiveWar _warFor(GameState state, int slot, {WarPhase? phase}) {
  final war = state.activeWar;
  if (war == null || !war.isParticipant(slot)) {
    throw ActionException('you are not at war');
  }
  if (phase != null && war.phase != phase) {
    throw ActionException('wrong war phase');
  }
  return war;
}

List<GameEvent> applyWarMove(
    GameState state, Realm realm, WarMove action, Rng rng) {
  final war = _warFor(state, realm.slot, phase: WarPhase.rounds);
  final troop = unitAt(realm, action.unitIndex);
  if (action.dx.abs() + action.dy.abs() != 1) {
    throw ActionException('move one orthogonal tile at a time');
  }
  final moves = war.movesLeft[realm.slot];
  if (moves == null ||
      action.unitIndex >= moves.length ||
      moves[action.unitIndex] < 1) {
    throw ActionException('this unit cannot move further this round');
  }
  final nx = troop.x + action.dx;
  final ny = troop.y + action.dy;
  final map = state.map;
  if (!map.inBounds(nx, ny) || map.isWaterAt(nx, ny)) {
    throw ActionException('impassable');
  }

  moves[action.unitIndex]--;
  final events = <GameEvent>[];
  final enemySlot = war.opponentOf(realm.slot);
  final enemyRealm = state.realm(enemySlot);

  // Meeting an enemy unit triggers per-tile combat (§11.3).
  final enemyUnit = enemyRealm.troops
      .where((t) => t.x == nx && t.y == ny)
      .toList();
  if (enemyUnit.isNotEmpty) {
    events.addAll(
        resolveCombat(state, realm.slot, troop, enemySlot, enemyUnit.first, rng));
    if (!realm.troops.contains(troop)) {
      _refreshMarkers(state);
      return events; // the mover was annihilated
    }
    if (enemyRealm.troops.contains(enemyUnit.first)) {
      _refreshMarkers(state);
      return events; // defender held the tile
    }
  }

  map.troopMarker[map.index(troop.x, troop.y)] = 0;
  troop.x = nx;
  troop.y = ny;
  map.troopMarker[map.index(nx, ny)] = 1;

  // Ruler capture (§11.2): a unit on the enemy capital ends the war.
  if (nx == enemyRealm.capitalX && ny == enemyRealm.capitalY) {
    endWarByCapture(state, realm.slot, rng, events);
  }
  return events;
}

void _refreshMarkers(GameState state) {
  final map = state.map;
  for (var i = 0; i < map.troopMarker.length; i++) {
    map.troopMarker[i] = 0;
  }
  for (final realm in state.realms) {
    for (final troop in realm.troops) {
      map.troopMarker[map.index(troop.x, troop.y)] = 1;
    }
  }
}

List<GameEvent> applyWarPlunder(
    GameState state, Realm realm, WarPlunder action, Rng rng) {
  final war = _warFor(state, realm.slot, phase: WarPhase.rounds);
  final map = state.map;
  if (!map.inBounds(action.x, action.y) ||
      map.buildingAt(action.x, action.y) == Building.none) {
    throw ActionException('Hier steht doch gar nichts !');
  }
  if (war.plunderedThisRound(realm.slot)) {
    throw ActionException('Sie haben diese Runde schon geplündert !');
  }
  if (map.ownerAt(action.x, action.y) == realm.slot) {
    throw ActionException('Wollen sie wirklich ihr eigenes Land plündern !');
  }
  // Your troops must have reached the tile.
  final present =
      realm.troops.any((t) => t.x == action.x && t.y == action.y);
  if (!present) {
    throw ActionException('no troops on this tile');
  }
  war.setPlunderedThisRound(realm.slot, true);
  return plunderTile(state, realm.slot, action.x, action.y, rng);
}

List<GameEvent> applyWarPeaceWish(
    GameState state, Realm realm, WarPeaceWish action) {
  final war = _warFor(state, realm.slot, phase: WarPhase.rounds);
  war.setWantsPeace(realm.slot, action.wantsPeace);
  if (!action.wantsPeace) return const [];
  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'peaceWish',
      visibility: EventVisibility.public,
      payload: const {},
    ),
  ];
}

List<GameEvent> applyWarEndRound(
    GameState state, Realm realm, WarEndRound action, Rng rng) {
  _warFor(state, realm.slot, phase: WarPhase.rounds);
  final events = <GameEvent>[];
  endWarRound(state, rng, events);
  return events;
}

List<GameEvent> applySettlementAnnex(
    GameState state, Realm realm, SettlementAnnex action) {
  final war = _warFor(state, realm.slot, phase: WarPhase.settlement);
  if (war.winnerSlot != realm.slot) {
    throw ActionException('only the winner settles the claim');
  }
  final map = state.map;
  final loserSlot = war.opponentOf(realm.slot);
  if (!map.inBounds(action.x, action.y) ||
      map.ownerAt(action.x, action.y) != loserSlot) {
    throw ActionException('Das gehört nicht Ihrem Feind !');
  }
  final value = Building.value[map.buildingAt(action.x, action.y)];
  if (value > war.remainingClaim) {
    throw ActionException('So viel steht Ihnen nicht zu !');
  }
  var borders = false;
  for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
    if (map.inBounds(action.x + dx, action.y + dy) &&
        map.ownerAt(action.x + dx, action.y + dy) == realm.slot) {
      borders = true;
      break;
    }
  }
  if (!borders) {
    throw ActionException(
        'Sie können sich nur Felder aneignen, die direkt an Ihr Land grenzen !');
  }
  final events = <GameEvent>[];
  transferTile(state, action.x, action.y, realm.slot, events);
  war.remainingClaim -= value;
  return events;
}

List<GameEvent> applySettlementFinish(
    GameState state, Realm realm, SettlementFinish action) {
  final war = _warFor(state, realm.slot, phase: WarPhase.settlement);
  if (war.winnerSlot != realm.slot) {
    throw ActionException('only the winner settles the claim');
  }
  final events = <GameEvent>[];
  finishSettlement(state, events);
  return events;
}

List<GameEvent> applySpyMission(
    GameState state, Realm realm, SpyMission action, Rng rng) {
  if (action.agents < 1 || action.agents > 30) {
    throw ActionException('So viele Spione würden zu sehr auffallen');
  }
  if (action.targetSlot == realm.slot ||
      action.targetSlot < 1 ||
      action.targetSlot > World.realmCount) {
    throw ActionException('invalid target');
  }
  final cost = action.agents *
      (action.spyKind == SpyKind.economy ? economySpyCost : militarySpyCost);
  if (realm.treasury < cost) {
    throw ActionException('not enough Taler (need $cost)');
  }
  realm.treasury -= cost;
  final target = state.realm(action.targetSlot);
  return action.spyKind == SpyKind.economy
      ? runEconomyMission(state, realm, target, action.agents, rng)
      : runMilitaryMission(state, realm, target, action.agents, rng);
}

List<GameEvent> applyOrderAssassination(
    GameState state, Realm realm, OrderAssassination action) {
  if (action.agents < 1 || action.agents > 30) {
    throw ActionException('So viele Spione würden zu sehr auffallen');
  }
  if (action.targetSlot == realm.slot ||
      action.targetSlot < 1 ||
      action.targetSlot > World.realmCount ||
      state.realm(action.targetSlot).isVacant) {
    throw ActionException('invalid target');
  }
  final cost = action.agents * assassinCost;
  if (realm.treasury < cost) {
    throw ActionException('not enough Taler (need $cost)');
  }
  realm.treasury -= cost;
  queueAssassination(state, realm.slot, action.targetSlot, action.agents);
  return [
    GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'assassinsDispatched',
      visibility: EventVisibility.owner,
      payload: {'targetSlot': action.targetSlot, 'agents': action.agents},
    ),
  ];
}

List<GameEvent> applyAdjustGuards(
    GameState state, Realm realm, AdjustGuards action) {
  if (action.delta == 0) throw ActionException('Das geht nicht !!!');
  if (action.delta > 0) {
    if (realm.guardLevel + action.delta > guardCap) {
      throw ActionException(
          'Das ist keine Spionageabwehr, sondern eine Armee !!!');
    }
    final cost = action.delta * guardCost;
    if (realm.treasury < cost) {
      throw ActionException('not enough Taler (need $cost)');
    }
    realm.treasury -= cost;
    realm.guardLevel += action.delta;
  } else {
    if (realm.guardLevel + action.delta < 0) {
      throw ActionException('you do not have that many guards');
    }
    realm.guardLevel += action.delta; // dismissing is free
  }
  return const [];
}
