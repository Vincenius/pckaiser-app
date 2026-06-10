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
/// - [currentRulesVersion] — the *gameplay rules*. Pinned per game at
///   creation and never changed afterwards: a running game always plays
///   under the rules it started with. A rule/balance change bumps this and
///   gates the new behavior on `state.rulesVersion >= n`, so only games
///   created after the update use it.
library;

/// Bump on incompatible JSON reshapes only; add a migration alongside.
const int currentSchemaVersion = 1;

/// Bump on gameplay rule/balance changes; gate the change on
/// `state.rulesVersion` so running games keep their original rules.
const int currentRulesVersion = 1;

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
