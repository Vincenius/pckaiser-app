import 'dart:io';

import 'package:flame/game.dart' show GameWidget, Vector2;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:pckaiser/game/map_game.dart';
import 'package:pckaiser/screens/game_screen.dart';
import 'package:pckaiser/services/local_game_session.dart';
import 'package:pckaiser/services/save_service.dart';

/// Drives the real gesture pipeline (long-press → box drag → release)
/// against [MapGame] — the box-select plumbing the field cultivation and
/// settlement annexation UIs hang off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  gc.GameState state() => gc.newGame(gc.GameSetup(
        humans: [
          gc.HumanPlayerSetup(
              founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'A'),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 7,
      ));

  testWidgets('long-press anchors, drag resizes, release fires the end hook',
      (tester) async {
    final game = MapGame(initial: state());
    var longPresses = 0;
    var drags = 0;
    var ends = 0;
    game.onLongPressTile = (x, y) {
      longPresses++;
      game.boxAnchor = (x, y);
      return true;
    };
    game.onBoxDrag = (x, y) {
      drags++;
      game.boxCorner = (x, y);
    };
    game.onBoxDragEnd = () => ends++;

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    // onLoad does real asset I/O: alternate real-async turns (runAsync)
    // with fake-clock pumps until the game reports loaded.
    for (var i = 0; i < 400 && !game.isLoaded; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(game.isLoaded, isTrue, reason: 'MapGame must finish loading');
    await tester.pump();

    var taps = 0;
    game.onTileTap = (x, y) => taps++;

    final center = tester.getCenter(find.byType(GameWidget<MapGame>));

    // Sanity: the component tap pipeline is up (onLoad finished).
    await tester.tapAt(center);
    await tester.pump();
    expect(game.isLoaded, isTrue);
    expect(taps, 1, reason: 'a plain tap must reach the map layer');

    // Long-press (Flame TapConfig.longTapDelay = 0.3 s), then drag, release.
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(longPresses, 1, reason: 'long-press must anchor the box');

    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(drags, greaterThan(0), reason: 'one-finger drag must resize');

    await gesture.up();
    await tester.pump();
    expect(ends, 1, reason: 'release after a box drag fires the end hook');
  });

  testWidgets('GameScreen: box select opens the batch-build sheet on release',
      (tester) async {
    late LocalGameSession session;
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('pckaiser_box_');
      session = await LocalGameSession.create(
        slotName: 'Test',
        setup: gc.GameSetup(
          humans: [
            gc.HumanPlayerSetup(
                founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'A'),
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
        MaterialApp(home: GameScreen.online(session: session)));

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
    expect(game, isNotNull);
    expect(game!.isLoaded, isTrue);

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

    // An own empty land tile nearest the capital (the camera centers there
    // on handoff), mapped from world into screen coordinates.
    final st = session.state;
    final map = st.map;
    final realm = st.realm(1);
    (int, int)? best;
    var bestDist = 1 << 30;
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        final owner = map.ownerAt(x, y);
        final selectable = map.buildingAt(x, y) == gc.Building.none &&
            gc.Terrain.isLand(map.terrainAt(x, y)) &&
            (owner == 1 ||
                (owner == gc.World.niemand && map.bordersSlot(x, y, 1)));
        if (!selectable) continue;
        final d = (x - realm.capitalX).abs() + (y - realm.capitalY).abs();
        if (d < bestDist) {
          bestDist = d;
          best = (x, y);
        }
      }
    }
    expect(best, isNotNull, reason: 'a field-selectable tile exists');
    final world = Vector2(
      (best!.$1 + 0.5) * tileSize,
      (best.$2 + 0.5) * tileSize,
    );
    final viewport = game.camera.localToGlobal(world);
    final widgetRect = tester.getRect(find.byType(GameWidget<MapGame>));
    final pos = widgetRect.topLeft + Offset(viewport.x, viewport.y);
    expect(widgetRect.contains(pos), isTrue,
        reason: 'the tile must be on screen (camera centered on the realm)');

    // Anywhere-anchor: a long-press on the (built) capital tile anchors a
    // box that selects nothing — releasing simply drops the selection
    // instead of opening the sheet.
    final capWorld = Vector2(
      (realm.capitalX + 0.5) * tileSize,
      (realm.capitalY + 0.5) * tileSize,
    );
    final capViewport = game.camera.localToGlobal(capWorld);
    final empty = await tester.startGesture(
        widgetRect.topLeft + Offset(capViewport.x, capViewport.y));
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.boxAnchor, isNotNull,
        reason: 'anchoring works from any tile, not only selectable ones');
    await empty.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Felder ausgewählt'), findsNothing,
        reason: 'no sheet for a box that reaches no buildable tile');
    expect(game.boxAnchor, isNull,
        reason: 'the empty box is dropped on release');

    // Long-press → drag → release: the batch-build sheet must open.
    final gesture = await tester.startGesture(pos);
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.boxAnchor, isNotNull,
        reason: 'long-press on an own empty tile anchors the box');
    await gesture.moveBy(const Offset(64, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Felder ausgewählt'), findsOneWidget,
        reason: 'releasing the box opens the batch-build sheet');
  });

  testWidgets('release without dragging also fires the end hook',
      (tester) async {
    final game = MapGame(initial: state());
    var ends = 0;
    game.onLongPressTile = (x, y) {
      game.boxAnchor = (x, y);
      return true;
    };
    game.onBoxDragEnd = () => ends++;

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(GameWidget<MapGame>)));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump();
    expect(ends, 1,
        reason: 'lift right after the anchoring long-press opens the sheet');
  });
}
