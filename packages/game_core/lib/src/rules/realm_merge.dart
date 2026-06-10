import '../rng/rng.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';

/// "Reiche zusammenlegen" (§6.2): merge slot [sourceSlot] into
/// [targetSlot] — both ruled by the same person. Free; the only gate is
/// that the source owns ≥ 1 tile (validated by the caller).
///
/// Population, harvests, all map tiles, towns, troops and the dynasty
/// members move to the target; the target's popularity becomes the
/// population-weighted average (plain 50 if it had no population); the
/// source slot is vacated with its stat left at 60. The target gets a
/// one-off movement bonus `source.titleClass + random(6)`.
/// [INTERPRETATION: the treasury moves too — the spec lists "Reichtümer"
/// only implicitly.]
void mergeRealms(GameState state, int targetSlot, int sourceSlot, Rng rng,
    List<GameEvent> events) {
  final target = state.realm(targetSlot);
  final source = state.realm(sourceSlot);

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

  // Towns, troops, sums, money, stocks.
  target.towns.addAll(source.towns);
  source.towns.clear();
  target.troops.addAll(source.troops);
  source.troops.clear();
  target.population += source.population;
  target.troopCapacity += source.troopCapacity;
  target.armySize += source.armySize;
  target.grainHarvest += source.grainHarvest;
  target.livestockHarvest += source.livestockHarvest;
  target.treasury += source.treasury;
  source.population = 0;
  source.troopCapacity = 0;
  source.armySize = 0;
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
  // then vacate the source slot.
  target.movementPoints += source.titleClass + rng.nextInt(6);
  source.rulerId = null;

  events.add(GameEvent(
    year: state.year,
    slot: targetSlot,
    type: 'realmsMerged',
    visibility: EventVisibility.public,
    payload: {'sourceSlot': sourceSlot},
  ));
}

/// Other slots ruled by the same ruler as [slot] that own ≥ 1 tile —
/// merge candidates for the Handel menu and the AI (§6.2, §20.7).
List<int> mergeableSlots(GameState state, int slot) {
  final rulerId = state.realm(slot).rulerId;
  if (rulerId == null) return const [];
  return [
    for (final realm in state.realms)
      if (realm.slot != slot &&
          realm.rulerId == rulerId &&
          realm.tileCount.fold(0, (a, b) => a + b) > 0)
        realm.slot,
  ];
}
