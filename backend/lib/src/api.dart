/// REST API (`/api/v1`, ARCHITECTURE.md): thin shelf layer over
/// [MatchService]. Responses are `{data, error}`; 400 validation,
/// 403 wrong turn/seat, 404 missing.
library;

import 'dart:convert';

import 'package:game_core/game_core.dart' as gc;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'match_service.dart';
import 'models.dart';

class Api {
  Api(this._service);

  final MatchService _service;

  Handler get handler {
    final router = Router()
      ..get('/version', _version)
      ..get('/api/v1/version', _version)
      ..post('/api/v1/players', _registerPlayer)
      ..patch('/api/v1/players/<id>', _updatePlayer)
      ..get('/api/v1/players/<id>/matches', _playerMatches)
      ..post('/api/v1/matches', _createMatch)
      // Must precede `/matches/<id>` so "public" isn't taken as a match id.
      ..get('/api/v1/matches/public', _publicMatches)
      ..post('/api/v1/matches/<id>/join', _joinMatch)
      ..post('/api/v1/matches/<id>/start', _startMatch)
      ..post('/api/v1/matches/<id>/leave', _leaveMatch)
      ..post('/api/v1/matches/<id>/kick', _kickPlayer)
      ..get('/api/v1/matches/<id>/openslots', _openSlots)
      ..get('/api/v1/matches/<id>', _getMatch)
      ..post('/api/v1/matches/<id>/turn', _submitTurn);
    return router.call;
  }

  /// Reports the app build this server is running so a client can confirm
  /// the deployment is current — an online turn from a client on a
  /// different [gc.appVersion] is rejected (426) until the app is updated.
  Future<Response> _version(Request request) => _guard(() async => {
        'app_version': gc.appVersion,
        'schema_version': gc.currentSchemaVersion,
      });

  Future<Response> _registerPlayer(Request request) => _guard(() async {
        final body = await _json(request);
        final player = await _service.registerPlayer(
          id: body['id'] as String?,
          displayName: body['display_name'] as String? ?? '',
          fcmToken: body['fcm_token'] as String?,
        );
        return player.toJson();
      });

  Future<Response> _updatePlayer(Request request, String id) =>
      _guard(() async {
        final body = await _json(request);
        final player = await _service.updatePlayer(
          id,
          displayName: body['display_name'] as String?,
          fcmToken: body['fcm_token'] as String?,
        );
        return player.toJson();
      });

  Future<Response> _playerMatches(Request request, String id) =>
      _guard(() => _service.matchesForPlayer(id));

  Future<Response> _publicMatches(Request request) =>
      _guard(() => _service.publicMatches());

  Future<Response> _createMatch(Request request) => _guard(() async {
        final body = await _json(request);
        // The seed is server-chosen: a creating client must not be able to
        // pick (and thus predict) the match's random stream.
        final settingsJson =
            (body['settings'] as Map?)?.cast<String, dynamic>() ?? {};
        settingsJson.remove('seed');
        // Matchmaking rooms are server-hosted (no creator, automatic start,
        // never deleted by leaving) — a client must not be able to open one
        // by claiming a template key.
        settingsJson.remove('template');
        // A wrong field TYPE inside a well-formed body is a client error —
        // report 400, not the catch-all 500.
        final MatchSettings settings;
        try {
          settings = MatchSettings.fromJson(settingsJson);
        } on TypeError {
          throw ApiException(400, 'invalid field type in settings');
        }
        final match = await _service.createMatch(
          playerId: _requireString(body, 'player_id'),
          settings: settings,
          setup: (body['setup'] as Map?)?.cast<String, dynamic>() ?? {},
        );
        return _service.view(match.id, _requireString(body, 'player_id'));
      });

  Future<Response> _joinMatch(Request request, String id) => _guard(() async {
        final body = await _json(request);
        final match = await _service.joinMatch(
          matchId: id,
          playerId: _requireString(body, 'player_id'),
          setup: (body['setup'] as Map?)?.cast<String, dynamic>() ?? {},
        );
        return _service.view(match.id, _requireString(body, 'player_id'));
      });

  Future<Response> _startMatch(Request request, String id) => _guard(() async {
        final body = await _json(request);
        final match = await _service.startMatch(
          matchId: id,
          playerId: _requireString(body, 'player_id'),
        );
        return _service.view(match.id, _requireString(body, 'player_id'));
      });

  Future<Response> _leaveMatch(Request request, String id) => _guard(() async {
        final body = await _json(request);
        final deleted = await _service.leaveMatch(
          matchId: id,
          playerId: _requireString(body, 'player_id'),
        );
        return {'left': true, 'deleted': deleted};
      });

  Future<Response> _kickPlayer(Request request, String id) => _guard(() async {
        final body = await _json(request);
        final requesterId = _requireString(body, 'player_id');
        await _service.kickPlayer(
          matchId: id,
          requesterId: requesterId,
          targetPlayerId: _requireString(body, 'target_player_id'),
        );
        return _service.view(id, requesterId);
      });

  Future<Response> _openSlots(Request request, String id) =>
      _guard(() => _service.openSlots(id));

  Future<Response> _getMatch(Request request, String id) => _guard(() {
        final playerId = request.url.queryParameters['player_id'];
        if (playerId == null || playerId.isEmpty) {
          throw ApiException(400, 'player_id query parameter is required');
        }
        return _service.view(
          id,
          playerId,
          clientAppVersion: request.url.queryParameters['app_version'],
        );
      });

  Future<Response> _submitTurn(Request request, String id) => _guard(() async {
        final body = await _json(request);
        return _service.submit(
          matchId: id,
          playerId: _requireString(body, 'player_id'),
          // The client always sends its build; a stale one is rejected (426).
          clientAppVersion: _requireString(body, 'app_version'),
          // Optional UI language so a rejection reads in the player's tongue.
          clientLocale: body['locale'] as String?,
          actionJson: (body['action'] as Map?)?.cast<String, dynamic>(),
          endTurn: body['end_turn'] == true,
        );
      });

  String _requireString(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is! String || value.isEmpty) {
      throw ApiException(400, '$key is required');
    }
    return value;
  }

  Future<Map<String, dynamic>> _json(Request request) async {
    try {
      final text = await request.readAsString();
      if (text.isEmpty) return {};
      return (jsonDecode(text) as Map).cast<String, dynamic>();
    } on Object {
      throw ApiException(400, 'malformed JSON body');
    }
  }

  Future<Response> _guard(Future<Object?> Function() body) async {
    try {
      final data = await body();
      return Response.ok(
        jsonEncode({'data': data, 'error': null}),
        headers: {'content-type': 'application/json'},
      );
    } on ApiException catch (e) {
      return Response(
        e.statusCode,
        body: jsonEncode({'data': null, 'error': e.message}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e, stack) {
      // Any non-ApiException (a corrupt match document, an engine
      // StateError, …) must still return the documented {data,error}
      // envelope the client parses — never a bare shelf 500 — and must not
      // be allowed to take down an unrelated request (e.g. the lobby list).
      print('[api] unhandled error: $e\n$stack');
      return Response(
        500,
        body: jsonEncode({'data': null, 'error': 'internal server error'}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
