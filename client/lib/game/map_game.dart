import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart' show Rect, Paint, Canvas;
import 'package:game_core/game_core.dart' as gc;

import 'realm_palette.dart';

/// World-space size of one map tile (the source sprites are 32×32 px).
const double tileSize = 32.0;

/// The Flame map: renders the 80×44 tile world from a [gc.GameState],
/// supports pinch-zoom + pan, and reports tile taps.
///
/// The whole map is rasterized into one [ui.Picture] whenever the state
/// changes; per-frame rendering is a single drawPicture — comfortably 60
/// fps even on low-end devices.
class MapGame extends FlameGame with ScaleDetector {
  MapGame({required gc.GameState initial, this.onTileTap})
      : _state = initial;

  /// Called with tile coordinates when the player taps the map.
  void Function(int x, int y)? onTileTap;

  gc.GameState _state;
  ui.Picture? _picture;
  final Map<int, ui.Image> _tiles = {};
  late double _startZoom;

  /// Tile sprite index per terrain value (§24): 0 Ebene, 1 Berg, 2 open
  /// water; shoreline variants 3–17 map onto sprites 03–13.
  /// [APPROX: the exact mask→sprite table was not traced; this mapping
  /// covers all 15 variants with plausible shore art.]
  static const List<int> _terrainSprite = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 3, 5, 7, 9,
  ];

  /// Building sprite index per building type (§24).
  static const List<int> _buildingSprite = [
    -1, 19, 20, 21, 22, 23, 24, 25, 27,
  ];

  static const int _troopSprite = 30; // knight icon
  static const int _capitalSprite = 26; // ruler figure

  @override
  Future<void> onLoad() async {
    images.prefix = 'assets/';
    for (var i = 0; i < 38; i++) {
      final n = i.toString().padLeft(2, '0');
      _tiles[i] = await images.load('tiles/large/$n.png');
    }
    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = Vector2(
        gc.World.mapWidth * tileSize / 2, gc.World.mapHeight * tileSize / 2);
    camera.viewfinder.zoom = 0.6;
    world.add(_MapLayer(this));
    _rebuild();
  }

  /// Swap in a new game state and re-rasterize.
  void updateState(gc.GameState state) {
    _state = state;
    if (_tiles.isNotEmpty) _rebuild();
  }

  void _rebuild() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final map = _state.map;
    final paint = Paint();

    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        final cell =
            Rect.fromLTWH(x * tileSize, y * tileSize, tileSize, tileSize);
        _drawSprite(canvas, _terrainSprite[map.terrainAt(x, y)], cell, paint);

        final building = map.buildingAt(x, y);
        if (building != gc.Building.none) {
          _drawSprite(canvas, _buildingSprite[building], cell, paint);
        }

        final owner = map.ownerAt(x, y);
        if (owner != gc.World.niemand) {
          RealmPalette.paintOwnership(canvas, cell, owner);
          final realm = _state.realm(owner);
          if (realm.capitalX == x && realm.capitalY == y) {
            _drawSprite(canvas, _capitalSprite, cell.deflate(tileSize / 4),
                paint);
          }
        }
        if (map.troopMarker[map.index(x, y)] != 0) {
          _drawSprite(
              canvas, _troopSprite, cell.deflate(tileSize / 5), paint);
        }
      }
    }
    _picture = recorder.endRecording();
  }

  void _drawSprite(Canvas canvas, int index, Rect dest, Paint paint) {
    final image = _tiles[index];
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dest,
      paint,
    );
  }

  // --- Gestures -------------------------------------------------------

  @override
  void onScaleStart(ScaleStartInfo info) {
    _startZoom = camera.viewfinder.zoom;
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    if (info.pointerCount >= 2) {
      camera.viewfinder.zoom =
          (_startZoom * info.scale.global.y).clamp(0.35, 6.0);
    } else {
      final delta = info.delta.global;
      camera.viewfinder.position -=
          Vector2(delta.x, delta.y) / camera.viewfinder.zoom;
    }
    _clampCamera();
  }

  void _clampCamera() {
    final p = camera.viewfinder.position;
    camera.viewfinder.position = Vector2(
      p.x.clamp(0.0, gc.World.mapWidth * tileSize),
      p.y.clamp(0.0, gc.World.mapHeight * tileSize),
    );
  }

}

/// World-space map layer: draws the cached picture and receives taps in
/// world coordinates (the camera transform is applied by Flame).
class _MapLayer extends PositionComponent with TapCallbacks {
  _MapLayer(this.game)
      : super(
          size: Vector2(gc.World.mapWidth * tileSize,
              gc.World.mapHeight * tileSize),
        );

  final MapGame game;

  @override
  void render(Canvas canvas) {
    final picture = game._picture;
    if (picture != null) canvas.drawPicture(picture);
  }

  @override
  void onTapUp(TapUpEvent event) {
    final x = (event.localPosition.x / tileSize).floor();
    final y = (event.localPosition.y / tileSize).floor();
    if (x >= 0 && x < gc.World.mapWidth && y >= 0 && y < gc.World.mapHeight) {
      game.onTileTap?.call(x, y);
    }
  }
}
