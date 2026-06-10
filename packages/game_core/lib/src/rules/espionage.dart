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

/// Fuzzes a spied value ±10% uniform — never show exact numbers
/// (§13.2 `[APPROX]`, adopted as final design).
int fuzz(int value, Rng rng) =>
    (value * (0.9 + rng.nextReal() * 0.2)).round();

/// §13.1/§13.2 economy intel mission. Writes an [IntelReport] on success.
List<GameEvent> runEconomyMission(GameState state, Realm spy, Realm target,
    int agents, Rng rng) {
  final defense = target.guardLevel;
  final caught = math.min(defense, rng.nextInt(2 * defense + 2));
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

/// §13.1/§13.2 military intel: a single check reveals the troop list.
List<GameEvent> runMilitaryMission(GameState state, Realm spy, Realm target,
    int agents, Rng rng) {
  final defense = target.guardLevel;
  final caught = math.min(defense, rng.nextInt(2 * defense + 5));
  final survivors = math.min(agents - caught, 49);
  if (survivors <= 0 || rng.nextInt(math.max(0, 50 - survivors)) >= 15) {
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

GameEvent _missionFailed(
        GameState state, Realm spy, Realm target, String kind, int caught) =>
    GameEvent(
      year: state.year,
      slot: spy.slot,
      type: 'missionFailed',
      visibility: EventVisibility.owner,
      payload: {'targetSlot': target.slot, 'kind': kind, 'caught': caught},
    );

/// §13.3 assassination resolution (queued orders run in the event phase).
/// On failure the sponsor is publicly named. NOT suppressed by the
/// protect-new-players rule — it is a deliberate action.
void resolveAssassinations(GameState state, int targetSlot, Rng rng,
    List<GameEvent> events) {
  final orders = state.assassinationOrders
      .where((o) => o.targetSlot == targetSlot)
      .toList();
  if (orders.isEmpty) return;
  state.assassinationOrders
      .removeWhere((o) => o.targetSlot == targetSlot);

  for (final order in orders) {
    final target = state.realm(targetSlot);
    final victim = state.person(target.rulerId);
    if (victim == null) continue;

    final g = 2 * target.guardLevel;
    final caught = math.min(rng.nextInt(g + 15), order.count);
    final survivors = math.min(order.count - caught, 49);
    final success = rng.nextInt(math.max(1, 50 - survivors)) < 15;

    if (success) {
      events.add(GameEvent(
        year: state.year,
        slot: targetSlot,
        type: 'assassination',
        visibility: EventVisibility.public,
        payload: {'victim': victim.name},
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
void queueAssassination(
    GameState state, int sponsorSlot, int targetSlot, int agents) {
  for (final order in state.assassinationOrders) {
    if (order.sponsorSlot == sponsorSlot &&
        order.targetSlot == targetSlot) {
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
