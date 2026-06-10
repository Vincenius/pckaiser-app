import 'dart:math' as math;

import '../rng/rng.dart';
import '../state/constants.dart';
import '../state/dynasty.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/pending_decision.dart';
import '../state/person.dart';
import '../state/realm.dart';
import '../state/town.dart';
import '../state/troop.dart';
import '../state/war.dart';
import 'dynasty.dart' as dyn;
import 'movement.dart';
import 'troops.dart';

/// §11.1: starts a war. Prunes empty units, snapshots positions, rolls the
/// first round's movement allowance.
ActiveWar startWar(GameState state, int attackerSlot, int defenderSlot,
    Rng rng) {
  for (final slot in [attackerSlot, defenderSlot]) {
    final realm = state.realm(slot);
    realm.troops.removeWhere((t) => t.men <= 0);
  }
  final war = ActiveWar(
    attackerSlot: attackerSlot,
    defenderSlot: defenderSlot,
  );
  for (final slot in [attackerSlot, defenderSlot]) {
    final realm = state.realm(slot);
    war.snapshots[slot] = [
      for (final t in realm.troops)
        UnitSnapshot(name: t.name, x: t.x, y: t.y),
    ];
  }
  _rollWarMoves(state, war, rng);
  state.activeWar = war;
  state.realm(attackerSlot).warThisYear = true;
  return war;
}

/// `[DESIGNED]` war-round movement allowance (§11.2 / §27): each unit gets
/// the owner's normal movement roll per war round.
void _rollWarMoves(GameState state, ActiveWar war, Rng rng) {
  for (final slot in [war.attackerSlot, war.defenderSlot]) {
    final realm = state.realm(slot);
    war.movesLeft[slot] = [
      for (final _ in realm.troops)
        rollMovementPoints(realm.titleClass, rng),
    ];
  }
}

/// §11.3 per-tile combat between two opposing units. Returns the events.
/// One `RandomReal` roll per encounter; def = 0 → zero casualties.
List<GameEvent> resolveCombat(GameState state, int slotA, Troop a,
    int slotB, Troop b, Rng rng) {
  int defense(Troop t) {
    var def = 0;
    if (state.map.terrainAt(t.x, t.y) == Terrain.berg) def += 1;
    def += switch (state.map.buildingAt(t.x, t.y)) {
      Building.dorf || Building.palast || Building.hafen => 1,
      Building.markt || Building.stadt => 2,
      Building.burg => 3,
      _ => 0,
    };
    return def;
  }

  final r = rng.nextReal() / 2 * 0.2;
  final powerA = (a.men * (3 * a.troopClass + a.quality) / 10).floor();
  final powerB = (b.men * (3 * b.troopClass + b.quality) / 10).floor();
  var lossesA = math.min(a.men, (powerB * defense(a) * 0.2 * r).round());
  var lossesB = math.min(b.men, (powerA * defense(b) * 0.2 * r).round());

  if (lossesA == a.men && lossesB == b.men) {
    // Simultaneous annihilation: random(2) picks one side to keep 1 man.
    if (rng.nextInt(2) == 0) {
      lossesA = a.men - 1;
    } else {
      lossesB = b.men - 1;
    }
  }

  _applyLosses(state.realm(slotA), a, lossesA);
  _applyLosses(state.realm(slotB), b, lossesB);

  return [
    GameEvent(
      year: state.year,
      slot: slotA,
      type: 'battle',
      visibility: EventVisibility.public,
      payload: {
        'attackerUnit': a.name,
        'defenderUnit': b.name,
        'attackerLosses': lossesA,
        'defenderLosses': lossesB,
        'x': b.x,
        'y': b.y,
      },
    ),
  ];
}

void _applyLosses(Realm realm, Troop troop, int losses) {
  if (losses <= 0) return;
  troop.men -= losses;
  if (troop.garrisonCounted) releaseGarrison(realm, losses);
  if (troop.men <= 0) {
    realm.troops.remove(troop);
  }
}

/// §11.4 conquest transfer: the tile changes owner; the winner also takes
/// a treasury and harvest share, doubled on the loser's capital. Town
/// tiles move their town object between the realms.
void transferTile(GameState state, int x, int y, int winnerSlot,
    List<GameEvent> events) {
  final map = state.map;
  final loserSlot = map.ownerAt(x, y);
  if (loserSlot == World.niemand || loserSlot == winnerSlot) return;
  final winner = state.realm(winnerSlot);
  final loser = state.realm(loserSlot);
  final building = map.buildingAt(x, y);

  // Treasury/harvest shares (T1 by building 0..7, T2 by building 0..8).
  const t1 = [0, 0, 1, 2, 3, 5, 6, 3];
  const t2 = [0, 0, 1, 2, 3, 0, 0, 2, 6];
  var sum1 = 0;
  var sum2 = 0;
  for (var i = 0; i < map.terrain.length; i++) {
    if (map.owner[i] != loserSlot) continue;
    final b = map.building[i];
    if (b < t1.length) sum1 += t1[b];
    sum2 += t2[b];
  }
  final isCapital = loser.capitalX == x && loser.capitalY == y;
  final factor = isCapital ? 2 : 1;
  if (sum1 > 0 && building < t1.length) {
    final share = loser.treasury * t1[building] * factor ~/ sum1;
    loser.treasury -= share;
    winner.treasury += share;
  }
  if (sum2 > 0) {
    final grainShare =
        loser.grainHarvest * t2[building] * factor ~/ sum2;
    final cattleShare =
        loser.livestockHarvest * t2[building] * factor ~/ sum2;
    loser.grainHarvest -= grainShare;
    loser.livestockHarvest -= cattleShare;
    winner.grainHarvest += grainShare;
    winner.livestockHarvest += cattleShare;
  }

  map.owner[map.index(x, y)] = winnerSlot;
  loser.tileCount[building]--;
  winner.tileCount[building]++;

  final townIndex =
      loser.towns.indexWhere((t) => t.x == x && t.y == y);
  if (townIndex >= 0) {
    final town = loser.towns.removeAt(townIndex);
    loser.population -= town.population;
    loser.troopCapacity -= town.troopCapacity;
    loser.armySize = math.max(0, loser.armySize - town.garrison);
    town.garrison = 0; // the defenders are gone with the realm
    winner.towns.add(town);
    winner.population += town.population;
    winner.troopCapacity += town.troopCapacity;
  }

  events.add(GameEvent(
    year: state.year,
    slot: winnerSlot,
    type: 'tileConquered',
    visibility: EventVisibility.public,
    payload: {'x': x, 'y': y, 'building': building, 'from': loserSlot},
  ));
}

/// Ruler capture (§11.2): the capturer takes over the loser's entire
/// realm, then post-war coercion (§12) — the ONLY path that triggers it.
void endWarByCapture(GameState state, int captorSlot, Rng rng,
    List<GameEvent> events) {
  final war = state.activeWar!;
  final loserSlot = war.opponentOf(captorSlot);
  final captor = state.realm(captorSlot);
  final loserRealm = state.realm(loserSlot);
  final capturedRuler = state.person(loserRealm.rulerId);

  events.add(GameEvent(
    year: state.year,
    slot: captorSlot,
    type: 'rulerCaptured',
    visibility: EventVisibility.public,
    payload: {'loserSlot': loserSlot, 'ruler': capturedRuler?.name},
  ));

  loserRealm.rulerId = captor.rulerId; // slot pointer overwritten (§19)
  _returnTroops(state, war, events);
  state.activeWar = null;

  if (capturedRuler != null) {
    runCoercion(state, captorSlot, capturedRuler, rng, events);
  }
}

/// §12 post-war coercion, checked in order; first applicable option fires.
/// AI victors auto-execute; a human victor gets a `coercion` decision
/// (default: apply). A human loser facing convert-or-die gets their own
/// decision; an AI loser flips a coin.
void runCoercion(GameState state, int victorSlot, Person capturedRuler,
    Rng rng, List<GameEvent> events) {
  final victorRealm = state.realm(victorSlot);
  final victor = state.person(victorRealm.rulerId);
  if (victor == null) return;
  final victorReligion = state.dynasty(victor.dynasty).religion;
  final loserDynasty = state.dynasty(capturedRuler.dynasty);

  final String option;
  if (loserDynasty.religion != victorReligion) {
    option = 'convertOrDie';
  } else if (victor.isMale &&
      victor.spouseId == null &&
      capturedRuler.spouseId == null &&
      victor.gender != capturedRuler.gender &&
      victor.age >= 14 &&
      capturedRuler.age >= 14 &&
      (victor.age - capturedRuler.age).abs() < 10) {
    option = 'forcedMarriage';
  } else if (state.kaiserId == capturedRuler.id) {
    option = 'abdication';
  } else if (state.kurfuerstenIds.contains(capturedRuler.id)) {
    option = 'stripSeat';
  } else {
    return;
  }

  if (state.dynasty(victor.dynasty).status == DynastyStatus.human) {
    state.pendingDecisions.add(PendingDecision(
      id: 'coercion-${capturedRuler.id}-${state.year}',
      type: 'coercion',
      decidingSlot: victor.dynasty,
      payload: {
        'option': option,
        'victorId': victor.id,
        'capturedRulerId': capturedRuler.id,
      },
    ));
    return;
  }
  applyCoercion(state, option, victor, capturedRuler, rng, events);
}

/// Executes a coercion option (§12).
void applyCoercion(GameState state, String option, Person victor,
    Person capturedRuler, Rng rng, List<GameEvent> events) {
  switch (option) {
    case 'convertOrDie':
      final loserDynasty = state.dynasty(capturedRuler.dynasty);
      if (loserDynasty.status == DynastyStatus.human) {
        state.pendingDecisions.add(PendingDecision(
          id: 'convert-${capturedRuler.id}-${state.year}',
          type: 'convertOrDie',
          decidingSlot: capturedRuler.dynasty,
          payload: {
            'capturedRulerId': capturedRuler.id,
            'religion': state.dynasty(victor.dynasty).religion,
          },
        ));
        return;
      }
      applyConvertOrDie(state, capturedRuler,
          state.dynasty(victor.dynasty).religion, rng.nextInt(2) == 0, rng,
          events);

    case 'forcedMarriage':
      dyn.marry(state, victor, capturedRuler, events);
      events.add(GameEvent(
        year: state.year,
        slot: victor.dynasty,
        type: 'forcedMarriage',
        visibility: EventVisibility.public,
        payload: {'victor': victor.name, 'spouse': capturedRuler.name},
      ));

    case 'abdication':
      state.kaiserId = null;
      events.add(GameEvent(
        year: state.year,
        slot: capturedRuler.dynasty,
        type: 'forcedAbdication',
        visibility: EventVisibility.public,
        payload: {'name': capturedRuler.name},
      ));

    case 'stripSeat':
      state.kurfuerstenIds.remove(capturedRuler.id);
      events.add(GameEvent(
        year: state.year,
        slot: capturedRuler.dynasty,
        type: 'kurfuerstStripped',
        visibility: EventVisibility.public,
        payload: {'name': capturedRuler.name},
      ));
  }
}

/// Resolves the captured ruler's convert-or-die answer (§12.1).
void applyConvertOrDie(GameState state, Person capturedRuler, int religion,
    bool accepts, Rng rng, List<GameEvent> events) {
  final dynasty = state.dynasty(capturedRuler.dynasty);
  if (accepts) {
    dynasty.religion = religion;
    if (religion == Religion.moslemisch) {
      for (final id in List.of(state.kurfuerstenIds)) {
        if (state.persons[id]?.dynasty == dynasty.index) {
          state.kurfuerstenIds.remove(id);
        }
      }
    }
    events.add(GameEvent(
      year: state.year,
      slot: dynasty.index,
      type: 'dynastyConverted',
      visibility: EventVisibility.public,
      payload: {'religion': religion},
    ));
  } else {
    events.add(GameEvent(
      year: state.year,
      slot: dynasty.index,
      type: 'execution',
      visibility: EventVisibility.public,
      payload: {'name': capturedRuler.name},
    ));
    dyn.handleDeath(state, capturedRuler, rng, events);
  }
}

/// Advances a war round (§11.2): applies the AI peace placeholders,
/// checks mutual peace and winter, and otherwise rolls the next round.
/// (AI unit movement arrives with Phase 5 — until then AI sides hold
/// position, which makes the traced AI peace rules fire naturally.)
void endWarRound(GameState state, Rng rng, List<GameEvent> events) {
  final war = state.activeWar;
  if (war == null || war.phase != WarPhase.rounds) return;

  // AI peace decisions (§11.2, incl. the original's dead-check quirk: an
  // AI attacker wants peace as soon as its units are back on/at their
  // pre-war spots).
  for (final slot in [war.attackerSlot, war.defenderSlot]) {
    if (state.dynasty(slot).status == DynastyStatus.human) continue;
    war.setWantsPeace(slot, _aiWantsPeace(state, war, slot));
  }

  if ((war.attackerWantsPeace && war.defenderWantsPeace) ||
      war.round >= 20) {
    if (war.round >= 20) {
      events.add(GameEvent(
        year: state.year,
        slot: 0,
        type: 'winterEndsWar',
        visibility: EventVisibility.public,
      ));
    }
    resolveWarEnd(state, rng, events);
    return;
  }

  war.round++;
  war.attackerWantsPeace = false;
  war.defenderWantsPeace = false;
  war.attackerPlunderedThisRound = false;
  war.defenderPlunderedThisRound = false;
  _rollWarMoves(state, war, rng);
}

bool _aiWantsPeace(GameState state, ActiveWar war, int slot) {
  final realm = state.realm(slot);
  final snapshots = war.snapshots[slot] ?? const [];
  var allHome = true;
  for (final troop in realm.troops) {
    final home = snapshots.any(
        (s) => s.name == troop.name && s.x == troop.x && s.y == troop.y);
    if (!home) {
      allHome = false;
      break;
    }
  }
  if (slot == war.attackerSlot) return allHome;

  // AI defender: home AND the war is decided.
  final attacker = state.realm(war.attackerSlot);
  final decided = warScore(state, war.attackerSlot) >= 1000 ||
      realm.troops.length > 2 * attacker.troops.length ||
      attacker.troops.isEmpty;
  return allHome && decided;
}

/// §11.2 war score for a side: Σ (avgStrength × unitStrength ×
/// value[occupied tile]) over its units on ENEMY tiles, +3,000 for a unit
/// on the enemy capital.
int warScore(GameState state, int slot) {
  final war = state.activeWar;
  if (war == null) return 0;
  final enemySlot = war.opponentOf(slot);
  final realm = state.realm(slot);
  final enemy = state.realm(enemySlot);
  if (realm.troops.isEmpty) return 0;

  final strengths = [for (final t in realm.troops) troopStrength(t)];
  final avg = strengths.fold(0.0, (a, b) => a + b) / strengths.length;

  var score = 0.0;
  for (var i = 0; i < realm.troops.length; i++) {
    final troop = realm.troops[i];
    if (state.map.ownerAt(troop.x, troop.y) != enemySlot) continue;
    score += avg *
        strengths[i] *
        Building.value[state.map.buildingAt(troop.x, troop.y)];
    if (troop.x == enemy.capitalX && troop.y == enemy.capitalY) {
      score += 3000;
    }
  }
  return score.round();
}

/// End-of-war resolution for peace/winter endings (§11.2): decisive
/// victory converts occupied tiles; a limited victory opens the claim
/// settlement (interactive for humans, automatic for AI).
void resolveWarEnd(GameState state, Rng rng, List<GameEvent> events) {
  final war = state.activeWar!;
  final scoreAttacker = warScore(state, war.attackerSlot);
  final scoreDefender = warScore(state, war.defenderSlot);

  if (scoreAttacker == scoreDefender) {
    events.add(GameEvent(
      year: state.year,
      slot: 0,
      type: 'warDraw',
      visibility: EventVisibility.public,
    ));
    _returnTroops(state, war, events);
    state.activeWar = null;
    return;
  }

  final winnerSlot =
      scoreAttacker > scoreDefender ? war.attackerSlot : war.defenderSlot;
  final loserSlot = war.opponentOf(winnerSlot);
  final claim = math.max(scoreAttacker, scoreDefender);
  final loser = state.realm(loserSlot);

  var loserValue = 0;
  for (var i = 0; i < state.map.terrain.length; i++) {
    if (state.map.owner[i] == loserSlot) {
      loserValue += Building.value[state.map.building[i]];
    }
  }

  events.add(GameEvent(
    year: state.year,
    slot: winnerSlot,
    type: 'warWon',
    visibility: EventVisibility.public,
    payload: {'claim': claim, 'loserSlot': loserSlot},
  ));

  if (claim >= (loserValue * 0.4).round()) {
    // Decisive: every tile occupied by a winner unit converts.
    final winner = state.realm(winnerSlot);
    for (final troop in List.of(winner.troops)) {
      if (state.map.ownerAt(troop.x, troop.y) == loserSlot) {
        transferTile(state, troop.x, troop.y, winnerSlot, events);
      }
    }
    _returnTroops(state, war, events);
    state.activeWar = null;
    _checkLandLoss(state, loser, events);
    return;
  }

  // Limited victory → claim settlement.
  war.phase = WarPhase.settlement;
  war.winnerSlot = winnerSlot;
  war.remainingClaim = claim;
  if (state.dynasty(winnerSlot).status != DynastyStatus.human) {
    autoSettleClaim(state, rng, events);
  }
}

/// §11.2 claim settlement, AI path `[APPROX]`: greedily annex affordable
/// loser tiles adjacent to own land, then take the remainder in cash.
void autoSettleClaim(GameState state, Rng rng, List<GameEvent> events) {
  final war = state.activeWar!;
  final winnerSlot = war.winnerSlot!;
  final loserSlot = war.opponentOf(winnerSlot);
  final map = state.map;

  var annexed = true;
  while (annexed && war.remainingClaim > 0) {
    annexed = false;
    for (var y = 0; y < map.height && !annexed; y++) {
      for (var x = 0; x < map.width && !annexed; x++) {
        if (map.ownerAt(x, y) != loserSlot) continue;
        final value = Building.value[map.buildingAt(x, y)];
        if (value > war.remainingClaim) continue;
        if (!_bordersTerritory(state, winnerSlot, x, y)) continue;
        transferTile(state, x, y, winnerSlot, events);
        war.remainingClaim -= value;
        annexed = true;
      }
    }
  }
  finishSettlement(state, events);
}

bool _bordersTerritory(GameState state, int slot, int x, int y) {
  for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
    if (state.map.inBounds(x + dx, y + dy) &&
        state.map.ownerAt(x + dx, y + dy) == slot) {
      return true;
    }
  }
  return false;
}

/// Ends the settlement ("F" — fertig): the unspent claim converts 1:1 into
/// Taler straight from the loser's treasury (which may go negative).
void finishSettlement(GameState state, List<GameEvent> events) {
  final war = state.activeWar!;
  final winnerSlot = war.winnerSlot!;
  final loserSlot = war.opponentOf(winnerSlot);
  if (war.remainingClaim > 0) {
    state.realm(loserSlot).treasury -= war.remainingClaim;
    state.realm(winnerSlot).treasury += war.remainingClaim;
    events.add(GameEvent(
      year: state.year,
      slot: winnerSlot,
      type: 'claimPaidOut',
      visibility: EventVisibility.public,
      payload: {'amount': war.remainingClaim, 'from': loserSlot},
    ));
  }
  _returnTroops(state, war, events);
  state.activeWar = null;
  _checkLandLoss(state, state.realm(loserSlot), events);
}

/// Afterwards every surviving unit returns to its snapshotted pre-war
/// position; emptied units are deleted (§11.2).
void _returnTroops(GameState state, ActiveWar war, List<GameEvent> events) {
  for (final slot in [war.attackerSlot, war.defenderSlot]) {
    final realm = state.realm(slot);
    realm.troops.removeWhere((t) => t.men <= 0);
    final snapshots = war.snapshots[slot] ?? const [];
    for (final troop in realm.troops) {
      final snapshot = snapshots.where((s) => s.name == troop.name);
      if (snapshot.isNotEmpty) {
        troop.x = snapshot.first.x;
        troop.y = snapshot.first.y;
      }
    }
  }
  _refreshTroopMarkers(state);
}

void _refreshTroopMarkers(GameState state) {
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

/// A ruler who lost all land loses any Kurfürst seat (§17.2).
void _checkLandLoss(GameState state, Realm loser, List<GameEvent> events) {
  final owned = loser.tileCount.fold(0, (a, b) => a + b);
  if (owned == 0 && loser.rulerId != null) {
    state.kurfuerstenIds.remove(loser.rulerId);
  }
}

/// §11.5 plunder during war rounds, once per side per round.
List<GameEvent> plunderTile(GameState state, int plundererSlot, int x,
    int y, Rng rng) {
  final map = state.map;
  final building = map.buildingAt(x, y);
  final victimSlot = map.ownerAt(x, y);
  final plunderer = state.realm(plundererSlot);
  final victim = state.realm(victimSlot);
  final events = <GameEvent>[];

  switch (building) {
    case Building.kornfeld || Building.weide:
      map.building[map.index(x, y)] = Building.none;
      map.owner[map.index(x, y)] = World.niemand;
      victim.tileCount[building]--;
    case Building.dorf || Building.markt || Building.stadt:
      final town = victim.towns.firstWhere((t) => t.x == x && t.y == y);
      final killed = rng.nextInt(town.population ~/ 2);
      final looted = rng.nextInt(town.population);
      final capacityCut =
          rng.nextInt(math.max(0, town.troopCapacity - town.garrison));
      plunderer.treasury += looted; // victim's treasury is NOT touched
      town.population -= killed;
      victim.population -= killed;
      if (capacityCut > 0) {
        town.troopCapacity -= capacityCut;
        victim.troopCapacity -= capacityCut;
      }
    case Building.burg || Building.palast || Building.hafen:
      final loot =
          victim.treasury > 0 ? rng.nextInt(victim.treasury) : 0;
      victim.treasury -= loot;
      plunderer.treasury += loot;
  }

  events.add(GameEvent(
    year: state.year,
    slot: plundererSlot,
    type: 'plunder',
    visibility: EventVisibility.public,
    payload: {'x': x, 'y': y, 'building': building, 'victim': victimSlot},
  ));
  return events;
}

/// Convenience used by tests and the (Phase 5) AI: a town object lookup.
Town? townAt(GameState state, int slot, int x, int y) {
  for (final town in state.realm(slot).towns) {
    if (town.x == x && town.y == y) return town;
  }
  return null;
}
