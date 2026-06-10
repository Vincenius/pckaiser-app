import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:pckaiser/services/local_game_session.dart';
import 'package:pckaiser/services/save_service.dart';
import 'package:pckaiser/state/game_controller.dart';

void main() {
  late Directory tmp;
  late SaveService saves;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pckaiser_ctrl_');
    saves = SaveService(tmp);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<GameController> twoPlayerGame() async {
    final session = await LocalGameSession.create(
      slotName: 'Test',
      setup: GameSetup(
        humans: [
          HumanPlayerSetup(
              founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'A'),
          HumanPlayerSetup(
              founderName: 'Berta', gender: 1, countrySlot: 5, dorfName: 'B'),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 42,
      ),
      saves: saves,
    );
    return GameController(session);
  }

  (int, int) claimableTile(GameState state, int slot) {
    final map = state.map;
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) {
          continue;
        }
        for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
          if (map.inBounds(x + dx, y + dy) &&
              map.ownerAt(x + dx, y + dy) == slot) {
            return (x, y);
          }
        }
      }
    }
    fail('no claimable tile');
  }

  test('starts with a handoff to the first human', () async {
    final controller = await twoPlayerGame();
    expect(controller.handoffPending, isTrue);
    expect(controller.handoffToSlot, 1);
    controller.confirmHandoff();
    expect(controller.handoffPending, isFalse);
  });

  test('undo restores the pre-action state; irreversible clears the stack',
      () async {
    final controller = await twoPlayerGame();
    controller.confirmHandoff();
    controller.currentRealm.movementPoints = 5;
    final (x, y) = claimableTile(controller.state, 1);

    controller.applyUndoable(ClaimTile(slot: 1, x: x, y: y));
    expect(controller.state.map.ownerAt(x, y), 1);
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.state.map.ownerAt(x, y), World.niemand);
    expect(controller.canUndo, isFalse);

    controller.applyUndoable(ClaimTile(slot: 1, x: x, y: y));
    controller.currentRealm.grainHarvest = 10;
    controller.applyIrreversible(
        SellGood(slot: 1, good: MarketGood.grain, amount: 5));
    expect(controller.canUndo, isFalse,
        reason: 'randomized/irreversible actions clear the undo stack');
  });

  test('endTurn advances through the AI to the next human with handoff',
      () async {
    final controller = await twoPlayerGame();
    controller.confirmHandoff();
    expect(controller.currentSlot, 1);

    await controller.endTurn();

    expect(controller.currentSlot, 5,
        reason: 'slots 2–4 are AI and play automatically');
    expect(controller.handoffPending, isTrue);
    expect(controller.handoffToSlot, 5);
    // Auto-save happened: reload from disk matches.
    final reloaded = await saves.load('Test');
    expect(reloaded.currentPlayer, 5);
  });

  test('recap collects events between a player\'s turns', () async {
    final controller = await twoPlayerGame();
    controller.confirmHandoff();
    controller.markRecapSeen(1);
    await controller.endTurn(); // AI slots 2–4 act → events accumulate
    final recap = controller.recapFor(1);
    expect(recap, isNotEmpty);
    expect(recap.every((e) => e.visibleTo(1)), isTrue);
  });

  test('a full round returns to player 1 and the year advances', () async {
    final controller = await twoPlayerGame();
    controller.confirmHandoff();
    expect(controller.state.year, 1000);
    await controller.endTurn(); // → slot 5
    controller.confirmHandoff();
    await controller.endTurn(); // → wraps through 6..30 back to 1
    expect(controller.currentSlot, 1);
    expect(controller.state.year, 1001);
  });
}
