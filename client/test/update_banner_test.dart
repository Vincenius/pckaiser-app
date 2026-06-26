import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckaiser/widgets/update_banner.dart';

void main() {
  Widget host(String? version) =>
      MaterialApp(home: Scaffold(body: UpdateRequiredBanner(serverVersion: version)));

  testWidgets('shows the message with the match version', (tester) async {
    await tester.pumpWidget(host('9.9.9'));
    expect(find.text('App-Update erforderlich'), findsOneWidget);
    expect(find.textContaining('Version 9.9.9'), findsOneWidget);
  });

  testWidgets('falls back to "?" when the server omits its version', (
    tester,
  ) async {
    await tester.pumpWidget(host(null));
    expect(find.textContaining('Version ?'), findsOneWidget);
  });

  testWidgets('offers a Play Store link on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(host('9.9.9'));
    expect(find.text('Im Play Store aktualisieren'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('hides the Play Store link off Android (iOS has no build yet)', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(host('9.9.9'));
    expect(find.text('Im Play Store aktualisieren'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
