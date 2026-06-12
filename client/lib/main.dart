import 'package:flutter/material.dart';

import 'l10n/strings.dart';
import 'screens/home_screen.dart';
import 'services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
