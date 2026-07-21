/// Save/state compatibility (ARCHITECTURE.md "Versioning & compatibility").
///
/// Every game always plays under the LATEST rules — there is no per-game
/// "ruleset version" to pin or migrate. A balance or rule change ships in
/// a new APP version; local saves simply adopt the new behavior on load,
/// and online matches require every seat to run the same app version
/// before they may take their turn (the server rejects a stale client —
/// see [appVersion] and the match service's turn submission).
///
/// One version number still travels inside every `GameState` JSON
/// document: [currentSchemaVersion], the *shape* of the JSON. Additive
/// changes (a new field with a default in `fromJson`) never bump it.
/// Incompatible reshapes (rename, type change, restructure) bump it by one
/// and add a migration step to [schemaMigrations]; old documents are
/// migrated transparently on load, and a document from a newer app version
/// is rejected with [UnsupportedSchemaVersionException] instead of guessed
/// at.
library;

/// The app's release version. The single source of truth shared by the
/// Flutter client (shown on the About screen, sent with every online turn
/// submission) and the Dart server (the build it runs, the version every
/// client must match to play). Mirror it in each `pubspec.yaml` `version:`
/// — the client guards the match in `test/app_version_test.dart`.
///
/// Bump this on every release that changes gameplay: an online match then
/// asks any seat still on the old build to update before their next turn.
const String appVersion = '0.2.0';

/// Bump on incompatible JSON reshapes only; add a migration alongside.
const int currentSchemaVersion = 1;

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
