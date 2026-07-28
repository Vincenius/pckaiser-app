import '../rng/rng.dart';
import '../state/dynasty.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/realm.dart';
import 'troops.dart' show disbandJanissaries;

/// "Reiche zusammenlegen" (§6.2): merge slot [sourceSlot] into
/// [targetSlot] — both under the same control (the same player, even across
/// different heirs of the dynasty; see [mergeableSlots]). Free; the only gate
/// is that the source owns ≥ 1 tile (validated by the caller).
///
/// Population, harvests, all map tiles, towns, troops and the dynasty
/// members move to the target; the target's popularity becomes the
/// population-weighted average (plain 50 if it had no population); the
/// source slot is vacated with its stat left at 60. The target gets a
/// one-off movement bonus `source.titleClass + random(6)`.
/// [INTERPRETATION: the treasury moves too — the spec lists "Reichtümer"
/// only implicitly.]
void mergeRealms(GameState state, int targetSlot, int sourceSlot, Rng rng,
    List<GameEvent> events, {bool emitEvent = true}) {
  final target = state.realm(targetSlot);
  final source = state.realm(sourceSlot);

  // §18.4 rework: the Ottoman guard serves the house it was installed
  // for — it disbands instead of marching into the absorbing realm. Must
  // run BEFORE the towns move: the garrison release walks source.towns.
  disbandJanissaries(state, sourceSlot, events);

  // Popularity: population-weighted average.
  if (target.population > 0) {
    final total = target.population + source.population;
    target.popularity = total == 0
        ? target.popularity
        : ((target.popularity * target.population +
                    source.popularity * source.population) /
                total)
            .round();
  } else {
    target.popularity = 50;
  }
  source.popularity = 60;

  // Map tiles.
  final map = state.map;
  for (var i = 0; i < map.terrain.length; i++) {
    if (map.owner[i] == sourceSlot) map.owner[i] = targetSlot;
  }
  for (var b = 0; b < source.tileCount.length; b++) {
    target.tileCount[b] += source.tileCount[b];
    source.tileCount[b] = 0;
  }

  // Towns, troops, ships, intel, pending trade-ship returns, sums, money,
  // stocks.
  target.towns.addAll(source.towns);
  source.towns.clear();
  target.troops.addAll(source.troops);
  source.troops.clear();
  target.ships.addAll(source.ships);
  source.ships.clear();
  target.intelReports.addAll(source.intelReports);
  source.intelReports.clear();
  // Trade ships still at sea must follow the ruler — the vacated source
  // never takes another turn, so its outstanding voyages would otherwise
  // never be credited (the staked Taler lost). The target resolves any
  // due voyage at its next turn-start (_resolveShipReturns).
  target.pendingShipReturns.addAll(source.pendingShipReturns);
  source.pendingShipReturns.clear();
  target.population += source.population;
  target.troopCapacity += source.troopCapacity;
  target.grainHarvest += source.grainHarvest;
  target.livestockHarvest += source.livestockHarvest;
  target.treasury += source.treasury;
  source.population = 0;
  source.troopCapacity = 0;
  source.grainHarvest = 0;
  source.livestockHarvest = 0;
  source.treasury = 0;

  // Dynasty members move to the target's dynasty.
  final sourceDynasty = state.dynasty(sourceSlot);
  final targetDynasty = state.dynasty(targetSlot);
  for (final id in List.of(sourceDynasty.memberIds)) {
    final person = state.persons[id];
    if (person == null) continue;
    person.dynasty = targetSlot;
    targetDynasty.memberIds.add(id);
  }
  sourceDynasty.memberIds.clear();

  // One-off movement bonus (raw titleClass byte, as in the original),
  // then vacate the source slot. The vacated slot is no longer a human
  // seat — a captured-then-merged slot would otherwise keep counting as a
  // human player (handoffs, decision routing) forever.
  target.movementPoints += source.titleClass + rng.nextInt(6);
  source.rulerId = null;
  sourceDynasty.status = DynastyStatus.ai;
  sourceDynasty.humanPlayer = null;

  if (emitEvent) {
    events.add(GameEvent(
      year: state.year,
      slot: targetSlot,
      type: 'realmsMerged',
      visibility: EventVisibility.public,
      payload: {'sourceSlot': sourceSlot},
    ));
  }
}

/// "Reich übertragen" [DESIGNED, deviation — the original has no voluntary
/// handover]: hand the entire realm — land, towns, troops, ships, treasury
/// and the dynasty's court — to a FOREIGN ruler. Mechanically a
/// [mergeRealms] into the foreign slot (same bookkeeping, the source seat
/// is vacated and stops being a human seat); on top of that the abdicating
/// ruler forfeits the Kaiser crown and any Kurfürst seat — unless they
/// still rule another realm (ruler aliasing, §19/§20.7). A cleared crown
/// triggers a fresh election through the regular offices phase (§17.3).
void transferRealm(GameState state, int targetSlot, int sourceSlot, Rng rng,
    List<GameEvent> events) {
  final formerRulerId = state.realm(sourceSlot).rulerId;
  final wasHuman = state.dynasty(sourceSlot).status == DynastyStatus.human;
  mergeRealms(state, targetSlot, sourceSlot, rng, events, emitEvent: false);
  events.add(GameEvent(
    year: state.year,
    slot: targetSlot,
    type: 'realmTransferred',
    visibility: EventVisibility.public,
    payload: {'sourceSlot': sourceSlot, 'human': wasHuman},
  ));

  if (formerRulerId == null) return;
  if (state.realms.any((r) => r.rulerId == formerRulerId)) return;
  final name = state.persons[formerRulerId]?.name ?? '';
  if (state.kaiserId == formerRulerId) {
    state.kaiserId = null;
    events.add(GameEvent(
      year: state.year,
      slot: sourceSlot,
      type: 'forcedAbdication',
      visibility: EventVisibility.public,
      payload: {'name': name},
    ));
  }
  if (state.kurfuerstenIds.remove(formerRulerId)) {
    events.add(GameEvent(
      year: state.year,
      slot: sourceSlot,
      type: 'kurfuerstStripped',
      visibility: EventVisibility.public,
      payload: {'name': name},
    ));
  }
}

/// Targets for "Reich übertragen": every realm under DIFFERENT control
/// that still has a ruler and ≥ 1 tile — the complement of
/// [mergeableSlots]' same-control gate (own seats consolidate via merge,
/// never via transfer). [DESIGNED] No adjacency gate: the handover is a
/// political act, not a territorial one.
List<int> transferableSlots(GameState state, int slot) {
  final rulerId = state.realm(slot).rulerId;
  if (rulerId == null) return const [];
  final dynasty = state.dynasty(slot);

  bool sameController(Realm other) {
    if (dynasty.status == DynastyStatus.human) {
      final otherDynasty = state.dynasty(other.slot);
      return otherDynasty.status == DynastyStatus.human &&
          otherDynasty.humanPlayer == dynasty.humanPlayer;
    }
    return other.rulerId == rulerId;
  }

  return [
    for (final realm in state.realms)
      if (realm.slot != slot &&
          realm.rulerId != null &&
          !sameController(realm) &&
          realm.tileCount.fold(0, (a, b) => a + b) > 0)
        realm.slot,
  ];
}

/// Slots that own ≥ 1 tile, share a border with [slot], and are under the SAME
/// control as [slot] — merge candidates for the Handel menu and the AI
/// (§6.2, §20.7).
///
/// The shared-border gate is faithful to the original: "Reiche zusammenlegen"
/// builds its candidate list from the same neighbour helper as war declaration
/// (confirmed in the disassembly — both reject with a "Nachbarn" message when
/// empty). Adjacency is plain orthogonal tile-touch on the ownership grid;
/// an owned Hafen sits on a water tile the realm owns, so it participates in
/// adjacency like any owned tile — but a harbour does NOT bridge an open-water
/// gap (the original has no sea/ship adjacency for merge or war).
///
/// "Same control" is the player, not the single ruler: a human may merge any
/// realm their dynasty holds, even one ruled by a different heir/branch
/// (inheritance, §15.4) — control already follows the dynasty
/// (`alignSlotControl`), so a slot whose `humanPlayer` matches is "yours".
/// AI/free seats keep plain ruler aliasing (§19/§20.7: one ruler, many slots).
List<int> mergeableSlots(GameState state, int slot) {
  final rulerId = state.realm(slot).rulerId;
  if (rulerId == null) return const [];
  final dynasty = state.dynasty(slot);
  final neighbors = state.map.realmNeighbors(slot);

  bool sameController(Realm other) {
    if (dynasty.status == DynastyStatus.human) {
      final otherDynasty = state.dynasty(other.slot);
      return otherDynasty.status == DynastyStatus.human &&
          otherDynasty.humanPlayer == dynasty.humanPlayer;
    }
    return other.rulerId == rulerId;
  }

  return [
    for (final realm in state.realms)
      if (realm.slot != slot &&
          sameController(realm) &&
          realm.tileCount.fold(0, (a, b) => a + b) > 0 &&
          neighbors.contains(realm.slot))
        realm.slot,
  ];
}
