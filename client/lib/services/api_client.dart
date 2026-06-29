import 'dart:convert';
import 'dart:io';

import '../app_version.dart';

/// Error from the server's `{data, error}` envelope (or transport).
class ApiError implements Exception {
  ApiError(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// Thin typed client for the V2 server (`/api/v1`, ARCHITECTURE.md).
/// Pure transport — no game logic; the server validates everything.
class ApiClient {
  ApiClient(this.baseUrl, {HttpClient? httpClient})
    : _http = httpClient ?? HttpClient();

  /// e.g. `https://kaiser.example.com` (no trailing slash).
  final String baseUrl;
  final HttpClient _http;

  Future<Map<String, dynamic>> registerPlayer({
    required String id,
    required String displayName,
    String? fcmToken,
  }) => _request(
    'POST',
    '/api/v1/players',
    body: {'id': id, 'display_name': displayName, 'fcm_token': fcmToken},
  );

  Future<Map<String, dynamic>> updatePlayer({
    required String id,
    String? displayName,
    String? fcmToken,
  }) => _request(
    'PATCH',
    '/api/v1/players/$id',
    body: {'display_name': ?displayName, 'fcm_token': ?fcmToken},
  );

  Future<Map<String, dynamic>> createMatch({
    required String playerId,
    required Map<String, dynamic> settings,
    required Map<String, dynamic> setup,
  }) => _request(
    'POST',
    '/api/v1/matches',
    body: {'player_id': playerId, 'settings': settings, 'setup': setup},
  );

  Future<Map<String, dynamic>> joinMatch({
    required String matchId,
    required String playerId,
    required Map<String, dynamic> setup,
  }) => _request(
    'POST',
    '/api/v1/matches/$matchId/join',
    body: {'player_id': playerId, 'setup': setup},
  );

  /// Open public matches anyone may join (the lobby's discovery list).
  Future<List<dynamic>> publicMatches() async =>
      (await _request(
            'GET',
            '/api/v1/matches/public',
            expectList: true,
          ))['list']
          as List<dynamic>;

  /// Starts a waiting match — creator only.
  Future<Map<String, dynamic>> startMatch({
    required String matchId,
    required String playerId,
  }) => _request(
    'POST',
    '/api/v1/matches/$matchId/start',
    body: {'player_id': playerId},
  );

  /// Leaves (or, as creator of a waiting match, deletes) a match. In a
  /// running game the server hands the seat's realm to the AI.
  Future<Map<String, dynamic>> leaveMatch({
    required String matchId,
    required String playerId,
  }) => _request(
    'POST',
    '/api/v1/matches/$matchId/leave',
    body: {'player_id': playerId},
  );

  /// Kicks an idle seat and replaces its realm with the AI — creator only,
  /// allowed once the seat has missed several turns in a row.
  Future<Map<String, dynamic>> kickPlayer({
    required String matchId,
    required String playerId,
    required String targetPlayerId,
  }) => _request(
    'POST',
    '/api/v1/matches/$matchId/kick',
    body: {'player_id': playerId, 'target_player_id': targetPlayerId},
  );

  Future<Map<String, dynamic>> match(String matchId, String playerId) =>
      _request(
        'GET',
        '/api/v1/matches/$matchId?player_id=$playerId&app_version=$appVersion',
      );

  Future<List<dynamic>> myMatches(String playerId) async =>
      (await _request(
            'GET',
            '/api/v1/players/$playerId/matches',
            expectList: true,
          ))['list']
          as List<dynamic>;

  Future<Map<String, dynamic>> submitAction({
    required String matchId,
    required String playerId,
    required Map<String, dynamic> action,
  }) => _request(
    'POST',
    '/api/v1/matches/$matchId/turn',
    body: {'player_id': playerId, 'app_version': appVersion, 'action': action},
  );

  Future<Map<String, dynamic>> endTurn({
    required String matchId,
    required String playerId,
  }) => _request(
    'POST',
    '/api/v1/matches/$matchId/turn',
    body: {'player_id': playerId, 'app_version': appVersion, 'end_turn': true},
  );

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool expectList = false,
  }) async {
    final HttpClientRequest request;
    try {
      request = await _http.openUrl(method, Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final decoded = (jsonDecode(text) as Map).cast<String, dynamic>();
      if (response.statusCode != 200) {
        throw ApiError(
          response.statusCode,
          decoded['error'] as String? ?? 'Serverfehler',
        );
      }
      final data = decoded['data'];
      if (expectList) return {'list': data as List<dynamic>};
      return (data as Map).cast<String, dynamic>();
    } on ApiError {
      rethrow;
    } on Object catch (e) {
      throw ApiError(0, 'Server nicht erreichbar: $e');
    }
  }
}
