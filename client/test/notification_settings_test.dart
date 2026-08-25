import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pckaiser/l10n/strings.dart';
import 'package:pckaiser/screens/options_screen.dart';
import 'package:pckaiser/services/push_kinds.dart';
import 'package:pckaiser/services/settings_service.dart';

/// `[DESIGNED 2026-08-24, user request]` Options ▸ Benachrichtigungen: the
/// optional online notifications (war declaration, fixed appointment,
/// quarter-hour reminder) are switchable, on by default, and remembered.
/// The server holds the authoritative copy — `OnlineService.syncPushPrefs`
/// uploads what is stored here, and only kinds it knows can be muted.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('pckaiser_notify_');
    addTearDown(() => dir.deleteSync(recursive: true));
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  test('every notification is on until it is switched off', () async {
    final settings = await SettingsService.init();
    expect(settings.pushOptOut, isEmpty);
    for (final kind in optionalPushKinds) {
      expect(settings.pushEnabled(kind), isTrue);
    }

    await settings.setPushEnabled(pushWarStartSoon, false);
    expect(settings.pushEnabled(pushWarStartSoon), isFalse);
    expect(settings.pushOptOut, {pushWarStartSoon});
    expect(settings.pushEnabled(pushWarStartFixed), isTrue,
        reason: 'switches are independent');

    // Survives a restart, and switching back clears the opt-out.
    final reloaded = await SettingsService.init();
    expect(reloaded.pushOptOut, {pushWarStartSoon});
    await reloaded.setPushEnabled(pushWarStartSoon, true);
    expect((await SettingsService.init()).pushOptOut, isEmpty);
  });

  testWidgets('the options screen lists a switch per optional notification',
      (tester) async {
    addTearDown(() => appLocale.value = 'de');
    // init() resolves the locale from the (device) default — pin it after.
    await SettingsService.init();
    appLocale.value = 'de';
    await tester.pumpWidget(const MaterialApp(home: OptionsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Benachrichtigungen'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(optionalPushKinds.length));
    for (final kind in optionalPushKinds) {
      expect(find.text(tr(pushKindTitleKey(kind))), findsOneWidget);
      expect(find.text(tr(pushKindSubtitleKey(kind))), findsOneWidget);
    }
    // Every label really is translated — a missing key would render as the
    // raw `notify.…` string.
    expect(find.textContaining('notify.'), findsNothing);

    // Toggling one writes it through to the stored settings. (There is no
    // online profile in this test, so nothing is uploaded.)
    await tester.tap(find.text(tr(pushKindTitleKey(pushWarStartSoon))));
    await tester.pumpAndSettle();
    expect(SettingsService.instance!.pushEnabled(pushWarStartSoon), isFalse);
  });

  test('the string table carries every notification label in both locales',
      () {
    addTearDown(() => appLocale.value = 'de');
    for (final locale in ['de', 'en']) {
      appLocale.value = locale;
      for (final key in [
        'notifications',
        'notificationsHint',
        'notifySyncFailed',
        for (final kind in optionalPushKinds) ...[
          pushKindTitleKey(kind),
          pushKindSubtitleKey(kind),
        ],
      ]) {
        expect(tr(key), isNot(contains(key)), reason: 'missing $locale: $key');
      }
    }
  });
}
