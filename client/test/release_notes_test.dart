import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckaiser/app_version.dart';
import 'package:pckaiser/l10n/strings.dart';
import 'package:pckaiser/release_notes.dart';
import 'package:pckaiser/services/settings_service.dart';
import 'package:pckaiser/widgets/whats_new_dialog.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Routes `getApplicationDocumentsDirectory` to a temp dir so
/// [SettingsService.init] works in tests without a real platform channel.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  test('the running app version has a release note', () {
    final note = releaseNotesFor(appVersion);
    expect(note, isNotNull,
        reason: 'bump appVersion without adding a ReleaseNote');
    expect(note!.items(), isNotEmpty);
  });

  test('an unknown version has no release note', () {
    expect(releaseNotesFor('0.0.0'), isNull);
  });

  test('every bullet resolves in both locales (no missing keys)', () {
    addTearDown(() => appLocale.value = 'de');
    final note = releaseNotesFor(appVersion)!;
    appLocale.value = 'de';
    final de = note.items();
    appLocale.value = 'en';
    final en = note.items();
    expect(de, hasLength(en.length));
    for (final s in de) {
      expect(s, isNot(contains('whatsnew.')), reason: 'missing de key: "$s"');
    }
    for (final s in en) {
      expect(s, isNot(contains('whatsnew.')), reason: 'missing en key: "$s"');
    }
  });

  testWidgets('the dialog shows the version and bullets and closes', (
    tester,
  ) async {
    appLocale.value = 'de';
    addTearDown(() => appLocale.value = 'de');
    final note = releaseNotesFor(appVersion)!;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWhatsNewDialog(context, note),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Was ist neu?'), findsOneWidget);
    expect(find.textContaining(appVersion), findsOneWidget);
    // At least the first bullet is visible.
    expect(find.textContaining('Steuern'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Was ist neu?'), findsNothing);
  });

  test('SettingsService remembers the last-seen version', () async {
    final dir = Directory.systemTemp.createTempSync('settings_');
    addTearDown(() => dir.deleteSync(recursive: true));
    PathProviderPlatform.instance = _FakePathProvider(dir.path);

    final first = await SettingsService.init();
    expect(first.lastSeenWhatsNewVersion, isNull);
    await first.markWhatsNewSeen('0.2.6');

    // A second init (fresh launch) reads the value back from disk.
    final second = await SettingsService.init();
    expect(second.lastSeenWhatsNewVersion, '0.2.6');
  });
}
