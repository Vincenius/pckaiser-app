import 'dart:math' as math;
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

  /// Tile sprite index per terrain value: the extracted sprites 00–17 map
  /// 1:1 onto terrain values — 0 Ebene, 1 Berg, 2 open water, 3–17 the
  /// shoreline variants in land-neighbor-mask order (verified against the
  /// art: 03 land below, 04 land above, 06 land left, 10 land right).
  static const List<int> _terrainSprite = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
  ];

  /// Building sprite index per building type. The extracted set is offset
  /// by one against the §24 table: 18 Kornfeld, 19 Weide, 20 Dorf,
  /// 21 Markt, 22 Stadt, 23 Burg, 24 Palast, 25 Hafen (verified visually).
  static const List<int> _buildingSprite = [
    -1, 18, 19, 20, 21, 22, 23, 24, 25,
  ];

  static const int _troopSprite = 35; // sword: attacking / idle own troops
  static const int _shieldSprite = 36; // shield: the war's defending side

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
    focusOnRealm(_state.currentPlayer);
  }

  /// Swap in a new game state and re-rasterize.
  void updateState(gc.GameState state) {
    _state = state;
    if (_tiles.isNotEmpty) _rebuild();
  }

  /// Centers and zooms the camera onto [slot]'s territory — called at the
  /// start of every player turn so the seated player's realm is in focus.
  void focusOnRealm(int slot) {
    final map = _state.map;
    var minX = map.width, minY = map.height, maxX = -1, maxY = -1;
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.ownerAt(x, y) != slot) continue;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }
    if (maxX < 0) {
      final realm = _state.realm(slot);
      minX = maxX = realm.capitalX;
      minY = maxY = realm.capitalY;
    }
    // One tile of margin on every side, then fit — but never closer than
    // 3.0 (tiny realms) and never farther out than the pan limit allows.
    final extentX = (maxX - minX + 3) * tileSize;
    final extentY = (maxY - minY + 3) * tileSize;
    final fit = math.min(size.x / extentX, size.y / extentY);
    camera.viewfinder.zoom = fit.clamp(0.6, 3.0);
    camera.viewfinder.position = Vector2(
        (minX + maxX + 1) / 2 * tileSize, (minY + maxY + 1) / 2 * tileSize);
    _clampCamera();
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
            RealmPalette.paintCapital(canvas, cell, owner);
          }
        }
        // The visible state encodes the troop owner in the marker: the
        // war's defending side gets the shield, everyone else the sword.
        final troopOwner = map.troopMarker[map.index(x, y)];
        if (troopOwner != 0) {
          final war = _state.activeWar;
          final sprite = war != null && troopOwner == war.defenderSlot
              ? _shieldSprite
              : _troopSprite;
          _drawSprite(canvas, sprite, cell.deflate(tileSize / 5), paint);
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

  /// Keeps the visible area inside the map: the camera center may not get
  /// closer to an edge than half the viewport (in world units). When the
  /// whole map fits on one axis, that axis is centered instead.
  void _clampCamera() {
    final zoom = camera.viewfinder.zoom;
    final halfW = size.x / (2 * zoom);
    final halfH = size.y / (2 * zoom);
    const mapW = gc.World.mapWidth * tileSize;
    const mapH = gc.World.mapHeight * tileSize;
    double axis(double value, double half, double max) =>
        2 * half >= max ? max / 2 : value.clamp(half, max - half);
    final p = camera.viewfinder.position;
    camera.viewfinder.position = Vector2(
      axis(p.x, halfW, mapW),
      axis(p.y, halfH, mapH),
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
