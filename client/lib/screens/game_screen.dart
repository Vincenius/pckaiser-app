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
import '../widgets/war_report.dart';

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
      _syncWarOverlay(controller, game);
      controller.addListener(() {
        game.updateState(controller.visibleState);
        _syncWarOverlay(controller, game);
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

  /// Mirrors the war state into the map overlay: pulsing ring on the
  /// selected unit.
  void _syncWarOverlay(GameController controller, MapGame game) {
    final war = controller.state.activeWar;
    final slot = controller.warHumanSlot;
    if (war == null || slot == null || war.phase != gc.WarPhase.rounds) {
      game.selectedTile = null;
      return;
    }
    final selected = controller.selectedWarUnit;
    final troops = controller.state.realm(slot).troops;
    game.selectedTile = selected != null && selected < troops.length
        ? (troops[selected].x, troops[selected].y)
        : null;
  }

  /// War-mode taps: tap an own army to select it (tap again to deselect),
  /// then tap any tile to march toward it — tapping an enemy army attacks
  /// it, reaching the enemy Königssitz wins the war. Battle results are
  /// shown as popups.
  Future<void> _onWarTileTap(GameController controller, int x, int y) async {
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
      controller.selectWarUnit(
          tappedUnit == controller.selectedWarUnit ? null : tappedUnit);
      return;
    }
    final selected = controller.selectedWarUnit;
    if (selected == null || selected >= realm.troops.length) {
      final enemyHere = controller.state
          .realm(war.opponentOf(slot))
          .troops
          .any((t) => t.x == x && t.y == y);
      _toast(enemyHere
          ? 'Wähle zuerst eine deiner Truppen — dann tippe die '
              'feindliche Armee an, um sie anzugreifen !'
          : 'Wähle zuerst eine deiner Truppen !');
      return;
    }
    await _marchToward(controller, slot, selected, x, y);
  }

  /// Greedy orthogonal march of the selected unit toward (tx, ty): one
  /// step at a time until the moves run out, combat holds the unit, the
  /// path is blocked, or the war ends (capital capture). Afterwards all
  /// battle/capture events of the march pop up as a report.
  Future<void> _marchToward(GameController controller, int slot,
      int unitIndex, int tx, int ty) async {
    final report = <gc.GameEvent>[];
    final unitName = controller.state.realm(slot).troops[unitIndex].name;
    for (var guard = 0; guard < 40; guard++) {
      final war = controller.state.activeWar;
      if (war == null || war.phase != gc.WarPhase.rounds) break;
      final troops = controller.state.realm(slot).troops;
      if (unitIndex >= troops.length ||
          troops[unitIndex].name != unitName) {
        controller.selectWarUnit(null);
        break; // the unit was destroyed
      }
      final troop = troops[unitIndex];
      final remainingX = tx - troop.x;
      final remainingY = ty - troop.y;
      if (remainingX == 0 && remainingY == 0) break; // arrived

      // Prefer the longer axis; fall back to the other on a blocked step.
      final primary = remainingX.abs() >= remainingY.abs()
          ? (remainingX.sign, 0)
          : (0, remainingY.sign);
      final secondary = remainingX.abs() >= remainingY.abs()
          ? (0, remainingY.sign)
          : (remainingX.sign, 0);
      final beforeX = troop.x;
      final beforeY = troop.y;
      var error = _warStep(controller, slot, unitIndex, primary, report);
      if (error != null && secondary != (0, 0)) {
        error = _warStep(controller, slot, unitIndex, secondary, report);
      }
      if (error != null) {
        // Blocked on both axes or out of moves: only worth a toast when
        // nothing happened — after a battle the popup explains the halt.
        if (report.isEmpty) _toast(error);
        break;
      }
      final after = controller.state.realm(slot).troops;
      if (unitIndex < after.length &&
          after[unitIndex].name == unitName &&
          after[unitIndex].x == beforeX &&
          after[unitIndex].y == beforeY) {
        break; // combat: the defender held the tile
      }
    }
    if (!mounted) return;
    await showWarReport(context, report, viewerSlot: slot);
    // A capital capture ends the war mid-march: resume the paused AI turn.
    if (controller.state.activeWar == null) {
      await controller.resumeAfterWar();
    }
  }

  /// One war step; returns null on success or the engine's message.
  /// Emitted events (battles, capture, war end) are appended to [report].
  String? _warStep(GameController controller, int slot, int unitIndex,
      (int, int) step, List<gc.GameEvent> report) {
    if (step == (0, 0)) return 'Unpassierbar !';
    try {
      final result = controller.applyWarAction(gc.WarMove(
          slot: slot, unitIndex: unitIndex, dx: step.$1, dy: step.$2));
      report.addAll(result.events);
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
                // Vitals over the map; hidden while the war panel or the
                // tile-pick banner occupies the top edge.
                if (controller.state.activeWar == null &&
                    !controller.tilePickActive &&
                    !controller.handoffPending)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _resourceChip(controller),
                  ),
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
                // Keyed: the war panel / tile-pick banner are inserted as
                // siblings above, and without a key that recreates this
                // element and resets the tutorial progress.
                if (widget.tutorial)
                  Align(
                    key: const ValueKey('tutorial-overlay'),
                    alignment: Alignment.bottomCenter,
                    child: Visibility(
                      visible: !controller.handoffPending &&
                          !controller.gameOver,
                      maintainState: true,
                      child: TutorialOverlay(
                        controller: controller,
                        // Both finishing and quitting leave the practice
                        // game and return to the main menu (the session
                        // is ephemeral and never saved).
                        onFinish: () => Navigator.of(context).pop(),
                        onQuit: () => Navigator.of(context).pop(),
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

  /// Always-visible vitals floating over the map (top right): treasury
  /// and remaining moves as compact icon chips, plus the low-popularity
  /// warning. Tapping opens "Mein Reich", like the status row below.
  Widget _resourceChip(GameController controller) {
    final realm = controller.currentRealm;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showInfoMenu(context, controller),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Semantics(
            container: true,
            label: '${tr('treasury')}: ${realm.treasury} Taler, '
                '${tr('moves')}: ${realm.movementPoints}',
            child: ExcludeSemantics(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.toll, size: 16),
                const SizedBox(width: 4),
                Text('${realm.treasury}',
                    style: theme.textTheme.titleSmall),
                const SizedBox(width: 12),
                const Icon(Icons.construction, size: 16),
                const SizedBox(width: 4),
                Text('${realm.movementPoints}',
                    style: theme.textTheme.titleSmall),
                if (realm.popularity < 30)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
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
      ),
    );
  }

  /// Asks for confirmation, then leaves the game back to the main menu —
  /// every completed turn is auto-saved, so leaving is always safe.
  Future<void> _confirmLeaveGame() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spiel verlassen?'),
        content: const Text(
            'Der letzte abgeschlossene Zug ist gespeichert.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Spiel verlassen')),
        ],
      ),
    );
    if (sure == true && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  /// Slim status row, replacing both the old HUD and the top-bar overlay
  /// (which used to block map tiles): leave-game button, one tappable
  /// chip with realm color and year/realm (tap for the full "Mein Reich"
  /// stats), undo, and end turn. Taler and Züge live in the top-right
  /// [_resourceChip].
  Widget _statusRow(GameController controller) {
    final realmName = gc.countryNames[controller.currentSlot];
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(children: [
          IconButton(
            onPressed: _confirmLeaveGame,
            icon: const Icon(Icons.logout),
            color: theme.colorScheme.error,
            tooltip: 'Spiel verlassen',
          ),
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
                      'Anno ${controller.state.year} — $realmName',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
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
  /// every menu is one tap away. Locked during a war pause: the menus act
  /// for the seated player's own turn, which is not running while another
  /// realm's turn stands paused on the war.
  Widget _actionBar(GameController controller) {
    final theme = Theme.of(context);
    final locked = controller.warPauseActive;
    Widget item(IconData icon, String label,
            void Function(BuildContext, GameController) open) =>
        Expanded(
          child: InkWell(
            onTap: locked ? null : () => open(context, controller),
            child: Opacity(
              opacity: locked ? 0.4 : 1,
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

  /// "Krieg !" orientation popup when the device is handed to the
  /// defender of a freshly started (or save-resumed) war: names the
  /// attacker and explains the war controls before the war panel takes
  /// over. The attacker started the war themselves and needs no briefing.
  Future<void> _maybeShowWarAlert(
      GameController controller, int slot) async {
    final war = controller.state.activeWar;
    if (war == null ||
        war.phase != gc.WarPhase.rounds ||
        war.defenderSlot != slot) {
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.gavel, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text('Krieg !',
              style: Theme.of(context).textTheme.titleLarge)),
        ]),
        content: Text(
            '${gc.countryNames[war.attackerSlot]} ist mit Armeen in dein '
            'Land eingefallen !\n\n'
            'Tippe eine deiner Truppen an (Schild auf farbigem Wappen) '
            'und dann ein Ziel auf der Karte: feindliche Armeen werden '
            'angegriffen. Einmal pro Runde kannst du auf feindlichem '
            'Boden plündern.\n\n'
            'Der Krieg endet, wenn beide Seiten Frieden wünschen '
            '(ohne Gebietsänderungen), spätestens im Winter — oder '
            'sofort, wenn eine Armee den gegnerischen Königssitz '
            '(Fahne) erreicht und den Herrscher gefangen '
            'nimmt.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zu den Waffen !'),
          ),
        ],
      ),
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
              await _maybeShowWarAlert(controller, slot);
              if (!mounted) return;
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
    final draw = event.type == 'gameDraw';
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(draw ? Icons.history_edu : Icons.emoji_events,
              size: 72, color: Colors.amber),
          const SizedBox(height: 12),
          Text(tr('gameOver'),
              style: Theme.of(context).textTheme.headlineMedium),
          Text(
            draw
                ? 'Alle Dynastien sind erloschen — das Land bleibt herrenlos.'
                : '${gc.countryNames[slot]} ist der alleinige Herrscher des ganzen Landes!',
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
