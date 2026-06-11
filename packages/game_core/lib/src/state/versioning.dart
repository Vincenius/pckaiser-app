/// Save/state compatibility (ARCHITECTURE.md "Versioning & compatibility").
///
/// Two independent version numbers travel inside every `GameState` JSON
/// document, so app updates never break existing games — local saves now,
/// online matches later (both store the exact same document):
///
/// - [currentSchemaVersion] — the *shape* of the JSON. Additive changes
///   (new field with a default in `fromJson`) never bump it. Incompatible
///   reshapes (rename, type change, restructure) bump it by one and add a
///   migration step to [schemaMigrations]; old documents are migrated
///   transparently on load.
/// - [currentRulesVersion] — the *gameplay rules*. A rule/balance change
///   bumps this and gates the new behavior on `state.rulesVersion >= n`.
///
///   Policy (changed 2026-06-11 by product decision): every game plays
///   under the LATEST rules — [adoptLatestRules] upgrades `rulesVersion`
///   at the save-load boundary (client `SaveService.load` now, the
///   server's document load later), and new games start at the latest
///   version anyway. The per-version gates stay in the engine: they
///   document each change, keep old behavior testable, and are the
///   re-pinning mechanism should online play ever need rule stability
///   within a match.
library;

/// Bump on incompatible JSON reshapes only; add a migration alongside.
const int currentSchemaVersion = 1;

/// Bump on gameplay rule/balance changes; gate the change on
/// `state.rulesVersion` so running games keep their original rules.
///
/// Changelog:
/// - v2 (2026-06-10): bare land costs 100 T in war claim settlements
///   (was 0 — any limited victory could strip the loser of all empty
///   tiles for free); war plunder only hits the war opponent (was: any
///   foreign realm a unit reached); recruiting, hiring Söldner,
///   reinforcing and peacetime troop moves are blocked while at war
///   (matching the existing merge/disband gate); a conquered town's
///   garrison is also removed from the loser's garrison-counted units.
/// - v3 (2026-06-11): peacetime troop moves (`MoveTroop`) no longer cost
///   a movement point — only building/claiming/demolishing consume Züge.
/// - v4 (2026-06-11): ruler capture requires the enemy capital tile to
///   still be OWNED by the enemy (was: coordinates only — a realm whose
///   capital tile had been conquered/seized earlier could be captured by
///   stepping onto a tile the attacker already owned); moving onto a tile
///   with several stacked enemy units fights them ALL, one after another
///   (was: only the first, then free co-location); an assassination whose
///   agents were all caught always fails (was: still 30%); `MergeRealms`
///   is blocked while either realm is in the active war (same reason as
///   the v2 recruit/reinforce gate — merged-in troops desync the war
///   bookkeeping); Kaiser-election candidates must currently rule a realm
///   (was: a deposed Kurfürst could be elected and hold a throne with no
///   realm to collect the pot).
/// - v5 (2026-06-11): war overhaul — (1) every army-vs-army encounter is
///   DECIDED: the side with the higher `P × (1+def/2) × fortune` wins
///   the clash, the loser takes 35–65% casualties (remnants under 5 men
///   are wiped), the winner 10–25% and always survives — a unit falls
///   after ~2–5 engagements (was: a single power-scaled roll that
///   typically killed 0–3 men, dragging wars on forever; the original's
///   combat was even more cosmetic — losses `P × def × 0.2 × R`,
///   R ∈ [0, 0.1), zero on open ground — its wars were walking races
///   decided by the score);
///   (2) mutual peace is a WHITE peace: both sides return home, no
///   tiles, no claim, no payment (was: the leading side collected its
///   full claim, auto-converting occupied tiles on a decisive score —
///   agreeing to peace could lose you land); (3) a war decided by winter
///   always opens the claim settlement, where the winner SELECTS which
///   loser tiles to annex (was: a decisive score auto-converted every
///   occupied tile with no choice) — ruler capture still takes the whole
///   realm; (4) the `TrainTroop` action (original "Truppe ausbilden"):
///   retrain a regular unit to another class for 5 T/man plus the class
///   surcharge (Kavallerie +500, Artillerie +1,000); (5) "Bürgerlich
///   heiraten" is always available: it no longer checks or consumes the
///   one-royal-proposal-per-turn gate (was: both marriage actions shared
///   it — a rejected royal proposal locked out commoner marriage too).
/// - v6 (2026-06-11): the original's "(S)chiff" colony ship (`SendShip`,
///   manual: send ships from a Hafen to colonize e.g. uninhabited
///   islands; disassembly proc_005D2B: flat 700 T, ship consumed): claim
///   any free land tile reachable over open water from an own Hafen for
///   700 T + 1 movement point. Pre-v6 games keep playing without it
///   (new capability = balance change).
/// - v7 (2026-06-11): (1) the AI war defender fights back — units
///   intercept enemy units standing on own territory and, once the
///   enemy army is wiped out or clearly outmatched (>1.5× strength),
///   counter-march on the enemy capital (was: defenders only ever
///   walked back to their pre-war spots, so a beaten attacker faced an
///   enemy that "never moved"); AI war pathing uses a BFS around water
///   (was: greedy axis step that stranded units on lake shores);
///   (2) `DrillTroop` — the traced original "Truppe ausbilden"
///   (proc_00A316): +1 quality for 5 T/man with no class change; once
///   per unit per turn, regulars only, capped at quality 10 [DESIGNED]
///   (the v5 `TrainTroop` class retrain stays, relabeled "umrüsten").
/// - v8 (2026-06-11): drilling has no per-turn limit anymore — a unit
///   may drill as often as the treasury allows within one turn; the
///   quality cap (10) still bounds the total `[DESIGNED]`.
const int currentRulesVersion = 8;

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
