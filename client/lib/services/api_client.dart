import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app_version.dart';
import '../l10n/strings.dart' show appLocale, tr;

/// Why a request failed — the transport reasons are told apart so the UI
/// can say what actually went wrong instead of one catch-all
/// "Server nicht erreichbar" (user request 2026-08-08). `server` covers
/// everything the server itself answered ([ApiError.statusCode] then
/// carries its HTTP status and the message its `{data, error}` envelope
/// sent, already in the player's language).
enum ApiFailure {
  /// No route to the internet at all (airplane mode, no Wi-Fi/mobile data).
  offline,

  /// The address could not be resolved — typically a mistyped or outdated
  /// server address (or DNS is down).
  unknownHost,

  /// The host answered but refuses connections: the server is down or
  /// restarting, or nothing listens on that port.
  refused,

  /// The connection or the response took too long (server overloaded, or a
  /// captive-portal/very slow link).
  timeout,

  /// TLS handshake failed — wrong certificate, clock far off, plain HTTP
  /// behind an HTTPS URL.
  tls,

  /// Reached the server but the answer was not the documented envelope —
  /// usually a proxy/error page in front of it, or a wrong base URL.
  badResponse,

  /// The server answered with a non-200 status and a message of its own.
  server,
}

/// Error from the server's `{data, error}` envelope (or transport).
class ApiError implements Exception {
  ApiError(this.statusCode, this.message, {this.failure = ApiFailure.server});

  /// HTTP status, or 0 when the request never got an answer.
  final int statusCode;

  /// Player-facing, localized text — shown as-is by every call site.
  final String message;

  final ApiFailure failure;

  /// True for transport-level failures — the request got no usable answer
  /// from the game server, so the UI shows the offline-style heading and a
  /// retry. NOT a guarantee the request never arrived: a timeout or a
  /// proxy's 5xx page may hide a request the server did process, so this
  /// must never gate an automatic re-submit.
  bool get isOffline => failure != ApiFailure.server;

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

  /// [pushOptOut] is the FULL set of muted notification kinds (Options ▸
  /// Notifications); omitting it leaves the server's stored set alone.
  Future<Map<String, dynamic>> updatePlayer({
    required String id,
    String? displayName,
    String? fcmToken,
    Set<String>? pushOptOut,
  }) => _request(
    'PATCH',
    '/api/v1/players/$id',
    body: {
      'display_name': ?displayName,
      'fcm_token': ?fcmToken,
      if (pushOptOut != null) 'push_opt_out': pushOptOut.toList()..sort(),
    },
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

  /// Country slots already taken in a (waiting) match, so a joiner can see
  /// which realms are still free before committing. Best-effort UX hint —
  /// the join call validates authoritatively.
  Future<Map<String, dynamic>> openSlots(String matchId) =>
      _request('GET', '/api/v1/matches/$matchId/openslots');

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
    body: {
      'player_id': playerId,
      'app_version': appVersion,
      // So the server renders any rejection in this player's language.
      'locale': appLocale.value,
      'action': action,
    },
  );

  Future<Map<String, dynamic>> endTurn({
    required String matchId,
    required String playerId,
  }) => _request(
    'POST',
    '/api/v1/matches/$matchId/turn',
    body: {
      'player_id': playerId,
      'app_version': appVersion,
      'locale': appLocale.value,
      'end_turn': true,
    },
  );

  /// How long a single call may take end to end before it is reported as
  /// [ApiFailure.timeout]. Without it a dead-but-reachable host (dropped
  /// packets, captive portal) left the UI on its spinner indefinitely.
  static const Duration requestTimeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool expectList = false,
  }) async {
    try {
      return await _send(method, path, body: body, expectList: expectList)
          .timeout(requestTimeout);
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw _transportError(ApiFailure.timeout);
    } on SocketException catch (e) {
      // `osError == null` on a name-lookup failure; the codes below are the
      // portable ones dart:io surfaces for "nothing there" vs "no network".
      final code = e.osError?.errorCode;
      throw _transportError(
        e.message.contains('Failed host lookup')
            ? ApiFailure.unknownHost
            : code == 61 || code == 111 || code == 10061 // ECONNREFUSED
            ? ApiFailure.refused
            // ENETUNREACH: Darwin 51 / Linux 101; EHOSTUNREACH: Darwin 65 /
            // Linux 113 (Android is Linux — without 113 an unreachable host
            // there read as "server refuses connections").
            : code == 51 || code == 101 || code == 65 || code == 113
            ? ApiFailure.offline
            : ApiFailure.refused,
      );
    } on HandshakeException {
      throw _transportError(ApiFailure.tls);
    } on TlsException {
      throw _transportError(ApiFailure.tls);
    } on HttpException {
      throw _transportError(ApiFailure.badResponse);
    } on FormatException {
      // Reached something that isn't our server (proxy/error page) — or a
      // malformed URL. Either way the answer is unusable.
      throw _transportError(ApiFailure.badResponse);
    } on Object {
      throw _transportError(ApiFailure.offline);
    }
  }

  ApiError _transportError(ApiFailure failure) => ApiError(
    0,
    switch (failure) {
      ApiFailure.unknownHost => tr('online.errUnknownHost', {'url': baseUrl}),
      ApiFailure.refused => tr('online.errRefused'),
      ApiFailure.timeout => tr('online.errTimeout'),
      ApiFailure.tls => tr('online.errTls'),
      ApiFailure.badResponse => tr('online.errBadResponse'),
      _ => tr('online.errOffline'),
    },
    failure: failure,
  );

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool expectList = false,
  }) async {
    final request = await _http.openUrl(method, Uri.parse('$baseUrl$path'));
    request.headers.contentType = ContentType.json;
    // The UI language, on EVERY request (GETs included): the server formats
    // its rejection messages in this language. The `locale` body field of
    // the turn submit stays — it localizes the engine's rule rejections.
    request.headers.set(HttpHeaders.acceptLanguageHeader, appLocale.value);
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final Map<String, dynamic> decoded;
    try {
      decoded = (jsonDecode(text) as Map).cast<String, dynamic>();
    } on Object {
      // A non-200 that isn't our envelope is a gateway/proxy talking, not
      // the game server — name the status so 502/503 reads as "server is
      // down" rather than a parse failure.
      throw ApiError(
        response.statusCode,
        response.statusCode >= 500 || response.statusCode == 0
            ? tr('online.errServerDown')
            : tr('online.errBadResponse'),
        failure: response.statusCode >= 500
            ? ApiFailure.refused
            : ApiFailure.badResponse,
      );
    }
    if (response.statusCode != 200) {
      throw ApiError(
        response.statusCode,
        // The server sends its rejections already localized (it reads the
        // Accept-Language header sent above); only the fallback is ours.
        decoded['error'] as String? ??
            (response.statusCode >= 500
                ? tr('online.errServerDown')
                : tr('online.errServer', {'code': '${response.statusCode}'})),
      );
    }
    final data = decoded['data'];
    if (expectList) return {'list': data as List<dynamic>};
    return (data as Map).cast<String, dynamic>();
  }
}
