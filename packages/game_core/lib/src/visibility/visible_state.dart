import '../state/dynasty.dart';
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

  // Slots whose troops the viewer may see: their own, plus BOTH sides of an
  // active war they fight in — combatants see each other's units (the war
  // panel and the map render the enemy army).
  final visibleTroopSlots = <int>{viewerSlot};
  final war = state.activeWar;
  if (war != null &&
      (war.attackerSlot == viewerSlot || war.defenderSlot == viewerSlot)) {
    visibleTroopSlots.addAll([war.attackerSlot, war.defenderSlot]);
  }

  for (var i = 0; i < filtered.realms.length; i++) {
    final slot = filtered.realms[i].slot;
    if (slot != viewerSlot) {
      // The opponent in a war the viewer fights keeps its troop list and
      // army size (visible to combatants); every other foreign realm is
      // fully redacted. Without this the online client received an empty
      // enemy troop list and showed no enemy units in war.
      filtered.realms[i] = _redactRealm(filtered.realms[i],
          keepTroops: visibleTroopSlots.contains(slot));
    }
  }

  // One player can control several slots (cross-dynasty inheritance,
  // §15.4): decisions raised for ANY of their slots are their own hidden
  // information and must surface at their next handoff — not only when the
  // deciding slot's own turn comes around.
  final viewerDynasty = state.dynasty(viewerSlot);
  bool sameHumanPlayer(int slot) {
    final dynasty = state.dynasty(slot);
    return viewerDynasty.status == DynastyStatus.human &&
        dynasty.status == DynastyStatus.human &&
        dynasty.humanPlayer != null &&
        dynasty.humanPlayer == viewerDynasty.humanPlayer;
  }

  filtered.pendingDecisions.retainWhere(
      (d) => d.decidingSlot == viewerSlot || sameHumanPlayer(d.decidingSlot));
  filtered.assassinationOrders.retainWhere((o) => o.sponsorSlot == viewerSlot);
  filtered.events.retainWhere((e) => e.visibleTo(viewerSlot));
  filtered.recapBaselines.removeWhere((slot, _) => slot != viewerSlot);

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
  // once the viewer fights in the active war (see visibleTroopSlots above).
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
/// foreign zeros as hidden, not as the value 0. Colony ships, in-flight
/// trade voyages and intel reports are simply omitted (the rebuilt realm
/// defaults them empty).
///
/// [keepTroops] retains the unit list and army size: set for the OPPONENT in
/// a war the viewer fights, so combatants can see each other's armies.
Realm _redactRealm(Realm realm, {bool keepTroops = false}) => Realm(
      slot: realm.slot,
      titleClass: realm.titleClass,
      capitalX: realm.capitalX,
      capitalY: realm.capitalY,
      tileCount: List.of(realm.tileCount),
      rulerId: realm.rulerId,
      popularity: 0,
      armySize: keepTroops ? realm.armySize : 0,
      troops: keepTroops ? [for (final t in realm.troops) t.copy()] : null,
      towns: [
        for (final town in realm.towns)
          town.copy()
            ..population = 0
            ..garrison = 0
            ..troopCapacity = 0
      ],
    );
