import 'dart:io';

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:pckaiser/game/map_game.dart';
import 'package:pckaiser/l10n/strings.dart';
import 'package:pckaiser/screens/game_screen.dart';
import 'package:pckaiser/services/local_game_session.dart';
import 'package:pckaiser/services/save_service.dart';

/// 2026-09-01, user request: ending the turn with build moves (Zuege) still
/// unspent asks first — they expire with the round, so a mis-tap silently
/// wastes a whole year of building.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ending the turn with unspent moves asks first', (tester) async {
    late LocalGameSession session;
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('pckaiser_endturn_');
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

    await tester.pumpWidget(
      MaterialApp(home: GameScreen.online(session: session)),
    );

    // Session future + MapGame asset loading: alternate real-async turns
    // with fake-clock pumps until the map is up.
    MapGame? game;
    for (var i = 0; i < 600 && (game == null || !game.isLoaded); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 10));
      final widgets = find.byType(GameWidget<MapGame>).evaluate();
      if (widgets.isNotEmpty) {
        game = (widgets.first.widget as GameWidget<MapGame>).game;
      }
    }
    expect(game?.isLoaded, isTrue);

    // Hot-seat handoff blocker → begin the turn, then dismiss the turn-start
    // popups (recap, decisions).
    await tester.tap(find.text('Zug beginnen'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final ok = find
          .byWidgetPredicate((w) => w is FilledButton || w is TextButton)
          .evaluate();
      if (find.byType(Dialog).evaluate().isEmpty &&
          find.byType(AlertDialog).evaluate().isEmpty &&
          find.byType(BottomSheet).evaluate().isEmpty) {
        break;
      }
      if (ok.isNotEmpty) {
        await tester.tap(find.byWidget(ok.last.widget), warnIfMissed: false);
      }
    }
    await tester.pump(const Duration(milliseconds: 300));

    final year = session.state.year;
    expect(
      session.state.realm(1).movementPoints,
      greaterThan(0),
      reason: 'a fresh turn always starts with build moves',
    );

    // Tap "Zug beenden": the warning stands in the way and "Weiter bauen"
    // keeps the turn open.
    await tester.tap(find.text(tr('endTurn')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(tr('game.movesLeftQuestion')), findsOneWidget);
    await tester.tap(find.text(tr('game.movesLeftBuild')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(session.state.year, year, reason: 'the turn must still be open');

    // Confirming through the dialog ends it for real.
    await tester.tap(find.text(tr('endTurn')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(tr('game.movesLeftQuestion')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, tr('endTurn')).last);
    for (var i = 0; i < 40 && session.state.year == year; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      session.state.year,
      greaterThan(year),
      reason: 'confirming ends the turn',
    );
  });
}
