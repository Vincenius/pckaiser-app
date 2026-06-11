import '../state/game_state.dart';
import '../state/realm.dart';

/// Hidden-information filter (ARCHITECTURE.md "State Visibility",
/// PROJECT_REQUIREMENTS.md "Hidden information & espionage").
///
/// Returns a copy of [state] containing only what the player in
/// [viewerSlot] may know. Used identically by local hot-seat views and the
/// online server (the authoritative full state never leaves the server).
///
/// Public: map ownership, dynasty names/titles/religion, persons, town
/// names and tiers, Kurfürsten, Kaiser/Sultan, chronicles, market prices,
/// tribute pots, events addressed to the viewer.
///
/// Hidden for every other realm: treasury, harvests/food stocks, troop
/// composition and army size, colony ships, guard level, popularity,
/// population numbers, town garrisons, movement points, per-turn flags,
/// intel reports.
/// Espionage reveals them as fuzzed [IntelReport]s in the viewer's own
/// realm instead.
GameState visibleStateFor(GameState state, int viewerSlot) {
  final filtered = state.copy();

  // Never ship the RNG seed — it would make every future roll predictable.
  filtered.rngSeed = 0;

  for (var i = 0; i < filtered.realms.length; i++) {
    if (filtered.realms[i].slot != viewerSlot) {
      filtered.realms[i] = _redactRealm(filtered.realms[i]);
    }
  }

  filtered.pendingDecisions
      .retainWhere((d) => d.decidingSlot == viewerSlot);
  filtered.assassinationOrders
      .retainWhere((o) => o.sponsorSlot == viewerSlot);
  filtered.events.retainWhere((e) => e.visibleTo(viewerSlot));
  filtered.recapBaselines
      .removeWhere((slot, _) => slot != viewerSlot);

  // Election internals are hidden information: bribes and cast votes stay
  // on the server/master state only. Each participant's pending decision
  // already carries exactly what they may know (e.g. the bribes addressed
  // to them in an `electorVote`).
  final election = filtered.activeElection;
  if (election != null) {
    election.bribes.clear();
    election.votes.clear();
  }

  // A war's unit snapshots and movement budgets reveal troop names,
  // counts and positions — visible to the two combatants only.
  final filteredWar = filtered.activeWar;
  if (filteredWar != null &&
      viewerSlot != filteredWar.attackerSlot &&
      viewerSlot != filteredWar.defenderSlot) {
    filteredWar.snapshots.clear();
    filteredWar.movesLeft.clear();
  }

  // The map's troop markers would betray foreign army positions: rebuild
  // them from the troops the viewer may see — their own, plus both sides'
  // once the viewer fights in the active war.
  final visibleTroopSlots = <int>{viewerSlot};
  final war = state.activeWar;
  if (war != null &&
      (war.attackerSlot == viewerSlot || war.defenderSlot == viewerSlot)) {
    visibleTroopSlots.addAll([war.attackerSlot, war.defenderSlot]);
  }
  // The visible copy encodes the troop's owner slot in the marker, so the
  // client can pick the attacker/defender icon (the master state keeps the
  // plain 0/1 convention).
  final marker = filtered.map.troopMarker;
  marker.fillRange(0, marker.length, 0);
  for (final slot in visibleTroopSlots) {
    for (final troop in state.realm(slot).troops) {
      marker[filtered.map.index(troop.x, troop.y)] = slot;
    }
  }

  return filtered;
}

/// Strips a foreign realm down to its public face. Identity, title, capital
/// and town tiers stay (visible on the map anyway); all economy and
/// military numbers go to zero, meaning "unknown" — the UI must render
/// foreign zeros as hidden, not as the value 0. Troops, colony ships and
/// intel reports are simply omitted (the rebuilt realm defaults them
/// empty).
Realm _redactRealm(Realm realm) => Realm(
      slot: realm.slot,
      titleClass: realm.titleClass,
      capitalX: realm.capitalX,
      capitalY: realm.capitalY,
      tileCount: List.of(realm.tileCount),
      rulerId: realm.rulerId,
      popularity: 0,
      towns: [
        for (final town in realm.towns)
          town.copy()
            ..population = 0
            ..garrison = 0
            ..troopCapacity = 0
      ],
    );
