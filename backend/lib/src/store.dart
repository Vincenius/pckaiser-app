/// Persistence behind the match service. The interface mirrors the
/// PostgreSQL data model (ARCHITECTURE.md) but lets the server start on
/// a plain JSON file store — the state is one JSON document either way,
/// so swapping in a Postgres-backed implementation later only touches
/// this file.
library;

import 'dart:convert';
import 'dart:io';

import 'models.dart';

abstract class GameStore {
  Future<PlayerRecord?> player(String id);
  Future<void> savePlayer(PlayerRecord player);

  Future<MatchRecord?> match(String id);
  Future<void> saveMatch(MatchRecord match);
  Future<void> deleteMatch(String id);
  Future<List<MatchRecord>> matchesForPlayer(String playerId);

  /// Matches whose turn deadline has passed — the timeout sweep input.
  Future<List<MatchRecord>> expiredMatches(DateTime now);

  /// Public matches still waiting for players — the lobby's open-games list.
  Future<List<MatchRecord>> publicWaitingMatches();
}

/// Volatile store for tests and local development.
class InMemoryStore implements GameStore {
  final Map<String, PlayerRecord> _players = {};
  final Map<String, MatchRecord> _matches = {};

  @override
  Future<PlayerRecord?> player(String id) async => _players[id];

  @override
  Future<void> savePlayer(PlayerRecord player) async =>
      _players[player.id] = player;

  @override
  Future<MatchRecord?> match(String id) async => _matches[id];

  @override
  Future<void> saveMatch(MatchRecord match) async => _matches[match.id] = match;

  @override
  Future<void> deleteMatch(String id) async => _matches.remove(id);

  @override
  Future<List<MatchRecord>> matchesForPlayer(String playerId) async => [
        for (final m in _matches.values)
          if (m.playerById(playerId) != null) m,
      ];

  @override
  Future<List<MatchRecord>> expiredMatches(DateTime now) async => [
        for (final m in _matches.values)
          if (m.status == MatchStatus.active &&
              m.turnDeadline != null &&
              m.turnDeadline!.isBefore(now))
            m,
      ];

  @override
  Future<List<MatchRecord>> publicWaitingMatches() async => [
        for (final m in _matches.values)
          if (m.status == MatchStatus.waiting && m.settings.isPublic) m,
      ];
}

/// Durable single-node store: one JSON file per match plus a players
/// file, written atomically (same pattern as the client's SaveService).
class FileStore implements GameStore {
  FileStore(this.directory) {
    Directory('$directory/matches').createSync(recursive: true);
  }

  final String directory;

  File get _playersFile => File('$directory/players.json');
  File _matchFile(String id) => File('$directory/matches/$id.json');

  Map<String, dynamic> _readJson(File file) => file.existsSync()
      ? (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>()
      : <String, dynamic>{};

  Future<void> _writeAtomic(File file, Object json) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<PlayerRecord?> player(String id) async {
    final all = _readJson(_playersFile);
    final json = all[id];
    if (json == null) return null;
    return PlayerRecord.fromJson((json as Map).cast<String, dynamic>());
  }

  @override
  Future<void> savePlayer(PlayerRecord player) async {
    final all = _readJson(_playersFile);
    all[player.id] = player.toJson();
    await _writeAtomic(_playersFile, all);
  }

  @override
  Future<MatchRecord?> match(String id) async {
    // The id becomes a file name — never trust it as a path. Covers both
    // id schemes: 5-letter room codes and legacy UUIDs.
    if (!RegExp(r'^[0-9A-Za-z-]{1,64}$').hasMatch(id)) return null;
    final file = _matchFile(id);
    if (!file.existsSync()) return null;
    return MatchRecord.fromJson(_readJson(file));
  }

  @override
  Future<void> saveMatch(MatchRecord match) async =>
      _writeAtomic(_matchFile(match.id), match.toJson());

  @override
  Future<void> deleteMatch(String id) async {
    // Same path guard as [match] — the id becomes a file name.
    if (!RegExp(r'^[0-9A-Za-z-]{1,64}$').hasMatch(id)) return;
    final file = _matchFile(id);
    if (file.existsSync()) file.deleteSync();
  }

  Future<List<MatchRecord>> _allMatches() async => [
        for (final f in Directory('$directory/matches').listSync())
          if (f is File && f.path.endsWith('.json'))
            MatchRecord.fromJson(_readJson(f)),
      ];

  @override
  Future<List<MatchRecord>> matchesForPlayer(String playerId) async => [
        for (final m in await _allMatches())
          if (m.playerById(playerId) != null) m,
      ];

  @override
  Future<List<MatchRecord>> expiredMatches(DateTime now) async => [
        for (final m in await _allMatches())
          if (m.status == MatchStatus.active &&
              m.turnDeadline != null &&
              m.turnDeadline!.isBefore(now))
            m,
      ];

  @override
  Future<List<MatchRecord>> publicWaitingMatches() async => [
        for (final m in await _allMatches())
          if (m.status == MatchStatus.waiting && m.settings.isPublic) m,
      ];
}
