import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../game/map_game.dart';
import '../game/realm_palette.dart';
import '../l10n/strings.dart';
import '../services/local_game_session.dart';
import '../services/save_service.dart';
import '../state/game_controller.dart';
import '../tutorial/tutorial_overlay.dart';
import '../tutorial/tutorial_steps.dart';
import '../widgets/decisions.dart';
import '../widgets/menus.dart';
import '../widgets/tile_sheet.dart';
import '../widgets/war_panel.dart';

/// The in-game screen: Flame map + HUD + menus, with the hot-seat handoff
/// blocker and pending-decision prompts layered on top.
class GameScreen extends StatefulWidget {
  const GameScreen._({required this.sessionFuture, this.tutorial = false});

  factory GameScreen.create({
    required String slotName,
    required gc.GameSetup setup,
    required SaveService saves,
  }) =>
      GameScreen._(
          sessionFuture: LocalGameSession.create(
              slotName: slotName, setup: setup, saves: saves));

  factory GameScreen.resume({
    required String slotName,
    required SaveService saves,
  }) =>
      GameScreen._(
          sessionFuture:
              LocalGameSession.resume(slotName: slotName, saves: saves));

  /// Interactive tutorial: a real single-player game (fixed seed) with
  /// the step overlay on top. The session is ephemeral — never saved.
  factory GameScreen.tutorial({required SaveService saves}) => GameScreen._(
      sessionFuture: LocalGameSession.create(
          slotName: tutorialSlotName,
          setup: tutorialSetup(),
          saves: saves,
          persist: false),
      tutorial: true);

  final Future<LocalGameSession> sessionFuture;
  final bool tutorial;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameController? _controller;
  MapGame? _game;
  late bool _tutorialActive = widget.tutorial;

  @override
  void initState() {
    super.initState();
    widget.sessionFuture.then((session) {
      if (!mounted) return;
      final controller = GameController(session);
      // The tutorial is single-player: skip the hot-seat handoff blocker
      // and its recap popup so the first step card appears immediately.
      if (widget.tutorial) controller.confirmHandoff();
      final game = MapGame(initial: controller.visibleState);
      game.onTileTap = (x, y) => _onTileTap(controller, x, y);
      controller.addListener(() {
        game.updateState(controller.visibleState);
        if (mounted) setState(() {});
      });
      setState(() {
        _controller = controller;
        _game = game;
      });
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onTileTap(GameController controller, int x, int y) {
    if (controller.handoffPending || controller.gameOver) return;
    // An active tile pick (e.g. stationing a new troop) consumes the tap.
    if (controller.resolveTilePick(x, y)) return;
    if (controller.state.activeWar != null) {
      _onWarTileTap(controller, x, y);
      return;
    }
    showTileActionSheet(context, controller, x, y);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// War-mode taps: tap an own army to select it, then tap any tile to
  /// march toward it (one orthogonal step per movement point; meeting an
  /// enemy unit fights, reaching the enemy Königssitz wins the war).
  void _onWarTileTap(GameController controller, int x, int y) {
    final war = controller.state.activeWar!;
    final slot = controller.warHumanSlot;
    if (slot == null) return;

    if (war.phase == gc.WarPhase.settlement) {
      if (war.winnerSlot != slot) return;
      try {
        controller
            .applyWarAction(gc.SettlementAnnex(slot: slot, x: x, y: y));
      } on gc.ActionException catch (e) {
        _toast(e.message);
      }
      return;
    }

    final realm = controller.state.realm(slot);
    final tappedUnit =
        realm.troops.indexWhere((t) => t.x == x && t.y == y);
    if (tappedUnit >= 0) {
      controller.selectWarUnit(tappedUnit);
      return;
    }
    final selected = controller.selectedWarUnit;
    if (selected == null || selected >= realm.troops.length) {
      _toast('Wähle zuerst eine deiner Truppen !');
      return;
    }
    _marchToward(controller, slot, selected, x, y);
  }

  /// Greedy orthogonal march of the selected unit toward (tx, ty): one
  /// step at a time until the moves run out, combat holds the unit, the
  /// path is blocked, or the war ends (capital capture).
  void _marchToward(
      GameController controller, int slot, int unitIndex, int tx, int ty) {
    final unitName = controller.state.realm(slot).troops[unitIndex].name;
    for (var guard = 0; guard < 40; guard++) {
      final war = controller.state.activeWar;
      if (war == null || war.phase != gc.WarPhase.rounds) return;
      final troops = controller.state.realm(slot).troops;
      if (unitIndex >= troops.length ||
          troops[unitIndex].name != unitName) {
        controller.selectWarUnit(null);
        return; // the unit was destroyed
      }
      final troop = troops[unitIndex];
      final remainingX = tx - troop.x;
      final remainingY = ty - troop.y;
      if (remainingX == 0 && remainingY == 0) return; // arrived

      // Prefer the longer axis; fall back to the other on a blocked step.
      final primary = remainingX.abs() >= remainingY.abs()
          ? (remainingX.sign, 0)
          : (0, remainingY.sign);
      final secondary = remainingX.abs() >= remainingY.abs()
          ? (0, remainingY.sign)
          : (remainingX.sign, 0);
      final beforeX = troop.x;
      final beforeY = troop.y;
      var error = _warStepError(controller, slot, unitIndex, primary);
      if (error != null && secondary != (0, 0)) {
        error = _warStepError(controller, slot, unitIndex, secondary);
      }
      if (error != null) {
        _toast(error); // blocked on both axes or out of moves
        return;
      }
      final after = controller.state.realm(slot).troops;
      if (unitIndex < after.length &&
          after[unitIndex].name == unitName &&
          after[unitIndex].x == beforeX &&
          after[unitIndex].y == beforeY) {
        return; // combat: the defender held the tile
      }
    }
  }

  /// One war step; returns null on success or the engine's message.
  String? _warStepError(GameController controller, int slot, int unitIndex,
      (int, int) step) {
    if (step == (0, 0)) return 'Unpassierbar !';
    try {
      controller.applyWarAction(gc.WarMove(
          slot: slot, unitIndex: unitIndex, dx: step.$1, dy: step.$2));
      return null;
    } on gc.ActionException catch (e) {
      return e.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final game = _game;
    if (controller == null || game == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: GameWidget(game: game)),
                if (controller.state.activeWar != null &&
                    !controller.handoffPending)
                  Align(
                    alignment: Alignment.topCenter,
                    child: WarPanel(controller: controller),
                  ),
                if (controller.tilePickActive && !controller.handoffPending)
                  Align(
                    alignment: Alignment.topCenter,
                    child: _tilePickBanner(controller),
                  ),
                // Tutorial card above the status row; kept in the tree
                // (just hidden) during handoffs so the step survives.
                if (_tutorialActive)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Visibility(
                      visible: !controller.handoffPending &&
                          !controller.gameOver,
                      maintainState: true,
                      child: TutorialOverlay(
                        controller: controller,
                        onExit: () =>
                            setState(() => _tutorialActive = false),
                      ),
                    ),
                  ),
              ]),
            ),
            _statusRow(controller),
            _actionBar(controller),
          ]),
          if (controller.busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (controller.handoffPending && !controller.gameOver)
            Positioned.fill(child: _handoff(controller)),
          if (controller.gameOver)
            Positioned.fill(child: _victory(controller)),
        ]),
      ),
    );
  }

  /// Floating instruction card while a map tile pick is active.
  Widget _tilePickBanner(GameController controller) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(12),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.touch_app, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(controller.tilePickHint ?? '',
                style: theme.textTheme.bodyMedium),
          ),
          TextButton(
            onPressed: controller.cancelTilePick,
            child: Text(tr('cancel')),
          ),
        ]),
      ),
    );
  }

  /// Slim status row, replacing both the old HUD and the top-bar overlay
  /// (which used to block map tiles): one tappable chip with realm color,
  /// year/realm and the two always-needed numbers (Taler, Züge — tap for
  /// the full "Mein Reich" stats), popularity warning when it matters,
  /// undo, and end turn. Leaving the game lives in Info → "Spiel
  /// verlassen" instead of a prominent back button.
  Widget _statusRow(GameController controller) {
    final realm = controller.currentRealm;
    final realmName = gc.countryNames[controller.currentSlot];
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(children: [
          const SizedBox(width: 4),
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => showInfoMenu(context, controller),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(
                    radius: 6,
                    backgroundColor:
                        RealmPalette.colorFor(controller.currentSlot),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Anno ${controller.state.year} — $realmName · '
                      '${realm.treasury} T · ${realm.movementPoints} Züge',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                      semanticsLabel: 'Anno ${controller.state.year}, '
                          '$realmName, '
                          '${tr('treasury')}: ${realm.treasury} Taler, '
                          '${tr('moves')}: ${realm.movementPoints}',
                    ),
                  ),
                  if (realm.popularity < 30)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message: 'Beliebtheit gefährlich niedrig!',
                        child: Icon(Icons.warning_amber,
                            size: 18, color: Colors.orange),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          IconButton(
            onPressed: controller.canUndo ? controller.undo : null,
            icon: const Icon(Icons.undo),
            tooltip: tr('undo'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: controller.state.activeWar == null
                ? () => controller.endTurn()
                : null,
            icon: const Icon(Icons.skip_next),
            label: Text(tr('endTurn')),
          ),
        ]),
      ),
    );
  }

  /// Persistent labeled category bar — replaces the old hamburger hub, so
  /// every menu is one tap away.
  Widget _actionBar(GameController controller) {
    final theme = Theme.of(context);
    Widget item(IconData icon, String label,
            void Function(BuildContext, GameController) open) =>
        Expanded(
          child: InkWell(
            onTap: () => open(context, controller),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 20),
                Text(label,
                    style: theme.textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        );

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(children: [
        item(Icons.storefront, tr('commerce'), showCommerceMenu),
        item(Icons.shield, tr('military'), showMilitaryMenu),
        item(Icons.visibility, tr('espionage'), showEspionageMenu),
        item(Icons.church, tr('misc'), showMiscMenu),
        item(Icons.info_outline, tr('info'), showInfoMenu),
      ]),
    );
  }

  /// Hot-seat handoff blocker: hides the predecessor's screen, shows the
  /// recap card, then prompts pending decisions (PROJECT_REQUIREMENTS).
  Widget _handoff(GameController controller) {
    final slot = controller.handoffToSlot;
    final ruler =
        controller.state.person(controller.state.realm(slot).rulerId);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.swap_horiz, size: 56),
          const SizedBox(height: 12),
          Text(tr('handoff'),
              style: Theme.of(context).textTheme.titleMedium),
          Text(
            '${gc.countryNames[slot]}'
            '${ruler == null ? '' : ' — ${ruler.name}'}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              controller.confirmHandoff();
              // Focus the map on the player whose turn begins.
              _game?.focusOnRealm(slot);
              await showRecapAndDecisions(context, controller, slot);
            },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(tr('yourTurn')),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _victory(GameController controller) {
    final event = controller.state.events.last;
    final slot = event.slot;
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.emoji_events, size: 72, color: Colors.amber),
          const SizedBox(height: 12),
          Text(tr('gameOver'),
              style: Theme.of(context).textTheme.headlineMedium),
          Text(
            '${gc.countryNames[slot]} ist der alleinige Herrscher des ganzen Landes!',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Zurück zum Hauptmenü'),
          ),
        ]),
      ),
    );
  }
}
