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
/// composition and army size, guard level, popularity, population numbers,
/// town garrisons, movement points, per-turn flags, intel reports.
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

  return filtered;
}

/// Strips a foreign realm down to its public face. Identity, title, capital
/// and town tiers stay (visible on the map anyway); all economy and
/// military numbers go to zero, meaning "unknown" — the UI must render
/// foreign zeros as hidden, not as the value 0.
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
