import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../game/map_game.dart';
import '../game/realm_palette.dart';
import '../l10n/strings.dart';
import '../services/local_game_session.dart';
import '../services/save_service.dart';
import '../state/game_controller.dart';
import '../widgets/decisions.dart';
import '../widgets/event_feed.dart';
import '../widgets/menus.dart';
import '../widgets/tile_sheet.dart';
import '../widgets/war_panel.dart';

/// The in-game screen: Flame map + HUD + menus, with the hot-seat handoff
/// blocker and pending-decision prompts layered on top.
class GameScreen extends StatefulWidget {
  const GameScreen._({required this.sessionFuture});

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

  final Future<LocalGameSession> sessionFuture;

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
    if (controller.state.activeWar != null) {
      showWarTileSheet(context, controller, x, y);
      return;
    }
    showTileActionSheet(context, controller, x, y);
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
          Positioned.fill(child: GameWidget(game: game)),
          if (controller.state.activeWar != null &&
              !controller.handoffPending)
            Align(
              alignment: Alignment.topCenter,
              child: WarPanel(controller: controller),
            )
          else
            Align(alignment: Alignment.topLeft, child: _topBar(controller)),
          Align(
              alignment: Alignment.bottomCenter, child: _hud(controller)),
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

  Widget _topBar(GameController controller) {
    final state = controller.visibleState;
    final realmName = gc.countryNames[controller.currentSlot];
    final ruler = state.person(controller.currentRealm.rulerId);
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to menu',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          CircleAvatar(
            radius: 10,
            backgroundColor: RealmPalette.colorFor(controller.currentSlot),
          ),
          const SizedBox(width: 8),
          Text(
            'Anno ${state.year} — $realmName'
            '${ruler == null ? '' : ' (${gc.titleName(controller.currentRealm.titleClass)} ${ruler.name})'}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ]),
      ),
    );
  }

  Widget _hud(GameController controller) {
    final realm = controller.currentRealm;
    final theme = Theme.of(context);
    Widget stat(IconData icon, String label, String value) => Semantics(
          label: '$label: $value',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18),
              Text(value, style: theme.textTheme.labelMedium),
            ]),
          ),
        );

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            stat(Icons.savings, tr('treasury'), '${realm.treasury} T'),
            stat(Icons.groups, tr('population'), '${realm.population}'),
            stat(Icons.agriculture, tr('food'),
                '${realm.grainHarvest + realm.livestockHarvest}'),
            stat(Icons.favorite, tr('popularity'), '${realm.popularity}'),
            stat(Icons.directions_walk, tr('moves'),
                '${realm.movementPoints}'),
            if (realm.popularity < 30)
              const Tooltip(
                message: 'Popularity dangerously low!',
                child: Icon(Icons.warning_amber, color: Colors.orange),
              ),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              onPressed: controller.canUndo ? controller.undo : null,
              icon: const Icon(Icons.undo),
              tooltip: tr('undo'),
            ),
            IconButton(
              onPressed: () => showGameMenus(context, controller),
              icon: const Icon(Icons.menu),
              tooltip: 'Menus',
            ),
            IconButton(
              onPressed: () => showEventFeed(context, controller),
              icon: const Icon(Icons.article),
              tooltip: tr('eventFeed'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: controller.state.activeWar == null
                  ? () => controller.endTurn()
                  : null,
              icon: const Icon(Icons.skip_next),
              label: Text(tr('endTurn')),
            ),
          ]),
        ]),
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
            '${gc.countryNames[slot]} rules the whole land!',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Back to menu'),
          ),
        ]),
      ),
    );
  }
}
