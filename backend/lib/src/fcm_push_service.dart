/// FCM HTTP-v1 push (ARCHITECTURE.md "FCM"): authenticates with a
/// service account and posts one message per notification. Strictly
/// fire-and-forget — every failure is logged and swallowed; the game
/// must work without push.
///
/// Enabled by `FIREBASE_SERVICE_ACCOUNT` (the service-account JSON,
/// base64-encoded); without it the server falls back to [LogPushService].
library;

import 'dart:convert';

import 'package:googleapis_auth/auth_io.dart';

import 'models.dart';
import 'push_service.dart';

class FcmPushService implements PushService {
  FcmPushService._(this._projectId, this._credentials);

  /// Builds the service from the base64-encoded service-account JSON
  /// (`FIREBASE_SERVICE_ACCOUNT`); returns null when it is malformed.
  static FcmPushService? fromEnv(String? base64Json) {
    if (base64Json == null || base64Json.trim().isEmpty) return null;
    try {
      final json =
          (jsonDecode(utf8.decode(base64Decode(base64Json.trim()))) as Map)
              .cast<String, dynamic>();
      return FcmPushService._(
        json['project_id'] as String,
        ServiceAccountCredentials.fromJson(json),
      );
    } on Object catch (e) {
      print('[push] invalid FIREBASE_SERVICE_ACCOUNT: $e');
      return null;
    }
  }

  static const _scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

  final String _projectId;
  final ServiceAccountCredentials _credentials;
  AutoRefreshingAuthClient? _client;

  Future<void> _send(
    PlayerRecord player,
    MatchRecord match,
    String kind,
    String title,
    String body,
  ) async {
    final token = player.fcmToken;
    if (token == null || token.isEmpty) return;
    try {
      _client ??= await clientViaServiceAccount(_credentials, _scopes);
      final response = await _client!.post(
        Uri.parse(
            'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'message': {
            'token': token,
            'notification': {'title': title, 'body': body},
            'data': {'kind': kind, 'match_id': match.id},
          },
        }),
      );
      if (response.statusCode != 200) {
        print('[push] FCM ${response.statusCode}: ${response.body}');
      }
    } on Object catch (e) {
      // Never fail the turn request over push (ARCHITECTURE.md).
      print('[push] FCM send failed: $e');
    }
  }

  @override
  Future<void> yourTurn(PlayerRecord player, MatchRecord match) => _send(
        player,
        match,
        'YOUR_TURN',
        'PC Kaiser',
        'Du bist am Zug !',
      );

  @override
  Future<void> yourDecision(PlayerRecord player, MatchRecord match) => _send(
        player,
        match,
        'YOUR_DECISION',
        'PC Kaiser',
        'Eine Entscheidung wartet auf dich.',
      );

  @override
  Future<void> warStarted(PlayerRecord player, MatchRecord match) => _send(
        player,
        match,
        'WAR_STARTED',
        'PC Kaiser',
        'Krieg ! Dein Reich wird angegriffen.',
      );
}
