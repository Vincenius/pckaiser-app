import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../game/map_game.dart';
import '../game/realm_palette.dart';
import '../l10n/strings.dart';
import '../services/game_session.dart';
import '../state/game_controller.dart';
import '../widgets/menus.dart';

/// Read-only view of the seat's realm(s) while it is another player's turn
/// in an online match: the Flame map with pan/zoom plus the Info menu
/// (Mein Reich, Ereignisse, Siedlungen, Dynastien, Kaiserchronik) — no
/// actions. The state is the server's per-seat filtered copy, so foreign
/// realms stay fuzzed exactly as in play. A player holding several realms
/// (control follows the ruler) can switch between them.
class MapViewerScreen extends StatefulWidget {
  const MapViewerScreen({
    super.key,
    required this.session,
    required this.viewerSlot,
    this.waitingFor,
  });

  /// Holds the seat's visible game state (already filtered by the
  /// server). Never submitted to — the controller runs read-only.
  final GameSession session;

  /// The seat's realm slot; the initially viewed/focused realm.
  final int viewerSlot;

  /// Who is currently at the turn ("Anna (Sachsen) ist am Zug …"), so the
  /// view explains why it is read-only.
  final String? waitingFor;

  @override
  State<MapViewerScreen> createState() => _MapViewerScreenState();
}

class _MapViewerScreenState extends State<MapViewerScreen> {
  late final GameController _controller = GameController.readOnly(
    widget.session,
    viewSlot: widget.viewerSlot,
  );
  late final MapGame _game = MapGame(
    initial: _controller.visibleState,
    focusSlot: widget.viewerSlot,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _switchRealm(int slot) {
    setState(() => _controller.setViewSlot(slot));
    _game.focusOnRealm(slot);
  }

  @override
  Widget build(BuildContext context) {
    final ownedSlots = _controller.ownedSlots.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Karte — Anno ${_controller.state.year}'),
            if (widget.waitingFor != null)
              Text(
                widget.waitingFor!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: GameWidget(game: _game)),
            _statusRow(ownedSlots),
            _menuBar(),
          ],
        ),
      ),
    );
  }

  /// Realm chip (tap for the "Mein Reich" info sheet), realm switcher for
  /// seats holding several realms, and the read-only marker.
  Widget _statusRow(List<int> ownedSlots) {
    final theme = Theme.of(context);
    final slot = _controller.currentSlot;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => showInfoMenu(context, _controller),
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
                        backgroundColor: RealmPalette.colorFor(slot),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          gc.countryNames[slot],
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
            if (ownedSlots.length > 1)
              PopupMenuButton<int>(
                tooltip: 'Reich wechseln',
                icon: const Icon(Icons.swap_horiz, size: 20),
                onSelected: _switchRealm,
                itemBuilder: (context) => [
                  for (final s in ownedSlots)
                    PopupMenuItem(
                      value: s,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 6,
                            backgroundColor: RealmPalette.colorFor(s),
                          ),
                          const SizedBox(width: 8),
                          Text(gc.countryNames[s]),
                          if (s == slot) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.check, size: 16),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            const Spacer(),
            Icon(
              Icons.lock_outline,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              'Nur ansehen',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The game screen's category bar in read-only form: the action menus
  /// (they issue actions for a running turn) stay locked, only the Info
  /// menu — pure reads — opens.
  Widget _menuBar() {
    final theme = Theme.of(context);
    Widget item(
      IconData icon,
      String label,
      void Function(BuildContext, GameController)? open,
    ) => Expanded(
      child: InkWell(
        onTap: open == null ? null : () => open(context, _controller),
        child: Opacity(
          opacity: open == null ? 0.4 : 1,
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
          item(Icons.storefront, tr('commerce'), null),
          item(Icons.shield, tr('military'), null),
          item(Icons.visibility, tr('espionage'), null),
          item(Icons.church, tr('misc'), null),
          item(Icons.info_outline, tr('info'), showInfoMenu),
        ],
      ),
    );
  }
}
