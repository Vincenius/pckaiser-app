import '../state/dynasty.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/realm.dart';
import '../state/troop.dart';

/// All realm slots the human player seated at [viewerSlot] currently
/// controls, [viewerSlot] included — control follows the ruler (§15.4), so
/// an inheritance can leave one player holding several realms. (A war
/// conquest no longer does: since 2026-07-13 a total takeover annexes the
/// loser's land into the winner's own realm instead of aliasing the slot.)
/// For an AI or vacant viewer slot this is just `{viewerSlot}`.
Set<int> humanControlledSlots(GameState state, int viewerSlot) {
  final viewer = state.dynasty(viewerSlot);
  if (viewer.status != DynastyStatus.human || viewer.humanPlayer == null) {
    return {viewerSlot};
  }
  return {
    viewerSlot,
    for (final dynasty in state.dynasties)
      if (dynasty.status == DynastyStatus.human &&
          dynasty.humanPlayer == viewer.humanPlayer)
        dynasty.index,
  };
}

/// Hidden-information filter (ARCHITECTURE.md "State Visibility",
/// PROJECT_REQUIREMENTS.md "Hidden information & espionage").
///
/// Returns a copy of [state] containing only what the player in
/// [viewerSlot] may know. Used identically by local hot-seat views and the
/// online server (the authoritative full state never leaves the server).
///
/// Hidden information is per PLAYER, not per realm slot: every realm of
/// the same human player ([humanControlledSlots]) counts as the viewer's
/// own and stays unredacted — a player holding several realms may study
/// all of them (e.g. in the online read-only view while another seat's
/// turn runs).
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

  // Every realm of the same human player is the viewer's own (control
  // follows the ruler, §15.4).
  final ownSlots = humanControlledSlots(state, viewerSlot);

  // Slots whose troops the viewer may see: their own realms, plus BOTH
  // sides of an active war they fight in — combatants see each other's
  // units (the war panel and the map render the enemy army).
  final visibleTroopSlots = <int>{...ownSlots};
  final war = state.activeWar;
  if (war != null &&
      (ownSlots.contains(war.attackerSlot) ||
          ownSlots.contains(war.defenderSlot))) {
    visibleTroopSlots.addAll([war.attackerSlot, war.defenderSlot]);
  }

  for (var i = 0; i < filtered.realms.length; i++) {
    final slot = filtered.realms[i].slot;
    if (!ownSlots.contains(slot)) {
      // The opponent in a war the viewer fights keeps its troop list and
      // army size (visible to combatants); every other foreign realm is
      // fully redacted. Without this the online client received an empty
      // enemy troop list and showed no enemy units in war.
      filtered.realms[i] = _redactRealm(filtered.realms[i],
          keepTroops: visibleTroopSlots.contains(slot));
    }
  }

  // Decisions raised for ANY of the player's slots are their own hidden
  // information and must surface at their next handoff — not only when the
  // deciding slot's own turn comes around.
  filtered.pendingDecisions
      .retainWhere((d) => ownSlots.contains(d.decidingSlot));
  filtered.assassinationOrders
      .retainWhere((o) => ownSlots.contains(o.sponsorSlot));
  // Hidden events are REDACTED in place, never removed: the recap
  // baselines (server-set at end_turn) and the client's "already shown"
  // drama tracking address events by absolute position
  // (`prunedEventCount + index`), so the filtered list must keep the
  // master state's indices. A removed middle would shift every later
  // event and silently empty the online recap. The placeholder (slot 0,
  // owner-visibility) is invisible to every realm slot and carries no
  // payload; all event consumers filter on `visibleTo` anyway.
  for (var i = 0; i < filtered.events.length; i++) {
    final event = filtered.events[i];
    if (!ownSlots.any(event.visibleTo)) {
      filtered.events[i] = GameEvent(
        year: event.year,
        slot: 0,
        type: 'redacted',
        visibility: EventVisibility.owner,
      );
    }
  }
  filtered.recapBaselines.removeWhere((slot, _) => !ownSlots.contains(slot));

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
      !ownSlots.contains(filteredWar.attackerSlot) &&
      !ownSlots.contains(filteredWar.defenderSlot)) {
    filteredWar.snapshots.clear();
    filteredWar.movesLeft.clear();
    // The duel appointment is the combatants' business too (2026-08-09):
    // their proposed times would tell a bystander when both will be busy.
    filteredWar.planSlots.clear();
    filteredWar.planAnsweredSlots.clear();
    filteredWar.scheduledStartMs = null;
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
/// [keepTroops] retains the unit list for the OPPONENT in a war the viewer
/// fights, so combatants see each other's armies on the map — but each unit
/// is reduced to its BATTLEFIELD-observable face ([_battlefieldTroop]): its
/// men and drill quality are stripped, revealed only by espionage.
Realm _redactRealm(Realm realm, {bool keepTroops = false}) => Realm(
      slot: realm.slot,
      titleClass: realm.titleClass,
      capitalX: realm.capitalX,
      capitalY: realm.capitalY,
      // Public identity like the title: without it every OTHER player's
      // chosen setup color fell back to the slot default on the map.
      colorArgb: realm.colorArgb,
      tileCount: List.of(realm.tileCount),
      rulerId: realm.rulerId,
      popularity: 0,
      // A war opponent's units are kept but zeroed to class + position; every
      // other foreign realm's list is omitted (reads as army size 0 anyway).
      troops: keepTroops
          ? [for (final t in realm.troops) _battlefieldTroop(t)]
          : null,
      towns: [
        for (final town in realm.towns)
          town.copy()
            ..population = 0
            ..garrison = 0
            ..troopCapacity = 0
      ],
    );

/// A war opponent's unit as seen from the battlefield: class, name and
/// position are observable (the Gattung drives the Schere-Stein-Papier
/// counters), but men and drill quality are hidden — only espionage
/// (fuzzed [IntelReport]s) reveals army strength. Zeroing them here keeps
/// the hidden-information rule IN THE DOMAIN MODEL, so a modified client (or
/// anyone inspecting the wire payload) cannot read the enemy's true strength
/// — not merely in what each widget chooses to draw.
Troop _battlefieldTroop(Troop t) => Troop(
      name: t.name,
      men: 0,
      troopClass: t.troopClass,
      quality: 0,
      garrisonCounted: t.garrisonCounted,
      x: t.x,
      y: t.y,
      id: t.id,
      stance: t.stance,
    );
