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
      ..post('/api/v1/matches/<id>/join', _joinMatch)
      ..post('/api/v1/matches/<id>/start', _startMatch)
      ..post('/api/v1/matches/<id>/leave', _leaveMatch)
      ..get('/api/v1/matches/<id>', _getMatch)
      ..post('/api/v1/matches/<id>/turn', _submitTurn);
    return router.call;
  }

  /// Reports the `game_core` build this server is running so a client can
  /// confirm the deployment is current — if these versions are stale, the
  /// server rejects/caps actions a fresh client allows.
  Future<Response> _version(Request request) => _guard(() async => {
        'rules_version': gc.currentRulesVersion,
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

  Future<Response> _createMatch(Request request) => _guard(() async {
        final body = await _json(request);
        final match = await _service.createMatch(
          playerId: _requireString(body, 'player_id'),
          settings: MatchSettings.fromJson(
              (body['settings'] as Map?)?.cast<String, dynamic>() ?? {}),
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

  Future<Response> _getMatch(Request request, String id) => _guard(() {
        final playerId = request.url.queryParameters['player_id'];
        if (playerId == null || playerId.isEmpty) {
          throw ApiException(400, 'player_id query parameter is required');
        }
        return _service.view(id, playerId);
      });

  Future<Response> _submitTurn(Request request, String id) => _guard(() async {
        final body = await _json(request);
        return _service.submit(
          matchId: id,
          playerId: _requireString(body, 'player_id'),
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
    }
  }
}
