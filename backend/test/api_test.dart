import 'dart:convert';

import 'package:backend/backend.dart';
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
  }) async {
    final request = Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null ? null : jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );
    final response = await handler(request);
    final decoded =
        (jsonDecode(await response.readAsString()) as Map)
            .cast<String, dynamic>();
    return (response.statusCode, decoded);
  }

  test('register → create → play a turn over HTTP', () async {
    final (status, registered) = await call('POST', '/api/v1/players',
        body: {'display_name': 'Anna'});
    expect(status, 200);
    final playerId = (registered['data'] as Map)['id'] as String;

    final (createStatus, created) = await call('POST', '/api/v1/matches',
        body: {
          'player_id': playerId,
          'human_count': 1,
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
    expect(match['status'], 'active');
    expect(match['your_turn'], true);
    final matchId = match['id'] as String;

    final (turnStatus, turned) = await call(
        'POST', '/api/v1/matches/$matchId/turn',
        body: {'player_id': playerId, 'end_turn': true});
    expect(turnStatus, 200);
    expect((turned['data'] as Map)['your_turn'], true,
        reason: 'sole human: the next year comes right back to them');

    final (listStatus, list) =
        await call('GET', '/api/v1/players/$playerId/matches');
    expect(listStatus, 200);
    expect((list['data'] as List), hasLength(1));
  });

  test('status mapping: 404 unknown, 400 validation, 403 foreign', () async {
    final (notFound, nf) = await call('GET',
        '/api/v1/matches/doesnotexist?player_id=nobody');
    expect(notFound, 404);
    expect(nf['error'], isNotNull);

    final (badRequest, br) =
        await call('POST', '/api/v1/players', body: {'display_name': ''});
    expect(badRequest, 400);
    expect(br['error'], isNotNull);

    final (_, registered) = await call('POST', '/api/v1/players',
        body: {'display_name': 'Anna'});
    final playerId = ((registered['data'] as Map)['id']) as String;
    final (_, created) = await call('POST', '/api/v1/matches', body: {
      'player_id': playerId,
      'human_count': 1,
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
    final (forbidden, fb) = await call(
        'GET', '/api/v1/matches/$matchId?player_id=$strangerId');
    expect(forbidden, 403);
    expect(fb['error'], isNotNull);
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
