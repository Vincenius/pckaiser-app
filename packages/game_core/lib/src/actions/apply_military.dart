/// Handlers for the §10–§13 actions, called from `applyAction`'s
/// dispatcher. Same contract: mutate the (already copied) state, throw
/// [ActionException] on invalid input, return the emitted events.
library;

import '../rng/rng.dart';
import '../rules/espionage.dart';
import '../rules/movement.dart' show warPathStep;
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
    throw ActionException('Diese Truppe gibt es nicht !');
  }
  return realm.troops[index];
}

/// Militarism costs popularity, but never below [floor] (default
/// [militarismPopularityFloor]) — the people grumble over levies and
/// conversions, yet those routine costs can never tip a realm into the
/// §19.1 strife revolution (< 20): without the floor the AI (which
/// recruits freely) collapsed into strife 5–9× as often in the 200-year
/// sim. War declarations pass the lower [warPopularityFloor] so REPEATED
/// aggression can reach the strife line (user feedback 2026-07-06). A stat
/// already below the floor is left untouched, never raised. Returns the
/// popularity actually lost (0 when the floor swallowed the cost) so
/// callers can report it.
int militarismPopularityCost(Realm realm, int cost,
    {int floor = militarismPopularityFloor}) {
  final floored =
      realm.popularity - cost < floor ? floor : realm.popularity - cost;
  if (floored < realm.popularity) {
    final lost = realm.popularity - floored;
    realm.popularity = floored;
    return lost;
  }
  return 0;
}

/// The people resent levies — recruiting or hiring [men] costs
/// 1 + men/200 popularity.
void _levyPopularityCost(GameState state, Realm realm, int men) {
  militarismPopularityCost(realm, 1 + men ~/ 200);
}

/// Per-turn levy limit for regulars (see [levyLimit]) — Söldner exempt.
void _requireLevy(Realm realm, int men) {
  final left = levyLeft(realm);
  if (men > left) {
    throw ActionException(left <= 0
        ? 'Deine Bevölkerung gibt dieses Jahr keine weiteren Rekruten her !'
        : 'Deine Bevölkerung gibt dieses Jahr nur noch $left Rekruten her !');
  }
}

List<GameEvent> applyRecruitTroops(
    GameState state, Realm realm, RecruitTroops action, Rng rng) {
  _requireNotAtWar(state, realm);
  if (action.men <= 0) throw ActionException('Das geht nicht !!!');
  if (action.troopClass < TroopClass.infanterie ||
      action.troopClass > TroopClass.artillerie) {
    throw ActionException('Unbekannte Truppengattung !');
  }
  if (realm.armySize + action.men > realm.troopCapacity) {
    throw ActionException('Nicht genügend Quartiere in deinen Orten !');
  }
  _requireLevy(realm, action.men);
  final cost = recruitCost(action.men, action.troopClass);
  if (realm.treasury < cost) {
    throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
  }
  final (px, py) = _stationAt(state, realm, action.x, action.y);
  realm.treasury -= cost;
  realm.recruitedThisTurn += action.men;
  _levyPopularityCost(state, realm, action.men);
  quarterRecruits(realm, action.men, rng);
  final recruitName = clampName(action.name);
  realm.troops.add(Troop(
    id: state.nextUnitId++,
    name: recruitName.isEmpty ? 'Rekruten' : recruitName,
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
  _requireNotAtWar(state, realm);
  if (action.men <= 0) throw ActionException('Das geht nicht !!!');
  final cost = soeldnerCost(action.men);
  if (realm.treasury < cost) {
    throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
  }
  final (px, py) = _stationAt(state, realm, action.x, action.y);
  realm.treasury -= cost;
  _levyPopularityCost(state, realm, action.men);
  final soeldnerName = clampName(action.name);
  realm.troops.add(Troop(
    id: state.nextUnitId++,
    name: soeldnerName.isEmpty ? 'Söldner' : soeldnerName,
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
  _requireNotAtWar(state, realm);
  final troop = unitAt(realm, action.unitIndex);
  if (action.men <= 0) throw ActionException('Das geht nicht !!!');
  // Söldner ignore garrison capacity and the levy; the price split lives
  // in [reinforceCost] (keyed on garrisonCounted, never on quality — a
  // drilled regular shares the Söldner quality value).
  if (troop.garrisonCounted) {
    if (realm.armySize + action.men > realm.troopCapacity) {
      throw ActionException('Nicht genügend Quartiere in deinen Orten !');
    }
    _requireLevy(realm, action.men);
  }
  final cost = reinforceCost(troop, action.men);
  if (realm.treasury < cost) {
    throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
  }
  final oldMen = troop.men;
  realm.treasury -= cost;
  if (troop.garrisonCounted) {
    realm.recruitedThisTurn += action.men;
    quarterRecruits(realm, action.men, rng);
  }
  _levyPopularityCost(state, realm, action.men);
  troop.men += action.men;
  // New recruits dilute the trained quality toward regular (1).
  if (troop.garrisonCounted && troop.quality > TroopQuality.regular) {
    troop.quality =
        ((oldMen * troop.quality + action.men * TroopQuality.regular) /
                troop.men)
            .round()
            .clamp(TroopQuality.regular, troop.quality);
  }
  return const [];
}

/// "Truppe ausbilden" — drill (§10.2): the traced original training
/// (`proc_00A316`). Regulars only, quality capped at [Troop.drillCap].
/// `[DESIGNED]` Cost scales with current level: `5 × men × quality` — early
/// levels are cheap; higher levels require proportionally more investment.
/// Reinforcing with new recruits dilutes quality back toward regular (1).
List<GameEvent> applyDrillTroop(
    GameState state, Realm realm, DrillTroop action) {
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
  final cost = drillCost(troop);
  if (realm.treasury < cost) {
    throw ActionException('Du hast nicht genügend Taler ! ($cost benötigt)');
  }
  realm.treasury -= cost;
  troop.quality++;
  return const [];
}

/// "Truppe umrüsten": retrain a regular unit to a new class for 5 T/man
/// plus the class surcharge.
List<GameEvent> applyTrainTroop(
    GameState state, Realm realm, TrainTroop action) {
  _requireNotAtWar(state, realm);
  final troop = unitAt(realm, action.unitIndex);
  // Garrison-counted = the realm's own regulars (drilled quality stays
  // retrainable); Söldner/event units are excluded.
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
  final cost = retrainCost(troop, action.troopClass);
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
  final name = clampName(action.name);
  if (name.isEmpty) {
    throw ActionException('Die Truppe braucht einen Namen !');
  }
  troop.name = name;
  return const [];
}

/// "Verhalten im Krieg" — set a unit's autopilot stance (§ [TroopStance]).
/// Allowed mid-war on purpose: the stance only steers an UNATTENDED round's
/// resolution; it touches neither the troop list nor `movesLeft`, so it
/// never desyncs the active war's parallel lists (unlike the actions guarded
/// by [_requireNotAtWar]).
List<GameEvent> applySetTroopStance(
    GameState state, Realm realm, SetTroopStance action) {
  final troop = unitAt(realm, action.unitIndex);
  if (action.stance != TroopStance.holdPosition &&
      action.stance != TroopStance.attack) {
    throw ActionException('Unbekannte Truppenhaltung !');
  }
  troop.stance = action.stance;
  return const [];
}

/// Forbidden for a war participant: recruiting, hiring, reinforcing,
/// drilling, merging/disbanding and peacetime troop moves all reshape or
/// reposition the troop list, which the active war's `movesLeft` and
/// snapshots are keyed to — new units desync those lists until the next
/// round roll, and a normal move would teleport a unit past the war
/// movement rules for one movement point.
void _requireNotAtWar(GameState state, Realm realm) {
  final war = state.activeWar;
  if (war != null && war.isParticipant(realm.slot)) {
    throw ActionException('Nicht mitten im Krieg !');
  }
}

List<GameEvent> applyMergeTroops(
    GameState state, Realm realm, MergeTroops action) {
  _requireNotAtWar(state, realm);
  if (action.fromIndex == action.toIndex) {
    throw ActionException('Wähle zwei verschiedene Truppen !');
  }
  final from = unitAt(realm, action.fromIndex);
  final to = unitAt(realm, action.toIndex);
  if (!canMergeTroops(from, to)) {
    throw ActionException('Nur gleichartige Truppen können vereinigt werden !');
  }
  to.men += from.men;
  realm.troops.remove(from);
  state.rebuildTroopMarkers(); // the absorbed unit's marker must not linger
  return const [];
}

List<GameEvent> applyDisbandTroop(
    GameState state, Realm realm, DisbandTroop action) {
  _requireNotAtWar(state, realm);
  final troop = unitAt(realm, action.unitIndex);
  if (troop.garrisonCounted) releaseGarrison(realm, troop.men);
  realm.troops.remove(troop);
  state.rebuildTroopMarkers(); // the disbanded unit's marker must not linger
  return const [];
}

List<GameEvent> applyMoveTroop(GameState state, Realm realm, MoveTroop action) {
  _requireNotAtWar(state, realm);
  final troop = unitAt(realm, action.unitIndex);
  final map = state.map;
  if (!map.inBounds(action.x, action.y) ||
      map.ownerAt(action.x, action.y) != realm.slot) {
    // Original: "Sie müssen Ihre Truppen auf Ihrem Territorium stationieren!"
    throw ActionException(
        'Du musst deine Truppen auf deinem Territorium stationieren !');
  }
  // Relocating troops is free — only building consumes Züge.
  map.troopMarker[map.index(troop.x, troop.y)] = 0;
  troop.x = action.x;
  troop.y = action.y;
  map.troopMarker[map.index(action.x, action.y)] = 1;
  return const [];
}

/// Why [realm] cannot declare ANY war right now (§11.1 general gates), or
/// null. Shared by the DeclareWar validation, the AI's war check and the
/// client's Militär menu (which greys the button with this exact reason)
/// — the gates exist exactly once.
String? warDeclarationBlocker(GameState state, Realm realm) {
  if (state.year < state.warStartYear) {
    return 'Kriege sind erst ab dem Jahr ${state.warStartYear} erlaubt !';
  }
  if (realm.warThisYear) {
    return 'Du hast dieses Jahr schon einmal Krieg geführt !';
  }
  if (realm.troops.where((t) => t.men > 0).isEmpty) {
    return 'Du hast nicht genug Truppen !';
  }
  if (state.activeWar != null) {
    return 'Es tobt bereits ein anderer Krieg !';
  }
  return null;
}

/// Why [realm] cannot declare war on [targetSlot], or null when the
/// declaration is legal — THE full DeclareWar validation. The AI filters
/// its target picks with it, so an AI pick can never be rejected.
String? declareWarBlocker(GameState state, Realm realm, int targetSlot) {
  final general = warDeclarationBlocker(state, realm);
  if (general != null) return general;
  if (targetSlot == realm.slot ||
      targetSlot < 1 ||
      targetSlot > World.realmCount ||
      state.realm(targetSlot).isVacant) {
    return 'Ungültiges Kriegsziel !';
  }
  // [DEVIATION] No war against a slot your own ruler already holds
  // (ruler aliasing, §19) — merging is the intended path.
  if (state.realm(targetSlot).rulerId == realm.rulerId) {
    return 'Dieses Reich gehört bereits deinem Herrscher !';
  }
  // Human-vs-human wars are allowed: war input alternates between the two
  // human sides (war.actingSlot, hot-seat handoff locally, the war clock
  // online).
  // [DEVIATION] Wars only against realms with a shared border.
  if (!state.map.realmNeighbors(realm.slot).contains(targetSlot)) {
    return 'Du hast keine gemeinsame Grenze !';
  }
  return null;
}

List<GameEvent> applyDeclareWar(
    GameState state, Realm realm, DeclareWar action, Rng rng) {
  final blocker = declareWarBlocker(state, realm, action.targetSlot);
  if (blocker != null) throw ActionException(blocker);
  final events = <GameEvent>[];
  startWar(state, realm.slot, action.targetSlot, rng, events: events);
  // The people resent war, and repeated aggression compounds: the penalty
  // escalates with every war this realm started without a peace year in
  // between (−5, −10, −15, …; recentWars decays at year start) and may
  // drop popularity below the §19.1 strife line — a serial warmonger can
  // now face revolt. `[DESIGNED 2026-07-06, user feedback]`; the traced
  // original had no direct war penalty at all (§8.4), wars hurt only via
  // food satisfaction.
  militarismPopularityCost(realm, 5 * (realm.recentWars + 1),
      floor: warPopularityFloor);
  realm.recentWars++;
  events.add(GameEvent(
    year: state.year,
    slot: realm.slot,
    type: 'warDeclared',
    visibility: EventVisibility.public,
    participants: [realm.slot, action.targetSlot],
    payload: {'targetSlot': action.targetSlot},
  ));
  return events;
}

ActiveWar _warFor(GameState state, int slot, {WarPhase? phase}) {
  final war = state.activeWar;
  if (war == null || !war.isParticipant(slot)) {
    throw ActionException('Du führst keinen Krieg !');
  }
  if (phase != null && war.phase != phase) {
    throw ActionException('Falsche Kriegsphase !');
  }
  // Human-vs-human rounds run sequentially (attacker first): only the
  // acting side may issue LIVE war input. AI sides are exempt — their
  // moves are driven by the round-end orchestration, not awaited input —
  // and so is a DELEGATED human side (war.autoSlots): its units are moved
  // by the same stance autopilot, out of turn by design. (Keying this on
  // the raw dynasty status used to reject every autopilot move for a
  // delegated human side — silently, behind the AI driver's old
  // catch-and-ignore.)
  if (war.phase == WarPhase.rounds &&
      warSideIsHuman(state, war, slot) &&
      warActingSlot(state) != slot) {
    throw ActionException('Dein Gegner ist gerade am Zug !');
  }
  return war;
}

/// The §11.2 per-step passability rule, shared by [applyWarMove]'s
/// validation and [applyWarMarch]'s step planning (ONE definition — a
/// planner that used its own copy could drift and plan a rejected step):
///  - water only through an own Hafen (embark) or when already at sea
///    (manual sea steering, tile by tile);
///  - `[DESIGNED]` own, enemy and neutral unowned tiles are passable;
///    only a THIRD realm's land is off-limits during the war.
/// Returns the rejection message, or null when the step is legal.
String? warStepBlocker(
    GameState state, int slot, int enemySlot, int x, int y, int nx, int ny) {
  final map = state.map;
  if (!map.inBounds(nx, ny)) return 'Unpassierbar !';
  if (map.isWaterAt(nx, ny)) {
    final embarking =
        map.ownerAt(nx, ny) == slot && map.buildingAt(nx, ny) == Building.hafen;
    if (!embarking && !map.isWaterAt(x, y)) {
      return 'Truppen gehen nur über einen eigenen Hafen an Bord !';
    }
  }
  final tileOwner = map.ownerAt(nx, ny);
  if (tileOwner != slot &&
      tileOwner != enemySlot &&
      tileOwner != World.niemand) {
    return 'Durch fremde Reiche darf man im Krieg nicht ziehen !';
  }
  return null;
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
    throw ActionException(
        'Diese Truppe kann in dieser Runde nicht weiter ziehen !');
  }
  final nx = troop.x + action.dx;
  final ny = troop.y + action.dy;
  final map = state.map;
  final enemySlot = war.opponentOf(realm.slot);
  final stepBlocker =
      warStepBlocker(state, realm.slot, enemySlot, troop.x, troop.y, nx, ny);
  if (stepBlocker != null) {
    throw ActionException(stepBlocker);
  }

  moves[action.unitIndex]--;
  final events = <GameEvent>[];
  final enemyRealm = state.realm(enemySlot);

  // Meeting an enemy unit triggers per-tile combat (§11.3); a stack of
  // enemy units is fought one after another.
  final defenders =
      enemyRealm.troops.where((t) => t.x == nx && t.y == ny).toList();
  for (final enemyUnit in defenders) {
    events.addAll(
        resolveCombat(state, realm.slot, troop, enemySlot, enemyUnit, rng));
    if (!realm.troops.contains(troop)) {
      state.rebuildTroopMarkers();
      return events; // the mover was annihilated
    }
    if (enemyRealm.troops.contains(enemyUnit)) {
      state.rebuildTroopMarkers();
      return events; // defender held the tile
    }
  }

  map.troopMarker[map.index(troop.x, troop.y)] = 0;
  troop.x = nx;
  troop.y = ny;
  map.troopMarker[map.index(nx, ny)] = 1;

  // Ruler capture (§11.2) does NOT trigger here: stepping onto the
  // enemy capital arms the capture, but the occupier must HOLD the tile
  // through the enemy's full response round — `endWarRound` resolves it
  // and opens the claim settlement.
  return events;
}

/// One whole march (§11.2): walks the unit step by step along the shortest
/// passable LAND path toward the target — every step with the full
/// [applyWarMove] semantics (combat, capture arming) — until it arrives,
/// its round moves run out, a defender holds the tile, the unit is
/// destroyed, or the war ends. Throws only when no step is possible AT ALL
/// (no passable path, or the unit cannot move this round); once the unit
/// moved, the march simply ends where it got to. Water crossings stay
/// manual (single [WarMove] steps / [WarNavalTransport]).
///
/// The unit is tracked by OBJECT identity across the steps: combat
/// compacts the troop list, so an index (or a name — they repeat) could
/// silently come to mean a different unit mid-march. This used to live in
/// the client as a 120-line loop with name+expected-position tracking.
List<GameEvent> applyWarMarch(
    GameState state, Realm realm, WarMarch action, Rng rng) {
  final war = _warFor(state, realm.slot, phase: WarPhase.rounds);
  final troop = unitAt(realm, action.unitIndex);
  final map = state.map;
  if (!map.inBounds(action.x, action.y)) {
    throw ActionException('Das Feld liegt außerhalb der Karte !');
  }
  if (troop.x == action.x && troop.y == action.y) {
    throw ActionException('Da steht die Truppe doch schon !');
  }
  // Own land, the enemy's, and neutral unowned tiles are passable in war
  // (mirrors [applyWarMove]); only third realms block the march.
  final enemySlot = war.opponentOf(realm.slot);
  final warOwners = {realm.slot, enemySlot, World.niemand};

  final events = <GameEvent>[];
  var guard = 0;
  while (identical(state.activeWar, war) &&
      war.phase == WarPhase.rounds &&
      guard++ < 60) {
    final index = realm.troops.indexOf(troop);
    if (index < 0) break; // destroyed in a step's combat
    if (troop.x == action.x && troop.y == action.y) break; // arrived
    var step = warPathStep(map, troop.x, troop.y, action.x, action.y,
        allowedOwners: warOwners);
    if (step == null) {
      // No land path (water target, unit at sea, island shore): manual
      // straight-line legs — primary axis first, then the secondary —
      // under the same per-step §11.2 rule ([warStepBlocker]) WarMove
      // enforces, so a planned step can never be rejected.
      final remX = action.x - troop.x;
      final remY = action.y - troop.y;
      final candidates = remX.abs() >= remY.abs()
          ? [(remX.sign, 0), (0, remY.sign)]
          : [(0, remY.sign), (remX.sign, 0)];
      for (final (dx, dy) in candidates) {
        if (dx == 0 && dy == 0) continue;
        if (warStepBlocker(state, realm.slot, enemySlot, troop.x, troop.y,
                troop.x + dx, troop.y + dy) ==
            null) {
          step = (dx, dy);
          break;
        }
      }
    }
    if (step == null) {
      if (events.isEmpty) {
        throw ActionException('Unpassierbar !');
      }
      break; // combat reshaped the situation — stop where we stand
    }
    final beforeX = troop.x;
    final beforeY = troop.y;
    try {
      events.addAll(applyWarMove(
          state,
          realm,
          WarMove(
              slot: action.slot, unitIndex: index, dx: step.$1, dy: step.$2),
          rng));
    } on ActionException {
      // Out of moves for this round (or the step became illegal): a march
      // that never moved surfaces the reason, a partial march just ends.
      if (events.isEmpty) rethrow;
      break;
    }
    if (realm.troops.contains(troop) &&
        troop.x == beforeX &&
        troop.y == beforeY) {
      break; // combat: the defender held the tile
    }
  }
  return events;
}

/// Seetransport im Krieg: embark a unit standing next to an own Hafen and
/// ship it to a sea-connected coastal tile. The destination may be own,
/// enemy or neutral coast — an **amphibious landing** on enemy coast fights
/// any defenders there (§11.3), exactly like a land step onto the tile; a
/// repelled landing leaves the unit at its embark coast. A third realm's
/// coast is off-limits, like the overland march. The voyage spends the
/// unit's whole round.
List<GameEvent> applyWarNavalTransport(
    GameState state, Realm realm, WarNavalTransport action, Rng rng) {
  final war = _warFor(state, realm.slot, phase: WarPhase.rounds);
  final troop = unitAt(realm, action.unitIndex);
  final moves = war.movesLeft[realm.slot];
  if (moves == null ||
      action.unitIndex >= moves.length ||
      moves[action.unitIndex] < 1) {
    throw ActionException(
        'Diese Truppe kann in dieser Runde nicht weiter ziehen !');
  }
  final map = state.map;
  if (!map.canNavalTransport(
      realm.slot, troop.x, troop.y, action.x, action.y)) {
    throw ActionException(
        'Keine Seeverbindung von einem eigenen Hafen zu diesem Ziel !');
  }
  final enemySlot = war.opponentOf(realm.slot);
  final tileOwner = map.ownerAt(action.x, action.y);
  if (tileOwner != realm.slot &&
      tileOwner != enemySlot &&
      tileOwner != World.niemand) {
    throw ActionException(
        'Du kannst nur an eigener, feindlicher oder neutraler Küste landen !');
  }
  // A sea voyage spends the unit's whole round, success or not.
  moves[action.unitIndex] = 0;
  final events = <GameEvent>[];
  final enemyRealm = state.realm(enemySlot);

  // Contested landing: fight the defenders stacked on the target tile.
  final defenders = enemyRealm.troops
      .where((t) => t.x == action.x && t.y == action.y)
      .toList();
  for (final enemyUnit in defenders) {
    events.addAll(
        resolveCombat(state, realm.slot, troop, enemySlot, enemyUnit, rng));
    if (!realm.troops.contains(troop)) {
      state.rebuildTroopMarkers();
      return events; // the landing force was annihilated at sea/shore
    }
    if (enemyRealm.troops.contains(enemyUnit)) {
      state.rebuildTroopMarkers();
      return events; // landing repelled — the unit stays at its embark coast
    }
  }

  map.troopMarker[map.index(troop.x, troop.y)] = 0;
  troop.x = action.x;
  troop.y = action.y;
  map.troopMarker[map.index(action.x, action.y)] = 1;
  // Like applyWarMove, landing on the enemy capital only ARMS the capture;
  // endWarRound resolves it if the unit holds the tile through the round.
  return events;
}

List<GameEvent> applyWarPlunder(
    GameState state, Realm realm, WarPlunder action, Rng rng) {
  final war = _warFor(state, realm.slot, phase: WarPhase.rounds);
  final map = state.map;
  if (!map.inBounds(action.x, action.y) ||
      map.buildingAt(action.x, action.y) == Building.none) {
    throw ActionException('Hier steht doch gar nichts !');
  }
  if (map.ownerAt(action.x, action.y) == realm.slot) {
    throw ActionException('Wollen sie wirklich ihr eigenes Land plündern !');
  }
  // Plunder only hits the war opponent — not any foreign realm a unit
  // could walk to during someone else's war.
  if (map.ownerAt(action.x, action.y) != war.opponentOf(realm.slot)) {
    throw ActionException('Das gehört nicht deinem Kriegsgegner !');
  }
  // Your troops must have reached the tile. §11.5: every ARMY plunders
  // once per war round — one of the tile's not-yet-spent units carries
  // this plunder.
  final unitsHere =
      realm.troops.where((t) => t.x == action.x && t.y == action.y).toList();
  if (unitsHere.isEmpty) {
    throw ActionException('Keine Truppen auf diesem Feld !');
  }
  Troop? unit;
  for (final t in unitsHere) {
    if (!t.plunderedThisRound) {
      unit = t;
      break;
    }
  }
  if (unit == null) {
    throw ActionException('Diese Armee hat diese Runde schon geplündert !');
  }
  unit.plunderedThisRound = true;
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

/// WARNING for drivers: this raw dispatch advances the round WITHOUT the
/// AI sides' war movement (`runAiWarMovement` lives in the ai/ layer, which
/// imports this one). Real drivers must call `endWarRoundFor` instead —
/// the local session and the server both do; only tests use this path.
List<GameEvent> applyWarEndRound(
    GameState state, Realm realm, WarEndRound action, Rng rng) {
  _warFor(state, realm.slot, phase: WarPhase.rounds);
  final events = <GameEvent>[];
  // Human-vs-human: the attacker's round end only hands the input to the
  // defender; the defender's round end advances the round for real.
  if (!handWarRoundOver(state, realm.slot)) {
    endWarRound(state, rng, events);
  }
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
  if (!map.bordersSlot(action.x, action.y, realm.slot)) {
    throw ActionException(
        'Du kannst dir nur Felder aneignen, die direkt an dein Land grenzen !');
  }
  final events = <GameEvent>[];
  transferTile(state, action.x, action.y, realm.slot, events);
  war.remainingClaim -= value;
  return events;
}

/// Batched settlement annexes in tap order, atomic: any invalid tile
/// throws before anything is committed (`applyAction` works on a copy).
/// The online client validated each tap locally with the same rules, so a
/// rejection here only happens on a genuine desync.
List<GameEvent> applySettlementAnnexMany(
    GameState state, Realm realm, SettlementAnnexMany action) {
  final events = <GameEvent>[];
  for (final tile in action.tiles) {
    events.addAll(applySettlementAnnex(state, realm,
        SettlementAnnex(slot: action.slot, x: tile.x, y: tile.y)));
  }
  return events;
}

/// "Ganzes Land übernehmen": greedy annex of every affordable bordering
/// loser tile, then the settlement finishes (rest in Taler).
List<GameEvent> applySettlementTakeAll(
    GameState state, Realm realm, SettlementTakeAll action, Rng rng) {
  final war = _warFor(state, realm.slot, phase: WarPhase.settlement);
  if (war.winnerSlot != realm.slot) {
    throw ActionException('Nur der Sieger stellt Ansprüche !');
  }
  final events = <GameEvent>[];
  annexAffordableTiles(state, events);
  finishSettlement(state, rng, events);
  return events;
}

List<GameEvent> applySettlementFinish(
    GameState state, Realm realm, SettlementFinish action, Rng rng) {
  final war = _warFor(state, realm.slot, phase: WarPhase.settlement);
  if (war.winnerSlot != realm.slot) {
    throw ActionException('Nur der Sieger stellt Ansprüche !');
  }
  final events = <GameEvent>[];
  finishSettlement(state, rng, events);
  return events;
}

List<GameEvent> applySpyMission(
    GameState state, Realm realm, SpyMission action, Rng rng) {
  if (action.agents < 1 || action.agents > maxAgentsPerMission) {
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
  if (action.agents < 1 || action.agents > maxAgentsPerMission) {
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
