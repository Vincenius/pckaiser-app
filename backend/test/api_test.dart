import 'dart:convert';

import 'package:backend/backend.dart';
import 'package:game_core/game_core.dart' show appVersion;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// The shelf layer: routing, body parsing, the {data, error} envelope and
/// status mapping. The game logic itself is covered in
/// match_service_test.dart.
void main() {
  late Handler handler;

  setUp(() {
    handler = Api(MatchService(InMemoryStore(), LogPushService())).handler;
  });

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final request = Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null ? null : jsonEncode(body),
      headers: {'content-type': 'application/json', ...?headers},
    );
    final response = await handler(request);
    final decoded = (jsonDecode(await response.readAsString()) as Map)
        .cast<String, dynamic>();
    return (response.statusCode, decoded);
  }

  test('register → create → start → play a turn over HTTP', () async {
    final (status, registered) =
        await call('POST', '/api/v1/players', body: {'display_name': 'Anna'});
    expect(status, 200);
    final playerId = (registered['data'] as Map)['id'] as String;

    final (createStatus, created) =
        await call('POST', '/api/v1/matches', body: {
      'player_id': playerId,
      'settings': {'seed': 42},
      'setup': {
        'founder_name': 'Anna',
        'gender': 1,
        'country_slot': 3,
        'dorf_name': 'Annadorf',
      },
    });
    expect(createStatus, 200);
    final match = (created['data'] as Map).cast<String, dynamic>();
    expect(match['status'], 'waiting');
    expect(match['id'], matches(RegExp(r'^[A-Z]{5}$')),
        reason: '5-letter room code');
    final matchId = match['id'] as String;

    final (startStatus, started) = await call(
        'POST', '/api/v1/matches/$matchId/start',
        body: {'player_id': playerId});
    expect(startStatus, 200);
    expect((started['data'] as Map)['status'], 'active');
    expect((started['data'] as Map)['your_turn'], true);

    final (turnStatus, turned) =
        await call('POST', '/api/v1/matches/$matchId/turn', body: {
      'player_id': playerId,
      'app_version': appVersion,
      'end_turn': true,
    });
    expect(turnStatus, 200);
    expect((turned['data'] as Map)['your_turn'], true,
        reason: 'sole human: the next year comes right back to them');

    final (listStatus, list) =
        await call('GET', '/api/v1/players/$playerId/matches');
    expect(listStatus, 200);
    expect((list['data'] as List), hasLength(1));
  });

  test('a turn from a stale app version is rejected (426)', () async {
    final (_, registered) =
        await call('POST', '/api/v1/players', body: {'display_name': 'Anna'});
    final playerId = (registered['data'] as Map)['id'] as String;
    final (_, created) = await call('POST', '/api/v1/matches', body: {
      'player_id': playerId,
      'settings': {'seed': 42},
      'setup': {
        'founder_name': 'Anna',
        'gender': 1,
        'country_slot': 3,
        'dorf_name': 'Annadorf',
      },
    });
    final matchId = (created['data'] as Map)['id'] as String;
    await call('POST', '/api/v1/matches/$matchId/start',
        body: {'player_id': playerId});

    // A client on an old build may not take its turn until it updates.
    final (stale, body) =
        await call('POST', '/api/v1/matches/$matchId/turn', body: {
      'player_id': playerId,
      'app_version': '0.0.1',
      'end_turn': true,
    });
    expect(stale, 426);
    expect(body['error'], contains('aktualisiere'));

    // The version endpoint advertises the build every client must match.
    final (versionStatus, version) = await call('GET', '/version');
    expect(versionStatus, 200);
    expect((version['data'] as Map)['app_version'], appVersion);
  });

  test('status mapping: 404 unknown, 400 validation, 403 foreign', () async {
    final (notFound, nf) =
        await call('GET', '/api/v1/matches/doesnotexist?player_id=nobody');
    expect(notFound, 404);
    expect(nf['error'], isNotNull);

    final (badRequest, br) =
        await call('POST', '/api/v1/players', body: {'display_name': ''});
    expect(badRequest, 400);
    expect(br['error'], isNotNull);

    final (_, registered) =
        await call('POST', '/api/v1/players', body: {'display_name': 'Anna'});
    final playerId = ((registered['data'] as Map)['id']) as String;
    final (_, created) = await call('POST', '/api/v1/matches', body: {
      'player_id': playerId,
      'settings': {'seed': 42},
      'setup': {
        'founder_name': 'Anna',
        'gender': 1,
        'country_slot': 3,
        'dorf_name': 'Annadorf',
      },
    });
    final matchId = ((created['data'] as Map)['id']) as String;
    final (_, stranger) = await call('POST', '/api/v1/players',
        body: {'display_name': 'Fremder'});
    final strangerId = ((stranger['data'] as Map)['id']) as String;
    final (forbidden, fb) =
        await call('GET', '/api/v1/matches/$matchId?player_id=$strangerId');
    expect(forbidden, 403);
    expect(fb['error'], isNotNull);
  });

  test(
      'rejections are player-readable and follow the Accept-Language '
      'header (2026-08-08)', () async {
    // No header → German, like clients from before the header (≤ 0.2.4).
    final (_, de) =
        await call('GET', '/api/v1/matches/doesnotexist?player_id=nobody');
    expect(de['error'], contains('Partie wurde nicht gefunden'),
        reason: 'a full German sentence, not developer English');

    // A region-tagged English header resolves to English.
    final (_, en) = await call(
        'GET', '/api/v1/matches/doesnotexist?player_id=nobody',
        headers: {'accept-language': 'en-US'});
    expect(en['error'], contains('could not be found'));

    // No raw catalog key may ever leak to a player.
    expect('${de['error']}${en['error']}', isNot(contains('api.')));
  });

  test('malformed JSON is a 400, not a crash', () async {
    final request = Request(
      'POST',
      Uri.parse('http://localhost/api/v1/players'),
      body: '{not json',
    );
    final response = await handler(request);
    expect(response.statusCode, 400);
  });
}
