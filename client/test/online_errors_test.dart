import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckaiser/services/api_client.dart';
import 'package:pckaiser/widgets/connection_error.dart';
import 'package:pckaiser/widgets/decisions.dart' show formatWarStartTime;

/// User requests 2026-08-08: a readable reason when the server cannot be
/// reached, and a war-start line that does not announce a time in the past.
void main() {
  test('a transport failure is told apart from a server rejection', () {
    final offline = ApiError(0, 'x', failure: ApiFailure.unknownHost);
    expect(offline.isOffline, isTrue);
    // 403 "not your turn" and friends: the server DID answer.
    expect(ApiError(403, 'not your turn').isOffline, isFalse);
  });

  testWidgets('an unreachable server explains itself and offers a retry', (
    tester,
  ) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionErrorTile(
            error: ApiError(
              0,
              'Keine Internetverbindung. Prüfe WLAN oder mobile Daten — '
                  'dein Zug wurde nicht gesendet.',
              failure: ApiFailure.offline,
            ),
            onRetry: () async => retried++,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.textContaining('Keine Internetverbindung'), findsOneWidget);
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pump();
    expect(retried, 1);
  });

  test('a war start that already passed reads "jeden Moment"', () {
    // The "sofort" slot is the top of the answering side's CURRENT hour,
    // so an agreement on it is in the past by the time both answered —
    // the panel used to announce "Heute 20:00 Uhr" at 20:40.
    final past = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 40))
        .millisecondsSinceEpoch;
    expect(formatWarStartTime(past), 'jeden Moment');

    final future = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 3))
        .millisecondsSinceEpoch;
    expect(formatWarStartTime(future), isNot('jeden Moment'));
  });
}
