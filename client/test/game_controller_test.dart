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
            founderName: 'Anna',
            gender: 1,
            countrySlot: 1,
            dorfName: 'A',
          ),
          HumanPlayerSetup(
            founderName: 'Berta',
            gender: 1,
            countrySlot: 5,
            dorfName: 'B',
          ),
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

  test(
    'undo restores the pre-action state; irreversible clears the stack',
    () async {
      final controller = await twoPlayerGame();
      controller.confirmHandoff();
      controller.currentRealm.movementPoints = 5;
      final (x, y) = claimableTile(controller.state, 1);

      await controller.applyUndoable(ClaimTile(slot: 1, x: x, y: y));
      expect(controller.state.map.ownerAt(x, y), 1);
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.state.map.ownerAt(x, y), World.niemand);
      expect(controller.canUndo, isFalse);

      await controller.applyUndoable(ClaimTile(slot: 1, x: x, y: y));
      controller.currentRealm.grainHarvest = 10;
      await controller.applyIrreversible(
        SellGood(slot: 1, good: MarketGood.grain, amount: 5),
      );
      expect(
        controller.canUndo,
        isFalse,
        reason: 'randomized/irreversible actions clear the undo stack',
      );
    },
  );

  test(
    'endTurn advances through the AI to the next human with handoff',
    () async {
      final controller = await twoPlayerGame();
      controller.confirmHandoff();
      expect(controller.currentSlot, 1);

      await controller.endTurn();

      expect(
        controller.currentSlot,
        5,
        reason: 'slots 2–4 are AI and play automatically',
      );
      expect(controller.handoffPending, isTrue);
      expect(controller.handoffToSlot, 5);
      // Auto-save happened: reload from disk matches.
      final reloaded = await saves.load('Test');
      expect(reloaded.currentPlayer, 5);
    },
  );

  test('recap collects events between a player\'s turns', () async {
    final controller = await twoPlayerGame();
    controller.confirmHandoff();
    controller.markRecapSeen(1);
    await controller.endTurn(); // AI slots 2–4 act → events accumulate
    final recap = controller.recapFor(1);
    expect(recap, isNotEmpty);
    expect(recap.every((e) => e.visibleTo(1)), isTrue);
  });

  test(
    'a war pause seats the human war side, not the paused AI realm',
    () async {
      final controller = await twoPlayerGame();
      controller.confirmHandoff();
      final state = controller.state;

      // Fabricate the pause: an AI realm's turn stands open on a war
      // against human slot 1 (what advanceUntilHuman leaves behind when an
      // AI declares war on a human defender).
      state.currentPlayer = 2;
      expect(state.dynasty(2).status, DynastyStatus.ai);
      state.activeWar = ActiveWar(attackerSlot: 2, defenderSlot: 1);

      expect(controller.warPauseActive, isTrue);
      expect(
        controller.currentSlot,
        1,
        reason: 'the seat belongs to the human defender',
      );
      expect(controller.currentRealm.slot, 1);
      expect(
        controller.visibleState.realm(1).treasury,
        state.realm(1).treasury,
        reason:
            'the map view is filtered for the seat — the defender '
            'sees their own realm, not a redacted one',
      );
      expect(
        controller.visibleState.realm(2).treasury,
        0,
        reason: 'the paused AI attacker stays hidden',
      );

      // Outside a war the seat follows the engine again.
      state.activeWar = null;
      expect(controller.warPauseActive, isFalse);
      expect(controller.currentSlot, 2);
    },
  );

  test(
    'a human-vs-human war hands the seat between the two sides',
    () async {
      final controller = await twoPlayerGame();
      controller.confirmHandoff();
      final state = controller.state;
      state.year = 1010;

      // Arm both human realms and give them a shared border, then let
      // slot 1 declare war on human slot 5 (allowed since ruleset v2).
      for (final slot in [1, 5]) {
        final realm = state.realm(slot);
        realm.treasury = 10000;
        realm.troops.add(
          Troop(
            name: 'Heer$slot',
            men: 50,
            troopClass: TroopClass.infanterie,
            quality: TroopQuality.regular,
            garrisonCounted: false,
            x: realm.capitalX,
            y: realm.capitalY,
          ),
        );
      }
      final map = state.map;
      final (bx, by) = claimableTile(state, 1);
      map.owner[map.index(bx, by)] = 5;
      state.realm(5).tileCount[Building.none]++;

      await controller.applyIrreversible(DeclareWar(slot: 1, targetSlot: 5));
      expect(controller.state.activeWar, isNotNull);
      expect(
        controller.currentSlot,
        1,
        reason: 'attacker before defender — no handoff for the declarer',
      );
      expect(controller.handoffPending, isFalse);

      // The attacker finishes their half: the seat passes to the
      // defender behind a handoff blocker.
      await controller.endWarRound();
      expect(controller.state.activeWar!.round, 0, reason: 'same round');
      expect(controller.currentSlot, 5);
      expect(controller.warPauseActive, isTrue,
          reason: 'the defender acts inside the attacker\'s paused turn');
      expect(controller.handoffPending, isTrue);
      expect(controller.handoffToSlot, 5);
      controller.confirmHandoff();

      // The defender's round end advances the round — back to the
      // attacker, again behind a handoff.
      await controller.endWarRound();
      expect(controller.state.activeWar!.round, 1);
      expect(controller.currentSlot, 1);
      expect(controller.handoffPending, isTrue);
      expect(controller.handoffToSlot, 1);
      controller.confirmHandoff();

      // Mutual peace ends the war; the seat stays with the attacker,
      // whose interrupted turn resumes.
      await controller.applyWarAction(
        WarPeaceWish(slot: 1, wantsPeace: true),
      );
      await controller.endWarRound(); // hands to the defender
      controller.confirmHandoff();
      await controller.applyWarAction(
        WarPeaceWish(slot: 5, wantsPeace: true),
      );
      await controller.endWarRound(); // both wish peace → white peace
      expect(controller.state.activeWar, isNull);
      expect(controller.currentSlot, 1);
      expect(controller.handoffPending, isTrue,
          reason: 'the device goes back to the attacker');
      expect(controller.handoffToSlot, 1);
    },
  );

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
