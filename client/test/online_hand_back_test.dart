import 'dart:io';

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:pckaiser/game/map_game.dart';
import 'package:pckaiser/screens/game_screen.dart';
import 'package:pckaiser/services/game_session.dart';
import 'package:pckaiser/services/local_game_session.dart';
import 'package:pckaiser/services/save_service.dart';

/// An online seat whose "server" hands the turn on as soon as a decision
/// is answered — the war-plan case: answering it (live command + war
/// times) makes the OPPONENT the awaited seat, while the confirmation
/// dialog is still being pushed over the map.
class _FakeOnlineSession implements GameSession {
  _FakeOnlineSession(this._inner);

  final LocalGameSession _inner;
  bool _awaiting = false;

  @override
  gc.GameState get state => _inner.state;

  @override
  bool get isOnline => true;

  @override
  bool get canUndo => false;

  @override
  int? get turnTimeoutHours => 24;

  @override
  bool get awaitingRemote => _awaiting;

  @override
  Future<gc.ActionResult> apply(gc.PlayerAction action) async {
    final result = await _inner.apply(action);
    if (action is gc.ResolveDecision) _awaiting = true;
    return result;
  }

  @override
  void restore(gc.GameState snapshot) => _inner.restore(snapshot);

  @override
  Future<List<gc.GameEvent>> endWarRound(int slot) => _inner.endWarRound(slot);

  @override
  Future<List<gc.GameEvent>> endTurnAndAdvance() async {
    final events = await _inner.endTurnAndAdvance();
    _awaiting = true;
    return events;
  }

  @override
  Future<void> resumeAfterWar() => _inner.resumeAfterWar();

  /// Online the server persists every submission — and a real file write
  /// would never complete under the test's fake clock anyway.
  @override
  Future<void> save() async {}
}

/// `[FIX 2026-08-13, user report]` The play screen must return to the
/// match view when the turn moves on — even though the turn regularly
/// changes hands while a DIALOG still covers the map (the attacker's war
/// plan: answering it awaits the defender, and the "Kriegsbeginn"
/// confirmation follows immediately). The old one-shot `maybePop` was
/// silently dropped in that race and left the player on a frozen map
/// behind the action spinner.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the online play screen hands back even when the turn moves '
      'on while a dialog is open', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.reset);

    late _FakeOnlineSession session;
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('pckaiser_handback_');
      session = _FakeOnlineSession(
        await LocalGameSession.create(
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
        ),
      );
    });
    addTearDown(() => tmp.delete(recursive: true));
    // TWO answers to give: the turn moves on with the first, so the second
    // dialog is on screen while the screen wants to hand back.
    for (final id in ['d1', 'd2']) {
      session.state.pendingDecisions.add(
        gc.PendingDecision(
          id: id,
          type: 'convertOrDie',
          decidingSlot: 1,
          // No such person — the engine consumes the answer without
          // touching the state; the test only needs the two DIALOGS.
          payload: const {'capturedRulerId': -1, 'religion': 0},
        ),
      );
    }

    // The screen must sit ON a route it can pop back to (the match view).
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GameScreen.online(session: session),
                  ),
                ),
                child: const Text('Spielen'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Spielen'));
    await tester.pump();

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

    // Begin the turn, then answer every popup the turn start raises —
    // among them the two decisions.
    await tester.tap(find.text('Zug beginnen'));
    // Answer whatever is on screen; a dialog raised only after the next
    // await must still be caught, so this never stops at the first quiet
    // frame. The hand-back retries every 200 ms in between.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      final open = find.byType(Dialog).evaluate().isNotEmpty ||
          find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.byType(SimpleDialog).evaluate().isNotEmpty;
      // The match view showing again means the screen handed back.
      if (!open && find.text('Spielen').evaluate().isNotEmpty) break;
      if (!open) continue;
      final buttons = find
          .byWidgetPredicate((w) => w is FilledButton || w is TextButton)
          .evaluate();
      if (buttons.isNotEmpty) {
        await tester.tap(
          find.byWidget(buttons.last.widget),
          warnIfMissed: false,
        );
      }
    }

    expect(
      find.text('Spielen'),
      findsOneWidget,
      reason: 'the play screen must hand back to the match view once '
          'another player is awaited — the old one-shot pop was dropped '
          'when the next dialog was pushed in the same moment',
    );
    expect(session.awaitingRemote, isTrue);
  });
}
