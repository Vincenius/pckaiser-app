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
import '../state/troop.dart';
import '../state/war.dart';
import 'dynasty.dart' as dyn;
import 'events.dart' show ensureRealmSeat;
import 'movement.dart';
import 'population.dart' show cutGarrisonTroops;
import 'titles.dart' show switchTitleLadder;
import 'troops.dart';
import 'victory.dart';

/// §11.1: starts a war. Prunes empty units, snapshots positions, rolls the
/// first round's movement allowance.
ActiveWar startWar(GameState state, int attackerSlot, int defenderSlot, Rng rng,
    {List<GameEvent>? events}) {
  // A war must be winnable: both seats are repaired up front. A capital
  // lost earlier the same year (settlement, earthquake, bankruptcy) is
  // normally only re-seated at the next year start — and a human may still
  // owe their relocate decision. The capital-occupation victory and the
  // map's seat flag both require the seat on OWN land, so a stale seat
  // means no flag and no way to win the war.
  for (final slot in [attackerSlot, defenderSlot]) {
    ensureRealmSeat(state, slot, rng, events ?? <GameEvent>[],
        allowDecision: false);
  }
  for (final slot in [attackerSlot, defenderSlot]) {
    final realm = state.realm(slot);
    // Fresh war, fresh §11.5 plunder budget for every army. (No empty-unit
    // pruning: a unit hits 0 men only through combat/desertion paths that
    // delete it on the spot.)
    for (final troop in realm.troops) {
      troop.plunderedThisRound = false;
    }
  }
  final war = ActiveWar(
    attackerSlot: attackerSlot,
    defenderSlot: defenderSlot,
  );
  for (final slot in [attackerSlot, defenderSlot]) {
    final realm = state.realm(slot);
    war.snapshots[slot] = [
      for (final t in realm.troops)
        UnitSnapshot(name: t.name, x: t.x, y: t.y, unitId: t.id),
    ];
  }
  state.activeWar = war;
  // §11.1: both sides are locked into one war per year — not just the attacker.
  state.realm(attackerSlot).warThisYear = true;
  state.realm(defenderSlot).warThisYear = true;
  // `[DESIGNED 2026-07-06, user-designed mechanic]` A war between two
  // HUMANS starts in a PREPARATION phase: both combatants choose (as a
  // `warPlan` decision) whether they command their side live or hand it to
  // the stance autopilot, and may re-set their units' stance. Live sides
  // may also propose duel start times (`war.planSlots`, 2026-07-08): the
  // earliest common proposal becomes the agreed start. The rounds begin
  // per `resolveWarPreparation`'s start rules (early start unless both
  // play live; online deadline = the agreed start, else half the turn
  // timer). Any other constellation starts the rounds immediately.
  if (state.dynasty(attackerSlot).status == DynastyStatus.human &&
      state.dynasty(defenderSlot).status == DynastyStatus.human) {
    war.phase = WarPhase.preparation;
    for (final (slot, role) in [
      (attackerSlot, 'attacker'),
      (defenderSlot, 'defender'),
    ]) {
      state.pendingDecisions.add(PendingDecision(
        id: 'warplan-$slot-${state.year}',
        type: 'warPlan',
        decidingSlot: slot,
        payload: {
          'attackerSlot': attackerSlot,
          'defenderSlot': defenderSlot,
          'role': role,
        },
      ));
    }
  } else {
    war.actingSlot = _firstHumanSide(state, war);
    _rollWarMoves(state, war, rng);
  }
  return war;
}

/// Ends the preparation phase: rolls the first round's movement allowance
/// and hands the input to the first (non-delegated) human side. No-op
/// outside the preparation phase.
void beginWarRounds(GameState state, Rng rng) {
  final war = state.activeWar;
  if (war == null || war.phase != WarPhase.preparation) return;
  war.phase = WarPhase.rounds;
  war.actingSlot = _firstHumanSide(state, war);
  _rollWarMoves(state, war, rng);
}

/// Whether [slot]'s war input is played by a human: a human dynasty that
/// has NOT delegated this war to the computer (`war.autoSlots`, the
/// `warDefense` decision). Delegated sides behave like AI sides — moved by
/// the stance autopilot, never awaited.
bool warSideIsHuman(GameState state, ActiveWar war, int slot) =>
    state.dynasty(slot).status == DynastyStatus.human &&
    !war.autoSlots.contains(slot);

/// The acting order of the CURRENT war round, `[DESIGNED 2026-07-19]`:
/// initiative alternates — the attacker opens the even rounds (round 0,
/// the declaration round, as in the original), the defender the odd ones.
/// Before, the attacker moved first in every one of the 20 rounds, which
/// summed to a real edge in human-vs-human wars (and decided the both-
/// occupy-capitals tie). ONE definition used by the round handover, the
/// acting-slot rolls, the AI movement order and the capital tie-break.
List<int> warRoundOrder(ActiveWar war) => war.round.isEven
    ? [war.attackerSlot, war.defenderSlot]
    : [war.defenderSlot, war.attackerSlot];

/// The first human war side in THIS round's initiative order
/// ([warRoundOrder]), or null in a pure AI (or fully delegated) war.
int? _firstHumanSide(GameState state, ActiveWar war) {
  for (final slot in warRoundOrder(war)) {
    if (warSideIsHuman(state, war, slot)) return slot;
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
  if (war.phase == WarPhase.preparation) {
    // Awaited is whoever still owes their warPlan answer (attacker first);
    // null once all have answered — the war then waits for its start
    // (early-start rules / the online deadline, `resolveWarPreparation`).
    for (final slot in [war.attackerSlot, war.defenderSlot]) {
      if (state.dynasty(slot).status == DynastyStatus.human &&
          state.pendingDecisions
              .any((d) => d.type == 'warPlan' && d.decidingSlot == slot)) {
        return slot;
      }
    }
    return null;
  }
  if (war.phase == WarPhase.settlement) {
    final winner = war.winnerSlot;
    return winner != null && warSideIsHuman(state, war, winner) ? winner : null;
  }
  final acting = war.actingSlot;
  if (acting != null && warSideIsHuman(state, war, acting)) {
    return acting;
  }
  return _firstHumanSide(state, war);
}

/// Human-vs-human round handover: the side that OPENED this round
/// ([warRoundOrder]) finishing their half passes the input to the other
/// human side instead of ending the round. Returns true when the handover
/// happened (the caller must NOT advance the round then). All other
/// constellations — AI opponent, the second side finishing — return
/// false: the round really ends.
bool handWarRoundOver(GameState state, int slot) {
  final war = state.activeWar;
  if (war == null || war.phase != WarPhase.rounds) return false;
  if (slot != warRoundOrder(war).first) return false;
  if (!warSideIsHuman(state, war, war.defenderSlot) ||
      !warSideIsHuman(state, war, war.attackerSlot)) {
    return false;
  }
  war.actingSlot = war.opponentOf(slot);
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
/// walking races to the capital. Every encounter here is DECIDED: the
/// side with the higher effective strength wins the clash.
///
/// `[BALANCE 2026-07-19, user-designed]` A unit's STRENGTH — men ×
/// per-man power (§10.1), exactly the number the client displays — is the
/// ONE base factor in combat. On top of it only these modifiers:
///  - fortification: +15% on an own Burg tile, +25% on a Palast;
///  - Artillerie besieges: a fortified ENEMY keeps only half its
///    fortification bonus against the guns, and the guns fire ×1.1 at it;
///  - Schere-Stein-Papier, ×1.15 against the countered class:
///    Infanterie schlägt Kavallerie, Kavallerie schlägt Artillerie,
///    Artillerie schlägt Infanterie;
///  - one shared fortune roll, [0.75, 1.25) vs its mirror — a ≥ 5/3×
///    effective advantage therefore wins EVERY clash.
///
/// Casualties follow the OPPONENT's effective strength (converted into
/// men via the casualty side's per-man power) — never a share of a unit's
/// own size, so chaff cannot strip fixed percentages off a giant:
///  - the loser loses 35–65% of what the winner's strength reaches
///    (a remnant under 5 men is wiped — no endless 1-man tail fights);
///  - the winner loses 10–25% of the loser's reach and always survives.
List<GameEvent> resolveCombat(
    GameState state, int slotA, Troop a, int slotB, Troop b, Rng rng) {
  bool fortified(Troop t) => switch (state.map.buildingAt(t.x, t.y)) {
        Building.burg || Building.palast => true,
        _ => false,
      };

  // Fortification bonus of the tile a unit stands on; Artillerie's guns
  // halve the enemy's bonus.
  double fortFactor(Troop t, Troop enemy) {
    final bonus = switch (state.map.buildingAt(t.x, t.y)) {
      Building.burg => 0.15,
      Building.palast => 0.25,
      _ => 0.0,
    };
    return 1 + (enemy.troopClass == TroopClass.artillerie ? bonus / 2 : bonus);
  }

  // Schere-Stein-Papier (×1.15 vs the countered class) plus the ×1.1
  // Artillerie siege bonus against a fortified enemy.
  double attackFactor(Troop t, Troop enemy) {
    const counters = [
      TroopClass.kavallerie, // Infanterie schlägt Kavallerie
      TroopClass.artillerie, // Kavallerie schlägt Artillerie
      TroopClass.infanterie, // Artillerie schlägt Infanterie
    ];
    var factor = counters[t.troopClass] == enemy.troopClass ? 1.15 : 1.0;
    if (t.troopClass == TroopClass.artillerie && fortified(enemy)) {
      factor *= 1.1;
    }
    return factor;
  }

  final r = rng.nextReal();
  final fortuneA = 0.75 + r / 2;
  final fortuneB = 1.25 - r / 2;
  final effA =
      troopStrength(a) * fortFactor(a, b) * attackFactor(a, b) * fortuneA;
  final effB =
      troopStrength(b) * fortFactor(b, a) * attackFactor(b, a) * fortuneB;
  final aWins = effA >= effB;
  final winner = aWins ? a : b;
  final loser = aWins ? b : a;
  final winnerEff = aWins ? effA : effB;
  final loserEff = aWins ? effB : effA;

  // The loser's casualties are what the WINNER's strength cuts down (its
  // reach in loser-quality men), the winner's what the loser's strength
  // still reaches. The winner always keeps ≥ 1 man — so exactly one side
  // can ever be wiped, never both.
  final loserShare = 0.35 + 0.3 * rng.nextReal();
  final winnerShare = 0.10 + 0.15 * rng.nextReal();
  var lossesLoser =
      math.max(1, (winnerEff * loserShare / powerPerMan(loser)).round());
  // A remnant under 5 men is wiped — no endless 1-man tail fights.
  if (loser.men - lossesLoser < 5) lossesLoser = loser.men;
  final lossesWinner = math.min(winner.men - 1,
      (loserEff * winnerShare / powerPerMan(winner)).round());

  final lossesA = aWins ? lossesWinner : lossesLoser;
  final lossesB = aWins ? lossesLoser : lossesWinner;

  final destroyedA = lossesA >= a.men;
  final destroyedB = lossesB >= b.men;
  _applyLosses(state, slotA, a, lossesA);
  _applyLosses(state, slotB, b, lossesB);

  // Running war tally for the end-of-war overview (events are transient);
  // the winner's tally also feeds the war score (`warScoreBattleBonus`).
  final war = state.activeWar;
  if (war != null && war.isParticipant(slotA) && war.isParticipant(slotB)) {
    war.battles++;
    war.attackerMenLost += slotA == war.attackerSlot ? lossesA : lossesB;
    war.defenderMenLost += slotA == war.attackerSlot ? lossesB : lossesA;
    final winnerSlot = aWins ? slotA : slotB;
    winnerSlot == war.attackerSlot
        ? war.attackerBattlesWon++
        : war.defenderBattlesWon++;
  }

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
        'attackerWon': aWins,
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
    final share = math.min(
        loser.treasury, loser.treasury * t1[building] * factor ~/ sum1);
    loser.treasury -= share;
    winner.treasury += share;
  }
  if (sum2 > 0) {
    // Clamp like the treasury share above: a high-value capital tile
    // (factor 2) can compute a share larger than the whole stock, which
    // would drive the loser's harvest negative.
    final grainShare = math.min(
        loser.grainHarvest, loser.grainHarvest * t2[building] * factor ~/ sum2);
    final cattleShare = math.min(loser.livestockHarvest,
        loser.livestockHarvest * t2[building] * factor ~/ sum2);
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
    // The lost garrison leaves the loser's garrison-counted units
    // (`armySize` follows the units by derivation).
    cutGarrisonTroops(loser, town.garrison);
    town.garrison = 0; // the defenders are gone with the realm
    winner.towns.add(town);
    winner.population += town.population;
    winner.troopCapacity += town.troopCapacity;
  }

  // Running war tally for the end-of-war overview.
  final war = state.activeWar;
  if (war != null &&
      war.isParticipant(winnerSlot) &&
      war.isParticipant(loserSlot)) {
    winnerSlot == war.attackerSlot
        ? war.attackerTilesTaken++
        : war.defenderTilesTaken++;
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
/// capital the higher war score wins (tie: whoever opened this round —
/// they moved first, [warRoundOrder]). Surfaced to the war UI ("end the
/// round to seal the victory").
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
    final first = warRoundOrder(war).first;
    final second = war.opponentOf(first);
    return warScore(state, second) > warScore(state, first) ? second : first;
  }
  if (attacker) return war.attackerSlot;
  if (defender) return war.defenderSlot;
  return null;
}

/// Whether [slot] occupies EVERY key point of [enemySlot]: each enemy
/// tile carrying a STRONGHOLD (Stadt, Burg, Palast) — and the enemy seat,
/// whatever stands there — holds at least one of [slot]'s units. Dörfer,
/// Märkte and Häfen are NOT key points (user rule 2026-07-13; they are
/// worth war-score points but need not be garrisoned), nor are fields
/// (Kornfeld/Weide) or bare land. Only this total occupation lets a ruler
/// capture take the WHOLE realm ([_endWarByCapitalOccupation]); a lone
/// capital capture wins on points (claim settlement). A rump state whose
/// only key point is its seat falls with that one tile.
bool occupiesAllKeyPoints(GameState state, int slot, int enemySlot) {
  final map = state.map;
  final troops = state.realm(slot).troops;
  bool occupied(int x, int y) => troops.any((t) => t.x == x && t.y == y);

  final enemy = state.realm(enemySlot);
  if (map.ownerAt(enemy.capitalX, enemy.capitalY) == enemySlot &&
      !occupied(enemy.capitalX, enemy.capitalY)) {
    return false;
  }
  for (var i = 0; i < map.terrain.length; i++) {
    if (map.owner[i] != enemySlot) continue;
    if (!Building.isSeat(map.building[i])) continue;
    if (!occupied(i % map.width, i ~/ map.width)) return false;
  }
  return true;
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
///
/// SMALL REALMS: a loser worth less than a single Burg (5,000) all told is
/// taken WHOLE — the cap only shields sizeable realms, so a tiny rump state
/// can always be finished off.
///
/// FLOOR: above that, a clear victory can still always claim at least the
/// single cheapest loser tile bordering the winner. Against a realm ground
/// down to a few cheap fragments the 50–80 % cap of the remaining value can
/// fall BELOW the cheapest tile, so the winner could take nothing of what
/// they fought for. The floor fixes that; the cap still keeps a sizeable
/// realm from being swallowed whole in one war.
int _cappedClaim(
    GameState state, int winnerSlot, int loserSlot, int claim, Rng rng) {
  final map = state.map;
  var total = 0;
  for (var i = 0; i < map.terrain.length; i++) {
    if (map.owner[i] == loserSlot) {
      total += settlementTileValue(state, map.building[i]);
    }
  }
  // A small realm — worth less than a single Burg (5,000) all told — can be
  // taken WHOLE: the anti-swallow cap only shields sizeable realms. Below
  // that the claim covers the loser's entire remaining territory, so a
  // victory is never left unable to finish off a tiny rump state.
  if (total < 5000) return total;
  final sharePercent = 50 + rng.nextInt(31);
  final capped = math.min(claim, total * sharePercent ~/ 100);
  final cheapestBorder =
      _cheapestBorderingLoserTile(state, winnerSlot, loserSlot);
  // The floor only restores what the anti-swallow CAP took away: a war
  // score that already earned the cheapest bordering tile stays claimable.
  // It must never lift a marginal score (e.g. 50) up to an expensive lone
  // border tile — the leftover claim is also payable in cash, so that
  // would extract 100× the earned score from the loser's treasury.
  if (cheapestBorder != null &&
      capped < cheapestBorder &&
      claim >= cheapestBorder) {
    return cheapestBorder;
  }
  return capped;
}

/// The lowest [settlementTileValue] among the loser's tiles that border the
/// winner's land (the only tiles the settlement can ever annex), or null
/// when the loser holds no bordering tile. Used to floor the war claim so a
/// victory is never too small to take a single remaining part.
int? _cheapestBorderingLoserTile(
    GameState state, int winnerSlot, int loserSlot) {
  final map = state.map;
  int? cheapest;
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.ownerAt(x, y) != loserSlot) continue;
      if (!_bordersTerritory(state, winnerSlot, x, y)) continue;
      final value = settlementTileValue(state, map.buildingAt(x, y));
      if (cheapest == null || value < cheapest) cheapest = value;
    }
  }
  return cheapest;
}

/// Ruler capture, resolved at ROUND END (§11.2): the captor holds the
/// enemy capital when the round ends. The captured ruler is coerced (§12).
/// The victory's SCOPE follows the occupation (user rule 2026-07-13):
///  - The captor occupies EVERY key point of the loser at that moment
///    ([occupiesAllKeyPoints]: all Stadt/Burg/Palast tiles, seat included
///    — several armies at work) → the loser's ENTIRE territory is annexed
///    into the captor's own realm, tile by tile through the §11.4 conquest
///    transfer — no claim settlement, no §19 ruler aliasing. The loser is
///    landless afterwards and the slot is vacated ([checkLandLoss]).
///  - Only the capital is held → the war is won on points: the captor
///    SELECTS loser tiles in the claim settlement, against a claim of
///    their war score (which includes the +3,000 capital bonus; capped —
///    see [_cappedClaim], but always at least the capital tile).
void _endWarByCapitalOccupation(
    GameState state, int captorSlot, Rng rng, List<GameEvent> events) {
  final war = state.activeWar!;
  final loserSlot = war.opponentOf(captorSlot);
  final loser = state.realm(loserSlot);
  final captor = state.realm(captorSlot);
  final capturedRuler = state.person(loser.rulerId);

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

  if (occupiesAllKeyPoints(state, captorSlot, loserSlot)) {
    // Total conquest (user rule 2026-07-13, replaces the §19 slot aliasing
    // of 2026-07-10): the loser's whole territory joins the WINNER'S realm
    // — the winner never "inherits" the loser's slot as a second realm to
    // play. Every tile moves through the §11.4 conquest transfer (towns,
    // population, treasury/harvest shares included); the per-tile
    // `tileConquered` events are discarded — the `warWon (conquered)`
    // event tells the story without ~50 feed lines of noise.
    final loserWasHuman =
        state.dynasty(loserSlot).status == DynastyStatus.human;
    final map = state.map;
    final discard = <GameEvent>[];
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) == loserSlot) {
          transferTile(state, x, y, captorSlot, discard);
        }
      }
    }
    // Land, towns and shares moved above; the leftover treasury and
    // harvest stock follow the conquered realm too. Debt is never
    // inherited (matches transferTile's rule).
    if (loser.treasury > 0) {
      captor.treasury += loser.treasury;
      loser.treasury = 0;
    }
    if (loser.grainHarvest > 0) {
      captor.grainHarvest += loser.grainHarvest;
      loser.grainHarvest = 0;
    }
    if (loser.livestockHarvest > 0) {
      captor.livestockHarvest += loser.livestockHarvest;
      loser.livestockHarvest = 0;
    }

    // Emitted AFTER the transfers so the summary's tile tally includes
    // the annexation sweep.
    events.add(GameEvent(
      year: state.year,
      slot: captorSlot,
      type: 'warWon',
      visibility: EventVisibility.public,
      payload: {
        'conquered': true,
        'loserSlot': loserSlot,
        'summary': war.summary(),
      },
    ));

    // The teardown vacates the landless loser (public `realmOverrun`
    // popup, checkLandLoss). The defeat reason is refined to
    // 'rulerCaptured' AFTER it (checkLandLoss stamps the generic
    // 'realmOverrun') — the ruler's capture is what actually fell the realm.
    _returnTroops(state, war, events);
    state.activeWar = null;
    if (loserWasHuman) state.humanLossReason = 'rulerCaptured';

    // The war state is gone before the coercion decisions land so their
    // prompts resolve outside any war screen. The Kurfürst strip already
    // happened in checkLandLoss, so only convert-or-die, forced marriage
    // and a Kaiser's abdication remain relevant here.
    if (capturedRuler != null) {
      runCoercion(state, captorSlot, capturedRuler, rng, events);
    }
    _surfaceMidTurnWin(state, captorSlot, events);
    return;
  }

  // The claim covers at least the loser's capital tile (overriding the
  // anti-swallow cap if needed): the captor held that very tile to win —
  // a quick war against a depleted enemy yields a tiny war score, and
  // the winner could otherwise never take the seat they conquered.
  final claim = math.max(
      _cappedClaim(
          state, captorSlot, loserSlot, warScore(state, captorSlot), rng),
      settlementTileValue(
          state, state.map.buildingAt(loser.capitalX, loser.capitalY)));
  events.add(GameEvent(
    year: state.year,
    slot: captorSlot,
    type: 'warWon',
    visibility: EventVisibility.public,
    payload: {
      'claim': claim,
      'loserSlot': loserSlot,
      'summary': war.summary(),
    },
  ));

  war.phase = WarPhase.settlement;
  war.winnerSlot = captorSlot;
  war.remainingClaim = claim;
  war.actingSlot = captorSlot; // the settlement awaits the winner

  if (capturedRuler != null) {
    runCoercion(state, captorSlot, capturedRuler, rng, events);
  }
  if (!warSideIsHuman(state, war, captorSlot)) {
    autoSettleClaim(state, rng, events);
  }
}

/// Advances a war round (§11.2): applies the AI peace placeholders,
/// checks mutual peace and winter, and otherwise rolls the next round.
/// (AI unit movement is NOT part of this function — drivers must go
/// through `endWarRoundFor`/`endWarRoundWithAi` in ai_turn.dart, which
/// run `runAiWarMovement` for the AI sides first.)
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

  // Both seats were repaired at startWar and nothing mid-war can strip a
  // seat tile (transfers only happen at settlement; plunder never touches
  // Stadt/Burg/Palast ownership), so the occupation check below always
  // finds two valid seats — no per-round re-repair needed.
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
  // pre-war spots). Delegated human sides negotiate like AI sides.
  for (final slot in [war.attackerSlot, war.defenderSlot]) {
    if (warSideIsHuman(state, war, slot)) continue;
    war.setWantsPeace(slot, _aiWantsPeace(state, war, slot));
  }

  // Winter fires when the 20th round ENDS (`round` is 0-based, so >= 19).
  // The war UI counts "Runde X/20", so the end must land on round 20, not
  // one round later.
  final winterReached = war.round >= 19;
  // Mutual peace takes precedence over winter: a peace BOTH sides agreed
  // to on the last round is still the negotiated white peace they were
  // promised (status quo ante) — not winter's score arbitration.
  if (war.attackerWantsPeace && war.defenderWantsPeace) {
    events.add(GameEvent(
      year: state.year,
      slot: 0,
      type: 'peaceAgreed',
      visibility: EventVisibility.public,
      participants: [war.attackerSlot, war.defenderSlot],
      payload: {'summary': war.summary()},
    ));
    _returnTroops(state, war, events);
    state.activeWar = null;
    return;
  }
  if (winterReached) {
    events.add(GameEvent(
      year: state.year,
      slot: 0,
      type: 'winterEndsWar',
      visibility: EventVisibility.public,
    ));
    resolveWarEnd(state, rng, events);
    return;
  }

  war.round++;
  war.attackerWantsPeace = false;
  war.defenderWantsPeace = false;
  // §11.5: every army may plunder once per round — new round, new budget.
  for (final slot in [war.attackerSlot, war.defenderSlot]) {
    for (final troop in state.realm(slot).troops) {
      troop.plunderedThisRound = false;
    }
  }
  // Every new round starts with the first human side in the NEW round's
  // initiative order — the round counter was just advanced, so
  // [warRoundOrder] already reflects the alternation.
  war.actingSlot = _firstHumanSide(state, war);
  _rollWarMoves(state, war, rng);
}

/// Pairs each troop with its snapshot: by STABLE UNIT ID first (the
/// identity that survives every list reshape), by name for legacy
/// snapshots without ids (pre-id saves, hand-built test units — names
/// repeat, so each snapshot is claimed at most once, in list order).
/// Entries are null for troops without a snapshot.
List<UnitSnapshot?> matchedSnapshots(
    List<Troop> troops, List<UnitSnapshot> snapshots) {
  final used = List<bool>.filled(snapshots.length, false);
  final result = List<UnitSnapshot?>.filled(troops.length, null);
  // Pass 1: stable ids.
  for (var t = 0; t < troops.length; t++) {
    final id = troops[t].id;
    if (id == 0) continue;
    for (var i = 0; i < snapshots.length; i++) {
      if (!used[i] && snapshots[i].unitId == id) {
        used[i] = true;
        result[t] = snapshots[i];
        break;
      }
    }
  }
  // Pass 2: legacy name matching for whatever has no id pairing.
  for (var t = 0; t < troops.length; t++) {
    if (result[t] != null) continue;
    for (var i = 0; i < snapshots.length; i++) {
      if (!used[i] &&
          snapshots[i].unitId == 0 &&
          snapshots[i].name == troops[t].name) {
        used[i] = true;
        result[t] = snapshots[i];
        break;
      }
    }
  }
  return result;
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
  // Home test: every unit stands on ITS OWN snapshotted pre-war position —
  // paired by stable unit id ([matchedSnapshots]; legacy snapshots without
  // ids pair by name).
  final matched = matchedSnapshots(realm.troops, snapshots);
  var allHome = true;
  for (var i = 0; i < realm.troops.length; i++) {
    final snapshot = matched[i];
    if (snapshot == null ||
        snapshot.x != realm.troops[i].x ||
        snapshot.y != realm.troops[i].y) {
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

/// War-score bonus per battle won (2026-07-19): ten won battles weigh
/// like an occupied Markt (2,500) — fighting well counts, but holding
/// valuable ground counts more.
const int warScoreBattleBonus = 250;

/// War-score bonus for standing on the enemy capital (§11.2, unchanged).
const int warScoreCapitalBonus = 3000;

/// §11.2 war score for a side, `[REWORKED 2026-07-19, user-designed]`:
/// "you get what you hold" — Σ `Building.value` over the DISTINCT enemy
/// tiles occupied by own units (a stack counts its tile once), plus
/// [warScoreCapitalBonus] for the enemy capital and [warScoreBattleBonus]
/// per battle won. The old formula multiplied average and unit strength
/// into the tile value — quadratic in army strength, so a big army was
/// rewarded twice (it wins the battles AND outscores per tile) and a
/// doomstack parked on one Kornfeld could outscore real conquest. Strength
/// now decides battles only; the score is denominated directly in tile
/// worth, so a claim reads as "what the winner actually held".
int warScore(GameState state, int slot) {
  final war = state.activeWar;
  if (war == null) return 0;
  final enemySlot = war.opponentOf(slot);
  final realm = state.realm(slot);
  final enemy = state.realm(enemySlot);

  var score = war.battlesWonBy(slot) * warScoreBattleBonus;
  final occupied = <int>{};
  for (final troop in realm.troops) {
    if (state.map.ownerAt(troop.x, troop.y) != enemySlot) continue;
    if (!occupied.add(state.map.index(troop.x, troop.y))) continue;
    score += Building.value[state.map.buildingAt(troop.x, troop.y)];
    if (troop.x == enemy.capitalX && troop.y == enemy.capitalY) {
      score += warScoreCapitalBonus;
    }
  }
  return score;
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
      payload: {'summary': war.summary()},
    ));
    _returnTroops(state, war, events);
    state.activeWar = null;
    return;
  }

  final winnerSlot =
      scoreAttacker > scoreDefender ? war.attackerSlot : war.defenderSlot;
  final loserSlot = war.opponentOf(winnerSlot);
  final claim = _cappedClaim(state, winnerSlot, loserSlot,
      math.max(scoreAttacker, scoreDefender), rng);

  events.add(GameEvent(
    year: state.year,
    slot: winnerSlot,
    type: 'warWon',
    visibility: EventVisibility.public,
    payload: {
      'claim': claim,
      'loserSlot': loserSlot,
      'summary': war.summary(),
    },
  ));

  // Victory → claim settlement: the winner chooses which tiles to take
  // (humans tap, AIs auto-settle).
  war.phase = WarPhase.settlement;
  war.winnerSlot = winnerSlot;
  war.remainingClaim = claim;
  war.actingSlot = winnerSlot; // the settlement awaits the winner
  if (!warSideIsHuman(state, war, winnerSlot)) {
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

/// Auto-annex pass over the open settlement, `[REWORKED 2026-07-19, user
/// request]`: a WAVE from the winner's border. The loser tiles adjacent
/// to the winner's land are seeded in reading order (top-left → bottom-
/// right), then processed breadth-first — every annexed tile extends the
/// wave to its loser-owned neighbors, so a PARTIAL claim grows one
/// compact, connected area from the border instead of scattering (the
/// old pass re-scanned the whole map in index order after each annex).
/// An unaffordable tile simply stops the wave there: the tiles behind it
/// are unreachable anyway (annexes must border winner land), and the
/// claim only shrinks, so a skipped tile can never become affordable
/// later. Shared by the AI auto-settle and the client's auto-annex
/// button ("Ganzes Land übernehmen" / "Auto-Annexion",
/// `SettlementTakeAll`).
void annexAffordableTiles(GameState state, List<GameEvent> events) {
  final war = state.activeWar!;
  final winnerSlot = war.winnerSlot!;
  final loserSlot = war.opponentOf(winnerSlot);
  final map = state.map;

  final queued = List<bool>.filled(map.terrain.length, false);
  final queue = <int>[];
  // Seed: every loser tile on the winner's border, in reading order.
  for (var i = 0; i < map.terrain.length; i++) {
    if (map.owner[i] != loserSlot) continue;
    if (_bordersTerritory(state, winnerSlot, i % map.width, i ~/ map.width)) {
      queued[i] = true;
      queue.add(i);
    }
  }
  for (var head = 0; head < queue.length; head++) {
    final i = queue[head];
    final x = i % map.width;
    final y = i ~/ map.width;
    final value = settlementTileValue(state, map.building[i]);
    if (value > war.remainingClaim) continue; // the wave breaks here
    transferTile(state, x, y, winnerSlot, events);
    war.remainingClaim -= value;
    // The annexed tile carries the wave to its loser-owned neighbors —
    // enqueued only now, so they are guaranteed to border winner land.
    for (final (nx, ny) in map.neighborsOf(x, y)) {
      final ni = map.index(nx, ny);
      if (!queued[ni] && map.owner[ni] == loserSlot) {
        queued[ni] = true;
        queue.add(ni);
      }
    }
  }
}

/// §11.2 claim settlement, AI path `[APPROX]`: greedily annex affordable
/// loser tiles adjacent to own land, then take the remainder in cash.
void autoSettleClaim(GameState state, Rng rng, List<GameEvent> events) {
  annexAffordableTiles(state, events);
  finishSettlement(state, rng, events);
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
void finishSettlement(GameState state, Rng rng, List<GameEvent> events) {
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
  // The settlement routinely annexes the loser's capital tile (a capital
  // occupation even forces it into the claim). Repair the seat NOW, not at
  // the next year start: the map flag stays correct and a follow-up war
  // the same year finds a valid seat. A human loser with an eligible tile
  // keeps the manual choice (relocateCapital decision); the teardown's
  // stranded-troop re-homing then still falls back to an owned tile.
  ensureRealmSeat(state, loserSlot, rng, events);
  // Teardown: troops return home (annexed snapshot tiles fall back to
  // owned ground) and a landless loser is vacated.
  _returnTroops(state, war, events);
  state.activeWar = null;
  _surfaceMidTurnWin(state, winnerSlot, events);
}

/// A war that overruns the last rival leaves the winner as sole ruler.
/// Surface the victory the instant the enemy's land is gone — for a HUMAN
/// winner, so the popup appears right after the war instead of only at
/// their next "Zug beenden". AI-vs-AI victories resolve at the normal
/// end-of-turn win check (completeTurn); a war can only ever annex tiles
/// here (settlement or total conquest), so these are the mid-turn paths
/// that can produce a sole ruler.
void _surfaceMidTurnWin(
    GameState state, int winnerSlot, List<GameEvent> events) {
  if (state.dynasty(winnerSlot).status == DynastyStatus.human &&
      !state.events.any((e) => e.type == 'gameWon') &&
      !events.any((e) => e.type == 'gameWon')) {
    final champion = checkWinCondition(state);
    if (champion != null) {
      events.add(GameEvent(
        year: state.year,
        slot: champion,
        type: 'gameWon',
        visibility: EventVisibility.public,
      ));
    }
  }
}

/// War teardown, run exactly once by every war-ending path (peace, draw,
/// winter settlement, total conquest): every surviving unit returns to its
/// snapshotted pre-war position (§11.2) — clamped to still-owned ground,
/// since a snapshot tile may have been annexed in the settlement — and a
/// landless side is vacated ([checkLandLoss]; since 2026-07-19 plunder
/// only devastates fields instead of erasing them, so mid-war land loss
/// can no longer happen — the check still guards the settlement paths).
void _returnTroops(GameState state, ActiveWar war, List<GameEvent> events) {
  final map = state.map;
  for (final slot in [war.attackerSlot, war.defenderSlot]) {
    final realm = state.realm(slot);
    final snapshots = war.snapshots[slot] ?? const [];
    final matched = matchedSnapshots(realm.troops, snapshots);
    int? homeX, homeY; // lazily resolved fallback for lost snapshot tiles
    for (var i = 0; i < realm.troops.length; i++) {
      final snapshot = matched[i];
      final x = snapshot?.x ?? realm.troops[i].x;
      final y = snapshot?.y ?? realm.troops[i].y;
      if (map.ownerAt(x, y) == realm.slot) {
        realm.troops[i].x = x;
        realm.troops[i].y = y;
        continue;
      }
      // Home base gone: the capital, or the first owned tile when the
      // capital itself was lost. A landless realm keeps positions as they
      // are — checkLandLoss below clears its troops anyway.
      if (homeX == null) {
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
        if (homeX == null) break;
      }
      realm.troops[i].x = homeX;
      realm.troops[i].y = homeY!;
    }
    checkLandLoss(state, realm, events);
  }
  state.rebuildTroopMarkers();
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
/// it to AI control, and `advanceUntilHuman` fires `humansDefeated`. It
/// would ALSO keep [checkWinCondition] from ever firing — a landless rival
/// counts as a living ruler, so the last player standing never "owns
/// everything". Called at every cause of land loss: the war teardown
/// (`_returnTroops` — settlement and conquest; plunder no longer destroys
/// tiles since 2026-07-19), the earthquake and the bankruptcy seizure.
/// No-op for a realm that still owns land or is already vacant, so
/// repeated calls are safe.
void checkLandLoss(GameState state, Realm loser, List<GameEvent> events) {
  if (loser.isVacant) return;
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
  state.noteHumanSeatLost(loser.slot, 'realmOverrun');
  dynasty.status = DynastyStatus.ai;
  dynasty.humanPlayer = null;
  state.rebuildTroopMarkers();
}

/// Minimum unit strength to plunder at all (2026-07-19): 1 — ten regular
/// levies. Splitting an army into 1-man chaff used to multiply plunder
/// (each splinter counts as its own "army" for §11.5's once-per-round).
const double minPlunderStrength = 1;

/// Plunder reach per point of unit strength (2026-07-19): loot caps at
/// 10 T × strength, killed civilians and burned quarters at 5 × strength.
/// A 100-man regular unit (strength 10) loots up to 100 T and kills up to
/// 50 — a real army sacks a town, a splinter merely raids it.
const int plunderLootPerStrength = 10;
const int plunderKillsPerStrength = 5;

/// How long a plundered Kornfeld/Weide lies fallow (2026-07-19): the
/// plunder year plus two more; it yields again in year + 3.
const int fieldDevastationYears = 3;

/// §11.5 plunder during war rounds, once per ARMY per round (the per-unit
/// flag lives on [Troop.plunderedThisRound], checked in `applyWarPlunder`).
///
/// `[BALANCE 2026-07-19, user-designed]` Plunder scales with the acting
/// [unit]'s strength ([minPlunderStrength], [plunderLootPerStrength]) —
/// before, a 1-man splinter looted and razed like a full army, so chaff
/// spam out-plundered real conquest. And fields are DEVASTATED, not
/// erased: the tile keeps owner and building but yields nothing until
/// [fieldDevastationYears] have passed (`WorldMap.devastatedUntil`) —
/// before, every plundered field fell to no-man's-land forever, so wars
/// permanently shrank the world even when they ended in a white peace.
List<GameEvent> plunderTile(
    GameState state, int plundererSlot, int x, int y, Troop unit, Rng rng) {
  final map = state.map;
  final building = map.buildingAt(x, y);
  final victimSlot = map.ownerAt(x, y);
  if (victimSlot == World.niemand) {
    // An ownerless building has no victim to plunder.
    throw ActionException('Hier steht doch gar nichts !');
  }
  final strength = troopStrength(unit);
  if (strength < minPlunderStrength) {
    throw ActionException('Diese Truppe ist zum Plündern zu schwach !');
  }
  final plunderer = state.realm(plundererSlot);
  final victim = state.realm(victimSlot);
  final events = <GameEvent>[];
  final lootCap = (strength * plunderLootPerStrength).round();
  final killCap = (strength * plunderKillsPerStrength).round();

  // Result numbers for the event payload (the client's battle report).
  var loot = 0;
  var killed = 0;
  var devastated = false;

  switch (building) {
    case Building.kornfeld || Building.weide:
      map.devastatedUntil[map.index(x, y)] =
          state.year + fieldDevastationYears;
      devastated = true;
    case Building.dorf || Building.markt || Building.stadt:
      final town = victim.townAt(x, y);
      // Every town tile has a town object; the assert surfaces a map/town
      // desync in debug and tests. In release nothing is plundered rather
      // than crashing mid-war.
      assert(town != null, 'town tile ($x,$y) has no town object');
      if (town != null) {
        killed = rng.nextInt(math.min(town.population ~/ 2, killCap) + 1);
        loot = rng.nextInt(math.min(town.population, lootCap) + 1);
        // Only FREE quarters burn (capacity above the garrison). The
        // difference can be briefly negative between a population shrink
        // (capacity follows at ¼ rate) and the next §8.3 normalization —
        // the min/max clamps that to a no-op.
        final capacityCut = rng.nextInt(math.max(
                0, math.min(town.troopCapacity - town.garrison, killCap)) +
            1);
        plunderer.treasury += loot; // victim's treasury is NOT touched
        town.population -= killed;
        victim.population -= killed;
        if (capacityCut > 0) {
          town.troopCapacity -= capacityCut;
          victim.troopCapacity -= capacityCut;
        }
      }
    case Building.burg || Building.palast || Building.hafen:
      loot = victim.treasury > 0
          ? rng.nextInt(math.min(victim.treasury, lootCap) + 1)
          : 0;
      victim.treasury -= loot;
      plunderer.treasury += loot;
  }

  // Running war tally for the end-of-war overview.
  final war = state.activeWar;
  if (war != null && war.isParticipant(plundererSlot)) {
    plundererSlot == war.attackerSlot
        ? war.attackerLoot += loot
        : war.defenderLoot += loot;
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
      // Key kept as 'destroyed' for older readers; since 2026-07-19 it
      // means "field devastated" (recovers in 'recoversIn' years).
      'destroyed': devastated,
      if (devastated) 'recoversIn': fieldDevastationYears,
    },
  ));
  return events;
}
