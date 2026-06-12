import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckaiser/app_version.dart';
import 'package:pckaiser/screens/about_screen.dart';

void main() {
  test('appVersion constant matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.firstWhere((l) => l.startsWith('version:'));
    final pubspecVersion = line.substring('version:'.length).trim();
    expect(
      appVersion,
      pubspecVersion,
      reason: 'keep lib/app_version.dart in sync with pubspec.yaml',
    );
  });

  testWidgets('the About screen shows description, version and credits', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    expect(find.textContaining('Version $appVersion'), findsOneWidget);
    expect(find.textContaining('Regelwerk'), findsOneWidget);
    expect(find.textContaining('Martin Gelter'), findsOneWidget);
    expect(find.textContaining('Remake'), findsOneWidget);
  });
}
