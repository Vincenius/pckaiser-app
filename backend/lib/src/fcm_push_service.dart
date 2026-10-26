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

  /// [match] null: a message about no particular match (tapping it just
  /// opens the app).
  Future<void> _send(
    PlayerRecord player,
    MatchRecord? match,
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
            'data': {'kind': kind, if (match != null) 'match_id': match.id},
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

  /// Broadcast to an FCM topic (no player, no match) — the client
  /// subscribes to `championship_<de|en>` after opting in.
  Future<void> _sendTopic(
    String topic,
    String kind,
    String title,
    String body,
  ) async {
    try {
      _client ??= await clientViaServiceAccount(_credentials, _scopes);
      final response = await _client!.post(
        Uri.parse(
            'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'message': {
            'topic': topic,
            'notification': {'title': title, 'body': body},
            'data': {'kind': kind},
          },
        }),
      );
      if (response.statusCode != 200) {
        print('[push] FCM topic ${response.statusCode}: ${response.body}');
      }
    } on Object catch (e) {
      print('[push] FCM topic send failed: $e');
    }
  }

  @override
  Future<void> yourTurn(PlayerRecord player, MatchRecord match) => _send(
        player,
        match,
        PushKind.yourTurn,
        'PCKaiser',
        'Du bist am Zug !',
      );

  @override
  Future<void> yourDecision(PlayerRecord player, MatchRecord match) => _send(
        player,
        match,
        PushKind.yourDecision,
        'PCKaiser',
        'Eine Entscheidung wartet auf dich.',
      );

  @override
  Future<void> warStarted(PlayerRecord player, MatchRecord match) => _send(
        player,
        match,
        PushKind.warStarted,
        'PCKaiser',
        'Krieg ! Dein Reich wird angegriffen.',
      );

  @override
  Future<void> warStartFixed(
          PlayerRecord player, MatchRecord match, DateTime start,
          {required bool agreed,
          bool toAttacker = false,
          bool opponentDelegated = false}) =>
      _send(
        player,
        match,
        PushKind.warStartFixed,
        'PCKaiser',
        // The exact time is shown in-app in the player's local timezone —
        // a push body can't carry it, so it only announces THAT it is set.
        // The attacker (who chose first) is told the defender has now chosen.
        opponentDelegated
            ? (agreed
                ? 'Dein Gegner lässt den Computer führen — der Krieg beginnt '
                    'zu deiner gewählten Zeit. Im Spiel kannst du ihn auch '
                    'sofort beginnen.'
                : 'Dein Gegner lässt den Computer führen — der Krieg beginnt '
                    'nach Ablauf der Vorbereitungsfrist. Im Spiel kannst du '
                    'ihn auch sofort beginnen.')
            : agreed
            ? (toAttacker
                ? 'Kriegstermin steht ! Der Verteidiger hat gewählt — '
                    'die Uhrzeit siehst du im Spiel.'
                : 'Kriegstermin steht ! Ihr habt euch auf eine Zeit '
                    'geeinigt — die Uhrzeit siehst du im Spiel.')
            : (toAttacker
                ? 'Der Verteidiger hat gewählt — kein gemeinsamer '
                    'Kriegstermin. Der Krieg beginnt nach Ablauf der '
                    'Vorbereitungsfrist.'
                : 'Kein gemeinsamer Kriegstermin — der Krieg beginnt nach '
                    'Ablauf der Vorbereitungsfrist.'),
      );

  @override
  Future<void> warStartSoon(PlayerRecord player, MatchRecord match) => _send(
        player,
        match,
        PushKind.warStartSoon,
        'PCKaiser',
        'Dein Krieg beginnt in Kürze — mach dich bereit !',
      );

  @override
  Future<void> matchExpiring(PlayerRecord player, MatchRecord match) => _send(
        player,
        match,
        PushKind.matchExpiring,
        'PCKaiser',
        'Eure Partie ruht seit langem und wird bald gelöscht — '
            'spielt einen Zug, um sie zu behalten.',
      );

  /// One message per language topic — a topic broadcast cannot be
  /// localized per device, so each UI language has its own topic.
  @override
  Future<void> championshipSignupOpen(int year, DateTime startsAt) async {
    // The start is always 1 Nov, 18:00 German time (championship.dart).
    final de = startsAt.add(const Duration(hours: 1));
    await _sendTopic(
      'championship_de',
      PushKind.championship,
      'PCKaiser-Weltmeisterschaft $year',
      'Die Anmeldung ist offen ! Start am ${de.day}.${de.month}.${de.year} '
          'um ${de.hour}:00 Uhr — 16 Plätze.',
    );
    await _sendTopic(
      'championship_en',
      PushKind.championship,
      'PCKaiser World Championship $year',
      'Sign-up is open! Starts ${de.year}-'
          '${de.month.toString().padLeft(2, '0')}-'
          '${de.day.toString().padLeft(2, '0')} at '
          '${de.hour}:00 CET — 16 seats.',
    );
  }

  /// The player's UI language is unknown to the server (old builds never
  /// report it), so the notice is bilingual.
  @override
  Future<void> championshipUpdateNotice(
      PlayerRecord player, int year, DateTime startsAt) {
    final de = startsAt.add(const Duration(hours: 1));
    return _send(
      player,
      null,
      PushKind.championship,
      'PCKaiser-Weltmeisterschaft $year',
      'Anmeldung offen bis ${de.day}.${de.month}. — App aktualisieren und '
          'mitspielen ! / Sign-up is open — update the app to join!',
    );
  }

  @override
  Future<void> championshipStarted(PlayerRecord player, MatchRecord match) =>
      _send(
        player,
        match,
        PushKind.championshipStarted,
        'PCKaiser-Weltmeisterschaft',
        'Die Weltmeisterschaft hat begonnen — viel Erfolg !',
      );
}
