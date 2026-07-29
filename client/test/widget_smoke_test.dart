import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' show cityNames, countryNames;
import 'package:pckaiser/main.dart';
import 'package:pckaiser/screens/online_setup_screen.dart';
import 'package:pckaiser/screens/setup_screen.dart';
import 'package:pckaiser/services/save_service.dart';
import 'package:pckaiser/widgets/empire_card.dart';
import 'package:pckaiser/widgets/room_card.dart';

void main() {
  testWidgets('the app builds and shows the home screen', (tester) async {
    await tester.pumpWidget(const PcKaiserApp());
    await tester.pump();
    expect(find.text('PCKaiser'), findsOneWidget);
    // German is the v1 default locale.
    expect(find.text('Neues Spiel'), findsOneWidget);
    // The language toggle is gone (German-only for now) and the header
    // shows the round app icon instead of the generic castle glyph.
    expect(find.text('DE'), findsNothing);
    expect(find.byType(ClipOval), findsOneWidget);
    expect(find.byIcon(Icons.castle), findsNothing);
  });

  testWidgets('the local setup screen shows sections and start button', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('saves');
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(home: SetupScreen(saves: SaveService(dir))),
    );
    expect(find.text('Spieler'), findsOneWidget);
    expect(find.text('Spieler hinzufügen'), findsOneWidget);
    expect(find.text('Spiel starten'), findsOneWidget);
    // Advanced options are collapsed by default and expand on tap. The
    // card sits below the fold since the color picker row (2026-07-27).
    expect(find.text('Stärke der KI-Gegner'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Erweiterte Optionen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Erweiterte Optionen'));
    await tester.pumpAndSettle();
    expect(find.text('Stärke der KI-Gegner'), findsOneWidget);
    expect(find.text('Frauen können überall herrschen'), findsOneWidget);
  });

  testWidgets('the online host setup is a full screen with match settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OnlineSetupScreen(mode: OnlineSetupMode.host, displayName: 'Vin'),
      ),
    );
    expect(find.text('Neue Online-Partie'), findsOneWidget);
    expect(find.text('Partie'), findsOneWidget);
    expect(find.text('Dein Reich'), findsOneWidget);
    expect(find.text('Zug-Zeitlimit'), findsOneWidget);
    expect(find.text('Partie erstellen'), findsOneWidget);
    // The founder name is pre-filled with the online display name.
    expect(find.text('Vin'), findsOneWidget);
    // The options card sits below the fold on the test surface.
    await tester.scrollUntilVisible(
      find.text('Erweiterte Optionen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Erweiterte Optionen'));
    await tester.pumpAndSettle();
    expect(find.text('Zugzeit im Krieg'), findsOneWidget);
  });

  testWidgets('the Land dropdown never discards a typed Dorf name', (
    tester,
  ) async {
    final name = TextEditingController(text: 'Anna');
    final dorf = TextEditingController(text: cityNames[0]); // slot 1 auto-fill
    addTearDown(name.dispose);
    addTearDown(dorf.dispose);
    int? slot = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => EmpireCard(
              name: name,
              nameLabel: 'Name',
              nameMaxLength: 30,
              dorf: dorf,
              gender: 0,
              onGenderChanged: (_) {},
              countrySlot: slot,
              onCountryChanged: (v) => setState(() => slot = v),
              color: null,
              onColorChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    // Opens the Land dropdown and picks [item] — the menu list is lazy and
    // scrolled to the current selection, so scroll up if needed.
    Future<void> pick(String item) async {
      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();
      if (find.text(item).evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.text(item),
          -60,
          scrollable: find.byType(Scrollable).last,
        );
      }
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    // A previous auto-fill is cleared when switching to "Zufällig" …
    await pick('Zufällig');
    expect(dorf.text, isEmpty);
    // … and replaced when picking a concrete Land.
    await pick(countryNames[3]);
    expect(dorf.text, cityNames[2]);
    // A name the player typed survives both directions.
    dorf.text = 'Entenhausen';
    await pick('Zufällig');
    expect(dorf.text, 'Entenhausen');
    await pick(countryNames[5]);
    expect(dorf.text, 'Entenhausen');
  });

  testWidgets(
      'shrinking the map resets a country pick beyond the new realm count', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('saves');
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(home: SetupScreen(saves: SaveService(dir))),
    );

    // Pick slot 13, the first beyond Klein's 12 realms (countryNames is
    // slot-indexed with the [0] "Niemand" sentinel, cityNames 0-based).
    await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
    await tester.pumpAndSettle();
    // The menu list is lazy: drag until the item is built, then make sure
    // it is fully on screen before tapping.
    await tester.scrollUntilVisible(
      find.text(countryNames[13]),
      60,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(countryNames[13]).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(countryNames[13]).last);
    await tester.pumpAndSettle();
    expect(find.text(countryNames[13]), findsOneWidget);
    expect(find.text(cityNames[12]), findsOneWidget); // Dorf auto-fill

    // Open the advanced options and switch to the small map.
    await tester.scrollUntilVisible(
      find.text('Erweiterte Optionen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Erweiterte Optionen'));
    await tester.pumpAndSettle();
    expect(find.text('Kartengröße'), findsOneWidget);
    await tester.ensureVisible(find.text('Klein'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Klein'));
    await tester.pumpAndSettle();
    expect(find.text('Reiche: 12'), findsOneWidget);

    // The out-of-range pick fell back to "Zufällig", the auto-filled
    // Dorf was cleared with it.
    expect(find.text(countryNames[13]), findsNothing);
    expect(find.text(cityNames[12]), findsNothing);
  });

  testWidgets('a matchmaking room card names the room and its start rule', (
    tester,
  ) async {
    var joined = false;
    // One entry as `GET /matches/public` sends it for a server-hosted room.
    final room = {
      'id': 'ABCDE',
      'joined': 3,
      'seats': 4,
      'auto_start_at': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 2, minutes: 30))
          .toIso8601String(),
      'settings': {
        'template': 'blitz',
        'map_size': 'klein',
        'realm_count': 12,
        'turn_timeout_hours': 12,
        'war_round_timeout': 300,
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomCard(match: room, onJoin: () => joined = true),
        ),
      ),
    );
    expect(find.text('Blitz'), findsOneWidget);
    expect(find.text('3/4'), findsOneWidget);
    expect(
      find.text('Klein · 12 Reiche · 12 h/Zug · 5 min Krieg'),
      findsOneWidget,
    );
    // Enough players joined ⇒ the room shows its countdown, not the target.
    expect(find.textContaining('Startet in 2 h'), findsOneWidget);
    await tester.tap(find.text('Beitreten'));
    expect(joined, isTrue);
  });

  testWidgets('a room below its threshold names the seats that start it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomCard(
            match: const {
              'id': 'ABCDE',
              'joined': 1,
              'seats': 10,
              'settings': {'template': 'kaiserreich', 'map_size': 'gross'},
            },
            onJoin: () {},
          ),
        ),
      ),
    );
    expect(find.text('Kaiserreich'), findsOneWidget);
    expect(find.text('Startet bei 10 Spielern'), findsOneWidget);
  });

  testWidgets('joining by code asks for the room code on the same screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OnlineSetupScreen(mode: OnlineSetupMode.joinByCode),
      ),
    );
    expect(find.text('Raum-Code'), findsOneWidget);
    // Host-only sections are hidden when joining.
    expect(find.text('Zug-Zeitlimit'), findsNothing);
    expect(find.text('Erweiterte Optionen'), findsNothing);
    // Submitting without a code is rejected with a hint.
    await tester.tap(find.text('Beitreten'));
    await tester.pump();
    expect(
      find.text('Bitte den 5-stelligen Raum-Code eingeben'),
      findsOneWidget,
    );
  });
}
