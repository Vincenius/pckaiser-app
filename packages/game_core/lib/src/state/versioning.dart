/// Save/state compatibility (ARCHITECTURE.md "Versioning & compatibility").
///
/// Two independent version numbers travel inside every `GameState` JSON
/// document, so app updates never break existing games — local saves now,
/// online matches too (both store the exact same document):
///
/// - [currentSchemaVersion] — the *shape* of the JSON. Additive changes
///   (new field with a default in `fromJson`) never bump it. Incompatible
///   reshapes (rename, type change, restructure) bump it by one and add a
///   migration step to [schemaMigrations]; old documents are migrated
///   transparently on load.
/// - [currentRulesVersion] — the *gameplay rules*. A rule/balance change
///   bumps this and gates the new behavior on `state.rulesVersion >= n`.
///
///   Policy: every game plays under the LATEST rules — [adoptLatestRules]
///   upgrades `rulesVersion` at the save-load boundary (client
///   `SaveService.load`, the server's document load), and new games start
///   at the latest version anyway. Per-version gates exist only while a
///   change is fresh: they document it, keep the old behavior testable,
///   and are the re-pinning mechanism should online play ever need rule
///   stability within a match.
library;

/// Bump on incompatible JSON reshapes only; add a migration alongside.
const int currentSchemaVersion = 1;

/// Bump on gameplay rule/balance changes; gate the change on
/// `state.rulesVersion` until the next release consolidates the gates.
///
/// v1 is the RELEASE 1 baseline. The fourteen pre-release iterations
/// (combat rework, white peace, manually steered colony ships, the AI
/// war defender, drilling, round-end ruler capture with claim
/// settlement, coercion/conversion fidelity, the half-territory claim
/// cap with capital floor, militarism popularity costs, debt-free
/// conquest, take-all settlement, agent-scaled espionage, and the war
/// bookkeeping gates) were consolidated into this baseline before the
/// first release — their history lives in docs/HISTORY.md.
///
/// v2 lifts the V1 block on human-vs-human wars: `DeclareWar` against
/// human realms is allowed, war-round input alternates between the two
/// human sides (`ActiveWar.actingSlot` — hot-seat handoff locally, the
/// war clock online).
///
/// v3 rolls the war-claim cap per war end (50–80% of the loser's
/// territory value instead of a flat 50% — see `_cappedClaim`) and
/// fires the winter war end when the 20th war round ends (was one round
/// later, contradicting the UI's "Runde X/20" counter). The AI
/// build-tile picks were randomized in the same change (ungated: AI
/// scripting, not a state rule).
///
/// v4 (universal — applied to every game on load, ungated like the AI
/// scripting above):
///  - War armies may march across neutral, unowned land, not only own and
///    enemy territory (`applyWarMove` / the AI war pathing); only a third
///    realm's land still blocks the march.
///  - A realm whose capital tile is lost (war claim, earthquake, bankruptcy
///    seizure) must take a new seat: AI realms re-seat automatically onto
///    their highest-value Stadt/Burg/Palast (random among ties), humans get
///    a `relocateCapital` decision (see `reseatLostCapitals`).
///  - "Sitz verlegen" is allowed at any time now (5,000 T voluntarily; free
///    when re-seating a lost capital), not only when the seat is lost.
///  - Drill ("Truppe ausbilden") raises quality up to 99 (the engine cap was
///    already 99; the client's cost display/gate were fixed to the real
///    `5 × men × quality`).
///  - The `humansDefeated` event now carries the real cause (`reason`) so
///    the defeat screen explains WHY rule, not just "no human dynasty".
///  - Bankruptcy (§19.2) no longer forecloses the instant the treasury
///    crosses the debt limit: a realm gets `bankruptcyGraceTurns` turns
///    below the limit (warned each turn via `debtWarning`) to recover
///    before the creditor seizes tiles. `Realm.debtTurns` tracks the streak.
///
/// v5 (universal — applied to every game on load, ungated):
///  - Söldner are now distinguished from regulars by `garrisonCounted`, not
///    by `quality == 3`. A regular drilled to quality 3 (now common with the
///    v4 drill-to-99 change) was wrongly treated as a mercenary: reinforcing
///    it cost 50 T/man and skipped the quarters check (`applyReinforceTroop`),
///    and §7.4 wages double-counted its men (`computeIncome`). The client hid
///    its drill/retrain buttons and mislabelled it "(Söldner)" at quality 3.
///  - War sea movement (`[DESIGNED]`, not in the original) is now usable two
///    ways. (1) Manual steering: `applyWarMove` lets a unit embark by
///    stepping onto an own Hafen, sail open water tile by tile (1 Zug each,
///    like the colony ship) and disembark on any reachable coast — only a
///    third realm's tiles still block. (2) One-shot transport:
///    `applyWarNavalTransport` ships a harbour-adjacent unit straight to any
///    sea-connected coast. Both target own, enemy OR neutral coast (was: own
///    only) and fight defenders on a contested landing (a repelled landing
///    stays at the embark coast). The client auto-routes to the connecting
///    harbour (`WorldMap.navalEmbarkTile`) when a sea-separated tile is
///    tapped, and tapping water/coast tiles steers manually. AI offensive
///    naval landings are still TODO (the AI defends a landing but does not
///    launch its own — its war pathing treats water as impassable).
const int currentRulesVersion = 5;

/// Upgrades a `GameState` JSON document to the latest gameplay rules
/// (see the library docs: all games always play the latest ruleset).
/// Applied wherever a saved document is loaded for PLAY — deliberately
/// not inside `GameState.fromJson`, which must stay a faithful decoder
/// (tests and tools rebuild old-rules states through it).
Map<String, dynamic> adoptLatestRules(Map<String, dynamic> stateJson) =>
    stateJson..['rulesVersion'] = currentRulesVersion;

/// A document from a newer app version than this one understands.
/// Surfaced to the user as "update the app to load this game" — never
/// guess at unknown future schemas.
class UnsupportedSchemaVersionException implements Exception {
  UnsupportedSchemaVersionException(this.found, this.supported);

  /// `schemaVersion` of the document.
  final int found;

  /// Highest version this build can read ([currentSchemaVersion]).
  final int supported;

  @override
  String toString() =>
      'UnsupportedSchemaVersionException: document has schema version '
      '$found but this build supports at most $supported — update the app';
}

/// One migration step: takes a version-`n` document, returns version `n+1`.
typedef SchemaMigration = Map<String, dynamic> Function(
    Map<String, dynamic> json);

/// Migration steps keyed by *from*-version. When [currentSchemaVersion]
/// becomes `n + 1`, add an entry `n: (json) => ...` here, e.g.:
///
/// ```dart
/// 1: (json) => json..['treasuries'] = json.remove('treasury'),
/// ```
///
/// Steps may mutate and return their argument; [migrateGameStateJson]
/// hands them a private copy.
const Map<int, SchemaMigration> schemaMigrations = {};

/// Brings a `GameState` JSON document (or a full save document containing
/// one) up to [currentSchemaVersion] by applying [schemaMigrations]
/// sequentially. Documents without a `schemaVersion` field are version 1
/// (written before the field existed).
///
/// Called by `GameState.fromJson`, so every load path — local save file
/// and the server's JSONB column — migrates automatically.
///
/// Throws [UnsupportedSchemaVersionException] for documents from a newer
/// app version, and [StateError] if a migration step is missing.
///
/// [toVersion] and [migrations] exist for tests only.
Map<String, dynamic> migrateGameStateJson(
  Map<String, dynamic> json, {
  int toVersion = currentSchemaVersion,
  Map<int, SchemaMigration> migrations = schemaMigrations,
}) {
  final from = json['schemaVersion'] as int? ?? 1;
  if (from > toVersion) {
    throw UnsupportedSchemaVersionException(from, toVersion);
  }
  if (from == toVersion) return json;

  var doc = Map<String, dynamic>.of(json);
  for (var v = from; v < toVersion; v++) {
    final step = migrations[v];
    if (step == null) {
      throw StateError('no schema migration from version $v to ${v + 1}');
    }
    doc = step(doc);
  }
  doc['schemaVersion'] = toVersion;
  return doc;
}
