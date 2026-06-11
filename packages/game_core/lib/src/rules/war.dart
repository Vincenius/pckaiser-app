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

/// Per-tile combat between two opposing units. Returns the events.
///
/// [DEVIATION from §11.3] The original's formula made tile defense
/// MULTIPLY the occupant's own losses (a Burg tripled your casualties)
/// and open ground meant zero casualties ever — wars degenerated into
/// walking races to the capital. The clone keeps the §10.1 power values
/// and the one-roll-per-encounter shape, but losses now scale with the
/// OPPONENT's power and are divided by the defender's tile defense:
///
///   losses_side = round(P_opponent × R / (2 × (1 + def_side)))
///
/// Rules < v5 keep a single `RandomReal` roll R ∈ [0, 1) per encounter
/// (battles typically killed 0–3 men, so wars dragged on forever). Rules
/// v5 decide each encounter: the side with the higher effective strength
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

  final defenseA = defense(a);
  final defenseB = defense(b);
  final r = rng.nextReal();
  final powerA = (a.men * (3 * a.troopClass + a.quality) / 10).floor();
  final powerB = (b.men * (3 * b.troopClass + b.quality) / 10).floor();
  int lossesA;
  int lossesB;

  if (state.rulesVersion >= 5) {
    final effA = powerA * (1 + defenseA / 2) * (0.5 + r);
    final effB = powerB * (1 + defenseB / 2) * (1.5 - r);
    final loserShare = 0.35 + 0.3 * rng.nextReal();
    final winnerShare = 0.10 + 0.15 * rng.nextReal();
    int loserLosses(int men) {
      final losses = math.max(1, (men * loserShare).round());
      // A remnant under 5 men is wiped — no endless 1-man tail fights.
      return men - losses < 5 ? men : losses;
    }

    int winnerLosses(int men) =>
        math.min(men - 1, (men * winnerShare).round());

    if (effA >= effB) {
      lossesA = winnerLosses(a.men);
      lossesB = loserLosses(b.men);
    } else {
      lossesA = loserLosses(a.men);
      lossesB = winnerLosses(b.men);
    }
  } else {
    lossesA =
        math.min(a.men, (powerB * r / (2 * (1 + defenseA))).round());
    lossesB =
        math.min(b.men, (powerA * r / (2 * (1 + defenseB))).round());
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
    // Rules v2: the lost garrison also leaves the loser's garrison-counted
    // units — v1 cut only `armySize` and let unit men drift out of sync.
    if (state.rulesVersion >= 2) {
      cutGarrisonTroops(loser, town.garrison);
    }
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

/// Ruler capture under rules < v9 (§11.2): the capturer takes over the
/// loser's entire realm, then post-war coercion (§12). From v9 on the
/// capture resolves at round end via [_endWarByCapitalOccupation]
/// instead — coercion still fires, but the winner selects tiles in the
/// claim settlement rather than swallowing the realm.
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
  dyn.alignSlotControl(state, loserSlot, captor.rulerId);
  _returnTroops(state, war, events);
  state.activeWar = null;

  if (capturedRuler != null) {
    runCoercion(state, captorSlot, capturedRuler, rng, events);
  }
}

/// §12 post-war coercion, checked in order. Convert-or-die and forced
/// marriage exclude each other (religions differ vs. match); Kaiser
/// abdication and the Kurfürst seat strip are independent checks on top.
/// Rules v10 fires every applicable option like the original ("prompt per
/// applicable option"); earlier rules fired only the first. AI victors
/// auto-execute; a human victor gets one `coercion` decision per option
/// (default: apply). A human loser facing convert-or-die gets their own
/// decision; an AI loser flips a coin.
void runCoercion(GameState state, int victorSlot, Person capturedRuler,
    Rng rng, List<GameEvent> events) {
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
  if (state.rulesVersion < 10 && options.length > 1) {
    options.removeRange(1, options.length); // pre-v10: first option only
  }

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
    // Rules v10: like every other conversion, the dynasty's home realm
    // switches onto the right title ladder (§4/§16.1) and religiously
    // incompatible marriages dissolve (§14.4). Only the HOME slot's
    // ladder switches: the promotion check (§16.2) keys the ladder off
    // the slot dynasty's religion, so an aliased realm (ruled by a
    // member of this dynasty but belonging to an unconverted slot
    // dynasty) must keep its ladder — switching it would strand the
    // title where its own ladder never promotes.
    if (state.rulesVersion >= 10) {
      switchTitleLadder(state.realm(dynasty.index), religion);
      dyn.divorceIncompatibleCouples(state, dynasty.index, events);
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
    return warScore(state, war.defenderSlot) >
            warScore(state, war.attackerSlot)
        ? war.defenderSlot
        : war.attackerSlot;
  }
  if (attacker) return war.attackerSlot;
  if (defender) return war.defenderSlot;
  return null;
}

/// Rules v9 ruler capture, resolved at ROUND END (was: instantly on the
/// move): the captor holds the enemy capital when the round ends. The
/// loser's ruler is captured and coerced (§12), but the realm is no
/// longer swallowed whole — instead the captor wins the war and SELECTS
/// loser tiles in the claim settlement, against a claim of their war
/// score (which includes the +3,000 capital bonus).
void _endWarByCapitalOccupation(GameState state, int captorSlot, Rng rng,
    List<GameEvent> events) {
  final war = state.activeWar!;
  final loserSlot = war.opponentOf(captorSlot);
  final capturedRuler = state.person(state.realm(loserSlot).rulerId);
  final claim = warScore(state, captorSlot);

  events.add(GameEvent(
    year: state.year,
    slot: captorSlot,
    type: 'rulerCaptured',
    visibility: EventVisibility.public,
    payload: {'loserSlot': loserSlot, 'ruler': capturedRuler?.name},
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
/// Rules v9: before anything else, a side holding the enemy capital wins
/// the war right here (see [_endWarByCapitalOccupation]). Rules v11
/// tightens this to holding it across TWO consecutive round ends — i.e.
/// through the opponent's full response round (the v9 check ran after the
/// AI side's movement, so an AI seizing the capital won before its human
/// opponent could ever react). The first round end only ARMS the capture
/// (`war.heldCapitalSlot`, `capitalHeld` event); an opponent with no
/// troops left cannot respond, so the capture resolves immediately.
void endWarRound(GameState state, Rng rng, List<GameEvent> events) {
  final war = state.activeWar;
  if (war == null || war.phase != WarPhase.rounds) return;

  if (state.rulesVersion >= 9) {
    final captor = capitalOccupier(state, war);
    if (captor != null &&
        (state.rulesVersion < 11 ||
            captor == war.heldCapitalSlot ||
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
  }

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
    } else if (state.rulesVersion >= 5) {
      // Rules v5: a NEGOTIATED peace is a white peace — status quo ante,
      // nobody gains tiles or money (under v1–v4 rules the leading side
      // still collected its full claim, so agreeing to peace could lose
      // you land). Only a winter-forced end goes to score arbitration.
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
  _rollWarMoves(state, war, rng);
}

/// Pairs each troop with a distinct snapshot of the same name, in list
/// order. Units are snapshotted by name only, and names repeat (every AI
/// recruit is "Rekruten") — naive name lookup would match every duplicate
/// to the FIRST snapshot. Entries are null for troops without a snapshot
/// (e.g. merged in mid-war under pre-v4 rules).
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

  // Rules < v5: a decisive score auto-converts every occupied tile. From
  // v5 on EVERY victory opens the claim settlement instead — the winner
  // chooses which tiles to take (humans tap, AIs auto-settle).
  if (state.rulesVersion < 5 && claim >= (loserValue * 0.4).round()) {
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

  // Victory → claim settlement.
  war.phase = WarPhase.settlement;
  war.winnerSlot = winnerSlot;
  war.remainingClaim = claim;
  if (state.dynasty(winnerSlot).status != DynastyStatus.human) {
    autoSettleClaim(state, rng, events);
  }
}

/// What a loser tile costs against the settlement claim. Rules v2: bare
/// land (building value 0) costs 100 T like a Kornfeld — under v1 rules
/// value-0 tiles were free, so any limited victory could strip the loser
/// of every reachable empty tile without spending the claim.
int settlementTileValue(GameState state, int building) {
  final value = Building.value[building];
  if (value == 0 && state.rulesVersion >= 2) return 100;
  return value;
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
        final value = settlementTileValue(state, map.buildingAt(x, y));
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
