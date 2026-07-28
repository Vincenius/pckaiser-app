import 'dart:math' as math;

import '../rng/rng.dart';
import '../state/chronicle.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/intel_report.dart';
import '../state/realm.dart';
import 'dynasty.dart' as dyn;

/// Guard level hard cap (§13): "Das ist keine Spionageabwehr, sondern eine
/// Armee !!!"
const int guardCap = 50;

/// Mission costs per agent (§13).
const int economySpyCost = 200;
const int militarySpyCost = 200;
const int assassinCost = 250;
const int guardCost = 100;

/// Largest squad per mission (§13): "So viele Spione würden zu sehr
/// auffallen" — shared by the spy/assassination action gates and the AI's
/// squad sizing.
const int maxAgentsPerMission = 30;

/// The mission ladder `[DESIGNED]`, easiest first — every chance below is
/// rolled on a 0–99 scale against these ceilings:
///
/// 1. **Wirtschaftsspionage** — what the markets and tax collectors
///    already gossip about; a full squad brings the headline numbers home
///    near-certainly (per-value checks in [runEconomyMission]).
/// 2. **Militärspionage** — counting tents in an open camp: up to
///    [militaryIntelMaxChance] with a full squad, ~50 % with ten agents.
/// 3. **Attentat** — reaching a ruler behind his own walls and bodyguard.
///    A full squad at an open court is a bit better than a coin flip
///    (~53 %, ceiling [assassinationMaxChance]) and still a real threat
///    against a maxed Leibwache (~36 %) — but never the reliable way to
///    remove a rival. Guards work twice: they catch agents on the way in
///    (the bulk of their effect) and shield the ruler
///    ([assassinationCeiling]).
const int militaryIntelMaxChance = 90;
const int assassinationMaxChance = 60;

/// Ceiling for an attempt on a court holding [guardLevel] guards: from
/// [assassinationMaxChance] on an unguarded ruler down to 50 % at the
/// [guardCap]. The guards' main defense is catching agents before the
/// deed; this ceiling is the extra shield of a ruler who never walks
/// alone.
int assassinationCeiling(int guardLevel) =>
    assassinationMaxChance - guardLevel ~/ 5;

/// Fuzzes a spied value ±10% uniform — never show exact numbers
/// (§13.2 `[APPROX]`, adopted as final design).
int fuzz(int value, Rng rng) => (value * (0.9 + rng.nextReal() * 0.2)).round();

/// `[DESIGNED]` deviation from the traced §13.1 roll: the defense
/// catches at most a random share of the agents sent —
/// `min(defenseRoll, random(agents+1))`. With the raw defense roll a
/// rich AI's 50 guards wiped ~70% of missions outright, so sending more
/// agents barely helped and espionage was effectively unplayable.
int _caughtAgents(GameState state, int defenseRoll, int agents, Rng rng) =>
    math.min(math.min(defenseRoll, agents), rng.nextInt(agents + 1));

/// §13.1/§13.2 economy intel mission. Writes an [IntelReport] on success.
List<GameEvent> runEconomyMission(
    GameState state, Realm spy, Realm target, int agents, Rng rng) {
  final defense = target.guardLevel;
  final caught = _caughtAgents(
      state, math.min(defense, rng.nextInt(2 * defense + 2)), agents, rng);
  final survivors = math.min(agents - caught, 99);
  if (survivors <= 0) {
    return [_missionFailed(state, spy, target, 'economy', caught)];
  }

  bool check(int n, int threshold) =>
      rng.nextInt(math.max(0, n - survivors)) <= threshold;

  final values = <String, int>{};
  if (check(55, 50)) values['treasury'] = fuzz(target.treasury, rng);
  if (check(55, 30)) values['grainStock'] = fuzz(target.grainHarvest, rng);
  if (check(55, 30)) {
    values['livestockStock'] = fuzz(target.livestockHarvest, rng);
  }
  if (check(60, 20)) {
    values['armySize'] = fuzz(target.armySize, rng);
    values['population'] = fuzz(target.population, rng);
  }
  if (check(60, 5)) values['guardLevel'] = fuzz(target.guardLevel, rng);

  if (values.isEmpty) {
    return [_missionFailed(state, spy, target, 'economy', caught)];
  }
  spy.intelReports.add(IntelReport(
    targetSlot: target.slot,
    year: state.year,
    values: values,
  ));
  return [
    GameEvent(
      year: state.year,
      slot: spy.slot,
      type: 'intelGathered',
      visibility: EventVisibility.owner,
      payload: {'targetSlot': target.slot, 'kind': 'economy', ...values},
    ),
  ];
}

/// §13.1/§13.2 military intel: a single check reveals the troop list;
/// success scales with the surviving agents `[DESIGNED]`.
List<GameEvent> runMilitaryMission(
    GameState state, Realm spy, Realm target, int agents, Rng rng) {
  final defense = target.guardLevel;
  final caught = _caughtAgents(
      state, math.min(defense, rng.nextInt(2 * defense + 5)), agents, rng);
  final survivors = math.min(agents - caught, 49);
  // Rung 2 of the ladder: 34 % with a lone survivor, ~50 % with ten,
  // topping out at [militaryIntelMaxChance] from ~15 agents on.
  final success = survivors > 0 &&
      rng.nextInt(100) <
          math.min(militaryIntelMaxChance, 30 + 4 * survivors);
  if (!success) {
    return [_missionFailed(state, spy, target, 'military', caught)];
  }

  final values = <String, int>{
    'unitCount': target.troops.length,
    'armySize': fuzz(target.armySize, rng),
    'guardLevel': fuzz(target.guardLevel, rng),
  };
  for (var i = 0; i < target.troops.length; i++) {
    values['unit${i}Men'] = fuzz(target.troops[i].men, rng);
    values['unit${i}Class'] = target.troops[i].troopClass;
    // Unit positions as of the spy year — the client renders the spied
    // army on the map as a faded snapshot.
    values['unit${i}X'] = target.troops[i].x;
    values['unit${i}Y'] = target.troops[i].y;
  }
  spy.intelReports.add(IntelReport(
    targetSlot: target.slot,
    year: state.year,
    values: values,
  ));
  return [
    GameEvent(
      year: state.year,
      slot: spy.slot,
      type: 'intelGathered',
      visibility: EventVisibility.owner,
      payload: {'targetSlot': target.slot, 'kind': 'military'},
    ),
  ];
}

/// Failed mission event. With caught agents the target learns the
/// sponsor — "Einer von ihnen gesteht unter Folter, aus `<X>` geschickt
/// worden zu sein !!!" (the §13.3 wording, applied to intel missions as
/// well `[DESIGNED]`: guards that catch spies must tell their realm).
GameEvent _missionFailed(
        GameState state, Realm spy, Realm target, String kind, int caught) =>
    GameEvent(
      year: state.year,
      slot: spy.slot,
      type: 'missionFailed',
      visibility:
          caught > 0 ? EventVisibility.participants : EventVisibility.owner,
      participants: caught > 0 ? [spy.slot, target.slot] : const [],
      payload: {'targetSlot': target.slot, 'kind': kind, 'caught': caught},
    );

/// §13.3 assassination resolution (queued orders run in the event phase).
/// On failure the sponsor is publicly named. NOT suppressed by the
/// protect-new-players rule — it is a deliberate action.
void resolveAssassinations(
    GameState state, int targetSlot, Rng rng, List<GameEvent> events) {
  final orders = state.assassinationOrders
      .where((o) => o.targetSlot == targetSlot)
      .toList();
  if (orders.isEmpty) return;
  state.assassinationOrders.removeWhere((o) => o.targetSlot == targetSlot);

  for (final order in orders) {
    final target = state.realm(targetSlot);
    final victim = state.person(target.rulerId);
    if (victim == null) continue;

    final g = 2 * target.guardLevel;
    final caught = _caughtAgents(
        state, math.min(rng.nextInt(g + 15), order.count), order.count, rng);
    final survivors = math.min(order.count - caught, 49);
    // Rung 3 of the ladder — the hard one. Like the spy missions an
    // attempt whose agents were ALL caught fails outright, and success
    // scales with the survivors, but every attempt stays a gamble:
    // ~11 % for five knifemen, ~53 % for a full squad at an open court,
    // ~36 % once 50 Leibwachen stand in the way `[DESIGNED]`.
    final success = survivors > 0 &&
        rng.nextInt(100) <
            math.min(assassinationCeiling(target.guardLevel),
                6 + 2 * survivors);

    if (success) {
      events.add(GameEvent(
        year: state.year,
        slot: targetSlot,
        type: 'assassination',
        visibility: EventVisibility.public,
        payload: {'victim': victim.name},
      ));
      // The sponsor's private confirmation (drama popup): the public
      // announcement above stays anonymous, so this one is owner-only.
      events.add(GameEvent(
        year: state.year,
        slot: order.sponsorSlot,
        type: 'assassinationSucceeded',
        visibility: EventVisibility.owner,
        payload: {'victim': victim.name, 'targetSlot': targetSlot},
      ));
      dyn.handleDeath(state, victim, rng, events);
    } else {
      // "Einer von ihnen gesteht unter Folter, aus <Sponsor> geschickt
      // worden zu sein !!!"
      events.add(GameEvent(
        year: state.year,
        slot: targetSlot,
        type: 'assassinationFailed',
        visibility: EventVisibility.public,
        payload: {
          'victim': victim.name,
          'caught': caught,
          'sponsorSlot': order.sponsorSlot,
        },
      ));
    }
  }
}

/// Queues an assassination order (§13.3): "Die Attentäter sind auf dem
/// Weg !!!"
///
/// Merging into an existing order is only a safety net: the action gate
/// allows one attempt per sponsor per target and round
/// (`Realm.assassinatedThisTurnSlots`), so a sponsor cannot stack squads
/// past [maxAgentsPerMission] any more.
void queueAssassination(
    GameState state, int sponsorSlot, int targetSlot, int agents) {
  for (final order in state.assassinationOrders) {
    if (order.sponsorSlot == sponsorSlot && order.targetSlot == targetSlot) {
      order.count += agents;
      return;
    }
  }
  state.assassinationOrders.add(AssassinationOrder(
    sponsorSlot: sponsorSlot,
    targetSlot: targetSlot,
    count: agents,
  ));
}
