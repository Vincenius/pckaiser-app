import 'dart:io';

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:pckaiser/game/map_game.dart';
import 'package:pckaiser/screens/game_screen.dart';
import 'package:pckaiser/services/local_game_session.dart';
import 'package:pckaiser/services/save_service.dart';

/// Realm name and year must stay fully readable on a narrow phone. They
/// used to sit in the bottom status row next to the leave/undo/end-turn
/// controls, where the ellipsis ate them on every 360 dp screen (user
/// reports 2026-07-10 and -07-28). They are now two separate overlays
/// over the map — realm top left, vitals top right — which must not grow
/// into each other. Any RenderFlex overflow in the HUD fails this test
/// on its own: the pump throws.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('realm name and year are readable on a 360 dp screen',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.reset);

    late LocalGameSession session;
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('pckaiser_hud_');
      session = await LocalGameSession.create(
        slotName: 'Test',
        setup: gc.GameSetup(
          humans: [
            // Slot 17 = "Mecklenburg", one of the longest realm names.
            gc.HumanPlayerSetup(
                founderName: 'Anna', gender: 1, countrySlot: 17, dorfName: 'A'),
          ],
          reformationYear: 1020,
          ottomanYear: 1040,
          seed: 7,
        ),
        saves: SaveService(tmp),
      );
    });
    addTearDown(() => tmp.delete(recursive: true));

    await tester
        .pumpWidget(MaterialApp(home: GameScreen.online(session: session)));

    // Session future + MapGame asset loading: alternate real-async turns
    // with fake-clock pumps until the map is up.
    MapGame? game;
    for (var i = 0; i < 600 && (game == null || !game.isLoaded); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 10));
      final widgets = find.byType(GameWidget<MapGame>).evaluate();
      if (widgets.isNotEmpty) {
        game = (widgets.first.widget as GameWidget<MapGame>).game;
      }
    }
    expect(game?.isLoaded, isTrue);

    // Hot-seat handoff blocker → begin the turn, then dismiss whatever
    // recap/decision popups the turn start raises.
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

    // Both must be present AND untruncated: a Text that ellipsizes still
    // matches find.text, so assert the painted glyphs fit the box.
    for (final label in ['Mecklenburg', '${session.state.year}']) {
      final finder = find.text(label);
      expect(finder, findsOneWidget, reason: '$label belongs in the HUD');
      final rendered = tester.renderObject<RenderParagraph>(finder);
      expect(rendered.didExceedMaxLines, isFalse,
          reason: '$label must not be cut off on a 360 dp screen');
      expect(rendered.size.width, greaterThan(0));
    }

    // The two overlays must stay clear of each other: the vitals column
    // is anchored right, the realm name grows to the right from the left
    // edge — a name wide enough to touch the numbers would mean the cap
    // in _realmChip is too generous for this screen width.
    final nameBox = tester.getRect(find.text('Mecklenburg'));
    final yearBox = tester.getRect(find.text('${session.state.year}'));
    expect(nameBox.right, lessThan(yearBox.left),
        reason: 'realm overlay must not reach into the vitals overlay');

    // The realm chip is the entry to "Mein Reich" now that the status row
    // carries no realm chip.
    await tester.tap(find.text('Mecklenburg'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Mecklenburg'), findsWidgets,
        reason: 'tapping the realm card opens the realm dialog');
  });
}
