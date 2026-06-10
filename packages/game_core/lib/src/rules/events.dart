import 'dart:math' as math;

import '../data/tables.dart';
import '../rng/rng.dart';
import '../state/constants.dart';
import '../state/dynasty.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/person.dart';
import '../state/realm.dart';
import '../state/town.dart';
import '../state/troop.dart';
import 'dynasty.dart' as dyn;
import 'protection.dart';
import 'troops.dart';

/// The between-turns world-event phase (§18): earthquake, disease,
/// Reformation, Ottoman invasion, merchant founders. Runs once per round.
void runWorldEvents(GameState state, Rng rng, List<GameEvent> events) {
  _maybeEarthquake(state, rng, events);
  _maybeDisease(state, rng, events);
  _maybeReformation(state, rng, events);
  _maybeOttomanInvasion(state, rng, events);
  _maybeMerchantFounders(state, rng, events);
}

/// §18.1 earthquake — 10% per round, radius 10 (Manhattan), 50% per tile.
/// Never before [firstEarthquakeYear] (grace period, [DEVIATION]).
void _maybeEarthquake(GameState state, Rng rng, List<GameEvent> events) {
  if (state.year < firstEarthquakeYear) return;
  if (rng.nextInt(10) != 0) return;
  final ex = rng.nextInt(79);
  final ey = rng.nextInt(43);
  final map = state.map;
  final affected = <int>{};

  for (var y = math.max(0, ey - 10); y <= math.min(map.height - 1, ey + 10); y++) {
    for (var x = math.max(0, ex - 10);
        x <= math.min(map.width - 1, ex + 10);
        x++) {
      if ((x - ex).abs() + (y - ey).abs() > 10) continue;
      final building = map.buildingAt(x, y);
      final owner = map.ownerAt(x, y);
      if (building == Building.none || owner == World.niemand) continue;
      if (rng.nextInt(2) != 1) continue;

      final realm = state.realm(owner);
      affected.add(owner);
      switch (building) {
        case Building.kornfeld ||
              Building.weide ||
              Building.burg ||
              Building.palast ||
              Building.hafen:
          map.building[map.index(x, y)] = Building.none;
          map.owner[map.index(x, y)] = World.niemand;
          realm.tileCount[building]--;
        case Building.dorf || Building.markt || Building.stadt:
          final town =
              realm.towns.firstWhere((t) => t.x == x && t.y == y);
          _damageTown(realm, town, rng.nextInt(town.population));
      }
    }
  }
  if (affected.isNotEmpty) {
    events.add(GameEvent(
      year: state.year,
      slot: 0,
      type: 'earthquake',
      visibility: EventVisibility.public,
      payload: {'x': ex, 'y': ey, 'affectedSlots': affected.toList()},
    ));
  }
}

/// §18.1/§18.2 exact town damage shape: `T` victims reduce capacity and
/// garrison proportionally; the garrison loss is removed from the army.
void _damageTown(Realm realm, Town town, int t) {
  if (town.population <= 0 || t <= 0) return;
  final capacityLoss = (t * town.troopCapacity / town.population).round();
  final garrisonLoss = (t * town.garrison / town.population).round();
  town.troopCapacity -= math.min(capacityLoss, town.troopCapacity);
  realm.troopCapacity -= math.min(capacityLoss, realm.troopCapacity);
  if (garrisonLoss > 0) {
    final cut = math.min(garrisonLoss, town.garrison);
    town.garrison -= cut;
    realm.armySize = math.max(0, realm.armySize - cut);
  }
  town.population -= t;
  realm.population -= t;
}

/// §18.2 disease: population control above 150/250 persons. One outbreak
/// kills 50% of ALL persons in the world — brutal but original.
/// Suppressed during the protect-new-players window (random deaths).
void _maybeDisease(GameState state, Rng rng, List<GameEvent> events) {
  if (newPlayerProtectionActive(state)) return;
  final personCount = state.persons.length;
  if (personCount <= 150) return;
  if (personCount <= 250 && rng.nextInt(20) != 0) return;

  const diseases = ['Pest', 'Cholera', 'Typhus', 'Ruhr'];
  final disease = diseases[rng.nextInt(4)];
  events.add(GameEvent(
    year: state.year,
    slot: 0,
    type: 'disease',
    visibility: EventVisibility.public,
    payload: {'name': disease},
  ));

  for (final realm in state.realms) {
    if (realm.population <= 10 || realm.isVacant) continue;
    var d = rng.nextInt(math.min(realm.population, 65000));
    var guard = 0;
    while (d > 0 && realm.towns.isNotEmpty && guard++ < 1000) {
      final town = realm.towns[rng.nextInt(realm.towns.length)];
      final t = math.min(
          town.population > 0 ? rng.nextInt(town.population) : 0, d);
      _damageTown(realm, town, t);
      d -= math.max(1, t);
    }
  }

  // Every person in the game dies with probability 1/2.
  for (final personId in List.of(state.persons.keys)) {
    final person = state.persons[personId];
    if (person == null) continue; // removed by an earlier succession chain
    if (rng.nextInt(2) == 0) {
      events.add(GameEvent(
        year: state.year,
        slot: person.dynasty,
        type: 'personDied',
        visibility: EventVisibility.public,
        payload: {'name': person.name, 'age': person.age, 'cause': disease},
      ));
      dyn.handleDeath(state, person, rng, events);
    }
  }
}

/// §18.3 Reformation at the player-chosen year: Protestantism appears and
/// one random AI dynasty converts [INTERPRETATION of "`<X>` tritt zum
/// evangelischen Glauben über"].
void _maybeReformation(GameState state, Rng rng, List<GameEvent> events) {
  if (state.year != state.reformationYear) return;
  final aiSlots = [
    for (final d in state.dynasties)
      if (d.status == DynastyStatus.ai &&
          !state.realm(d.index).isVacant)
        d.index,
  ];
  int? convertSlot;
  if (aiSlots.isNotEmpty) {
    convertSlot = aiSlots[rng.nextInt(aiSlots.length)];
    state.dynasty(convertSlot).religion = Religion.evangelisch;
  }
  events.add(GameEvent(
    year: state.year,
    slot: convertSlot ?? 0,
    type: 'reformation',
    visibility: EventVisibility.public,
    payload: {'convertedSlot': convertSlot},
  ));
}

/// §18.4 Ottoman invasion at the player-chosen year: one realm falls to
/// the Moslems, its capital town is renamed "`<ruler>`sburg" and grows by
/// 1,000, and "Die Janitscharen" (1,000 men, quality 50) spawn.
/// [INTERPRETATION: the realm is chosen at random among living AI realms;
/// a human realm is only taken if no AI realm exists.]
void _maybeOttomanInvasion(GameState state, Rng rng, List<GameEvent> events) {
  if (state.year != state.ottomanYear) return;
  final living = [
    for (final d in state.dynasties)
      if (!state.realm(d.index).isVacant &&
          state.realm(d.index).towns.isNotEmpty)
        d.index,
  ];
  if (living.isEmpty) return;
  final aiSlots = [
    for (final slot in living)
      if (state.dynasty(slot).status == DynastyStatus.ai) slot,
  ];
  final slot = (aiSlots.isNotEmpty ? aiSlots : living)[
      rng.nextInt((aiSlots.isNotEmpty ? aiSlots : living).length)];
  final realm = state.realm(slot);
  final dynasty = state.dynasty(slot);
  final ruler = state.person(realm.rulerId);

  dynasty.religion = Religion.moslemisch;
  state.kurfuerstenIds.remove(realm.rulerId);

  // The capital town: nearest town to the capital (usually the first Dorf).
  final town = realm.towns.first;
  town.name = '${ruler?.name ?? 'Sultan'}sburg';
  town.population += 1000;
  town.troopCapacity += 1000;
  town.garrison += 1000;
  realm.population += 1000;
  realm.troopCapacity += 1000;
  realm.armySize += 1000;

  realm.troops.add(Troop(
    name: 'Die Janitscharen',
    men: 1000,
    troopClass: TroopClass.infanterie,
    quality: TroopQuality.janitscharen,
    garrisonCounted: true,
    x: town.x,
    y: town.y,
  ));
  state.map.troopMarker[state.map.index(town.x, town.y)] = 1;

  events.add(GameEvent(
    year: state.year,
    slot: slot,
    type: 'ottomanInvasion',
    visibility: EventVisibility.public,
    payload: {'capital': town.name},
  ));
}

/// §18.5 merchant founders: vacant slots that still hold territory can be
/// re-founded by a rich merchant. `[DESIGNED: 1-in-10 chance per vacant
/// slot per round — the original's trigger rate was not traced.]`
void _maybeMerchantFounders(GameState state, Rng rng, List<GameEvent> events) {
  for (final realm in state.realms) {
    if (!realm.isVacant) continue;
    final owned = realm.tileCount.fold(0, (a, b) => a + b);
    if (owned == 0 || rng.nextInt(10) != 0) continue;
    final founder =
        foundReplacementDynasty(state, realm.slot, rng, treasury: 1000);
    events.add(GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'merchantFounder',
      visibility: EventVisibility.public,
      payload: {'name': founder.name},
    ));
  }
}

/// Founds a replacement dynasty on [slot] (§5 replacement values, §15.2
/// religion availability, §18.5/§19.2): new founder aged 17+random(5),
/// Ritter/Scheich, the old dynasty's members vanish, the slot becomes AI.
Person foundReplacementDynasty(GameState state, int slot, Rng rng,
    {int? treasury}) {
  final realm = state.realm(slot);
  final dynasty = state.dynasty(slot);

  // The old dynasty's members disappear with it.
  for (final id in List.of(dynasty.memberIds)) {
    final person = state.persons.remove(id);
    if (person == null) continue;
    final spouse = state.person(person.spouseId);
    spouse?.spouseId = null;
    state.kurfuerstenIds.remove(id);
  }
  dynasty.memberIds.clear();

  // §15.2 religion availability for new dynasties.
  final int religion;
  if (state.year <= state.reformationYear) {
    religion = Religion.katholisch;
  } else if (state.year <= state.ottomanYear) {
    religion = rng.nextInt(2);
  } else {
    religion = rng.nextInt(3);
  }
  dynasty.religion = religion;
  dynasty.status = DynastyStatus.ai;
  dynasty.humanPlayer = null;

  final gender = rng.nextInt(2);
  final muslim = religion == Religion.moslemisch;
  final List<String> names = muslim
      ? (gender == 0 ? ottomanMaleNames : ottomanFemaleNames)
      : (gender == 0 ? europeanMaleNames : europeanFemaleNames);
  final founder = Person(
    id: state.nextPersonId++,
    name: names[rng.nextInt(names.length)],
    age: 17 + rng.nextInt(5),
    dynasty: slot,
    gender: gender,
  );
  state.persons[founder.id] = founder;
  dynasty.memberIds.add(founder.id);

  realm.rulerId = founder.id;
  realm.titleClass = (muslim ? 9 : 1) + (gender == 1 ? 12 : 0);
  realm.popularity = 50;
  if (treasury != null) {
    realm.treasury = treasury;
  } else {
    // §5: replacement treasury = (territoryValue × 1.2) / 2, clamped.
    var territoryValue = 0;
    final map = state.map;
    for (var i = 0; i < map.terrain.length; i++) {
      if (map.owner[i] == slot) {
        territoryValue += Building.value[map.building[i]];
      }
    }
    realm.treasury = ((territoryValue * 1.2) / 2).round().clamp(500, 25000);
  }
  return founder;
}

/// §19.1 internal strife + §19.2 bankruptcy, run in the end-of-turn
/// elimination check for [slot]. Both are suppressed in the
/// protect-new-players window.
void runEliminationChecks(GameState state, int slot, Rng rng,
    List<GameEvent> events) {
  if (newPlayerProtectionActive(state)) return;
  final realm = state.realm(slot);
  final dynasty = state.dynasty(slot);
  if (realm.isVacant) return;

  // §19.1 popularity crisis: the realm collapses to the rival branch.
  if (realm.popularity < 20 && dynasty.memberIds.length > 3) {
    final rivals = [
      for (final id in dynasty.memberIds)
        if (id != realm.rulerId && state.persons[id] != null) id,
    ];
    if (rivals.isNotEmpty) {
      final newRuler = rivals[rng.nextInt(rivals.length)];
      realm.rulerId = newRuler;
      realm.popularity = 50;
      if (dynasty.status == DynastyStatus.human) {
        dynasty.status = DynastyStatus.ai;
        dynasty.humanPlayer = null;
      }
      events.add(GameEvent(
        year: state.year,
        slot: slot,
        type: 'internalStrife',
        visibility: EventVisibility.public,
        payload: {'newRuler': state.persons[newRuler]!.name},
      ));
      return;
    }
  }

  // §19.2 bankruptcy.
  const thresholds = [
    10000, 15000, 20000, 30000, 40000, 50000, 75000, 100000,
  ];
  final base =
      realm.titleClass > 12 ? realm.titleClass - 12 : realm.titleClass;
  final classIndex = (base >= 9 ? _muslimEquivalent(base) : base) - 1;
  final limit = thresholds[classIndex.clamp(0, 7)];
  if (realm.treasury >= -limit) return;

  final debt = -realm.treasury;
  events.add(GameEvent(
    year: state.year,
    slot: slot,
    type: 'bankruptcy',
    visibility: EventVisibility.public,
    payload: {'debt': debt},
  ));

  // The creditor seizes one Stadt/Burg/Palast tile per 5,000 T of debt.
  var seizures = debt ~/ 5000;
  final map = state.map;
  for (var i = 0; i < map.terrain.length && seizures > 0; i++) {
    if (map.owner[i] != slot) continue;
    final building = map.building[i];
    if (building != Building.stadt &&
        building != Building.burg &&
        building != Building.palast) {
      continue;
    }
    if (building == Building.stadt) {
      final x = i % map.width;
      final y = i ~/ map.width;
      final townIndex =
          realm.towns.indexWhere((t) => t.x == x && t.y == y);
      if (townIndex >= 0) {
        final town = realm.towns.removeAt(townIndex);
        realm.population -= town.population;
        realm.troopCapacity -= town.troopCapacity;
        releaseGarrison(realm, town.garrison);
      }
    }
    map.owner[i] = World.niemand;
    map.building[i] = Building.none;
    realm.tileCount[building]--;
    seizures--;
  }

  foundReplacementDynasty(state, slot, rng);
}

int _muslimEquivalent(int muslimClass) =>
    const {9: 1, 10: 3, 11: 6, 12: 8}[muslimClass] ?? 1;
