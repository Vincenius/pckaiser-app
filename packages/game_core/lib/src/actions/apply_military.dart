/// Handlers for the §10–§13 actions, called from `applyAction`'s
/// dispatcher. Same contract: mutate the (already copied) state, throw
/// [ActionException] on invalid input, return the emitted events.
library;

import '../l10n/messages.dart';
import '../rng/rng.dart';
import '../rules/espionage.dart';
import '../rules/movement.dart'
    show SeaEmbark, closestReachableTile, warField, warSeaEmbark;
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
    throw ActionException(coreMessage('noSuchTroop'));
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
        ? coreMessage('noRecruitsThisYear')
        : coreMessage('fewRecruitsThisYear', {'left': left}));
  }
}

List<GameEvent> applyRecruitTroops(
    GameState state, Realm realm, RecruitTroops action, Rng rng) {
  _requireNotAtWar(state, realm);
  if (action.men <= 0) throw ActionException(coreMessage('notPossible'));
  if (action.troopClass < TroopClass.infanterie ||
      action.troopClass > TroopClass.artillerie) {
    throw ActionException(coreMessage('unknownTroopClass'));
  }
  if (realm.armySize + action.men > realm.troopCapacity) {
    throw ActionException(coreMessage('notEnoughQuarters'));
  }
  _requireLevy(realm, action.men);
  final cost = recruitCost(action.men, action.troopClass);
  if (realm.treasury < cost) {
    throw ActionException(coreMessage('notEnoughTaler', {'cost': cost}));
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
    throw ActionException(coreMessage('stationOnOwnTerritory'));
  }
  return (x, y);
}

List<GameEvent> applyHireSoeldner(
    GameState state, Realm realm, HireSoeldner action) {
  _requireNotAtWar(state, realm);
  if (action.men <= 0) throw ActionException(coreMessage('notPossible'));
  final cost = soeldnerCost(action.men);
  if (realm.treasury < cost) {
    throw ActionException(coreMessage('notEnoughTaler', {'cost': cost}));
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
  if (action.men <= 0) throw ActionException(coreMessage('notPossible'));
  // Söldner ignore garrison capacity and the levy; the price split lives
  // in [reinforceCost] (keyed on garrisonCounted, never on quality — a
  // drilled regular shares the Söldner quality value).
  if (troop.garrisonCounted) {
    if (realm.armySize + action.men > realm.troopCapacity) {
      throw ActionException(coreMessage('notEnoughQuarters'));
    }
    _requireLevy(realm, action.men);
  }
  final cost = reinforceCost(troop, action.men);
  if (realm.treasury < cost) {
    throw ActionException(coreMessage('notEnoughTaler', {'cost': cost}));
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
    throw ActionException(coreMessage('onlyRegularsTrain'));
  }
  if (troop.quality >= Troop.drillCap) {
    throw ActionException(coreMessage('troopFullyDrilled'));
  }
  final cost = drillCost(troop);
  if (realm.treasury < cost) {
    throw ActionException(coreMessage('notEnoughTaler', {'cost': cost}));
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
    throw ActionException(coreMessage('onlyRegularsTrain'));
  }
  if (action.troopClass < TroopClass.infanterie ||
      action.troopClass > TroopClass.artillerie) {
    throw ActionException(coreMessage('unknownTroopClass'));
  }
  if (action.troopClass == troop.troopClass) {
    throw ActionException(coreMessage('troopAlreadyTrained'));
  }
  final cost = retrainCost(troop, action.troopClass);
  if (realm.treasury < cost) {
    throw ActionException(coreMessage('notEnoughTaler', {'cost': cost}));
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
    throw ActionException(coreMessage('troopNeedsName'));
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
    throw ActionException(coreMessage('unknownTroopStance'));
  }
  // The march target (2026-09-01) belongs to the attack stance: holding
  // position always clears it, and an attack order without one restores the
  // default target, the enemy capital.
  final x = action.targetX;
  final y = action.targetY;
  if (action.stance == TroopStance.attack && x != null && y != null) {
    if (!state.map.inBounds(x, y)) {
      throw ActionException(coreMessage('tileOffMap'));
    }
    // Armies march over land only — a water tile would simply be
    // unreachable, and the unit would stand still all war.
    if (state.map.isWaterAt(x, y)) {
      throw ActionException(coreMessage('stanceTargetOnLand'));
    }
    troop.stanceTargetX = x;
    troop.stanceTargetY = y;
  } else {
    troop.stanceTargetX = null;
    troop.stanceTargetY = null;
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
    throw ActionException(coreMessage('notDuringWar'));
  }
}

List<GameEvent> applyMergeTroops(
    GameState state, Realm realm, MergeTroops action) {
  _requireNotAtWar(state, realm);
  if (action.fromIndex == action.toIndex) {
    throw ActionException(coreMessage('chooseTwoDifferentTroops'));
  }
  final from = unitAt(realm, action.fromIndex);
  final to = unitAt(realm, action.toIndex);
  if (!canMergeTroops(from, to)) {
    throw ActionException(coreMessage('onlySameKindMerge'));
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
    throw ActionException(coreMessage('stationOnOwnTerritory'));
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
    return coreMessage('warTooEarly', {'year': state.warStartYear});
  }
  if (realm.warThisYear) {
    return coreMessage('warAlreadyThisYear');
  }
  if (realm.troops.where((t) => t.men > 0).isEmpty) {
    return coreMessage('notEnoughTroops');
  }
  if (state.activeWar != null) {
    return coreMessage('anotherWarActive');
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
      targetSlot > state.realmCount ||
      state.realm(targetSlot).isVacant) {
    return coreMessage('invalidWarTarget');
  }
  // [DEVIATION] No war against a slot your own ruler already holds
  // (ruler aliasing, §19) — merging is the intended path.
  if (state.realm(targetSlot).rulerId == realm.rulerId) {
    return coreMessage('realmAlreadyYourRulers');
  }
  // Human-vs-human wars are allowed: war input alternates between the two
  // human sides (war.actingSlot, hot-seat handoff locally, the war clock
  // online).
  // [DEVIATION] Wars only against realms with a shared border.
  if (!state.map.realmNeighbors(realm.slot).contains(targetSlot)) {
    return coreMessage('noSharedBorder');
  }
  // `[DESIGNED 2026-08-08, user feedback]` Post-war truce ([truceYears]):
  // the same pair may not go at each other again right away. Applies to
  // humans and AI alike — the AI filters its target picks with this very
  // function, so it can never pick a truce-bound neighbour.
  final truce = truceUntil(state, realm.slot, targetSlot);
  if (truce != null) {
    return coreMessage('truceActive', {'year': truce});
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
    throw ActionException(coreMessage('notAtWar'));
  }
  if (phase != null && war.phase != phase) {
    throw ActionException(coreMessage('wrongWarPhase'));
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
    throw ActionException(coreMessage('opponentActing'));
  }
  return war;
}

/// The §11.2 per-step passability rule, shared by [applyWarMove]'s
/// validation and [applyWarMarch]'s step planning (ONE definition — a
/// planner that used its own copy could drift and plan a rejected step):
///  - water only through an own or ENEMY Hafen (embark; captured enemy
///    ports serve the invader, user rule 2026-07-19) or when already at
///    sea (manual sea steering, tile by tile);
///  - `[DESIGNED]` own, enemy and neutral unowned tiles are passable;
///    only a THIRD realm's land is off-limits during the war.
/// Returns the rejection message, or null when the step is legal.
String? warStepBlocker(
    GameState state, int slot, int enemySlot, int x, int y, int nx, int ny) {
  final map = state.map;
  if (!map.inBounds(nx, ny)) return coreMessage('impassable');
  if (map.isWaterAt(nx, ny)) {
    final harborOwner = map.ownerAt(nx, ny);
    final embarking = (harborOwner == slot || harborOwner == enemySlot) &&
        map.buildingAt(nx, ny) == Building.hafen;
    if (!embarking && !map.isWaterAt(x, y)) {
      return coreMessage('embarkViaHarborOnly');
    }
  }
  final tileOwner = map.ownerAt(nx, ny);
  if (tileOwner != slot &&
      tileOwner != enemySlot &&
      tileOwner != World.niemand) {
    return coreMessage('noWarTransitForeignRealms');
  }
  return null;
}

List<GameEvent> applyWarMove(
    GameState state, Realm realm, WarMove action, Rng rng) {
  final war = _warFor(state, realm.slot, phase: WarPhase.rounds);
  final troop = unitAt(realm, action.unitIndex);
  if (action.dx.abs() + action.dy.abs() != 1) {
    throw ActionException(coreMessage('oneTilePerMove'));
  }
  final moves = war.movesLeft[realm.slot];
  if (moves == null ||
      action.unitIndex >= moves.length ||
      moves[action.unitIndex] < 1) {
    throw ActionException(coreMessage('troopCannotMoveThisRound'));
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

/// Outcome of one march ([marchWarUnit]): the events it produced, whether
/// the unit actually left its tile, and — only when it did NOT — why.
///
/// The distinction matters because a march is a SEQUENCE of moves: "the
/// last step was refused" is the normal end of a march that ran out of
/// Züge, not a failure. `[FIXED 2026-08-24]` The old loop inferred this
/// from the event list, and a plain step emits no event: a march to a tile
/// beyond the round's reach walked its steps, hit the moves limit with an
/// empty event list, rethrew — and `applyAction`, which works on a copy,
/// then threw the whole advance away. Ordering a unit to a far tile left
/// it standing where it was with "Diese Truppe kann in dieser Runde nicht
/// weiter ziehen!".
class WarMarchOutcome {
  const WarMarchOutcome(this.events, {required this.moved, this.blocker});

  final List<GameEvent> events;

  /// Whether the unit changed tile (or spent its round on a voyage).
  final bool moved;

  /// Player-facing reason the unit could not move AT ALL, or null.
  final String? blocker;
}

/// One whole march (§11.2) — THE movement brain, shared by the player's
/// [WarMarch] action and the AI's war movement (`runAiWarMovement`), so
/// both sides march by the same rules and the same map knowledge.
///
/// The unit walks the cheapest passable route toward ([tx],[ty]), every
/// step with the full [applyWarMove] semantics (combat, capture arming),
/// until it arrives, its round moves run out, a defender holds the tile,
/// it is destroyed, or the war ends. Three things make the route smart:
///
///  * **Out of reach is fine.** A target further than the round's Züge is
///    not an error — the unit spends every move it has getting there and
///    stops, keeping the ground it won `[DESIGNED 2026-08-24, user
///    request]`.
///  * **Unreachable is fine too.** A land target no path reaches (an
///    island, third-realm land) retargets to the tile that approaches it
///    best ([closestReachableTile], 2026-07-24).
///  * **Ships count as roads.** When the sea reaches the target and the
///    land route is at least [warSeaRouteAdvantage] steps longer (or does
///    not exist), the march walks to the right harbor coast and embarks
///    ([warSeaEmbark]) — one order, one action. This used to be a
///    client-side convenience the AI did not share, which is why AI
///    armies never crossed water.
///
/// The unit is tracked by OBJECT identity across the steps: combat
/// compacts the troop list, so an index (or a name — they repeat) could
/// silently come to mean a different unit mid-march.
WarMarchOutcome marchWarUnit(GameState state, Realm realm, ActiveWar war,
    Troop troop, int tx, int ty, Rng rng) {
  final map = state.map;
  final events = <GameEvent>[];
  if (!map.inBounds(tx, ty)) {
    return WarMarchOutcome(events,
        moved: false, blocker: coreMessage('tileOffMap'));
  }
  if (troop.x == tx && troop.y == ty) {
    return WarMarchOutcome(events,
        moved: false, blocker: coreMessage('troopAlreadyThere'));
  }
  final slot = realm.slot;
  final enemySlot = war.opponentOf(slot);
  final enemyRealm = state.realm(enemySlot);
  // Own land, the enemy's, and neutral unowned tiles are passable in war
  // (mirrors [applyWarMove]); only third realms block the march.
  final warOwners = {slot, enemySlot, World.niemand};

  // Enemy stacks the route should walk AROUND when it can — the ordered
  // destination itself is never avoided (tapping an enemy unit IS the
  // order to attack it).
  Set<int> enemyStacks() => {
        for (final e in enemyRealm.troops)
          if (e.x != tx || e.y != ty) map.index(e.x, e.y),
      };

  // This unit's remaining Züge, or -1 once it is off the troop list.
  int movesLeft() {
    final index = realm.troops.indexOf(troop);
    if (index < 0) return -1;
    final moves = war.movesLeft[slot];
    if (moves == null || index >= moves.length) return -1;
    return moves[index];
  }

  // ---- plan the route -------------------------------------------------
  var goalX = tx;
  var goalY = ty;
  SeaEmbark? sea;
  String? blocker;
  final atSea = map.isWaterAt(troop.x, troop.y);
  // Ordering a LAND unit onto open water is not a march: there is no route
  // over the sea to walk. The one legal case is boarding — a single step
  // onto an adjacent own or captured Hafen (§11.2), after which the unit
  // is steered tile by tile. Anything else is refused before a single Zug
  // is spent (the unit must not wander to some random shore).
  if (map.isWaterAt(tx, ty) && !atSea) {
    final board = (tx - troop.x).abs() + (ty - troop.y).abs() == 1
        ? warStepBlocker(state, slot, enemySlot, troop.x, troop.y, tx, ty)
        : coreMessage('embarkViaHarborOnly');
    if (board != null) {
      return WarMarchOutcome(events, moved: false, blocker: board);
    }
  }
  // Sea planning only applies between land tiles: a unit already at sea is
  // steered tile by tile, and a water click is a manual steering order.
  if (!atSea && !map.isWaterAt(tx, ty)) {
    final field = warField(map, troop.x, troop.y,
        allowedOwners: warOwners, avoid: enemyStacks());
    final landWalk = field.stepsTo(tx, ty);
    // A landing obeys the same ownership rule as an overland step, so a
    // third realm's coast is no destination.
    if (warOwners.contains(map.ownerAt(tx, ty))) {
      final embark = warSeaEmbark(map, troop.x, troop.y, tx, ty,
          harborOwners: {slot, enemySlot}, field: field);
      // Walking wins whenever it can still finish the job: the voyage
      // costs the unit's WHOLE round however short the crossing, so it
      // only pays off when the land march could not arrive anyway and the
      // detour to the port is much shorter than the overland route.
      if (embark != null &&
          (landWalk < 0 ||
              (landWalk > movesLeft() &&
                  landWalk > embark.walk + warSeaRouteAdvantage))) {
        sea = embark;
        goalX = embark.x;
        goalY = embark.y;
      }
    }
    if (sea == null && landWalk < 0) {
      final near = closestReachableTile(map, troop.x, troop.y, tx, ty,
          allowedOwners: warOwners);
      if (near == null) {
        return WarMarchOutcome(events,
            moved: false, blocker: coreMessage('impassable'));
      }
      (goalX, goalY) = near;
    }
  }

  // ---- walk it --------------------------------------------------------
  var moved = false;
  var guard = 0;
  while (identical(state.activeWar, war) &&
      war.phase == WarPhase.rounds &&
      guard++ < 200) {
    final index = realm.troops.indexOf(troop);
    if (index < 0) break; // destroyed in a step's combat
    if (troop.x == goalX && troop.y == goalY) break; // arrived
    if (movesLeft() < 1) {
      // Out of Züge — the march simply ends here; next round continues it.
      blocker ??= coreMessage('troopCannotMoveThisRound');
      break;
    }
    var step = warField(map, troop.x, troop.y,
            allowedOwners: warOwners, avoid: enemyStacks())
        .firstStepTo(goalX, goalY);
    if (step == null) {
      // No land route (water target, unit at sea, island shore): manual
      // straight-line legs — primary axis first, then the secondary —
      // under the same per-step §11.2 rule ([warStepBlocker]) WarMove
      // enforces, so a planned step can never be rejected.
      final remX = goalX - troop.x;
      final remY = goalY - troop.y;
      final candidates = remX.abs() >= remY.abs()
          ? [(remX.sign, 0), (0, remY.sign)]
          : [(0, remY.sign), (remX.sign, 0)];
      for (final (dx, dy) in candidates) {
        if (dx == 0 && dy == 0) continue;
        if (warStepBlocker(state, slot, enemySlot, troop.x, troop.y,
                troop.x + dx, troop.y + dy) ==
            null) {
          step = (dx, dy);
          break;
        }
      }
    }
    if (step == null) {
      blocker ??= coreMessage('impassable');
      break;
    }
    final beforeX = troop.x;
    final beforeY = troop.y;
    events.addAll(applyWarMove(state, realm,
        WarMove(slot: slot, unitIndex: index, dx: step.$1, dy: step.$2), rng));
    if (!realm.troops.contains(troop)) {
      moved = true; // it marched into its death — the order was carried out
      break;
    }
    if (troop.x == beforeX && troop.y == beforeY) {
      moved = moved || events.isNotEmpty; // a battle it did not win
      break; // combat: the defender held the tile
    }
    moved = true;
  }

  // ---- and ship it, if that was the plan ------------------------------
  if (sea != null &&
      identical(state.activeWar, war) &&
      war.phase == WarPhase.rounds &&
      troop.x == sea.x &&
      troop.y == sea.y) {
    final index = realm.troops.indexOf(troop);
    if (index >= 0) {
      if (movesLeft() < 1) {
        // Walked to the port but has no Zug left to sail — it embarks next
        // round; the walk still counts as progress.
        blocker ??= coreMessage('troopCannotMoveThisRound');
      } else {
        try {
          events.addAll(applyWarNavalTransport(
              state,
              realm,
              WarNavalTransport(slot: slot, unitIndex: index, x: tx, y: ty),
              rng));
          moved = true;
        } on ActionException catch (e) {
          blocker ??= e.message;
        }
      }
    }
  }
  return WarMarchOutcome(events, moved: moved, blocker: blocker);
}

/// The [WarMarch] action: validates the order, then hands it to
/// [marchWarUnit]. Rejects only when the unit could not move AT ALL —
/// a march that got part of the way is a success and keeps its ground
/// (throwing would roll the whole advance back, see [WarMarchOutcome]).
List<GameEvent> applyWarMarch(
    GameState state, Realm realm, WarMarch action, Rng rng) {
  final war = _warFor(state, realm.slot, phase: WarPhase.rounds);
  final troop = unitAt(realm, action.unitIndex);
  final outcome =
      marchWarUnit(state, realm, war, troop, action.x, action.y, rng);
  if (!outcome.moved && outcome.blocker != null) {
    throw ActionException(outcome.blocker!);
  }
  return outcome.events;
}

/// Seetransport im Krieg: embark a unit standing next to an own or ENEMY
/// Hafen (captured ports serve the invader, user rule 2026-07-19) and
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
    throw ActionException(coreMessage('troopCannotMoveThisRound'));
  }
  final map = state.map;
  final enemySlot = war.opponentOf(realm.slot);
  if (!map.canNavalTransport(realm.slot, troop.x, troop.y, action.x, action.y,
      harborOwners: {realm.slot, enemySlot})) {
    throw ActionException(coreMessage('noSeaRouteToTarget'));
  }
  final tileOwner = map.ownerAt(action.x, action.y);
  if (tileOwner != realm.slot &&
      tileOwner != enemySlot &&
      tileOwner != World.niemand) {
    throw ActionException(coreMessage('landOnOwnEnemyNeutralCoast'));
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
  // THE shared gate — same predicate the war panel enables its button on.
  final block = warPlunderBlocker(state, realm.slot, action.x, action.y);
  if (block != null) {
    throw ActionException(coreMessage(block));
  }
  // §11.5: every ARMY plunders once per war round — the STRONGEST unspent
  // unit on the tile carries it (its strength bounds the haul, plunderTile
  // 2026-07-19), so a weak splinter cannot shadow a full army. The blocker
  // guaranteed such a unit exists.
  Troop? unit;
  for (final t in realm.troops) {
    if (t.x != action.x || t.y != action.y || t.plunderedThisRound) continue;
    if (unit == null || troopStrength(t) > troopStrength(unit)) unit = t;
  }
  unit!.plunderedThisRound = true;
  // The carrying unit also bounds the haul: loot, kills and razed
  // quarters scale with ITS strength (see plunderTile, 2026-07-19).
  return plunderTile(state, realm.slot, action.x, action.y, unit, rng);
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

/// `[DESIGNED 2026-08-09, user request]` Revises this side's war-start plan
/// while the preparation window runs: live command vs. stance autopilot,
/// and the proposed duel start times. Free and repeatable — the player may
/// switch to manual control right before the duel begins, and two sides who
/// found no common time can widen their offers until they do. Outside the
/// preparation phase (the war already started) it is rejected, so a
/// revision can never flip a running duel's command mode.
List<GameEvent> applyWarPrepPlan(
    GameState state, Realm realm, WarPrepPlan action) {
  final war = _warFor(state, realm.slot, phase: WarPhase.preparation);
  setWarPrepPlan(state, war, realm.slot,
      auto: action.auto, slots: action.slots);
  return const [];
}

/// `[DESIGNED 2026-08-24, user request]` Takes this side's war command back
/// from the no-show autopilot mid-war (`war.autoSlots`). `_warFor`'s
/// "opponent is acting" guard never fires here: it only rejects a LIVE
/// side's out-of-turn input, and a delegated side is never live by
/// definition ([warSideIsHuman]).
List<GameEvent> applyResumeWarCommand(
    GameState state, Realm realm, ResumeWarCommand action) {
  final war = _warFor(state, realm.slot, phase: WarPhase.rounds);
  if (!war.autoSlots.contains(realm.slot)) {
    throw ActionException(coreMessage('notDelegated'));
  }
  war.autoSlots.remove(realm.slot);
  return const [];
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
    GameState state, Realm realm, SettlementAnnex action, Rng rng) {
  final war = _warFor(state, realm.slot, phase: WarPhase.settlement);
  if (war.winnerSlot != realm.slot) {
    throw ActionException(coreMessage('onlyVictorClaims'));
  }
  final map = state.map;
  final loserSlot = war.opponentOf(realm.slot);
  if (!map.inBounds(action.x, action.y) ||
      map.ownerAt(action.x, action.y) != loserSlot) {
    throw ActionException(coreMessage('notYourEnemy'));
  }
  final value = settlementTileValue(state, map.buildingAt(action.x, action.y));
  if (value > war.remainingClaim) {
    throw ActionException(coreMessage('claimTooMuch'));
  }
  if (!map.bordersSlot(action.x, action.y, realm.slot)) {
    throw ActionException(coreMessage('annexOnlyBordering'));
  }
  final events = <GameEvent>[];
  transferTile(state, action.x, action.y, realm.slot, events);
  war.remainingClaim -= value;
  _finishIfLoserLandless(state, loserSlot, rng, events);
  return events;
}

/// Annexing the loser's LAST tile ends the settlement on the spot: there is
/// nothing left to claim, and leaving the war open parked the online AI
/// turn forever (bug 2026-07-27 — "won the war, got all the land, war
/// continued"). `finishSettlement` then vacates the landless realm via
/// `checkLandLoss` and the server's resume-after-war check can fire.
void _finishIfLoserLandless(
    GameState state, int loserSlot, Rng rng, List<GameEvent> events) {
  if (state.activeWar == null) return;
  final owned = state.realm(loserSlot).tileCount.fold(0, (a, b) => a + b);
  if (owned == 0) finishSettlement(state, rng, events);
}

/// Batched settlement annexes in tap order, atomic: any invalid tile
/// throws before anything is committed (`applyAction` works on a copy).
/// The online client validated each tap locally with the same rules, so a
/// rejection here only happens on a genuine desync.
List<GameEvent> applySettlementAnnexMany(
    GameState state, Realm realm, SettlementAnnexMany action, Rng rng) {
  final events = <GameEvent>[];
  for (final tile in action.tiles) {
    events.addAll(applySettlementAnnex(state, realm,
        SettlementAnnex(slot: action.slot, x: tile.x, y: tile.y), rng));
  }
  return events;
}

/// "Ganzes Land übernehmen": greedy annex of every affordable bordering
/// loser tile, then the settlement finishes (rest in Taler).
List<GameEvent> applySettlementTakeAll(
    GameState state, Realm realm, SettlementTakeAll action, Rng rng) {
  final war = _warFor(state, realm.slot, phase: WarPhase.settlement);
  if (war.winnerSlot != realm.slot) {
    throw ActionException(coreMessage('onlyVictorClaims'));
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
    throw ActionException(coreMessage('onlyVictorClaims'));
  }
  final events = <GameEvent>[];
  finishSettlement(state, rng, events);
  return events;
}

List<GameEvent> applySpyMission(
    GameState state, Realm realm, SpyMission action, Rng rng) {
  if (action.agents < 1 || action.agents > maxAgentsPerMission) {
    throw ActionException(coreMessage('tooManySpies'));
  }
  if (action.targetSlot == realm.slot ||
      action.targetSlot < 1 ||
      action.targetSlot > state.realmCount ||
      state.realm(action.targetSlot).isVacant) {
    throw ActionException(coreMessage('invalidTarget'));
  }
  final cost = action.agents *
      (action.spyKind == SpyKind.economy ? economySpyCost : militarySpyCost);
  if (realm.treasury < cost) {
    throw ActionException(coreMessage('notEnoughTaler', {'cost': cost}));
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
    throw ActionException(coreMessage('tooManySpies'));
  }
  if (action.targetSlot == realm.slot ||
      action.targetSlot < 1 ||
      action.targetSlot > state.realmCount ||
      state.realm(action.targetSlot).isVacant) {
    throw ActionException(coreMessage('invalidTarget'));
  }
  // One attempt per target realm per round — otherwise several orders
  // against the same realm merge into a single squad and the
  // [maxAgentsPerMission] cap means nothing.
  if (realm.assassinatedThisTurnSlots.contains(action.targetSlot)) {
    throw ActionException(coreMessage('assassinsAlreadySent'));
  }
  final cost = action.agents * assassinCost;
  if (realm.treasury < cost) {
    throw ActionException(coreMessage('notEnoughTaler', {'cost': cost}));
  }
  realm.treasury -= cost;
  realm.assassinatedThisTurnSlots.add(action.targetSlot);
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
  if (action.delta == 0) throw ActionException(coreMessage('notPossible'));
  if (action.delta > 0) {
    if (realm.guardLevel + action.delta > guardCap) {
      throw ActionException(coreMessage('guardsNotArmy'));
    }
    final cost = action.delta * guardCost;
    if (realm.treasury < cost) {
      throw ActionException(coreMessage('notEnoughTaler', {'cost': cost}));
    }
    realm.treasury -= cost;
    realm.guardLevel += action.delta;
  } else {
    if (realm.guardLevel + action.delta < 0) {
      throw ActionException(coreMessage('notSoManyGuards'));
    }
    realm.guardLevel += action.delta; // dismissing is free
  }
  return const [];
}
