import 'dart:math' as math;

import '../data/tables.dart';
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
import 'dynasty.dart' as dyn;
import 'population.dart' show cutGarrisonTroops, removeArmyMen;
import 'protection.dart';
import 'troops.dart' show disbandJanissaries;
import 'titles.dart'
    show christianEquivalentClass, regenderTitle, switchTitleLadder;
import 'war.dart' show checkLandLoss;

/// `[DESIGNED]` How many consecutive end-of-turns a realm may stay below
/// the §19.2 bankruptcy limit before the creditor forecloses. The first
/// turns only warn, giving the player time to sell goods, raise taxes or
/// disband troops and recover.
const int bankruptcyGraceTurns = 3;

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
  final map = state.map;
  final ex = rng.nextInt(map.width);
  final ey = rng.nextInt(map.height);
  final affected = <int>{};

  for (var y = math.max(0, ey - 10);
      y <= math.min(map.height - 1, ey + 10);
      y++) {
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
          final town = realm.townAt(x, y);
          // Every town tile has a town object; the assert surfaces a
          // map/town desync in debug and tests. In release the tile is
          // skipped rather than aborting the event phase mid-pass (a
          // throw would leave the world partially mutated).
          assert(town != null, 'town tile ($x,$y) has no town object');
          if (town != null) {
            _damageTown(state, realm, town, rng.nextInt(town.population));
          }
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
    // A quake that levelled a realm's LAST tile vacates it right here —
    // a landless "zombie" must never linger in the turn order or block
    // the §19.3 sole-ruler win (no-op for realms that kept land).
    for (final slot in affected) {
      checkLandLoss(state, state.realm(slot), events);
    }
  }
}

/// `[DESIGNED]` Re-seat realms whose capital tile is no longer theirs —
/// lost to a war claim, an earthquake, or a bankruptcy seizure (§18.1,
/// §11.2, §19.2). A realm without a valid seat must move it onto another
/// own Stadt/Burg/Palast:
///  - AI realms re-seat automatically onto the highest-VALUE eligible tile,
///    picking at random among ties.
///  - Human realms get a `relocateCapital` decision so the player chooses
///    manually; the seat stays put until they resolve it.
///  - A realm with NO seat-eligible tile left re-seats automatically (even
///    a human — there is no Stadt/Burg/Palast to choose) onto its
///    highest-value own tile of any kind: a realm that still owns land must
///    always have a seat on that land, or a war against it becomes
///    unwinnable (the capital-occupation victory and the map's seat flag
///    both require an OWNED capital tile). Only a landless realm keeps its
///    stale seat — the elimination paths handle it.
void reseatLostCapitals(GameState state, Rng rng, List<GameEvent> events) {
  for (final realm in state.realms) {
    ensureRealmSeat(state, realm.slot, rng, events);
  }
}

/// Repairs [slot]'s seat when its capital tile is no longer owned (see
/// [reseatLostCapitals] for the rules). With [allowDecision] a human realm
/// that owns a seat-eligible tile is PROMPTED instead of moved; without it
/// (war context: war start, every war-round end, the claim settlement) the
/// seat is re-seated immediately — mid-war there is no decision loop, and
/// an unresolved seat would make the war unwinnable and flag-less.
void ensureRealmSeat(GameState state, int slot, Rng rng, List<GameEvent> events,
    {bool allowDecision = true}) {
  final realm = state.realm(slot);
  if (realm.isVacant) return;
  final map = state.map;
  if (map.ownerAt(realm.capitalX, realm.capitalY) == realm.slot) {
    // Seat is valid (again) — drop any stale re-seat prompt.
    state.pendingDecisions.removeWhere(
        (d) => d.type == 'relocateCapital' && d.decidingSlot == realm.slot);
    return;
  }
  final best = _bestSeatTile(state, realm.slot, rng);
  if (allowDecision &&
      best != null &&
      state.dynasty(realm.slot).status == DynastyStatus.human) {
    final already = state.pendingDecisions.any(
        (d) => d.type == 'relocateCapital' && d.decidingSlot == realm.slot);
    if (!already) {
      state.pendingDecisions.add(PendingDecision(
        id: 'relocate-${realm.slot}-${state.year}',
        type: 'relocateCapital',
        decidingSlot: realm.slot,
        payload: const {},
      ));
      events.add(GameEvent(
        year: state.year,
        slot: realm.slot,
        type: 'capitalLost',
        visibility: EventVisibility.owner,
      ));
    }
    return;
  }
  final seat = best ?? _bestSeatTile(state, realm.slot, rng, anyTile: true);
  if (seat == null) return; // landless — elimination handles the realm
  realm.capitalX = seat.$1;
  realm.capitalY = seat.$2;
  // A forced re-seat supersedes any open manual prompt.
  state.pendingDecisions.removeWhere(
      (d) => d.type == 'relocateCapital' && d.decidingSlot == realm.slot);
  events.add(GameEvent(
    year: state.year,
    slot: realm.slot,
    type: 'capitalReseated',
    visibility: EventVisibility.public,
    payload: {'x': seat.$1, 'y': seat.$2},
  ));
}

/// Highest-VALUE own Stadt/Burg/Palast tile for [slot], chosen at random
/// among ties; null when the realm holds no seat-eligible tile. With
/// [anyTile] every owned tile qualifies (the no-Burg fallback seat).
(int, int)? _bestSeatTile(GameState state, int slot, Rng rng,
    {bool anyTile = false}) {
  final map = state.map;
  var bestValue = -1;
  final best = <(int, int)>[];
  for (var i = 0; i < map.terrain.length; i++) {
    if (map.owner[i] != slot) continue;
    final building = map.building[i];
    if (!anyTile && !Building.isSeat(building)) {
      continue;
    }
    final value = Building.value[building];
    final tile = (i % map.width, i ~/ map.width);
    if (value > bestValue) {
      bestValue = value;
      best
        ..clear()
        ..add(tile);
    } else if (value == bestValue) {
      best.add(tile);
    }
  }
  if (best.isEmpty) return null;
  return best[rng.nextInt(best.length)];
}

/// §18.1/§18.2 exact town damage shape: `T` victims reduce capacity and
/// garrison proportionally; the garrison loss is removed from the army.
/// Also cuts the garrison-counted troop units, keeping unit men
/// in sync with `armySize` (the same desync the v2 conquest fix closed).
void _damageTown(GameState state, Realm realm, Town town, int t) {
  if (town.population <= 0 || t <= 0) return;
  final capacityLoss = (t * town.troopCapacity / town.population).round();
  final garrisonLoss = (t * town.garrison / town.population).round();
  town.troopCapacity -= math.min(capacityLoss, town.troopCapacity);
  realm.troopCapacity -= math.min(capacityLoss, realm.troopCapacity);
  if (garrisonLoss > 0) {
    final cut = math.min(garrisonLoss, town.garrison);
    town.garrison -= cut;
    cutGarrisonTroops(realm, cut);
  }
  // The two proportional losses round independently, which can leave the
  // garrison a man above the shrunken capacity — trim right here so
  // `garrison ≤ troopCapacity` survives every damage path (war-round
  // plunder reads it mid-turn, before the next §8.3 normalization).
  if (town.garrison > town.troopCapacity) {
    final excess = town.garrison - town.troopCapacity;
    town.garrison = town.troopCapacity;
    cutGarrisonTroops(realm, excess);
  }
  town.population -= t;
  realm.population -= t;
}

/// `[DESIGNED 2026-08-08, user feedback]` The §18.2 outbreak thresholds
/// scale with the WORLD SIZE instead of the original's flat 150/250 persons.
/// Those numbers assume a full 30-realm world (≈ 5 persons per living
/// realm); on a Klein/Mittel map with 6–20 realms the world never held that
/// many people, so the plague — one of the events that gave the original
/// its historical texture — could not fire at all. Per living realm now,
/// with a floor so a late-game world of two survivors is not permanently
/// plague-ridden; at 30 realms the values come out at the original 150/250
/// (the upper threshold is 5/3 × this one, as before).
int diseaseThreshold(GameState state) {
  final living = state.realms.where((r) => !r.isVacant).length;
  return math.max(60, 5 * living);
}

/// §18.2 disease: population control above two person-count thresholds
/// ([diseaseThreshold]). One outbreak kills 50% of ALL persons in the
/// world. [DEVIATION] Mercy rule: a person who is currently the last living
/// member of their dynasty is spared — the original could erase a player's
/// whole dynasty in one between-turns tick with zero counterplay.
/// Population control still works (the floor is one survivor per dynasty).
/// Suppressed during the protect-new-players window (random deaths).
void _maybeDisease(GameState state, Rng rng, List<GameEvent> events) {
  if (newPlayerProtectionActive(state)) return;
  final personCount = state.persons.length;
  final low = diseaseThreshold(state);
  if (personCount <= low) return;
  if (personCount <= low * 5 ~/ 3 && rng.nextInt(20) != 0) return;

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
      final t =
          math.min(town.population > 0 ? rng.nextInt(town.population) : 0, d);
      _damageTown(state, realm, town, t);
      d -= math.max(1, t);
    }
  }

  // Every person in the game dies with probability 1/2 — except the last
  // member of a dynasty (mercy rule, see doc comment).
  for (final personId in List.of(state.persons.keys)) {
    final person = state.persons[personId];
    if (person == null) continue; // removed by an earlier succession chain
    if (state.dynasty(person.dynasty).memberIds.length <= 1) continue;
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
      if (d.status == DynastyStatus.ai && !state.realm(d.index).isVacant)
        d.index,
  ];
  int? convertSlot;
  if (aiSlots.isNotEmpty) {
    convertSlot = aiSlots[rng.nextInt(aiSlots.length)];
    state.dynasty(convertSlot).religion = Religion.evangelisch;
    // §14.4 — incompatible marriages dissolve on conversion.
    dyn.divorceIncompatibleCouples(state, convertSlot, events);
  }
  events.add(GameEvent(
    year: state.year,
    slot: convertSlot ?? 0,
    type: 'reformation',
    visibility: EventVisibility.public,
    payload: {'convertedSlot': convertSlot},
  ));
}

/// §18.4 Ottoman invasion at the player-chosen year, reworked (deviation
/// 2026-07-28, see PROJECT_REQUIREMENTS.md): one AI realm converts to
/// Islam — capital renamed "`<ruler>`sburg", Muslim title ladder, Kurfürst
/// seats of the converting house forfeit — and "Die Janitscharen" garrison
/// its capital. Changes vs the original: never a human realm (no AI
/// candidate → the event is skipped; Islam still unlocks through the
/// §15.2 year gates), the guard scales with the world instead of a flat
/// 1,000 men, its quality is [TroopQuality.janitscharenGuard] instead of
/// the near-unbeatable 50, and the unit is `janissary`-flagged: it serves
/// only the house it was installed for and disbands whenever the realm
/// changes hands ([disbandJanissaries]) — the original's free elite army
/// kept surfacing in human hands (direct hit in all-human games, or years
/// later via inheritance/merge) as an inexplicable 1,000-man level-50
/// troop (user report 2026-07-28).
void _maybeOttomanInvasion(GameState state, Rng rng, List<GameEvent> events) {
  if (state.year != state.ottomanYear) return;
  final aiSlots = [
    for (final d in state.dynasties)
      if (d.status == DynastyStatus.ai &&
          !state.realm(d.index).isVacant &&
          state.realm(d.index).towns.isNotEmpty)
        d.index,
  ];
  if (aiSlots.isEmpty) return;
  final slot = aiSlots[rng.nextInt(aiSlots.length)];
  final realm = state.realm(slot);
  final dynasty = state.dynasty(slot);
  final ruler = state.person(realm.rulerId);

  dynasty.religion = Religion.moslemisch;
  // Every dynasty member's Kurfürst seat is forfeit, like the menu and
  // coerced conversions to Islam (§12.1, §17.2) — but ONLY members of the
  // converting house: a cross-dynasty ruler (§15.4) whose own house stays
  // Christian keeps his seat.
  state.kurfuerstenIds.removeWhere((id) => state.persons[id]?.dynasty == slot);
  // Switch to the Muslim title ladder, like every other conversion
  // (§16.1; mirrors `_changeReligion` and `foundReplacementDynasty`).
  switchTitleLadder(realm, Religion.moslemisch);
  // §14.4 — incompatible marriages dissolve on conversion.
  dyn.divorceIncompatibleCouples(state, slot, events);

  // The capital town: nearest town to the capital (usually the first Dorf).
  final town = realm.towns.first;
  town.name = '${ruler?.name ?? 'Sultan'}sburg';

  // The guard scales with the world: twice the average standing army of
  // the living realms, clamped to [200, 1000] (the cap is the original's
  // flat size). The settling horde brings its own quarters and stays as
  // population even if the guard later disbands — same bookkeeping as the
  // original, just scaled.
  final living = [
    for (final r in state.realms)
      if (!r.isVacant && r.towns.isNotEmpty) r,
  ];
  final totalArmy = living.fold(0, (sum, r) => sum + r.armySize);
  final men = (2 * totalArmy ~/ living.length).clamp(200, 1000);
  town.population += men;
  town.troopCapacity += men;
  town.garrison += men;
  realm.population += men;
  realm.troopCapacity += men;
  realm.troops.add(Troop(
    id: state.nextUnitId++,
    name: 'Die Janitscharen',
    men: men,
    troopClass: TroopClass.infanterie,
    quality: TroopQuality.janitscharenGuard,
    garrisonCounted: true,
    janissary: true,
    x: town.x,
    y: town.y,
  ));
  state.map.troopMarker[state.map.index(town.x, town.y)] = 1;

  events.add(GameEvent(
    year: state.year,
    slot: slot,
    type: 'ottomanInvasion',
    visibility: EventVisibility.public,
    payload: {'capital': town.name, 'men': men},
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
        foundReplacementDynasty(state, realm.slot, rng, events, treasury: 1000);
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
Person foundReplacementDynasty(
    GameState state, int slot, Rng rng, List<GameEvent> events,
    {int? treasury}) {
  final realm = state.realm(slot);
  final dynasty = state.dynasty(slot);
  // A whole new house takes the slot — the Ottoman guard never serves it
  // (§18.4 rework).
  disbandJanissaries(state, slot, events);

  // The old dynasty's members disappear with it. Each removal runs the
  // same reference cleanup as a death (`removePersonFromWorld`): a
  // vanished person must not stay referenced as spouse, Kurfürst or
  // Kaiser/Sultan (a dangling kaiserId would block every future
  // election). Child links are swept once for the whole batch, and ruled
  // slots pass on §15.4-style below (no per-person succession — the
  // house is gone as a whole).
  final removedIds = <int>{};
  for (final id in List.of(dynasty.memberIds)) {
    final person = state.persons[id];
    if (person == null) continue;
    removedIds.add(id);
    dyn.removePersonFromWorld(state, person, rng, events);
  }
  for (final person in state.persons.values) {
    person.childrenIds.removeWhere(removedIds.contains);
  }

  // Other slots ruled by a removed person pass on like a dynasty
  // extinction (§15.4): to a random other living ruler, else vacant.
  final aliasedSlots = [
    for (final r in state.realms)
      if (r.slot != slot && removedIds.contains(r.rulerId)) r.slot,
  ];
  if (aliasedSlots.isNotEmpty) {
    final livingRulers = <int>{
      for (final r in state.realms)
        if (r.rulerId != null && !removedIds.contains(r.rulerId)) r.rulerId!,
    }.toList();
    final inheritor = livingRulers.isEmpty
        ? null
        : livingRulers[rng.nextInt(livingRulers.length)];
    for (final aliased in aliasedSlots) {
      state.realm(aliased).rulerId = inheritor;
      if (inheritor != null) {
        dyn.alignSlotControl(state, aliased, inheritor);
        regenderTitle(state, state.realm(aliased));
      }
      // The slot passes to another house (or falls vacant) — the Ottoman
      // guard never follows a new master (§18.4 rework).
      disbandJanissaries(state, aliased, events);
      events.add(GameEvent(
        year: state.year,
        slot: aliased,
        type: 'dynastyExtinct',
        visibility: EventVisibility.public,
        payload: {'inheritor': state.persons[inheritor]?.name},
      ));
    }
  }

  // §15.2 religion availability for new dynasties — inclusive of the event
  // year itself, matching the ChangeReligion gate: the faith exists the
  // moment its event is announced.
  final int religion;
  if (state.year < state.reformationYear) {
    religion = Religion.katholisch;
  } else if (state.year < state.ottomanYear) {
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
  // The old house's tax policy dies with it (§7.1 tuning, 2026-08-13) —
  // the new one starts on the original formula.
  realm.taxRate = taxRateDefault;
  // A whole new house answers for none of the old one's wars — weariness,
  // war history and truces all start clean with it (2026-08-08).
  realm.recentWars = 0;
  realm.peaceYears = 0;
  realm.lastWarYear = 0;
  realm.lastDefendedYear = 0;
  realm.truceUntilYear.clear();
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

/// `[DESIGNED 2026-08-08, user feedback]` Peasant revolt tuning: what an
/// uprising costs the realm it breaks out in (see [_peasantRevolt]).
/// A share of the standing army deserts to the mob or melts away, the
/// biggest town loses people, and the year's takings are looted.
const int peasantRevoltDesertionPercent = 20;
const int peasantRevoltTownLossPercent = 10;
const int peasantRevoltTreasuryLossPercent = 10;

/// Popularity the realm is left with once an uprising has burnt itself
/// out. Above the §19.1 strife line (20) so the revolt is a recurring
/// scourge, not a per-turn death spiral: keep warring or starving and the
/// people rise again in a few years.
const int peasantRevoltVentedPopularity = 30;

/// §19.1 internal strife + §19.2 bankruptcy, run in the end-of-turn
/// elimination check for [slot]. Both are suppressed in the
/// protect-new-players window.
void runEliminationChecks(
    GameState state, int slot, Rng rng, List<GameEvent> events) {
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
      // Whether a HUMAN player just lost this realm to the coup — the
      // client keys a prominent "you lost your realm because ..." popup
      // off this flag (a quiet feed line was easy to miss, especially
      // online while another player's turn ran).
      final wasHuman = dynasty.status == DynastyStatus.human;
      realm.rulerId = newRuler;
      regenderTitle(state, realm);
      realm.popularity = 50;
      // The pretender is not blamed for the deposed ruler's campaigns:
      // without this the inherited weariness ceiling would pull the fresh
      // ruler straight back under the strife line (2026-08-08).
      realm.recentWars = 0;
      realm.peaceYears = 0;
      if (wasHuman) {
        state.humanLossReason = 'internalStrife';
        dynasty.status = DynastyStatus.ai;
        dynasty.humanPlayer = null;
      }
      events.add(GameEvent(
        year: state.year,
        slot: slot,
        type: 'internalStrife',
        visibility: EventVisibility.public,
        payload: {
          'newRuler': state.persons[newRuler]!.name,
          'human': wasHuman,
        },
      ));
      return;
    }
  }

  // `[DESIGNED 2026-08-08, user feedback]` The coup above needs a rival
  // BRANCH (> 3 members, at least one non-ruler alive). A young or thinned
  // house could therefore sit at popularity 5 indefinitely with no
  // consequence whatsoever — which is why an expansionist player never met
  // the unrest the original punished them with. A realm below the strife
  // line whose house cannot produce a pretender now faces a PEASANT
  // REVOLT: it costs, it repeats while the cause persists, and it never
  // takes the realm away (that stays the pretender's privilege).
  // (No early return: the realm keeps its ruler, so the §19.2 debt check
  // below still applies this turn — the revolt's looting can even be what
  // tips it over.)
  if (realm.popularity < 20) _peasantRevolt(state, realm, events);

  // §19.2 bankruptcy.
  const thresholds = [
    10000,
    15000,
    20000,
    30000,
    40000,
    50000,
    75000,
    100000,
  ];
  final classIndex = christianEquivalentClass(realm.titleClass) - 1;
  final limit = thresholds[classIndex.clamp(0, 7)];
  if (realm.treasury >= -limit) {
    realm.debtTurns = 0; // back above the limit — the debt clock resets
    return;
  }

  // `[DESIGNED]` Below the limit the creditor does NOT foreclose at once:
  // the realm gets [bankruptcyGraceTurns] end-of-turns to climb back out,
  // with an owner-visible warning each turn. Only sustained deep debt
  // triggers the §19.2 seizure + replacement dynasty.
  realm.debtTurns++;
  if (realm.debtTurns < bankruptcyGraceTurns) {
    events.add(GameEvent(
      year: state.year,
      slot: slot,
      type: 'debtWarning',
      visibility: EventVisibility.owner,
      payload: {
        'debt': -realm.treasury,
        'turnsLeft': bankruptcyGraceTurns - realm.debtTurns,
      },
    ));
    return;
  }
  realm.debtTurns = 0; // the debt episode is resolved by the foreclosure

  final debt = -realm.treasury;
  events.add(GameEvent(
    year: state.year,
    slot: slot,
    type: 'bankruptcy',
    visibility: EventVisibility.public,
    // 'human': a player loses this realm to the foreclosure — flags the
    // client's "you lost your realm" popup (see internalStrife above).
    payload: {
      'debt': debt,
      'human': dynasty.status == DynastyStatus.human,
    },
  ));

  // The creditor seizes one Stadt/Burg/Palast tile per 5,000 T of debt.
  var seizures = debt ~/ 5000;
  final map = state.map;
  for (var i = 0; i < map.terrain.length && seizures > 0; i++) {
    if (map.owner[i] != slot) continue;
    final building = map.building[i];
    if (!Building.isSeat(building)) continue;
    if (building == Building.stadt) {
      final x = i % map.width;
      final y = i ~/ map.width;
      final townIndex = realm.towns.indexWhere((t) => t.x == x && t.y == y);
      if (townIndex >= 0) {
        final town = realm.towns.removeAt(townIndex);
        realm.population -= town.population;
        realm.troopCapacity -= town.troopCapacity;
        // The seized town's garrison vanishes with it — like a dying town
        // (§8.3), not like a disbanded unit: cutting other towns' garrisons
        // here (the old releaseGarrison call) double-counted the loss.
        cutGarrisonTroops(realm, town.garrison);
      }
    }
    map.owner[i] = World.niemand;
    map.building[i] = Building.none;
    realm.tileCount[building]--;
    seizures--;
  }

  final wasHuman = dynasty.status == DynastyStatus.human;
  foundReplacementDynasty(state, slot, rng, events);
  if (wasHuman) state.humanLossReason = 'bankruptcy';
  // A seizure that took the realm's LAST tiles leaves the fresh founder
  // landless — vacate immediately (no-op when land remains).
  checkLandLoss(state, realm, events);
}

/// `[DESIGNED 2026-08-08, user feedback]` A peasant revolt: the fallback
/// consequence for a realm below the §19.1 strife line whose house holds no
/// pretender to depose the ruler (see the caller). The uprising costs
/// soldiers (deserted or lost to the mob), townspeople and the treasury,
/// then burns itself out at [peasantRevoltVentedPopularity] — well above
/// the strife line, so this is a recurring scourge for a ruler who keeps
/// warring or starving their people, never a per-turn spiral. It never
/// changes who rules: losing the realm stays the pretender's privilege.
void _peasantRevolt(GameState state, Realm realm, List<GameEvent> events) {
  final deserted = realm.armySize * peasantRevoltDesertionPercent ~/ 100;
  if (deserted > 0) removeArmyMen(realm, deserted);

  // The biggest town is where the mob gathers.
  var townLoss = 0;
  if (realm.towns.isNotEmpty) {
    var biggest = realm.towns.first;
    for (final town in realm.towns) {
      if (town.population > biggest.population) biggest = town;
    }
    townLoss = biggest.population * peasantRevoltTownLossPercent ~/ 100;
    // `_damageTown` keeps the town/realm population, capacity and garrison
    // bookkeeping in sync (and may dissolve a town that empties out).
    if (townLoss > 0) _damageTown(state, realm, biggest, townLoss);
  }

  // Only a POSITIVE treasury can be looted — a realm already in debt must
  // not gain money here (`~/` on a negative would subtract a negative).
  final looted = realm.treasury > 0
      ? realm.treasury * peasantRevoltTreasuryLossPercent ~/ 100
      : 0;
  realm.treasury -= looted;

  realm.popularity = peasantRevoltVentedPopularity;

  events.add(GameEvent(
    year: state.year,
    slot: realm.slot,
    type: 'peasantRevolt',
    visibility: EventVisibility.public,
    payload: {
      'men': deserted,
      'people': townLoss,
      'taler': looted,
    },
  ));
}
