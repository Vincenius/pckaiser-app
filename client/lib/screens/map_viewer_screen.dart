import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../game/map_game.dart';

/// Read-only board view: just the Flame map with pan/zoom, no HUD and no
/// actions. Shown when a seat wants to study the map while it is another
/// player's turn in an online match. The state is the server's per-seat
/// filtered copy, so foreign realms stay fuzzed exactly as in play.
class MapViewerScreen extends StatefulWidget {
  const MapViewerScreen({super.key, required this.state, this.focusSlot});

  /// The seat's visible game state (already filtered by the server).
  final gc.GameState state;

  /// Realm to center on; the watching seat's own realm by default.
  final int? focusSlot;

  @override
  State<MapViewerScreen> createState() => _MapViewerScreenState();
}

class _MapViewerScreenState extends State<MapViewerScreen> {
  late final MapGame _game = MapGame(
    initial: widget.state,
    focusSlot: widget.focusSlot,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Karte — Anno ${widget.state.year}')),
      body: SafeArea(child: GameWidget(game: _game)),
    );
  }
}
