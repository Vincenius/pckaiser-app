import 'dart:math' as math;

import '../actions/player_action.dart' show ActionException;
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
import 'population.dart' show cutGarrisonTroops;
import 'titles.dart' show switchTitleLadder;
import 'troops.dart';

/// §11.1: starts a war. Prunes empty units, snapshots positions, rolls the
/// first round's movement allowance.
ActiveWar startWar(
    GameState state, int attackerSlot, int defenderSlot, Rng rng) {
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
      for (final t in realm.troops) UnitSnapshot(name: t.name, x: t.x, y: t.y),
    ];
  }
  war.actingSlot = _firstHumanSide(state, war);
  _rollWarMoves(state, war, rng);
  state.activeWar = war;
  // §11.1: both sides are locked into one war per year — not just the attacker.
  state.realm(attackerSlot).warThisYear = true;
  state.realm(defenderSlot).warThisYear = true;
  return war;
}

/// The first human war side in attacker-before-defender order (the
/// original's round order), or null in a pure AI war.
int? _firstHumanSide(GameState state, ActiveWar war) {
  for (final slot in [war.attackerSlot, war.defenderSlot]) {
    if (state.dynasty(slot).status == DynastyStatus.human) return slot;
  }
  return null;
}

/// The war side whose interactive input is awaited right now, or null
/// (no war, or no human has to act). Drives the local seat AND the
/// server's awaited player (ARCHITECTURE.md "Human-vs-human wars
/// online"): during war rounds it is `war.actingSlot` (falling back to
/// the first human side for pre-HvH saves), in the claim settlement the
/// human winner.
int? warActingSlot(GameState state) {
  final war = state.activeWar;
  if (war == null) return null;
  if (war.phase == WarPhase.settlement) {
    final winner = war.winnerSlot;
    return winner != null && state.dynasty(winner).status == DynastyStatus.human
        ? winner
        : null;
  }
  final acting = war.actingSlot;
  if (acting != null && state.dynasty(acting).status == DynastyStatus.human) {
    return acting;
  }
  return _firstHumanSide(state, war);
}

/// Human-vs-human round handover: an attacker finishing their half of
/// the round passes the input to the human defender instead of ending
/// the round. Returns true when the handover happened (the caller must
/// NOT advance the round then). All other constellations — AI opponent,
/// defender finishing — return false: the round really ends.
bool handWarRoundOver(GameState state, int slot) {
  final war = state.activeWar;
  if (war == null || war.phase != WarPhase.rounds) return false;
  if (slot != war.attackerSlot) return false;
  if (state.dynasty(war.defenderSlot).status != DynastyStatus.human ||
      state.dynasty(war.attackerSlot).status != DynastyStatus.human) {
    return false;
  }
  war.actingSlot = war.defenderSlot;
  return true;
}

/// `[DESIGNED]` war-round movement allowance (§11.2 / §27): each unit gets
/// the owner's normal movement roll per war round.
void _rollWarMoves(GameState state, ActiveWar war, Rng rng) {
  for (final slot in [war.attackerSlot, war.defenderSlot]) {
    final realm = state.realm(slot);
    war.movesLeft[slot] = [
      for (final _ in realm.troops) rollMovementPoints(realm.titleClass, rng),
    ];
  }
}

/// Per-tile combat between two opposing units. Returns the events.
///
/// [DEVIATION from §11.3] The original's formula made tile defense
/// MULTIPLY the occupant's own losses (a Burg tripled your casualties)
/// and open ground meant zero casualties ever — wars degenerated into
/// walking races to the capital. The clone keeps the §10.1 power values
/// and the one-roll-per-encounter shape, but every encounter is DECIDED:
/// the side with the higher effective strength
///
///   eff = P × (1 + def / 2) × fortune     (one shared fortune roll,
///                                          [0.5, 1.5) vs its mirror)
///
/// wins the clash — the loser takes 35–65% casualties (a remnant under 5
/// men is wiped), the winner 10–25% (and always survives). Equal forces
/// on open ground trade ~50/50 wins, so a unit typically falls after
/// 2–5 engagements; a fortified or clearly stronger side wins most
/// clashes and grinds the enemy down fast while bleeding slowly. Spec'd
/// in PROJECT_REQUIREMENTS.md "Rule deviations".
List<GameEvent> resolveCombat(
    GameState state, int slotA, Troop a, int slotB, Troop b, Rng rng) {
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

  final defenseA = defense(a);
  final defenseB = defense(b);
  final r = rng.nextReal();
  final powerA = (a.men * (3 * a.troopClass + a.quality) / 10).floor();
  final powerB = (b.men * (3 * b.troopClass + b.quality) / 10).floor();
  int lossesA;
  int lossesB;

  final effA = powerA * (1 + defenseA / 2) * (0.5 + r);
  final effB = powerB * (1 + defenseB / 2) * (1.5 - r);
  final loserShare = 0.35 + 0.3 * rng.nextReal();
  final winnerShare = 0.10 + 0.15 * rng.nextReal();
  int loserLosses(int men) {
    final losses = math.max(1, (men * loserShare).round());
    // A remnant under 5 men is wiped — no endless 1-man tail fights.
    return men - losses < 5 ? men : losses;
  }

  int winnerLosses(int men) => math.min(men - 1, (men * winnerShare).round());

  if (effA >= effB) {
    lossesA = winnerLosses(a.men);
    lossesB = loserLosses(b.men);
  } else {
    lossesA = loserLosses(a.men);
    lossesB = winnerLosses(b.men);
  }

  if (lossesA == a.men && lossesB == b.men) {
    // Simultaneous annihilation: random(2) picks one side to keep 1 man.
    if (rng.nextInt(2) == 0) {
      lossesA = a.men - 1;
    } else {
      lossesB = b.men - 1;
    }
  }

  final destroyedA = lossesA >= a.men;
  final destroyedB = lossesB >= b.men;
  _applyLosses(state, slotA, a, lossesA);
  _applyLosses(state, slotB, b, lossesB);

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
        'defenderSlot': slotB,
        'attackerDestroyed': destroyedA,
        'defenderDestroyed': destroyedB,
        'x': b.x,
        'y': b.y,
      },
    ),
  ];
}

void _applyLosses(GameState state, int slot, Troop troop, int losses) {
  if (losses <= 0) return;
  final realm = state.realm(slot);
  troop.men -= losses;
  if (troop.garrisonCounted) releaseGarrison(realm, losses);
  if (troop.men <= 0) {
    // `movesLeft` is parallel to the troop list — drop the dead unit's
    // entry too, or every later unit would read its neighbor's budget.
    final index = realm.troops.indexOf(troop);
    final moves = state.activeWar?.movesLeft[slot];
    if (moves != null && index >= 0 && index < moves.length) {
      moves.removeAt(index);
    }
    realm.troops.remove(troop);
  }
}

/// §11.4 conquest transfer: the tile changes owner; the winner also takes
/// a treasury and harvest share, doubled on the loser's capital. Town
/// tiles move their town object between the realms.
void transferTile(
    GameState state, int x, int y, int winnerSlot, List<GameEvent> events) {
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
  // No share of an EMPTY (or indebted) treasury — the winner must never
  // inherit a share of the loser's DEBT.
  if (sum1 > 0 && building < t1.length && loser.treasury > 0) {
    // Clamp to the loser's purse: a high-value capital tile (factor 2) can
    // compute a share larger than the whole treasury — the winner must
    // never take more money than the loser has, so war can't push a
    // treasury negative.
    final share =
        math.min(loser.treasury, loser.treasury * t1[building] * factor ~/ sum1);
    loser.treasury -= share;
    winner.treasury += share;
  }
  if (sum2 > 0) {
    final grainShare = loser.grainHarvest * t2[building] * factor ~/ sum2;
    final cattleShare = loser.livestockHarvest * t2[building] * factor ~/ sum2;
    loser.grainHarvest -= grainShare;
    loser.livestockHarvest -= cattleShare;
    winner.grainHarvest += grainShare;
    winner.livestockHarvest += cattleShare;
  }

  map.owner[map.index(x, y)] = winnerSlot;
  loser.tileCount[building]--;
  winner.tileCount[building]++;

  final townIndex = loser.towns.indexWhere((t) => t.x == x && t.y == y);
  if (townIndex >= 0) {
    final town = loser.towns.removeAt(townIndex);
    loser.population -= town.population;
    loser.troopCapacity -= town.troopCapacity;
    loser.armySize = math.max(0, loser.armySize - town.garrison);
    // The lost garrison also leaves the loser's garrison-counted units —
    // cutting only `armySize` would let unit men drift out of sync.
    cutGarrisonTroops(loser, town.garrison);
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

/// §12 post-war coercion, checked in order. Convert-or-die and forced
/// marriage exclude each other (religions differ vs. match); Kaiser
/// abdication and the Kurfürst seat strip are independent checks on top.
/// Every applicable option fires, like the original ("prompt per
/// applicable option"). AI victors auto-execute; a human victor gets one
/// `coercion` decision per option (default: apply). A human loser facing
/// convert-or-die gets their own decision; an AI loser flips a coin.
void runCoercion(GameState state, int victorSlot, Person capturedRuler, Rng rng,
    List<GameEvent> events) {
  final victorRealm = state.realm(victorSlot);
  final victor = state.person(victorRealm.rulerId);
  if (victor == null) return;
  final victorReligion = state.dynasty(victor.dynasty).religion;
  final loserDynasty = state.dynasty(capturedRuler.dynasty);

  final options = <String>[];
  if (loserDynasty.religion != victorReligion) {
    options.add('convertOrDie');
  } else if (victor.isMale &&
      victor.spouseId == null &&
      capturedRuler.spouseId == null &&
      victor.gender != capturedRuler.gender &&
      victor.age >= 14 &&
      capturedRuler.age >= 14 &&
      (victor.age - capturedRuler.age).abs() < 10) {
    options.add('forcedMarriage');
  }
  if (state.kaiserId == capturedRuler.id) options.add('abdication');
  if (state.kurfuerstenIds.contains(capturedRuler.id)) {
    options.add('stripSeat');
  }
  if (options.isEmpty) return;

  final humanVictor =
      state.dynasty(victor.dynasty).status == DynastyStatus.human;
  for (final option in options) {
    if (humanVictor) {
      state.pendingDecisions.add(PendingDecision(
        id: 'coercion-${capturedRuler.id}-${state.year}-$option',
        type: 'coercion',
        decidingSlot: victor.dynasty,
        payload: {
          'option': option,
          'victorId': victor.id,
          'capturedRulerId': capturedRuler.id,
        },
      ));
    } else {
      applyCoercion(state, option, victor, capturedRuler, rng, events);
      // An executed ruler (refused conversion) needs no further coercion —
      // succession already cleared their offices.
      if (!state.persons.containsKey(capturedRuler.id)) break;
    }
  }
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
      applyConvertOrDie(
          state,
          capturedRuler,
          state.dynasty(victor.dynasty).religion,
          rng.nextInt(2) == 0,
          rng,
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
      // A pending decision can outlive the capture (succession or an
      // election may crown someone else first) — only the captured
      // ruler's own crown is forfeit, never a successor's.
      if (state.kaiserId != capturedRuler.id) break;
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
    // Like every other conversion, the dynasty's home realm switches
    // onto the right title ladder (§4/§16.1) and religiously
    // incompatible marriages dissolve (§14.4). Only the HOME slot's
    // ladder switches: the promotion check (§16.2) keys the ladder off
    // the slot dynasty's religion, so an aliased realm (ruled by a
    // member of this dynasty but belonging to an unconverted slot
    // dynasty) must keep its ladder — switching it would strand the
    // title where its own ladder never promotes.
    switchTitleLadder(state.realm(dynasty.index), religion);
    dyn.divorceIncompatibleCouples(state, dynasty.index, events);
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

/// The war side holding the enemy's (still enemy-owned) capital tile with
/// at least one unit, or null. When both sides stand on each other's
/// capital the higher war score wins (tie: the attacker — they moved
/// first). Surfaced to the war UI ("end the round to seal the victory").
int? capitalOccupier(GameState state, ActiveWar war) {
  bool occupies(int slot) {
    final enemy = state.realm(war.opponentOf(slot));
    return state.map.ownerAt(enemy.capitalX, enemy.capitalY) ==
            war.opponentOf(slot) &&
        state
            .realm(slot)
            .troops
            .any((t) => t.x == enemy.capitalX && t.y == enemy.capitalY);
  }

  final attacker = occupies(war.attackerSlot);
  final defender = occupies(war.defenderSlot);
  if (attacker && defender) {
    return warScore(state, war.defenderSlot) > warScore(state, war.attackerSlot)
        ? war.defenderSlot
        : war.attackerSlot;
  }
  if (attacker) return war.attackerSlot;
  if (defender) return war.defenderSlot;
  return null;
}

/// The settlement claim is capped at a share of the loser's total
/// territory settlement value. War scores grow with army strength
/// squared, so any sizeable army's claim used to dwarf the loser's whole
/// realm — the winner could annex every reachable tile and the cash
/// remainder bankrupted the loser on top. With the cap, one lost war
/// never costs the whole realm (the last tile is never affordable), so
/// a losing party is never erased by a single war.
///
/// The cap share is ROLLED per war end, 50–80% (rather than a flat 50%,
/// which made every victory against a similar-sized realm pay out the
/// same, predictable claim).
int _cappedClaim(GameState state, int loserSlot, int claim, Rng rng) {
  final map = state.map;
  var total = 0;
  for (var i = 0; i < map.terrain.length; i++) {
    if (map.owner[i] == loserSlot) {
      total += settlementTileValue(state, map.building[i]);
    }
  }
  final sharePercent = 50 + rng.nextInt(31);
  return math.min(claim, total * sharePercent ~/ 100);
}

/// Ruler capture, resolved at ROUND END: the captor holds the enemy
/// capital when the round ends. The loser's ruler is captured and
/// coerced (§12), but the realm is not swallowed whole — the captor
/// wins the war and SELECTS loser tiles in the claim settlement,
/// against a claim of their war score (which includes the +3,000
/// capital bonus; capped — see [_cappedClaim]).
void _endWarByCapitalOccupation(
    GameState state, int captorSlot, Rng rng, List<GameEvent> events) {
  final war = state.activeWar!;
  final loserSlot = war.opponentOf(captorSlot);
  final loser = state.realm(loserSlot);
  final capturedRuler = state.person(loser.rulerId);
  // The claim covers at least the loser's capital tile (overriding the
  // half-territory cap if needed): the captor held that very tile to
  // win — a quick war against a depleted enemy yields a tiny war score,
  // and the winner could otherwise never take the seat they conquered.
  final claim = math.max(
      _cappedClaim(state, loserSlot, warScore(state, captorSlot), rng),
      settlementTileValue(
          state, state.map.buildingAt(loser.capitalX, loser.capitalY)));

  events.add(GameEvent(
    year: state.year,
    slot: captorSlot,
    type: 'rulerCaptured',
    visibility: EventVisibility.public,
    payload: {
      'loserSlot': loserSlot,
      'ruler': capturedRuler?.name,
      'loserHuman': state.dynasty(loserSlot).status == DynastyStatus.human,
    },
  ));
  events.add(GameEvent(
    year: state.year,
    slot: captorSlot,
    type: 'warWon',
    visibility: EventVisibility.public,
    payload: {'claim': claim, 'loserSlot': loserSlot},
  ));

  war.phase = WarPhase.settlement;
  war.winnerSlot = captorSlot;
  war.remainingClaim = claim;
  war.actingSlot = captorSlot; // the settlement awaits the winner

  if (capturedRuler != null) {
    runCoercion(state, captorSlot, capturedRuler, rng, events);
  }
  if (state.dynasty(captorSlot).status != DynastyStatus.human) {
    autoSettleClaim(state, rng, events);
  }
}

/// Advances a war round (§11.2): applies the AI peace placeholders,
/// checks mutual peace and winter, and otherwise rolls the next round.
/// (AI unit movement arrives with Phase 5 — until then AI sides hold
/// position, which makes the traced AI peace rules fire naturally.)
///
/// Before anything else, a side holding the enemy capital across TWO
/// consecutive round ends — i.e. through the opponent's full response
/// round — wins the war right here ([_endWarByCapitalOccupation]). The
/// first round end only ARMS the capture (`war.heldCapitalSlot`, public
/// `capitalHeld` event); an opponent with no troops left cannot respond,
/// so the capture resolves immediately.
void endWarRound(GameState state, Rng rng, List<GameEvent> events) {
  final war = state.activeWar;
  if (war == null || war.phase != WarPhase.rounds) return;

  final captor = capitalOccupier(state, war);
  if (captor != null &&
      (captor == war.heldCapitalSlot ||
          state.realm(war.opponentOf(captor)).troops.isEmpty)) {
    _endWarByCapitalOccupation(state, captor, rng, events);
    return;
  }
  if (captor != null && captor != war.heldCapitalSlot) {
    events.add(GameEvent(
      year: state.year,
      slot: captor,
      type: 'capitalHeld',
      visibility: EventVisibility.public,
      payload: {'loserSlot': war.opponentOf(captor)},
    ));
  }
  war.heldCapitalSlot = captor;

  // AI peace decisions (§11.2, incl. the original's dead-check quirk: an
  // AI attacker wants peace as soon as its units are back on/at their
  // pre-war spots).
  for (final slot in [war.attackerSlot, war.defenderSlot]) {
    if (state.dynasty(slot).status == DynastyStatus.human) continue;
    war.setWantsPeace(slot, _aiWantsPeace(state, war, slot));
  }

  // Winter fires when the 20th round ENDS (`round` is 0-based, so >= 19).
  // The war UI counts "Runde X/20", so the end must land on round 20, not
  // one round later.
  final winterReached = war.round >= 19;
  if ((war.attackerWantsPeace && war.defenderWantsPeace) || winterReached) {
    if (winterReached) {
      events.add(GameEvent(
        year: state.year,
        slot: 0,
        type: 'winterEndsWar',
        visibility: EventVisibility.public,
      ));
    } else {
      // A NEGOTIATED peace is a white peace — status quo ante, nobody
      // gains tiles or money. Only a winter-forced end goes to score
      // arbitration.
      events.add(GameEvent(
        year: state.year,
        slot: 0,
        type: 'peaceAgreed',
        visibility: EventVisibility.public,
        participants: [war.attackerSlot, war.defenderSlot],
      ));
      _returnTroops(state, war, events);
      state.activeWar = null;
      return;
    }
    resolveWarEnd(state, rng, events);
    return;
  }

  war.round++;
  war.attackerWantsPeace = false;
  war.defenderWantsPeace = false;
  war.attackerPlunderedThisRound = false;
  war.defenderPlunderedThisRound = false;
  // Attacker before defender, as in the original: every new round starts
  // with the first human side's input.
  war.actingSlot = _firstHumanSide(state, war);
  _rollWarMoves(state, war, rng);
}

/// Pairs each troop with a distinct snapshot of the same name, in list
/// order. Units are snapshotted by name only, and names repeat (every AI
/// recruit is "Rekruten") — naive name lookup would match every duplicate
/// to the FIRST snapshot. Entries are null for troops without a snapshot
/// (defensive — merging is forbidden mid-war).
List<UnitSnapshot?> matchedSnapshots(
    List<Troop> troops, List<UnitSnapshot> snapshots) {
  final used = List<bool>.filled(snapshots.length, false);
  UnitSnapshot? claim(Troop troop) {
    for (var i = 0; i < snapshots.length; i++) {
      if (!used[i] && snapshots[i].name == troop.name) {
        used[i] = true;
        return snapshots[i];
      }
    }
    return null;
  }

  return [for (final troop in troops) claim(troop)];
}

/// Whether [slot]'s AI would currently agree to peace (§11.2 AI peace
/// rules). Surfaced to the war UI so a human knows that wishing for
/// peace and ending the round would actually end the war.
bool aiWouldAcceptPeace(GameState state, int slot) {
  final war = state.activeWar;
  if (war == null || !war.isParticipant(slot)) return false;
  return _aiWantsPeace(state, war, slot);
}

bool _aiWantsPeace(GameState state, ActiveWar war, int slot) {
  final realm = state.realm(slot);
  final snapshots = war.snapshots[slot] ?? const [];
  // Home test: every unit claims a distinct snapshot matching name AND
  // position — same-named units are interchangeable, so the side is home
  // exactly when the position multisets match.
  final used = List<bool>.filled(snapshots.length, false);
  var allHome = true;
  for (final troop in realm.troops) {
    var found = false;
    for (var i = 0; i < snapshots.length; i++) {
      if (!used[i] &&
          snapshots[i].name == troop.name &&
          snapshots[i].x == troop.x &&
          snapshots[i].y == troop.y) {
        used[i] = true;
        found = true;
        break;
      }
    }
    if (!found) {
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

/// End-of-war resolution for winter endings (§11.2): the leading side
/// wins and opens the claim settlement (interactive for humans,
/// automatic for AI); equal scores end in a draw.
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
  final claim = _cappedClaim(
      state, loserSlot, math.max(scoreAttacker, scoreDefender), rng);

  events.add(GameEvent(
    year: state.year,
    slot: winnerSlot,
    type: 'warWon',
    visibility: EventVisibility.public,
    payload: {'claim': claim, 'loserSlot': loserSlot},
  ));

  // Victory → claim settlement: the winner chooses which tiles to take
  // (humans tap, AIs auto-settle).
  war.phase = WarPhase.settlement;
  war.winnerSlot = winnerSlot;
  war.remainingClaim = claim;
  war.actingSlot = winnerSlot; // the settlement awaits the winner
  if (state.dynasty(winnerSlot).status != DynastyStatus.human) {
    autoSettleClaim(state, rng, events);
  }
}

/// What a loser tile costs against the settlement claim. Bare land
/// (building value 0) costs 100 T like a Kornfeld — were it free, any
/// limited victory could strip the loser of every reachable empty tile
/// without spending the claim.
int settlementTileValue(GameState state, int building) {
  final value = Building.value[building];
  if (value == 0) return 100;
  return value;
}

/// Greedy annex pass over the open settlement: every affordable loser
/// tile bordering the winner's land is taken (annexed tiles extend the
/// border, so connected territory is swept). Shared by the AI auto-settle
/// and the human "Ganzes Land übernehmen" shortcut (`SettlementTakeAll`).
void annexAffordableTiles(GameState state, List<GameEvent> events) {
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
        final value = settlementTileValue(state, map.buildingAt(x, y));
        if (value > war.remainingClaim) continue;
        if (!_bordersTerritory(state, winnerSlot, x, y)) continue;
        transferTile(state, x, y, winnerSlot, events);
        war.remainingClaim -= value;
        annexed = true;
      }
    }
  }
}

/// §11.2 claim settlement, AI path `[APPROX]`: greedily annex affordable
/// loser tiles adjacent to own land, then take the remainder in cash.
void autoSettleClaim(GameState state, Rng rng, List<GameEvent> events) {
  annexAffordableTiles(state, events);
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
/// Taler from the loser's treasury — but capped at what the loser actually
/// owns. War must never drive a treasury negative: a bankrupt loser would
/// otherwise be soft-locked out of paying for anything afterwards (e.g. an
/// election bribe prompt) and could lose far more than they ever had.
void finishSettlement(GameState state, List<GameEvent> events) {
  final war = state.activeWar!;
  final winnerSlot = war.winnerSlot!;
  final loserSlot = war.opponentOf(winnerSlot);
  if (war.remainingClaim > 0) {
    final loser = state.realm(loserSlot);
    final paid = math.max(0, math.min(war.remainingClaim, loser.treasury));
    loser.treasury -= paid;
    state.realm(winnerSlot).treasury += paid;
    events.add(GameEvent(
      year: state.year,
      slot: winnerSlot,
      type: 'claimPaidOut',
      visibility: EventVisibility.public,
      payload: {'amount': paid, 'from': loserSlot},
    ));
  }
  _returnTroops(state, war, events);
  // Settlement annexation can transfer tiles that were snapshot positions for
  // the loser's troops. Re-home any stranded unit to the loser's capital (or
  // the nearest owned tile if the capital itself was annexed).
  _rehomeStrandedTroops(state, state.realm(loserSlot));
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
    final matched = matchedSnapshots(realm.troops, snapshots);
    for (var i = 0; i < realm.troops.length; i++) {
      final snapshot = matched[i];
      if (snapshot != null) {
        realm.troops[i].x = snapshot.x;
        realm.troops[i].y = snapshot.y;
      }
    }
  }
  _refreshTroopMarkers(state);
}

/// Moves any troop that ended up on non-owned territory (e.g. because its
/// pre-war snapshot position was annexed during settlement) to the realm's
/// capital, or to the nearest owned tile if the capital itself was taken.
void _rehomeStrandedTroops(GameState state, Realm realm) {
  final map = state.map;
  int? homeX, homeY;
  for (final troop in realm.troops) {
    if (map.ownerAt(troop.x, troop.y) == realm.slot) continue;
    if (homeX == null) {
      // Capital first; fall back to a map scan if the capital was also annexed.
      if (map.ownerAt(realm.capitalX, realm.capitalY) == realm.slot) {
        homeX = realm.capitalX;
        homeY = realm.capitalY;
      } else {
        outer:
        for (var y = 0; y < map.height; y++) {
          for (var x = 0; x < map.width; x++) {
            if (map.ownerAt(x, y) == realm.slot) {
              homeX = x;
              homeY = y;
              break outer;
            }
          }
        }
      }
      if (homeX == null) break; // realm is landless; _checkLandLoss handles it
    }
    troop.x = homeX;
    troop.y = homeY!;
  }
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

/// A ruler who lost all land loses any Kurfürst seat (§17.2). Losing the
/// LAST tile also emits a public `realmOverrun` event — both war sides
/// get an explicit "everything was won/lost" popup in the client instead
/// of having to read it off the map.
///
/// The loser's realm is eliminated: `rulerId` set to null so the slot is
/// vacant and no longer participates in turns or the win-condition check.
/// Without this a "zombie realm" with no tiles stays in the turn order;
/// when the human player's own ruler later dies with no heirs, the only
/// surviving ruler is the zombie's — it inherits the human slot, converts
/// it to AI control, and `advanceUntilHuman` fires `humansDefeated`.
void _checkLandLoss(GameState state, Realm loser, List<GameEvent> events) {
  final owned = loser.tileCount.fold(0, (a, b) => a + b);
  if (owned > 0) return;
  if (loser.rulerId != null) {
    state.kurfuerstenIds.remove(loser.rulerId);
  }
  events.add(GameEvent(
    year: state.year,
    slot: loser.slot,
    type: 'realmOverrun',
    visibility: EventVisibility.public,
    // Whether a HUMAN player just lost their last land — the client shows
    // a prominent popup to everyone for that (a strong, story-worthy event).
    payload: {
      'human': state.dynasty(loser.slot).status == DynastyStatus.human,
    },
  ));
  // Vacate the slot so it no longer appears in turn order or living-ruler
  // lists. Troops are cleared because a realm with no land has no base to
  // return to; the map markers are refreshed to match.
  loser.rulerId = null;
  loser.troops.clear();
  loser.ships.clear();
  final dynasty = state.dynasty(loser.slot);
  dynasty.status = DynastyStatus.ai;
  dynasty.humanPlayer = null;
  _refreshTroopMarkers(state);
}

/// §11.5 plunder during war rounds, once per side per round.
List<GameEvent> plunderTile(
    GameState state, int plundererSlot, int x, int y, Rng rng) {
  final map = state.map;
  final building = map.buildingAt(x, y);
  final victimSlot = map.ownerAt(x, y);
  if (victimSlot == World.niemand) {
    // An ownerless building has no victim to plunder.
    throw ActionException('Hier steht doch gar nichts !');
  }
  final plunderer = state.realm(plundererSlot);
  final victim = state.realm(victimSlot);
  final events = <GameEvent>[];

  // Result numbers for the event payload (the client's battle report).
  var loot = 0;
  var killed = 0;
  var destroyed = false;

  switch (building) {
    case Building.kornfeld || Building.weide:
      map.building[map.index(x, y)] = Building.none;
      map.owner[map.index(x, y)] = World.niemand;
      victim.tileCount[building]--;
      destroyed = true;
    case Building.dorf || Building.markt || Building.stadt:
      final town = victim.towns.firstWhere((t) => t.x == x && t.y == y);
      killed = rng.nextInt(town.population ~/ 2);
      loot = rng.nextInt(town.population);
      final capacityCut =
          rng.nextInt(math.max(0, town.troopCapacity - town.garrison));
      plunderer.treasury += loot; // victim's treasury is NOT touched
      town.population -= killed;
      victim.population -= killed;
      if (capacityCut > 0) {
        town.troopCapacity -= capacityCut;
        victim.troopCapacity -= capacityCut;
      }
    case Building.burg || Building.palast || Building.hafen:
      loot = victim.treasury > 0 ? rng.nextInt(victim.treasury) : 0;
      victim.treasury -= loot;
      plunderer.treasury += loot;
  }

  events.add(GameEvent(
    year: state.year,
    slot: plundererSlot,
    type: 'plunder',
    visibility: EventVisibility.public,
    payload: {
      'x': x,
      'y': y,
      'building': building,
      'victim': victimSlot,
      'loot': loot,
      'killed': killed,
      'destroyed': destroyed,
    },
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
