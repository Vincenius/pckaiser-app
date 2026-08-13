import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:pckaiser/services/local_game_session.dart';
import 'package:pckaiser/services/save_service.dart';
import 'package:pckaiser/state/game_controller.dart';
import 'package:pckaiser/widgets/war_panel.dart';

/// The war-preparation panel must stay a SLIM bottom dock: it sits over
/// the map while the player lines up their army, and used to stack three
/// explanatory paragraphs above its controls (user report 2026-08-13 —
/// "viel zu viel Text"). It now shows a header line, ONE status line and
/// the two controls; the explanation lives behind the header's ⓘ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GameController> prepController(WidgetTester tester) async {
    late LocalGameSession session;
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('pckaiser_warprep_');
      session = await LocalGameSession.create(
        slotName: 'Test',
        setup: gc.GameSetup(
          humans: [
            gc.HumanPlayerSetup(
              founderName: 'Anna',
              gender: 1,
              countrySlot: 1,
              dorfName: 'A',
            ),
          ],
          reformationYear: 1020,
          ottomanYear: 1040,
          seed: 7,
        ),
        saves: SaveService(tmp),
      );
    });
    addTearDown(() => tmp.delete(recursive: true));
    final state = session.state;
    // A preparation window this seat has already answered (live command),
    // with one army to line up.
    state.realm(1).troops.add(
      gc.Troop(
        name: 'Heerhaufen',
        men: 500,
        troopClass: gc.TroopClass.infanterie,
        quality: gc.TroopQuality.regular,
        garrisonCounted: false,
        x: 3,
        y: 3,
      ),
    );
    state.activeWar = gc.ActiveWar(
      attackerSlot: 1,
      defenderSlot: 2,
      phase: gc.WarPhase.preparation,
      planAnsweredSlots: {1},
      planSlots: {1: const [0]},
    );
    return GameController(session);
  }

  testWidgets('the preparation panel is a header, one status line and the '
      'controls — the explanation sits behind the ⓘ', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.reset);

    final controller = await prepController(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // The panel's hosts (game screen, map viewer) rebuild it on every
          // controller notification — a unit pick only shows up that way.
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Align(
              alignment: Alignment.bottomCenter,
              child: WarPanel(controller: controller),
            ),
          ),
        ),
      ),
    );

    // Header names both sides, the status line the (local) start rule.
    expect(find.textContaining('gegen'), findsOneWidget);
    expect(
      find.text('Der Krieg beginnt, sobald beide Seiten bereit sind.'),
      findsOneWidget,
    );
    // Command mode + stance section, no prose paragraphs.
    expect(find.text('Selbst führen'), findsOneWidget);
    expect(find.text('Computer führt'), findsOneWidget);
    expect(find.text('Truppenhaltung'), findsOneWidget);
    expect(find.textContaining('Die Haltung gilt'), findsNothing);
    // The panel must leave the map the bulk of the screen. (The test font
    // renders every glyph as a square, so text-heavy rows measure taller
    // here than on a device — the budget is generous on purpose.)
    expect(tester.getSize(find.byType(WarPanel)).height, lessThan(260));

    // The full explanation is one tap away.
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Führung:'), findsOneWidget);
  });

  testWidgets('picking a troop offers its stance under its name', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.reset);

    final controller = await prepController(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // The panel's hosts (game screen, map viewer) rebuild it on every
          // controller notification — a unit pick only shows up that way.
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Align(
              alignment: Alignment.bottomCenter,
              child: WarPanel(controller: controller),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Truppe wählen, um ihre Haltung zu setzen.'),
        findsOneWidget);
    await tester.tap(find.textContaining('Heerhaufen'));
    await tester.pumpAndSettle();
    expect(find.text('Heerhaufen: '), findsOneWidget);
    expect(find.text('Halten'), findsOneWidget);
    expect(find.text('Angreifen'), findsOneWidget);
  });
}
