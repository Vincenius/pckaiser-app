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
import '../state/dynasty.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/realm.dart';
import '../state/troop.dart';
import '../state/war.dart';
import 'player_action.dart';

Troop unitAt(Realm realm, int index) {
  if (index < 0 || index >= realm.troops.length) {
    throw ActionException('Diese Truppe gibt es nicht !');
  }
  return realm.troops[index];
}

List<GameEvent> applyRecruitTroops(
    GameState state, Realm realm, RecruitTroops action, Rng rng) {
  _requireNotAtWarV2(state, realm);
  if (action.men <= 0) throw ActionException('Das geht nicht !!!');
  if (action.troopClass < TroopClass.infanterie ||
      action.troopClass > TroopClass.artillerie) {
    throw ActionException('Unbekannte Truppengattung !');
  }
  if (realm.armySize + action.men > realm.troopCapacity) {
    throw ActionException('Nicht genügend Quartiere in deinen Orten !');
  }
  final cost = 5 * action.men + classSurcharge(action.troopClass);
  if (realm.treasury < cost) {
    throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
  }
  final (px, py) = _stationAt(state, realm, action.x, action.y);
  realm.treasury -= cost;
  quarterRecruits(realm, action.men, rng);
  realm.troops.add(Troop(
    name: action.name.trim().isEmpty ? 'Rekruten' : action.name.trim(),
    men: action.men,
    troopClass: action.troopClass,
    quality: TroopQuality.regular,
    garrisonCounted: true,
    x: px,
    y: py,
  ));
  state.map.troopMarker[state.map.index(px, py)] = 1;
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

/// Station point for a new unit: the requested own tile, or the capital.
(int, int) _stationAt(GameState state, Realm realm, int? x, int? y) {
  if (x == null || y == null) return (realm.capitalX, realm.capitalY);
  if (!state.map.inBounds(x, y) || state.map.ownerAt(x, y) != realm.slot) {
    // Original: "Sie müssen Ihre Truppen auf Ihrem Territorium stationieren!"
    throw ActionException(
        'Du musst deine Truppen auf deinem Territorium stationieren !');
  }
  return (x, y);
}

List<GameEvent> applyHireSoeldner(
    GameState state, Realm realm, HireSoeldner action) {
  _requireNotAtWarV2(state, realm);
  if (action.men <= 0) throw ActionException('Das geht nicht !!!');
  final cost = 50 * action.men;
  if (realm.treasury < cost) {
    throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
  }
  final (px, py) = _stationAt(state, realm, action.x, action.y);
  realm.treasury -= cost;
  realm.troops.add(Troop(
    name: action.name.trim().isEmpty ? 'Söldner' : action.name.trim(),
    men: action.men,
    troopClass: TroopClass.infanterie,
    quality: TroopQuality.soeldner,
    garrisonCounted: false,
    x: px,
    y: py,
  ));
  state.map.troopMarker[state.map.index(px, py)] = 1;
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
  _requireNotAtWarV2(state, realm);
  final troop = unitAt(realm, action.unitIndex);
  if (action.men <= 0) throw ActionException('Das geht nicht !!!');
  final int cost;
  if (troop.quality == TroopQuality.soeldner) {
    cost = 50 * action.men;
  } else {
    if (realm.armySize + action.men > realm.troopCapacity) {
      throw ActionException('Nicht genügend Quartiere in deinen Orten !');
    }
    cost = 5 * action.men;
  }
  if (realm.treasury < cost) {
    throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
  }
  realm.treasury -= cost;
  if (troop.garrisonCounted) quarterRecruits(realm, action.men, rng);
  troop.men += action.men;
  return const [];
}

/// "Truppe ausbilden" — drill (§10.2, rules v7): the traced original
/// training (`proc_00A316`: cost = men × 5, quality counter +1). Regulars
/// only, quality capped at [Troop.drillCap] `[DESIGNED]`. Pre-v7 games
/// keep playing without it; v7 limited it to once per unit per turn,
/// since v8 a unit drills as often as the treasury allows.
List<GameEvent> applyDrillTroop(
    GameState state, Realm realm, DrillTroop action) {
  if (state.rulesVersion < 7) {
    throw ActionException('Das geht in diesem Spielstand noch nicht !');
  }
  _requireNotAtWar(state, realm);
  final troop = unitAt(realm, action.unitIndex);
  // Söldner (and event units) are not garrison-counted — only the realm's
  // own regulars drill, whatever quality they have reached.
  if (!troop.garrisonCounted) {
    throw ActionException('Nur reguläre Truppen lassen sich ausbilden !');
  }
  if (troop.quality >= Troop.drillCap) {
    throw ActionException('Diese Truppe ist bereits voll ausgebildet !');
  }
  if (state.rulesVersion < 8 && troop.drilledThisTurn) {
    throw ActionException(
        'Diese Truppe wurde in dieser Runde schon ausgebildet !');
  }
  final cost = 5 * troop.men;
  if (realm.treasury < cost) {
    throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
  }
  realm.treasury -= cost;
  troop.quality++;
  troop.drilledThisTurn = true;
  return const [];
}

/// "Truppe umrüsten" (rules v5): retrain a regular unit to a new
/// class for 5 T/man plus the class surcharge. Pre-v5 games keep playing
/// without it (new capability = balance change).
List<GameEvent> applyTrainTroop(
    GameState state, Realm realm, TrainTroop action) {
  if (state.rulesVersion < 5) {
    throw ActionException('Das geht in diesem Spielstand noch nicht !');
  }
  _requireNotAtWar(state, realm);
  final troop = unitAt(realm, action.unitIndex);
  // Garrison-counted = the realm's own regulars (drilled quality stays
  // retrainable under v7); Söldner/event units are excluded.
  if (!troop.garrisonCounted) {
    throw ActionException('Nur reguläre Truppen lassen sich ausbilden !');
  }
  if (action.troopClass < TroopClass.infanterie ||
      action.troopClass > TroopClass.artillerie) {
    throw ActionException('Unbekannte Truppengattung !');
  }
  if (action.troopClass == troop.troopClass) {
    throw ActionException('Diese Ausbildung hat die Truppe schon !');
  }
  final cost = 5 * troop.men + classSurcharge(action.troopClass);
  if (realm.treasury < cost) {
    throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
  }
  realm.treasury -= cost;
  troop.troopClass = action.troopClass;
  return const [];
}

/// Renames a unit. Free, but forbidden at war: the war's snapshots and
/// the post-war troop return match units BY NAME.
List<GameEvent> applyRenameTroop(
    GameState state, Realm realm, RenameTroop action) {
  _requireNotAtWar(state, realm);
  final troop = unitAt(realm, action.unitIndex);
  final name = action.name.trim();
  if (name.isEmpty) {
    throw ActionException('Die Truppe braucht einen Namen !');
  }
  troop.name = name.length > 20 ? name.substring(0, 20) : name;
  return const [];
}

/// Merging/disbanding reshapes the troop list, which the active war's
/// `movesLeft` and snapshots are keyed to — forbidden while at war.
void _requireNotAtWar(GameState state, Realm realm) {
  final war = state.activeWar;
  if (war != null && war.isParticipant(realm.slot)) {
    throw ActionException('Nicht mitten im Krieg !');
  }
}

/// Rules v2 widens the at-war gate to recruiting, hiring, reinforcing and
/// peacetime troop moves: new units desync the war's `movesLeft`/snapshot
/// lists until the next round roll, and a normal move would teleport a
/// unit past the war movement rules for one movement point.
void _requireNotAtWarV2(GameState state, Realm realm) {
  if (state.rulesVersion >= 2) _requireNotAtWar(state, realm);
}

List<GameEvent> applyMergeTroops(
    GameState state, Realm realm, MergeTroops action) {
  _requireNotAtWar(state, realm);
  if (action.fromIndex == action.toIndex) {
    throw ActionException('Wähle zwei verschiedene Truppen !');
  }
  final from = unitAt(realm, action.fromIndex);
  final to = unitAt(realm, action.toIndex);
  if (from.troopClass != to.troopClass || from.quality != to.quality) {
    throw ActionException('Nur gleichartige Truppen können vereinigt werden !');
  }
  to.men += from.men;
  realm.troops.remove(from);
  _refreshMarkers(state); // the absorbed unit's marker must not linger
  return const [];
}

List<GameEvent> applyDisbandTroop(
    GameState state, Realm realm, DisbandTroop action) {
  _requireNotAtWar(state, realm);
  final troop = unitAt(realm, action.unitIndex);
  if (troop.garrisonCounted) releaseGarrison(realm, troop.men);
  realm.troops.remove(troop);
  _refreshMarkers(state); // the disbanded unit's marker must not linger
  return const [];
}

List<GameEvent> applyMoveTroop(
    GameState state, Realm realm, MoveTroop action) {
  _requireNotAtWarV2(state, realm);
  final troop = unitAt(realm, action.unitIndex);
  final map = state.map;
  if (!map.inBounds(action.x, action.y) ||
      map.ownerAt(action.x, action.y) != realm.slot) {
    // Original: "Sie müssen Ihre Truppen auf Ihrem Territorium stationieren!"
    throw ActionException(
        'Du musst deine Truppen auf deinem Territorium stationieren !');
  }
  // Rules v3: relocating troops is free — only building consumes Züge.
  if (state.rulesVersion < 3) {
    if (realm.movementPoints < 1) {
      throw ActionException('Du hast keine Züge mehr !');
    }
    realm.movementPoints--;
  }
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
        'Du hast dieses Jahr schon einmal Krieg geführt !');
  }
  if (realm.troops.where((t) => t.men > 0).isEmpty) {
    throw ActionException('Du hast nicht genug Truppen !');
  }
  if (state.activeWar != null) {
    throw ActionException('Es tobt bereits ein anderer Krieg !');
  }
  if (action.targetSlot == realm.slot ||
      action.targetSlot < 1 ||
      action.targetSlot > World.realmCount ||
      state.realm(action.targetSlot).isVacant) {
    throw ActionException('Ungültiges Kriegsziel !');
  }
  // [DEVIATION] No war against a slot your own ruler already holds
  // (ruler aliasing, §19) — merging is the intended path.
  if (state.realm(action.targetSlot).rulerId == realm.rulerId) {
    throw ActionException('Dieses Reich gehört bereits deinem Herrscher !');
  }
  // V1 limitation: human-vs-human wars wait for the online war clock
  // (ARCHITECTURE.md "Human-vs-human wars online") — the war UI can only
  // seat one human side, so such a war would deadlock the game.
  if (state.dynasty(realm.slot).status == DynastyStatus.human &&
      state.dynasty(action.targetSlot).status == DynastyStatus.human) {
    throw ActionException(
        'Krieg gegen menschliche Mitspieler ist noch nicht möglich !');
  }
  // [DEVIATION] Wars only against realms with a shared border.
  if (!state.map.realmNeighbors(realm.slot).contains(action.targetSlot)) {
    throw ActionException('Du hast keine gemeinsame Grenze !');
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
    throw ActionException('Du führst keinen Krieg !');
  }
  if (phase != null && war.phase != phase) {
    throw ActionException('Falsche Kriegsphase !');
  }
  return war;
}

List<GameEvent> applyWarMove(
    GameState state, Realm realm, WarMove action, Rng rng) {
  final war = _warFor(state, realm.slot, phase: WarPhase.rounds);
  final troop = unitAt(realm, action.unitIndex);
  if (action.dx.abs() + action.dy.abs() != 1) {
    throw ActionException('Nur ein Feld pro Zug — gerade, nicht diagonal !');
  }
  final moves = war.movesLeft[realm.slot];
  if (moves == null ||
      action.unitIndex >= moves.length ||
      moves[action.unitIndex] < 1) {
    throw ActionException('Diese Truppe kann in dieser Runde nicht weiter ziehen !');
  }
  final nx = troop.x + action.dx;
  final ny = troop.y + action.dy;
  final map = state.map;
  if (!map.inBounds(nx, ny) || map.isWaterAt(nx, ny)) {
    throw ActionException('Unpassierbar !');
  }

  moves[action.unitIndex]--;
  final events = <GameEvent>[];
  final enemySlot = war.opponentOf(realm.slot);
  final enemyRealm = state.realm(enemySlot);

  // Meeting an enemy unit triggers per-tile combat (§11.3). Rules v4: a
  // stack of enemy units is fought one after another — earlier rules
  // fought only the first and then co-located with the survivors.
  final defenders =
      enemyRealm.troops.where((t) => t.x == nx && t.y == ny).toList();
  for (final enemyUnit
      in state.rulesVersion >= 4 ? defenders : defenders.take(1)) {
    events.addAll(
        resolveCombat(state, realm.slot, troop, enemySlot, enemyUnit, rng));
    if (!realm.troops.contains(troop)) {
      _refreshMarkers(state);
      return events; // the mover was annihilated
    }
    if (enemyRealm.troops.contains(enemyUnit)) {
      _refreshMarkers(state);
      return events; // defender held the tile
    }
  }

  map.troopMarker[map.index(troop.x, troop.y)] = 0;
  troop.x = nx;
  troop.y = ny;
  map.troopMarker[map.index(nx, ny)] = 1;

  // Ruler capture (§11.2): a unit on the enemy capital ends the war.
  // Rules v4: only while the capital tile is still enemy-owned — stale
  // capital coordinates (the tile was conquered or seized in an earlier
  // war/bankruptcy and the seat never relocated) no longer grant an
  // instant capture by stepping onto a tile the attacker may even own.
  // Rules v9: stepping onto the capital no longer ends the war on the
  // spot — the occupier must HOLD the tile until the war round ends
  // (`endWarRound` resolves the capture, opening the claim settlement).
  if (state.rulesVersion < 9 &&
      nx == enemyRealm.capitalX &&
      ny == enemyRealm.capitalY &&
      (state.rulesVersion < 4 || map.ownerAt(nx, ny) == enemySlot)) {
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
    throw ActionException('Du hast diese Runde schon geplündert !');
  }
  if (map.ownerAt(action.x, action.y) == realm.slot) {
    throw ActionException('Wollen sie wirklich ihr eigenes Land plündern !');
  }
  // Rules v2: plunder only hits the war opponent — v1 let a unit sack any
  // foreign realm it could walk to during someone else's war.
  if (state.rulesVersion >= 2 &&
      map.ownerAt(action.x, action.y) != war.opponentOf(realm.slot)) {
    throw ActionException('Das gehört nicht deinem Kriegsgegner !');
  }
  // Your troops must have reached the tile.
  final present =
      realm.troops.any((t) => t.x == action.x && t.y == action.y);
  if (!present) {
    throw ActionException('Keine Truppen auf diesem Feld !');
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
    throw ActionException('Nur der Sieger stellt Ansprüche !');
  }
  final map = state.map;
  final loserSlot = war.opponentOf(realm.slot);
  if (!map.inBounds(action.x, action.y) ||
      map.ownerAt(action.x, action.y) != loserSlot) {
    throw ActionException('Das gehört nicht deinem Feind !');
  }
  final value = settlementTileValue(state, map.buildingAt(action.x, action.y));
  if (value > war.remainingClaim) {
    throw ActionException('So viel steht dir nicht zu !');
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
        'Du kannst dir nur Felder aneignen, die direkt an dein Land grenzen !');
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
    throw ActionException('Nur der Sieger stellt Ansprüche !');
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
      action.targetSlot > World.realmCount ||
      state.realm(action.targetSlot).isVacant) {
    throw ActionException('Ungültiges Ziel !');
  }
  final cost = action.agents *
      (action.spyKind == SpyKind.economy ? economySpyCost : militarySpyCost);
  if (realm.treasury < cost) {
    throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
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
    throw ActionException('Ungültiges Ziel !');
  }
  final cost = action.agents * assassinCost;
  if (realm.treasury < cost) {
    throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
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
      throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
    }
    realm.treasury -= cost;
    realm.guardLevel += action.delta;
  } else {
    if (realm.guardLevel + action.delta < 0) {
      throw ActionException('So viele Wachen hast du nicht !');
    }
    realm.guardLevel += action.delta; // dismissing is free
  }
  return const [];
}
