import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../game/map_game.dart';
import '../game/realm_palette.dart';
import '../l10n/strings.dart';
import '../services/game_session.dart';
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
  }) => GameScreen._(
    sessionFuture: LocalGameSession.create(
      slotName: slotName,
      setup: setup,
      saves: saves,
    ),
  );

  factory GameScreen.resume({
    required String slotName,
    required SaveService saves,
  }) => GameScreen._(
    sessionFuture: LocalGameSession.resume(slotName: slotName, saves: saves),
  );

  /// Interactive tutorial: a real single-player game (fixed seed) with
  /// the step overlay on top. The session is ephemeral — never saved.
  factory GameScreen.tutorial({required SaveService saves}) => GameScreen._(
    sessionFuture: LocalGameSession.create(
      slotName: tutorialSlotName,
      setup: tutorialSetup(),
      saves: saves,
      persist: false,
    ),
    tutorial: true,
  );

  /// One online turn: the session already holds the server's view; the
  /// screen pops itself once another player is awaited.
  factory GameScreen.online({required GameSession session}) =>
      GameScreen._(sessionFuture: Future.value(session));

  final Future<GameSession> sessionFuture;
  final bool tutorial;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameController? _controller;
  MapGame? _game;
  bool _poppedForRemote = false;

  @override
  void initState() {
    super.initState();
    widget.sessionFuture.then(
      (session) {
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
          // Online: the turn went to another player — hand back to the
          // waiting lobby (once; guarded against re-entry).
          if (controller.isOnline &&
              controller.awaitingRemote &&
              !controller.gameOver &&
              !_poppedForRemote) {
            _poppedForRemote = true;
            if (mounted) Navigator.of(context).maybePop();
            return;
          }
          if (mounted) setState(() {});
        });
        setState(() {
          _controller = controller;
          _game = game;
        });
      },
      onError: (Object e, StackTrace _) {
        // A corrupt save or failed session setup would otherwise leave the
        // screen on the spinner forever.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Spiel konnte nicht geladen werden: $e')),
        );
        Navigator.of(context).maybePop();
      },
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onTileTap(GameController controller, int x, int y) async {
    if (controller.handoffPending || controller.gameOver) return;
    // An active tile pick (e.g. stationing a new troop) consumes the tap.
    if (await controller.resolveTilePick(x, y)) return;
    // During the war PREPARATION window the map behaves normally — the
    // attacker's turn continues until both sides chose (war taps only
    // exist in the rounds/settlement phases).
    if (controller.state.activeWar != null &&
        controller.state.activeWar!.phase != gc.WarPhase.preparation) {
      await _onWarTileTap(controller, x, y);
      return;
    }
    if (mounted) await showTileActionSheet(context, controller, x, y);
  }

  void _toast(String message) {
    // Callers await war submissions first — online the listener may have
    // popped this screen in the meantime.
    if (!mounted) return;
    // Replace instead of queue: repeated taps (e.g. picking loot the claim
    // can't pay for) would otherwise stack 4s snackbars for minutes.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Ends the turn with feedback on failure: online the submission can be
  /// rejected (turn already advanced, outdated build) or fail on transport
  /// — without a toast the button looks like a no-op while the turn
  /// silently stays open.
  Future<void> _endTurn(GameController controller) async {
    try {
      await controller.endTurn();
    } on gc.ActionException catch (e) {
      _toast(e.message);
    }
  }

  /// Mirrors the war state into the map overlay: pulsing ring on the
  /// selected unit — during the rounds AND the preparation window (where
  /// units are selected via their chips to set the stance per troop).
  void _syncWarOverlay(GameController controller, MapGame game) {
    final war = controller.state.activeWar;
    final slot = war?.phase == gc.WarPhase.preparation
        ? controller.warPrepSlot
        : controller.warHumanSlot;
    if (war == null ||
        slot == null ||
        (war.phase != gc.WarPhase.rounds &&
            war.phase != gc.WarPhase.preparation)) {
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
  /// it; holding the enemy Königssitz until the round ends wins the war.
  /// Battle results are shown as popups.
  Future<void> _onWarTileTap(GameController controller, int x, int y) async {
    final war = controller.state.activeWar!;
    final slot = controller.warHumanSlot;
    if (slot == null) return;

    if (war.phase == gc.WarPhase.settlement) {
      if (war.winnerSlot != slot) return;
      try {
        await controller.applyWarAction(
          gc.SettlementAnnex(slot: slot, x: x, y: y),
        );
      } on gc.ActionException catch (e) {
        _toast(e.message);
      }
      return;
    }

    final realm = controller.state.realm(slot);
    final tappedUnit = realm.troops.indexWhere((t) => t.x == x && t.y == y);
    if (tappedUnit >= 0) {
      controller.selectWarUnit(
        tappedUnit == controller.selectedWarUnit ? null : tappedUnit,
      );
      return;
    }
    final selected = controller.selectedWarUnit;
    if (selected == null || selected >= realm.troops.length) {
      final enemyHere = controller.state
          .realm(war.opponentOf(slot))
          .troops
          .any((t) => t.x == x && t.y == y);
      _toast(
        enemyHere
            ? 'Wähle zuerst eine deiner Truppen — dann tippe die '
                  'feindliche Armee an, um sie anzugreifen !'
            : 'Wähle zuerst eine deiner Truppen !',
      );
      return;
    }
    await _marchToward(controller, slot, selected, x, y);
  }

  /// Greedy orthogonal march of the selected unit toward (tx, ty): one
  /// step at a time until the moves run out, combat holds the unit, or
  /// the path is blocked. Afterwards all battle events of the march pop
  /// up as a report. (Should the war end mid-march, the post-march
  /// resume handles it.)
  Future<void> _marchToward(
    GameController controller,
    int slot,
    int unitIndex,
    int tx,
    int ty,
  ) async {
    final report = <gc.GameEvent>[];
    final unitName = controller.state.realm(slot).troops[unitIndex].name;
    // Names repeat ("Rekruten", "Söldner") and the engine compacts the
    // troop list on destruction — track the expected position too, or a
    // same-named unit sliding into this index would silently inherit the
    // march (and the selection ring).
    var expectedX = controller.state.realm(slot).troops[unitIndex].x;
    var expectedY = controller.state.realm(slot).troops[unitIndex].y;
    // The tile we currently walk toward. It starts as the tapped target and
    // is re-pointed at an own harbor's coast when the only way across is by
    // sea — then the unit ships from there to the tapped target.
    var goalX = tx;
    var goalY = ty;
    for (var guard = 0; guard < 60; guard++) {
      final war = controller.state.activeWar;
      if (war == null || war.phase != gc.WarPhase.rounds) break;
      final troops = controller.state.realm(slot).troops;
      if (unitIndex >= troops.length ||
          troops[unitIndex].name != unitName ||
          troops[unitIndex].x != expectedX ||
          troops[unitIndex].y != expectedY) {
        controller.selectWarUnit(null);
        break; // the unit was destroyed
      }
      final troop = troops[unitIndex];
      final map = controller.state.map;
      final remainingX = goalX - troop.x;
      final remainingY = goalY - troop.y;
      if (remainingX == 0 && remainingY == 0) {
        // Reached the goal. If it was a harbor approach (goal ≠ tapped
        // target), embark now and ship across — unless a battle en route
        // deferred it (re-tap to finish the hop next round).
        if ((goalX != tx || goalY != ty) &&
            report.isEmpty &&
            map.canNavalTransport(slot, troop.x, troop.y, tx, ty)) {
          final navError = await _navalTransport(
            controller,
            slot,
            unitIndex,
            tx,
            ty,
            report,
          );
          if (navError != null) _toast(navError);
        }
        break;
      }

      // Prefer the longer axis; fall back to the other on a blocked step.
      final primary = remainingX.abs() >= remainingY.abs()
          ? (remainingX.sign, 0)
          : (0, remainingY.sign);
      final secondary = remainingX.abs() >= remainingY.abs()
          ? (0, remainingY.sign)
          : (remainingX.sign, 0);
      final beforeX = troop.x;
      final beforeY = troop.y;
      var step = primary;
      var error = await _warStep(controller, slot, unitIndex, primary, report);
      if (error != null && secondary != (0, 0)) {
        step = secondary;
        error = await _warStep(controller, slot, unitIndex, secondary, report);
      }
      if (error != null) {
        // Blocked or out of moves. The convenience sea-route only applies
        // from LAND (at sea the unit is steered manually, tile by tile) and
        // while no battle has happened yet (a fought march defers it).
        if (report.isEmpty && !map.isWaterAt(beforeX, beforeY)) {
          // Standing next to a harbor that reaches the target → ship across.
          if (map.canNavalTransport(slot, beforeX, beforeY, tx, ty)) {
            final navError = await _navalTransport(
              controller,
              slot,
              unitIndex,
              tx,
              ty,
              report,
            );
            if (navError != null) _toast(navError);
            break;
          }
          // Otherwise march to the nearest harbor coast that connects, then
          // ship from there on a later iteration.
          final embark = map.navalEmbarkTile(slot, beforeX, beforeY, tx, ty);
          if (embark != null &&
              (embark.$1 != goalX || embark.$2 != goalY) &&
              (embark.$1 != beforeX || embark.$2 != beforeY)) {
            goalX = embark.$1;
            goalY = embark.$2;
            continue; // head for the harbor now
          }
          _toast(error);
        }
        break;
      }
      final after = controller.state.realm(slot).troops;
      if (unitIndex < after.length &&
          after[unitIndex].name == unitName &&
          after[unitIndex].x == beforeX &&
          after[unitIndex].y == beforeY) {
        break; // combat: the defender held the tile
      }
      // The step went through: the unit now stands one tile further along
      // [step] — the next iteration's identity check expects it there.
      expectedX = beforeX + step.$1;
      expectedY = beforeY + step.$2;
    }
    if (!mounted) return;
    await showWarReport(context, report, viewerSlot: slot);
    // A capital capture ends the war mid-march: resume the paused AI turn.
    if (controller.state.activeWar == null) {
      await controller.resumeAfterWar();
      // Coercion choices from a capture come immediately.
      if (mounted) await promptDecisionsFor(context, controller, slot);
    }
  }

  /// Naval transport: ship the selected unit to [tx],[ty] via an own harbor.
  /// Appends any landing-battle events to [report]. Returns null on success
  /// or the engine's message on failure.
  Future<String?> _navalTransport(
    GameController controller,
    int slot,
    int unitIndex,
    int tx,
    int ty,
    List<gc.GameEvent> report,
  ) async {
    try {
      final result = await controller.applyWarAction(
        gc.WarNavalTransport(slot: slot, unitIndex: unitIndex, x: tx, y: ty),
      );
      report.addAll(result.events);
      return null;
    } on gc.ActionException catch (e) {
      return e.message;
    }
  }

  /// One war step; returns null on success or the engine's message.
  /// Emitted events (battles, capture, war end) are appended to [report].
  Future<String?> _warStep(
    GameController controller,
    int slot,
    int unitIndex,
    (int, int) step,
    List<gc.GameEvent> report,
  ) async {
    if (step == (0, 0)) return 'Unpassierbar !';
    try {
      final result = await controller.applyWarAction(
        gc.WarMove(slot: slot, unitIndex: unitIndex, dx: step.$1, dy: step.$2),
      );
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // The full-screen blockers (busy, handoff, victory) live OUTSIDE the
    // SafeArea: inside it they leave the system-inset strips (status bar,
    // gesture nav) uncovered, and the map shines through there — a hot-seat
    // handoff must hide the predecessor's screen completely.
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
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
                      if (controller.tilePickActive &&
                          !controller.handoffPending)
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
                            visible:
                                !controller.handoffPending &&
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
                    ],
                  ),
                ),
                _statusRow(controller),
                _actionBar(controller),
              ],
            ),
          ),
          if (controller.busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (controller.handoffPending && !controller.gameOver)
            Positioned.fill(child: _handoff(controller)),
          if (controller.gameOver) Positioned.fill(child: _victory(controller)),
        ],
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                controller.tilePickHint ?? '',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: controller.cancelTilePick,
              child: Text(tr('cancel')),
            ),
          ],
        ),
      ),
    );
  }

  /// Always-visible vitals floating over the map (top right): year,
  /// treasury, remaining moves and popularity stacked as compact icon
  /// rows. Tapping opens "Mein Reich", like the status row below. The
  /// year also lives in the bottom status row, but that line ellipsizes
  /// on narrow screens — here it stays readable mid-turn (user report
  /// 2026-07-10).
  Widget _resourceChip(GameController controller) {
    final realm = controller.currentRealm;
    final theme = Theme.of(context);
    final lowPopularity = realm.popularity < 30;

    Widget line(IconData icon, String value, {Color? color}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(value, style: theme.textTheme.titleSmall?.copyWith(color: color)),
      ],
    );

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
            label:
                'Anno ${controller.state.year}, '
                '${tr('treasury')}: ${realm.treasury} Taler, '
                '${tr('moves')}: ${realm.movementPoints}, '
                '${tr('popularity')}: ${realm.popularity}'
                '${lowPopularity ? ' — gefährlich niedrig' : ''}',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  line(Icons.calendar_today, '${controller.state.year}'),
                  const SizedBox(height: 2),
                  line(Icons.toll, '${realm.treasury}'),
                  const SizedBox(height: 2),
                  line(Icons.construction, '${realm.movementPoints}'),
                  const SizedBox(height: 2),
                  Tooltip(
                    message: lowPopularity
                        ? 'Beliebtheit gefährlich niedrig!'
                        : tr('popularity'),
                    child: line(
                      lowPopularity ? Icons.heart_broken : Icons.favorite,
                      '${realm.popularity}',
                      color: lowPopularity ? theme.colorScheme.error : null,
                    ),
                  ),
                ],
              ),
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
        content: Text(
          _controller?.isOnline == true
              ? 'Die Partie läuft auf dem Server weiter — du kannst '
                    'jederzeit zurückkehren.'
              : 'Der letzte abgeschlossene Zug ist gespeichert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Spiel verlassen'),
          ),
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
        child: Row(
          children: [
            // Compact fixed-width members: on narrow phones the row's
            // minimum width (icons + year + end-turn button) must stay
            // under the screen width — only the realm name may truncate.
            IconButton(
              onPressed: _confirmLeaveGame,
              icon: const Icon(Icons.logout),
              color: theme.colorScheme.error,
              tooltip: 'Spiel verlassen',
              visualDensity: VisualDensity.compact,
            ),
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => showInfoMenu(context, controller),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 6,
                        backgroundColor: RealmPalette.colorFor(
                          controller.currentSlot,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // One ellipsized text: the realm name (the tail)
                      // truncates first; on extremely narrow screens the
                      // year ellipsizes too instead of overflowing.
                      Flexible(
                        child: Text(
                          'Anno ${controller.state.year} — $realmName',
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (controller.supportsUndo)
              IconButton(
                onPressed: controller.canUndo ? controller.undo : null,
                icon: const Icon(Icons.undo),
                tooltip: tr('undo'),
                visualDensity: VisualDensity.compact,
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: controller.state.activeWar == null
                  ? () => _endTurn(controller)
                  : null,
              icon: const Icon(Icons.skip_next),
              label: Text(tr('endTurn')),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ],
        ),
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
    Widget item(
      IconData icon,
      String label,
      void Function(BuildContext, GameController) open,
    ) => Expanded(
      child: InkWell(
        onTap: locked ? null : () => open(context, controller),
        child: Opacity(
          opacity: locked ? 0.4 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20),
                Text(
                  label,
                  style: theme.textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          item(Icons.storefront, tr('commerce'), showCommerceMenu),
          item(Icons.shield, tr('military'), showMilitaryMenu),
          item(Icons.visibility, tr('espionage'), showEspionageMenu),
          item(Icons.church, tr('misc'), showMiscMenu),
          item(Icons.info_outline, tr('info'), showInfoMenu),
        ],
      ),
    );
  }

  /// "Krieg !" orientation popup when the device is handed to the
  /// defender of a freshly started (or save-resumed) war: names the
  /// attacker and explains the war controls before the war panel takes
  /// over. The attacker started the war themselves and needs no briefing.
  Future<void> _maybeShowWarAlert(GameController controller, int slot) async {
    final war = controller.state.activeWar;
    if (war == null ||
        war.phase != gc.WarPhase.rounds ||
        war.defenderSlot != slot) {
      return;
    }
    // Brief the defender exactly once — while the declaration is still fresh
    // in their recap. The recap baseline advances per war round (and online
    // the GameScreen is rebuilt every turn, so an instance flag wouldn't
    // survive), so once this side has played one war round the warDeclared
    // event is no longer in the recap and the briefing never repeats.
    final freshDeclaration = controller
        .recapFor(slot)
        .any((e) => e.type == 'warDeclared');
    if (!freshDeclaration) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.gavel, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Krieg !',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        // Long briefing — must scroll on small screens / large text scale.
        content: SingleChildScrollView(
          child: Text(
            '${gc.countryNames[war.attackerSlot]} ist mit Armeen in dein '
            'Land eingefallen !\n\n'
            'Tippe eine deiner Truppen an (Schild auf farbigem Wappen) '
            'und dann ein Ziel auf der Karte: feindliche Armeen werden '
            'angegriffen. Einmal pro Runde kannst du auf feindlichem '
            'Boden plündern.\n\n'
            'Der Krieg endet, wenn beide Seiten Frieden wünschen '
            '(ohne Gebietsänderungen), spätestens im Winter — oder '
            'wenn eine Armee den gegnerischen Königssitz (Fahne) über '
            'eine volle Runde hält: ihr Herrscher wird gefangen '
            'genommen, und der Sieger wählt, welche Felder er '
            'übernimmt.',
          ),
        ),
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
    final ruler = controller.state.person(controller.state.realm(slot).rulerId);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz, size: 56),
            const SizedBox(height: 12),
            Text(
              _controller?.isOnline == true
                  ? tr('onlineYourTurn')
                  : tr('handoff'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
          ],
        ),
      ),
    );
  }

  /// Plain-language reason for the defeat screen, keyed off the
  /// `humansDefeated` event's `reason` payload (set by `advanceUntilHuman`).
  String _defeatReasonText(String? reason) {
    const tail =
        'Keine menschliche Dynastie hält mehr die Macht — '
        'eure Herrschaft ist Geschichte.';
    final cause = switch (reason) {
      'internalStrife' =>
        'Ein Volksaufstand hat deine Dynastie entthront (Popularität unter 20).',
      'bankruptcy' =>
        'Dein Reich ist bankrott gegangen und einem neuen Herrscherhaus zugefallen.',
      'islamicSuccessionCrisis' =>
        'Eine Thronfolgekrise hat dein Reich unter fremde (computergesteuerte) Kontrolle gebracht.',
      'realmInherited' =>
        'Beim Tod deines Herrschers ging dein Reich durch Erbfolge an ein '
            'fremdes Herrscherhaus über.',
      'rulerCaptured' =>
        'Dein Herrscher wurde im Krieg gefangen genommen und das Reich erobert.',
      'realmOverrun' => 'Dein Reich wurde im Krieg vollständig überrannt.',
      'dynastyExtinct' ||
      'totalExtinction' => 'Deine Dynastie ist ausgestorben.',
      _ => null,
    };
    return cause == null ? tail : '$cause\n\n$tail';
  }

  Widget _victory(GameController controller) {
    final event = controller.gameEndEvent!;
    final slot = event.slot;
    final draw = event.type == 'gameDraw';
    final defeat = event.type == 'humansDefeated';
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        // Scrolls when a long defeat reason plus large text scale exceeds
        // the screen height; padded so the text never touches the edges.
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                defeat
                    ? Icons.cancel
                    : draw
                    ? Icons.history_edu
                    : Icons.emoji_events,
                size: 72,
                color: defeat ? Colors.red : Colors.amber,
              ),
              const SizedBox(height: 12),
              Text(
                tr(defeat ? 'gameLost' : 'gameOver'),
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              Text(
                defeat
                    ? _defeatReasonText(event.payload['reason'] as String?)
                    : draw
                    ? 'Alle Dynastien sind erloschen — das Land bleibt herrenlos.'
                    : '${gc.countryNames[slot]} ist der alleinige Herrscher des ganzen Landes!',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Zurück zum Hauptmenü'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
