import 'dart:math' as math;

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:game_core/game_core.dart' as gc;

import '../game/map_game.dart';
import '../game/realm_palette.dart';
import '../l10n/labels.dart';
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

/// Which map drag-select is armed: none, cultivating fields (peacetime),
/// transferring own tiles (peacetime multi-select), or annexing enemy tiles
/// in a post-war settlement. Field and transfer are both peacetime-only and
/// never overlap (transfer rides on the armed tile pick, which blocks field
/// mode); annex is war-settlement-only. They share the map's drag-select
/// plumbing.
enum _DragMode { none, field, transfer, annex }

/// How often the online hand-back retries its pop (200 ms apart) before it
/// gives up — see `_GameScreenState._handBackToLobby`.
const int _handBackAttempts = 300;

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

  /// Tiles (index `y * width + x`) drag-selected for batch cultivation —
  /// wired into [MapGame.dragSelection] while [_dragMode] is `field`.
  /// (Annexation uses the controller's own selection set.)
  final Set<int> _selectedFields = <int>{};

  /// Which map drag-select is currently armed. Field mode is user-toggled;
  /// annex mode is driven by the war phase (see [_syncDragMode]).
  _DragMode _dragMode = _DragMode.none;

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
        game.onLongPressTile = (x, y) => _onLongPressTile(controller, x, y);
        game.onBoxDrag = (x, y) => _onBoxDrag(controller, x, y);
        game.onBoxDragEnd = () => _onBoxSelectDone(controller);
        // Lets the war panel scroll the map to a unit picked from its list.
        controller.focusTile = game.focusOnTile;
        // Assign the field now (not only in the setState below) so
        // _syncDragMode's _applyDragMode can wire the map immediately — a
        // save resumed mid-settlement must arm annex mode right away.
        _game = game;
        _syncWarOverlay(controller, game);
        _syncDragMode(controller);
        controller.addListener(() {
          game.updateState(controller.visibleState);
          game.highlightTiles = controller.seatPickCandidates;
          _syncWarOverlay(controller, game);
          // Keep the map drag-select in step with the phase: auto-arm annex
          // mode when the winner's settlement opens, and drop field mode if
          // a war / handoff starts mid-selection. The listener's own
          // setState below repaints — no nested setState needed here.
          _syncDragMode(controller);
          // The "Felder übertragen" multi-select paints its own selection
          // on the map as a white-on-dark outline (the drag mode is none
          // while its pick is armed).
          game.outlineSelection = controller.transferTargetSlot != null
              ? controller.transferSelection
              : const <int>{};
          // Online: the turn went to another player — hand back to the
          // waiting lobby (once; guarded against re-entry). The repaint
          // below still runs: the hand-back may WAIT (see _handBackToLobby)
          // and the screen must not stay frozen on the last frame, which
          // was painted while the submission was still in flight — with the
          // full-screen busy spinner on top (`[FIX 2026-08-13]`).
          if (controller.isOnline &&
              controller.awaitingRemote &&
              !controller.gameOver &&
              !_poppedForRemote) {
            _poppedForRemote = true;
            _handBackToLobby();
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
          SnackBar(content: Text(tr('game.loadFailed', {'error': e}))),
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

  /// Online: leaves the play screen once the turn has moved on to another
  /// player, returning to the match view.
  ///
  /// `[FIX 2026-08-13, user report]` It waits until this screen is the
  /// topmost route again. The turn regularly changes hands while a DIALOG
  /// is still open on top of it — the attacker's war-plan prompt is the
  /// reported case: answering it (live + war times) makes the DEFENDER the
  /// awaited seat, and the "Kriegsbeginn" confirmation appears right after.
  /// `Navigator.maybePop` then either closed that dialog instead of this
  /// screen, or — when the dialog was pushed while it was still resolving —
  /// silently dropped the pop ("something happened in the meantime"). The
  /// player was left on a dead map behind the action spinner, with the
  /// one-shot guard already spent.
  ///
  /// So it only ever pops while this screen is the top-most route (never a
  /// dialog above it) and retries until the route has left the navigator —
  /// `isActive` turns false the moment the pop goes through, which also
  /// ends the loop while the exit animation still runs.
  ///
  /// Bounded ([_handBackAttempts] × 200 ms ≈ a minute): a pop that can never
  /// succeed — this screen sitting at the bottom of the navigator, a route
  /// that refuses to pop — must not leave a timer re-firing every 200 ms for
  /// the rest of the session. The screen then simply stays put; the player
  /// can leave it by hand.
  Future<void> _handBackToLobby() async {
    for (var attempt = 0; attempt < _handBackAttempts; attempt++) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return; // gone already
      if (route.isCurrent) {
        await Navigator.of(context).maybePop();
        if (!route.isActive) return; // popped
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _onTileTap(GameController controller, int x, int y) async {
    if (controller.handoffPending || controller.gameOver) return;
    // An active tile pick (seat relocation, troop stationing) consumes the
    // tap FIRST — even over field mode, which would otherwise exit the
    // mode and swallow the pick's tap.
    if (await controller.resolveTilePick(x, y)) return;
    // Field-cultivation mode: any tap leaves the selection mode — the box
    // is sized by dragging, confirmed via the sheet that opens on release.
    // (Annex mode taps flow through to the war handler below.)
    if (_dragMode == _DragMode.field) {
      _exitFieldMode(controller);
      return;
    }
    final war = controller.state.activeWar;
    // War ROUNDS / settlement: taps drive the duel (select army, march…).
    if (war != null && war.phase != gc.WarPhase.preparation) {
      await _onWarTileTap(controller, x, y);
      return;
    }
    // War PREPARATION window: tapping an own army selects it (tap again to
    // deselect) so its stance (Angreifen / Position halten) can be set right
    // from the map, mirroring the WarPanel unit chips. Anything else falls
    // through to the normal peacetime tile sheet — the turn continues.
    if (war != null && war.phase == gc.WarPhase.preparation) {
      final slot = controller.warPrepSlot;
      if (slot != null) {
        final troops = controller.state.realm(slot).troops;
        final tapped = troops.indexWhere((t) => t.x == x && t.y == y);
        if (tapped >= 0) {
          controller.selectWarUnit(
            tapped == controller.selectedWarUnit ? null : tapped,
          );
          return;
        }
      }
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

  /// Commits every selected tile to the transfer target, one engine action
  /// per tile (the engine's `TransferTile` is single-tile). Stops on the
  /// first rejection; the selection ends either way.
  Future<void> _confirmTransferTiles(GameController controller) async {
    final target = controller.transferTargetSlot;
    final slot = controller.currentSlot;
    if (target == null || target == slot) return;
    final selection = controller.transferSelection.toList(growable: false);
    if (selection.isEmpty) return;
    final map = controller.state.map;
    for (final idx in selection) {
      final x = idx % map.width;
      final y = idx ~/ map.width;
      try {
        await controller.applyUndoable(
          gc.TransferTile(slot: slot, targetSlot: target, x: x, y: y),
        );
      } on gc.ActionException catch (e) {
        _toast(e.message);
        break;
      }
    }
    controller.cancelTransferSelection();
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

  // --- Map box select (field cultivation + war annexation) -----------

  /// Points the map's shared box-select at the active mode's selection set
  /// and highlight color. Called on enter/exit and on every phase change
  /// ([_syncDragMode]).
  void _applyDragMode(GameController controller) {
    final game = _game;
    if (game == null) return;
    switch (_dragMode) {
      case _DragMode.none:
        game.clearBox();
        game.dragSelection = const <int>{};
      case _DragMode.field:
        game.dragSelection = _selectedFields;
        game.dragSelectColor = 0xFF4CAF50; // green
      case _DragMode.annex:
        game.dragSelection = controller.settlementSelection;
        game.dragSelectColor = 0xFFEF6C00; // amber
      case _DragMode.transfer:
        // No translucent fill — the transfer selection renders as the white
        // dashed contour (MapGame.outlineSelection). The box frame stays
        // visible while dragging (the anchor lives until the gesture ends).
        game.dragSelection = const <int>{};
    }
  }

  /// Keeps [_dragMode] consistent with the game phase: arms annex mode while
  /// the winner's settlement is open, and drops field mode when a war,
  /// handoff or off-turn view takes over. Never called with a nested
  /// setState — the controller listener repaints after it.
  void _syncDragMode(GameController controller) {
    final war = controller.state.activeWar;
    final settling =
        war != null &&
        war.phase == gc.WarPhase.settlement &&
        war.winnerSlot == controller.warHumanSlot &&
        !controller.handoffPending &&
        !controller.readOnly;
    if (settling) {
      if (_dragMode != _DragMode.annex) {
        _dragMode = _DragMode.annex;
        // Clear directly (not via the notifying setter): _syncDragMode runs
        // inside the controller listener, and re-notifying would recurse.
        controller.settlementSelection.clear();
        _game?.clearBox();
      } else {
        // A committed annex turned the anchor tile into own land: the box
        // has served its purpose — drop the dashed frame. (While dragging,
        // the anchor always stays enemy-owned, so this never fires then.)
        final anchor = _game?.boxAnchor;
        if (anchor != null &&
            !_annexSelectable(controller, anchor.$1, anchor.$2)) {
          _game?.clearBox();
          controller.settlementSelection.clear();
        }
      }
    } else if (_dragMode == _DragMode.annex) {
      _dragMode = _DragMode.none;
      controller.settlementSelection.clear();
    } else if (_dragMode == _DragMode.transfer &&
        controller.transferTargetSlot == null) {
      _dragMode = _DragMode.none;
    } else if (_dragMode == _DragMode.field && !_canFieldMode(controller)) {
      _dragMode = _DragMode.none;
      _selectedFields.clear();
    }
    _applyDragMode(controller);
  }

  /// Long-press on a map tile: anchors a selection box there — an enemy
  /// tile during the winner's open settlement (annex mode, already armed
  /// by phase), or ANY tile on the peacetime turn (enters field mode; the
  /// box selects only buildable tiles, so an anchor far from the realm
  /// simply starts empty and is dropped on release if it stays that way).
  /// Returns whether the press was consumed; the map layer then swallows
  /// the accompanying tap so no tile sheet opens on release. A later
  /// long-press re-anchors a fresh box.
  bool _onLongPressTile(GameController controller, int x, int y) {
    final game = _game;
    if (game == null || controller.handoffPending || controller.gameOver) {
      return false;
    }
    if (_dragMode == _DragMode.annex) {
      if (!_annexSelectable(controller, x, y)) return false;
    } else if (controller.transferTargetSlot != null && !widget.tutorial) {
      // Transfer multi-select: long-press anchors a box that drag-selects
      // transferable own tiles (the pick stays armed for the banner).
      if (_dragMode != _DragMode.transfer) {
        _dragMode = _DragMode.transfer;
        _applyDragMode(controller);
      }
    } else if (_canFieldMode(controller) && !widget.tutorial) {
      if (_dragMode != _DragMode.field) {
        controller.cancelTilePick();
        _dragMode = _DragMode.field;
        _applyDragMode(controller);
      }
    } else {
      return false;
    }
    HapticFeedback.selectionClick();
    game.boxAnchor = (x, y);
    game.boxCorner = null;
    _reselectBox(controller);
    return true;
  }

  /// Box drag: the finger moved to ([x],[y]) — resize the box to it and
  /// reselect the eligible tiles inside.
  void _onBoxDrag(GameController controller, int x, int y) {
    final game = _game;
    if (game == null || game.boxAnchor == null) return;
    if (game.boxCorner == (x, y)) return;
    game.boxCorner = (x, y);
    _reselectBox(controller);
  }

  /// Recomputes the active selection as every eligible tile inside the
  /// anchor..corner box. Field mode owns [_selectedFields]; transfer and
  /// annex mode write the controller's transfer/settlement selection
  /// (one notify per resize).
  void _reselectBox(GameController controller) {
    final game = _game;
    final anchor = game?.boxAnchor;
    if (game == null || anchor == null) return;
    final corner = game.boxCorner ?? anchor;
    final map = controller.visibleState.map;
    final x0 = math.min(anchor.$1, corner.$1);
    final x1 = math.max(anchor.$1, corner.$1);
    final y0 = math.min(anchor.$2, corner.$2);
    final y1 = math.max(anchor.$2, corner.$2);
    final picked = <int>{};
    if (_dragMode == _DragMode.field) {
      picked.addAll(_fieldTilesInBox(controller, x0, y0, x1, y1));
      setState(
        () => _selectedFields
          ..clear()
          ..addAll(picked),
      );
      return;
    }
    if (_dragMode == _DragMode.transfer) {
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          if (_transferSelectable(controller, x, y)) {
            picked.add(map.index(x, y));
          }
        }
      }
      controller.setTransferSelection(picked);
      return;
    }
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if (_annexSelectable(controller, x, y)) picked.add(map.index(x, y));
      }
    }
    controller.setSettlementSelection(picked);
  }

  /// Field tiles selectable inside a box: empty land the realm owns, plus
  /// unowned empty land CONNECTED to its territory — directly bordering,
  /// or through a chain of other selected tiles (the engine claims each
  /// built border tile, which lets the next one behind it build too, see
  /// `planFieldCultivation`). Without the chain wave a box dragged into
  /// free land would only ever offer the first border row.
  Set<int> _fieldTilesInBox(
    GameController controller,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    final map = controller.visibleState.map;
    final slot = controller.currentSlot;
    final candidates = <int>{};
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final owner = map.ownerAt(x, y);
        if ((owner == slot || owner == gc.World.niemand) &&
            gc.Terrain.isLand(map.terrainAt(x, y)) &&
            map.buildingAt(x, y) == gc.Building.none) {
          candidates.add(map.index(x, y));
        }
      }
    }
    // Wave: own tiles and border-touching unowned tiles seed; each picked
    // tile carries the selection to its candidate neighbors.
    final picked = <int>{};
    final queue = <int>[];
    for (final i in candidates) {
      final x = i % map.width;
      final y = i ~/ map.width;
      if (map.ownerAt(x, y) == slot || map.bordersSlot(x, y, slot)) {
        picked.add(i);
        queue.add(i);
      }
    }
    for (var head = 0; head < queue.length; head++) {
      final i = queue[head];
      for (final (nx, ny) in map.neighborsOf(i % map.width, i ~/ map.width)) {
        final ni = map.index(nx, ny);
        if (candidates.contains(ni) && picked.add(ni)) queue.add(ni);
      }
    }
    return picked;
  }

  /// Whether ([x],[y]) may be drag-selected for transfer: an own tile that
  /// is not the capital and carries no troops or ships — the exact gates of
  /// the engine's `TransferTile` action (and of the tap pick).
  bool _transferSelectable(GameController controller, int x, int y) {
    final map = controller.visibleState.map;
    final slot = controller.currentSlot;
    if (map.ownerAt(x, y) != slot) return false;
    final realm = controller.visibleState.realm(slot);
    if (x == realm.capitalX && y == realm.capitalY) return false;
    if (realm.troops.any((t) => t.x == x && t.y == y)) return false;
    if (realm.ships.any((s) => s.x == x && s.y == y)) return false;
    return true;
  }

  /// Whether the field-cultivation drag-select may run right now: only on
  /// the seated player's own peacetime turn, never during a war, handoff,
  /// tile pick, off-turn view or after the game ended.
  bool _canFieldMode(GameController controller) =>
      controller.state.activeWar == null &&
      !controller.warPauseActive &&
      !controller.handoffPending &&
      !controller.gameOver &&
      !controller.tilePickActive &&
      !controller.readOnly;

  /// Finger lifted off the box gesture: field mode opens the batch-build
  /// sheet (the same bottom sheet as a single-tile tap) over the live
  /// selection. Building leaves the mode; dismissing keeps the selection —
  /// drag again to resize, or tap anywhere to cancel. A box that reaches
  /// no buildable tile (started and released away from the realm) is
  /// simply dropped. Annex mode confirms via the war panel instead, so
  /// the lift does nothing there.
  Future<void> _onBoxSelectDone(GameController controller) async {
    if (_dragMode == _DragMode.transfer) {
      // Drop the dashed frame; the white contour stays on the selection and
      // the banner's "Felder übertragen" commits it.
      _game?.clearBox();
      return;
    }
    if (_dragMode != _DragMode.field) return;
    if (_selectedFields.isEmpty) {
      _exitFieldMode(controller);
      return;
    }
    if (!mounted) return;
    final built = await showFieldBatchSheet(
      context,
      controller,
      _selectedFields,
    );
    if (built) _exitFieldMode(controller);
  }

  void _exitFieldMode(GameController controller) {
    _selectedFields.clear();
    _dragMode = _DragMode.none;
    setState(() => _applyDragMode(controller));
  }

  /// Whether ([x],[y]) is an enemy tile the winner may drag-select to annex:
  /// a tile still owned by the war's loser. Adjacency to the winner's border
  /// and affordability are resolved later, per confirm — an unreachable or
  /// unaffordable selected tile is simply left with the loser.
  bool _annexSelectable(GameController controller, int x, int y) {
    final war = controller.state.activeWar;
    if (war == null || war.phase != gc.WarPhase.settlement) return false;
    final winner = war.winnerSlot;
    if (winner == null) return false;
    final map = controller.state.map;
    if (!map.inBounds(x, y)) return false;
    return map.ownerAt(x, y) == war.opponentOf(winner);
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
      // Tap toggles a single enemy tile in/out of the annex selection (a
      // drag paints); the war panel's "Annektieren" button commits it.
      final idx = controller.state.map.index(x, y);
      if (controller.settlementSelection.contains(idx)) {
        controller.toggleSettlementTile(idx);
      } else if (_annexSelectable(controller, x, y)) {
        controller.addSettlementTile(idx);
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
            ? tr('game.selectTroopFirstEnemy')
            : tr('game.selectTroopFirst'),
      );
      return;
    }
    await _marchToward(controller, slot, selected, x, y);
  }

  /// Marches the selected unit toward (tx, ty): ONE engine `WarMarch`
  /// walks the whole order — shortest passable route, as far as the round's
  /// Züge reach, around enemy stacks it was not sent to fight, and by ship
  /// through a harbor when the sea is the faster way (`marchWarUnit`).
  ///
  /// `[2026-08-24]` The routing used to be split: the engine walked the
  /// land while the CLIENT decided the sea legs, so the AI — which cannot
  /// run client code — never used a harbor at all. Both sides now share
  /// the engine's planner, and the tap simply forwards the order.
  Future<void> _marchToward(
    GameController controller,
    int slot,
    int unitIndex,
    int tx,
    int ty,
  ) async {
    final report = <gc.GameEvent>[];
    try {
      final result = await controller.applyWarAction(
        gc.WarMarch(slot: slot, unitIndex: unitIndex, x: tx, y: ty),
      );
      report.addAll(result.events);
    } on gc.ActionException catch (e) {
      // Only a march that could not move AT ALL throws; one that ran out
      // of Züge part-way keeps the ground it won and reports nothing.
      _toast(e.message);
    }

    // The march may have ended with the unit destroyed — drop a stale
    // selection so the ring never marks a different unit.
    final troops = controller.state.realm(slot).troops;
    if (unitIndex >= troops.length) controller.selectWarUnit(null);

    if (!mounted) return;
    await showWarReport(context, report, viewerSlot: slot);
    // A capital capture ends the war mid-march: resume the paused AI turn.
    if (controller.state.activeWar == null) {
      await controller.resumeAfterWar();
      // Coercion choices from a capture come immediately.
      if (mounted) await promptDecisionsFor(context, controller, slot);
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
                      // The two map overlays share the top edge but not a
                      // box: the realm name (left) may be long, the vitals
                      // (right) must stay a narrow column of numbers —
                      // stacking them in one card made it grow into the
                      // map (user report 2026-07-28). Both are hidden while
                      // the tile-pick banner occupies the top edge; during
                      // a war the vitals drop to the year alone (the docked
                      // war panel owns the numbers).
                      if (!controller.tilePickActive &&
                          !controller.handoffPending) ...[
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _realmChip(controller),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _resourceChip(
                            controller,
                            vitals: controller.state.activeWar == null,
                          ),
                        ),
                      ],
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
                // War controls docked above the status row: full width,
                // an extension of the bottom menu block instead of an
                // overlay hiding the map.
                if (controller.state.activeWar != null &&
                    !controller.handoffPending)
                  WarPanel(controller: controller),
                _statusRow(controller),
                // The category bar is hidden during a war: the war panel
                // replaces it as THE bottom menu (the info menu stays
                // reachable via the realm name in the status row).
                if (controller.state.activeWar == null) _actionBar(controller),
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

  /// Floating instruction card while a map tile pick is active. The
  /// "Felder übertragen" multi-select additionally offers its two confirm
  /// buttons (Abbrechen / Felder übertragen) on their own line.
  Widget _tilePickBanner(GameController controller) {
    final theme = Theme.of(context);
    final transferring = controller.transferTargetSlot != null;
    final hint = controller.tilePickHint ?? '';
    final selected = controller.transferSelection.length;
    final hintRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.touch_app, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            transferring && selected > 0
                ? tr('menus.transferTileHintCount', {
                    'hint': hint,
                    'n': selected,
                  })
                : hint,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
    return Card(
      margin: const EdgeInsets.all(12),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: transferring
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  hintRow,
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: controller.cancelTransferSelection,
                        child: Text(tr('cancel')),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: selected == 0
                            ? null
                            : () => _confirmTransferTiles(controller),
                        child: Text(tr('menus.transferTiles')),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  hintRow,
                  if (controller.tilePickCancellable)
                    TextButton(
                      onPressed: controller.cancelTilePick,
                      child: Text(tr('cancel')),
                    ),
                ],
              ),
      ),
    );
  }

  /// Whose turn it is, floating over the map's top left: the realm color
  /// and name on one line. Tapping opens "Mein Reich", like the vitals
  /// card opposite.
  ///
  /// Its own overlay rather than a header inside [_resourceChip]: names
  /// run up to ~13 characters and dragged that card's whole column of
  /// numbers out to their width (user report 2026-07-28). Anchored left,
  /// the name grows away from the numbers and only against free map, so
  /// it needs no truncation until it would meet the vitals card — the
  /// cap below (45 % of the screen) is the never-reached safety net.
  Widget _realmChip(GameController controller) {
    final theme = Theme.of(context);
    final realmLabel = realmName(controller.currentSlot);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showInfoMenu(context, controller),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 6,
                backgroundColor: RealmPalette.colorFor(
                  controller.currentSlot,
                  state: controller.state,
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.45,
                ),
                child: Text(
                  realmLabel,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Always-visible vitals floating over the map (top right): year,
  /// treasury, remaining moves and popularity as a narrow column of icon
  /// rows — its width is fixed by 4-digit numbers, never by text.
  /// Tapping opens "Mein Reich". With [vitals] false only the year is
  /// drawn: the form used during a war, where the docked war panel owns
  /// the numbers but the year must stay on screen (the bottom row carries
  /// neither year nor realm since 2026-07-28).
  Widget _resourceChip(GameController controller, {bool vitals = true}) {
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
            label: [
              tr('game.anno', {'year': controller.state.year}),
              if (vitals) ...[
                '${tr('treasury')}: ${realm.treasury} Taler',
                '${tr('moves')}: ${realm.movementPoints}',
                '${tr('popularity')}: ${realm.popularity}'
                    '${lowPopularity ? ' — ${tr('game.dangerouslyLow')}' : ''}',
              ],
            ].join(', '),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  line(Icons.calendar_today, '${controller.state.year}'),
                  if (vitals) ...[
                    const SizedBox(height: 2),
                    line(Icons.toll, '${realm.treasury}'),
                    const SizedBox(height: 2),
                    line(Icons.construction, '${realm.movementPoints}'),
                    const SizedBox(height: 2),
                    Tooltip(
                      message: lowPopularity
                          ? tr('game.popularityDangerLow')
                          : tr('popularity'),
                      child: line(
                        lowPopularity ? Icons.heart_broken : Icons.favorite,
                        '${realm.popularity}',
                        color: lowPopularity ? theme.colorScheme.error : null,
                      ),
                    ),
                  ],
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
        title: Text(tr('game.leaveGameQuestion')),
        content: Text(
          _controller?.isOnline == true
              ? tr('game.leaveGameOnlineBody')
              : tr('game.leaveGameLocalBody'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('game.leaveGame')),
          ),
        ],
      ),
    );
    if (sure == true && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  /// Slim action row, replacing both the old HUD and the top-bar overlay
  /// (which used to block map tiles): leave-game on the left, the two
  /// turn controls (undo, end turn) grouped on the right. Realm, year and
  /// the vitals live over the map in [_resourceChip] — sharing this row
  /// with them left every element too narrow (user report 2026-07-28).
  Widget _statusRow(GameController controller) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: _confirmLeaveGame,
              icon: const Icon(Icons.logout),
              color: theme.colorScheme.error,
              tooltip: tr('game.leaveGame'),
              visualDensity: VisualDensity.compact,
            ),
            const Spacer(),
            if (controller.supportsUndo)
              IconButton(
                onPressed: controller.canUndo ? controller.undo : null,
                icon: const Icon(Icons.undo),
                tooltip: tr('undo'),
                visualDensity: VisualDensity.compact,
              ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed:
                  controller.state.activeWar == null &&
                      !controller.tilePickActive
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
    final locked = controller.warPauseActive || controller.tilePickActive;
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
    // Brief the defender exactly once per war: an explicit marker on the
    // controller (which outlives the per-turn GameScreen rebuilds) instead
    // of inferring freshness from the recap contents. After an app restart
    // mid-war the briefing may show once more — by design, it doubles as
    // the save-resume orientation.
    if (war == null || !controller.takeWarBriefing(slot)) return;
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
                tr('game.warTitle'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        // Long briefing — must scroll on small screens / large text scale.
        content: SingleChildScrollView(
          child: Text(
            tr('game.warBriefing', {'attacker': realmName(war.attackerSlot)}),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('game.toArms')),
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
              '${realmName(slot)}'
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
    final tail = tr('game.defeatTail');
    final cause = switch (reason) {
      'internalStrife' => tr('game.defeatInternalStrife'),
      'bankruptcy' => tr('game.defeatBankruptcy'),
      'islamicSuccessionCrisis' => tr('game.defeatSuccessionCrisis'),
      'realmInherited' => tr('game.defeatRealmInherited'),
      'rulerCaptured' => tr('game.defeatRulerCaptured'),
      'realmOverrun' => tr('game.defeatRealmOverrun'),
      'dynastyExtinct' || 'totalExtinction' => tr('game.defeatDynastyExtinct'),
      _ => null,
    };
    return cause == null ? tail : '$cause\n\n$tail';
  }

  Widget _victory(GameController controller) {
    final event = controller.gameEndEvent!;
    final slot = event.slot;
    final draw = event.type == 'gameDraw';
    // A realm transfer ends the game in the same action that eliminates the
    // former human seat. The resulting gameWon event is public so the
    // recipient can see it online, but the player who gave up the last realm
    // must see a defeat modal instead of a victory modal. During a local
    // action the engine's currentPlayer remains the source slot; online the
    // receiving player's filtered view is keyed to their own slot.
    final transferredSource = event.payload['sourceSlot'];
    final defeat =
        event.type == 'humansDefeated' ||
        (event.type == 'gameWon' &&
            transferredSource is int &&
            transferredSource == controller.currentSlot);
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
                    ? tr('game.drawBody')
                    : tr('game.victoryBody', {'realm': realmName(slot)}),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(tr('game.backToMainMenu')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
