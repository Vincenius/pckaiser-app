import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import 'l10n/strings.dart';
import 'screens/home_screen.dart';
import 'services/push_service.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Resolves the UI language before the first frame: stored choice, or
  // the device language (German → German, everything else → English).
  await SettingsService.init();
  // Engine messages (ActionException, …) follow the UI language —
  // presentation only, the deterministic rules never read this.
  gc.messageLocale = appLocale.value;
  appLocale.addListener(() => gc.messageLocale = appLocale.value);
  // Push is optional — yields no service on desktop or without the
  // Firebase config files (README "Push notifications").
  await PushService.init();
  runApp(const PcKaiserApp());
}

class PcKaiserApp extends StatelessWidget {
  const PcKaiserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: appLocale,
      builder: (context, _, _) => MaterialApp(
        title: tr('appTitle'),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6D4C2F),
            brightness: Brightness.dark,
          ),
          // Accessibility: generous minimum touch targets.
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
