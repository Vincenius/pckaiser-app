import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:pckaiser/services/local_game_session.dart';
import 'package:pckaiser/services/save_service.dart';
import 'package:pckaiser/state/game_controller.dart';
import 'package:pckaiser/tutorial/tutorial_steps.dart';

/// The tutorial is a real game with a scripted overlay: these tests prove
/// that, on the fixed tutorial seed, every interactive step can actually
/// be completed and its completion check fires.
void main() {
  late Directory tmp;
  late SaveService saves;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pckaiser_tutorial_');
    saves = SaveService(tmp);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<GameController> tutorialGame() async {
    // Mirrors GameScreen.tutorial: an ephemeral session, never saved.
    final session = await LocalGameSession.create(
      slotName: tutorialSlotName,
      setup: tutorialSetup(),
      saves: saves,
      persist: false,
    );
    return GameController(session)..confirmHandoff();
  }

  TutorialStep stepNamed(String title) =>
      tutorialSteps.firstWhere((s) => s.title == title);

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

  test('the tutorial seats the human player on Brandenburg', () async {
    final controller = await tutorialGame();
    expect(controller.currentSlot, 1);
    expect(controller.state.dynasty(1).status, DynastyStatus.human);
    expect(controller.currentRealm.movementPoints, greaterThan(0));
  });

  test('every interactive tutorial step is completable on the fixed seed',
      () async {
    final controller = await tutorialGame();
    final slot = controller.currentSlot;
    final realm = controller.currentRealm;
    final startYear = controller.state.year;

    // Build step: Weide on a claimable neighbor tile (any land terrain).
    final buildStep = stepNamed('Bauen & Erweitern');
    var since = TutorialBaseline(controller);
    expect(buildStep.isDone!(controller, since), isFalse);
    final (x, y) = claimableTile(controller.state, slot);
    controller.applyUndoable(
        Build(slot: slot, x: x, y: y, building: Building.weide));
    expect(buildStep.isDone!(controller, since), isTrue);

    // Trade step: the first upkeep leaves something to sell.
    final tradeStep = stepNamed('Handel');
    since = TutorialBaseline(controller);
    expect(tradeStep.isDone!(controller, since), isFalse);
    expect(realm.grainHarvest + realm.livestockHarvest, greaterThan(0),
        reason: 'tutorial seed must leave goods to sell on turn one');
    final good = realm.grainHarvest > 0 ? MarketGood.grain : MarketGood.cattle;
    controller.applyIrreversible(SellGood(slot: slot, good: good, amount: 1));
    expect(tradeStep.isDone!(controller, since), isTrue);

    // Military step: recruit one man at the capital.
    final militaryStep = stepNamed('Militär');
    since = TutorialBaseline(controller);
    expect(militaryStep.isDone!(controller, since), isFalse);
    controller.applyIrreversible(RecruitTroops(
        slot: slot,
        men: 1,
        troopClass: TroopClass.infanterie,
        name: 'Rekruten',
        x: realm.capitalX,
        y: realm.capitalY));
    expect(militaryStep.isDone!(controller, since), isTrue);

    // The tutorial must finish within the first round: every interactive
    // step above completed without ending the turn.
    expect(controller.state.year, startYear);
  });

  test('no tutorial step requires ending the turn', () {
    // The last step ends the tutorial itself, so the round-start
    // handoff/recap flow never appears while the overlay is up.
    expect(tutorialSteps.last.task, isNull);
    expect(tutorialSteps.last.isDone, isNull);
  });

  test('the tutorial session never writes a save file', () async {
    final controller = await tutorialGame();
    await controller.endTurn(); // even the auto-save stays a no-op
    expect(await saves.exists(tutorialSlotName), isFalse);
    expect(await saves.listSlots(), isEmpty);
  });
}
