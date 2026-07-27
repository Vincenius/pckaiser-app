import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart'
    show
        Canvas,
        Color,
        FontWeight,
        Offset,
        Paint,
        PaintingStyle,
        Rect,
        RRect,
        Radius,
        Shadow,
        TextPainter,
        TextSpan,
        TextStyle;
import 'package:game_core/game_core.dart' as gc;

import '../l10n/labels.dart';
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
  MapGame({required gc.GameState initial, this.onTileTap, this.focusSlot})
    : _state = initial;

  /// Called with tile coordinates when the player taps the map.
  void Function(int x, int y)? onTileTap;

  /// Realm to center on once the camera is ready; defaults to whoever is
  /// currently at the turn ([gc.GameState.currentPlayer]). The read-only
  /// map viewer passes the watching seat's own realm here.
  final int? focusSlot;

  /// Tile of the currently selected war unit (pulsing ring); null = none.
  (int, int)? selectedTile;

  /// Box select (field cultivation / post-war annexation): a LONG-PRESS on
  /// an eligible tile anchors the box ([onLongPressTile] decides and sets
  /// [boxAnchor]); while an anchor is set, a one-finger drag moves the
  /// opposite corner ([boxCorner], via [onBoxDrag]) instead of panning —
  /// two-finger pinch still zooms/pans. The screen recomputes which tiles
  /// inside the box are eligible and keeps them in [dragSelection].
  (int, int)? boxAnchor;

  /// Opposite corner of the selection box, dragged by the finger; null
  /// while the box is just the anchor tile.
  (int, int)? boxCorner;

  /// Long-press on tile ([x],[y]): the screen returns true when it anchors
  /// a selection box there (the layer then swallows the tap-up of the same
  /// press so no tile sheet opens on release).
  bool Function(int x, int y)? onLongPressTile;

  /// Called with the tile under the finger (clamped to the map) while a
  /// box drag is in progress — the screen resizes the box and reselects.
  void Function(int x, int y)? onBoxDrag;

  /// Fired when the finger lifts off a box gesture — after sizing the box,
  /// or right after the anchoring long-press with no drag. The screen
  /// opens the batch-build sheet on it (field mode).
  void Function()? onBoxDragEnd;

  /// True while the CURRENT scale gesture resizes the box — so a pinch
  /// (zoom/pan) ending mid-selection does not count as a box drag end.
  bool _boxDragging = false;

  /// Tile indices (`y * width + x`) currently box-selected — owned by the
  /// screen (or controller), rendered here as a translucent highlight.
  Set<int> dragSelection = <int>{};

  /// Base ARGB color of the selected-tile fill (green for fields, amber
  /// for annexation). The dashed box frame is always white-on-dark so it
  /// stays visible on same-hued terrain.
  int dragSelectColor = 0xFF4CAF50;

  /// Drops the selection box (mode exit / phase change).
  void clearBox() {
    boxAnchor = null;
    boxCorner = null;
  }

  gc.GameState _state;
  ui.Picture? _picture;
  final Map<int, ui.Image> _tiles = {};
  late double _startZoom;

  /// Tile sprite index per terrain value: the extracted sprites 00–17 map
  /// 1:1 onto terrain values — 0 Ebene, 1 Berg, 2 open water, 3–17 the
  /// shoreline variants in land-neighbor-mask order (verified against the
  /// art: 03 land below, 04 land above, 06 land left, 10 land right).
  static const List<int> _terrainSprite = [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
  ];

  /// Building sprite index per building type. The extracted set is offset
  /// by one against the §24 table: 18 Kornfeld, 19 Weide, 20 Dorf,
  /// 21 Markt, 22 Stadt, 23 Burg, 24 Palast, 25 Hafen (verified visually).
  static const List<int> _buildingSprite = [-1, 18, 19, 20, 21, 22, 23, 24, 25];

  static const int _troopSprite = 35; // sword: attacking / idle own troops
  static const int _shieldSprite = 36; // shield: the war's defending side
  static const int _shipSprite = 37; // colony ship at sea

  @override
  Future<void> onLoad() async {
    images.prefix = 'assets/';
    for (var i = 0; i < 38; i++) {
      final n = i.toString().padLeft(2, '0');
      _tiles[i] = await images.load('tiles/large/$n.png');
    }
    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = Vector2(
      _state.map.width * tileSize / 2,
      _state.map.height * tileSize / 2,
    );
    camera.viewfinder.zoom = 0.5;
    world.add(_MapLayer(this));
    _rebuild();
    focusOnRealm(focusSlot ?? _state.currentPlayer);
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
    // One tile of margin on every side, then fit — backed off to 80% so
    // the default view starts a bit zoomed out (more surroundings
    // visible), and never closer than 2.5 (tiny realms) or farther out
    // than the pan limit allows.
    final extentX = (maxX - minX + 3) * tileSize;
    final extentY = (maxY - minY + 3) * tileSize;
    final fit = math.min(size.x / extentX, size.y / extentY);
    camera.viewfinder.zoom = (fit * 0.8).clamp(0.5, 2.5);
    camera.viewfinder.position = Vector2(
      (minX + maxX + 1) / 2 * tileSize,
      (minY + maxY + 1) / 2 * tileSize,
    );
    _clampCamera();
  }

  void _rebuild() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final map = _state.map;
    final paint = Paint();

    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        final cell = Rect.fromLTWH(
          x * tileSize,
          y * tileSize,
          tileSize,
          tileSize,
        );
        _drawSprite(canvas, _terrainSprite[map.terrainAt(x, y)], cell, paint);

        final building = map.buildingAt(x, y);
        if (building != gc.Building.none) {
          _drawSprite(canvas, _buildingSprite[building], cell, paint);
          // A war-plundered field lies fallow (engine rule 2026-07-19):
          // darken it so the lost yield is readable off the map.
          if (map.isDevastatedAt(x, y, _state.year)) {
            canvas.drawRect(cell, Paint()..color = const Color(0x77201008));
          }
        }

        final owner = map.ownerAt(x, y);
        if (owner != gc.World.niemand) {
          bool foreign(int nx, int ny) =>
              !map.inBounds(nx, ny) || map.ownerAt(nx, ny) != owner;
          RealmPalette.paintOwnership(
            canvas,
            cell,
            owner,
            state: _state,
            left: foreign(x - 1, y),
            top: foreign(x, y - 1),
            right: foreign(x + 1, y),
            bottom: foreign(x, y + 1),
          );
          final realm = _state.realm(owner);
          if (realm.capitalX == x && realm.capitalY == y) {
            RealmPalette.paintCapital(canvas, cell, owner, state: _state);
          }
        }
        // The visible state encodes the troop owner in the marker: the
        // war's defending side gets the shield, everyone else the sword —
        // on a realm-colored badge so armies are attributable at a glance.
        final troopOwner = map.troopMarker[map.index(x, y)];
        if (troopOwner != 0) {
          final war = _state.activeWar;
          final sprite = war != null && troopOwner == war.defenderSlot
              ? _shieldSprite
              : _troopSprite;
          canvas.drawCircle(
            cell.center,
            tileSize * 0.42,
            Paint()
              ..color = RealmPalette.colorFor(
                troopOwner,
                state: _state,
              ).withValues(alpha: 0.8),
          );
          canvas.drawCircle(
            cell.center,
            tileSize * 0.42,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = const Color(0xEEFFFFFF),
          );
          _drawSprite(canvas, sprite, cell.deflate(tileSize / 5), paint);
          _drawTroopClassGlyph(canvas, cell, troopOwner, x, y);
        }
      }
    }
    _drawShips(canvas, paint);
    _drawSpiedTroops(canvas, paint);
    _drawRealmLabels(canvas);
    // Release the previous rasterization's native memory right away —
    // _rebuild runs on every state notification.
    _picture?.dispose();
    _picture = recorder.endRecording();
  }

  /// Class letters (e.g. I/K/A, localized) on a troop badge's lower edge — the Gattung is
  /// battlefield-observable (user rule 2026-07-19: the Schere-Stein-Papier
  /// counters need visible classes to play against). Drawn for every army
  /// whose unit list the visible state carries: the viewer's own troops
  /// and, at war, the enemy's ([gc.visibleStateFor] keeps both sides'
  /// lists). Distinct classes of a stack are joined ("IK"); men and
  /// quality stay hidden as before.
  void _drawTroopClassGlyph(
    Canvas canvas,
    Rect cell,
    int troopOwner,
    int x,
    int y,
  ) {
    final classes = <int>{
      for (final t in _state.realm(troopOwner).troops)
        if (t.x == x && t.y == y) t.troopClass,
    };
    if (classes.isEmpty) return;
    final text = [
      for (final c in classes.toList()..sort()) troopClassInitial(c),
    ].join();
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: tileSize * 0.3,
          fontWeight: FontWeight.w800,
          shadows: [
            Shadow(blurRadius: 3, color: Color(0xDD000000)),
            Shadow(blurRadius: 1, color: Color(0xDD000000)),
          ],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        cell.center.dx - painter.width / 2,
        cell.bottom - painter.height + 2,
      ),
    );
  }

  /// Faded ghost badges for enemy units known from the newest military
  /// intel report per target (positions as of the spy year). The state is
  /// the seated player's visible copy, so only their own realm carries
  /// intel reports. Tiles with a live (visible) troop marker are skipped —
  /// real knowledge beats stale intel.
  void _drawSpiedTroops(Canvas canvas, Paint paint) {
    final map = _state.map;
    final ghostPaint = Paint()..color = const Color(0x77FFFFFF);
    for (final realm in _state.realms) {
      final newestByTarget = <int, gc.IntelReport>{};
      for (final report in realm.intelReports) {
        if (report.values.containsKey('unitCount')) {
          newestByTarget[report.targetSlot] = report; // list is in order
        }
      }
      for (final report in newestByTarget.values) {
        final units = report.values['unitCount'] ?? 0;
        for (var i = 0; i < units; i++) {
          final x = report.values['unit${i}X'];
          final y = report.values['unit${i}Y'];
          // Defensive: a report without positions is skipped.
          if (x == null || y == null || !map.inBounds(x, y)) continue;
          if (map.troopMarker[map.index(x, y)] != 0) continue;
          final cell = Rect.fromLTWH(
            x * tileSize,
            y * tileSize,
            tileSize,
            tileSize,
          );
          canvas.drawCircle(
            cell.center,
            tileSize * 0.42,
            Paint()
              ..color = RealmPalette.colorFor(
                report.targetSlot,
                state: _state,
              ).withValues(alpha: 0.35),
          );
          canvas.drawCircle(
            cell.center,
            tileSize * 0.42,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = const Color(0x88FFFFFF),
          );
          _drawSprite(
            canvas,
            _troopSprite,
            cell.deflate(tileSize / 5),
            ghostPaint,
          );
        }
      }
    }
  }

  /// Colony ships at sea. The state is the seated player's visible copy:
  /// foreign realms carry no ships (hidden information), so everything
  /// here may be drawn.
  void _drawShips(Canvas canvas, Paint paint) {
    for (final realm in _state.realms) {
      for (final ship in realm.ships) {
        final cell = Rect.fromLTWH(
          ship.x * tileSize,
          ship.y * tileSize,
          tileSize,
          tileSize,
        );
        canvas.drawCircle(
          cell.center,
          tileSize * 0.42,
          Paint()
            ..color = RealmPalette.colorFor(realm.slot, state: _state)
                .withValues(alpha: 0.8),
        );
        canvas.drawCircle(
          cell.center,
          tileSize * 0.42,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xEEFFFFFF),
        );
        _drawSprite(canvas, _shipSprite, cell.deflate(tileSize / 6), paint);
      }
    }
  }

  /// Small country-name caption per realm: under the capital flag while
  /// the realm still owns that tile, otherwise on the owned tile nearest
  /// its territory's centroid. Realms without any land get no label — a
  /// conquered (or overrun) realm must not haunt the map at its old seat.
  void _drawRealmLabels(Canvas canvas) {
    final map = _state.map;
    final owned = <int, List<(int, int)>>{};
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        final owner = map.ownerAt(x, y);
        if (owner != gc.World.niemand) {
          owned.putIfAbsent(owner, () => []).add((x, y));
        }
      }
    }
    for (final realm in _state.realms) {
      if (realm.isVacant) continue;
      final tiles = owned[realm.slot];
      if (tiles == null || tiles.isEmpty) continue;
      int labelX;
      int labelY;
      if (map.ownerAt(realm.capitalX, realm.capitalY) == realm.slot) {
        labelX = realm.capitalX;
        labelY = realm.capitalY;
      } else {
        var cx = 0.0;
        var cy = 0.0;
        for (final (x, y) in tiles) {
          cx += x;
          cy += y;
        }
        cx /= tiles.length;
        cy /= tiles.length;
        var best = tiles.first;
        var bestDist = double.infinity;
        for (final (x, y) in tiles) {
          final dist = (x - cx) * (x - cx) + (y - cy) * (y - cy);
          if (dist < bestDist) {
            bestDist = dist;
            best = (x, y);
          }
        }
        (labelX, labelY) = best;
      }
      final painter = TextPainter(
        text: TextSpan(
          text: realmName(realm.slot),
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: tileSize * 0.38,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(blurRadius: 3, color: Color(0xDD000000)),
              Shadow(blurRadius: 1, color: Color(0xDD000000)),
            ],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (labelX + 0.5) * tileSize - painter.width / 2,
          (labelY + 1) * tileSize + 1,
        ),
      );
    }
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
  void onScaleEnd(ScaleEndInfo info) {
    if (_boxDragging) {
      _boxDragging = false;
      onBoxDragEnd?.call();
    }
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    // Box select: while an anchor is set, a one-finger drag moves the box
    // corner under the finger instead of panning. Two-finger gestures
    // still zoom/pan below so the player can navigate meanwhile.
    if (boxAnchor != null && info.pointerCount < 2) {
      _boxDragging = true;
      _dragBoxAt(info.eventPosition.widget);
      return;
    }
    if (info.pointerCount >= 2) {
      // raw.scale is direction-independent (pointer distance), unlike
      // scale.global.y which ignores horizontal pinches (e.g. two thumbs).
      camera.viewfinder.zoom = (_startZoom * info.raw.scale).clamp(0.35, 6.0);
    }
    final delta = info.delta.global;
    camera.viewfinder.position -=
        Vector2(delta.x, delta.y) / camera.viewfinder.zoom;
    _clampCamera();
  }

  /// Reports the map tile under a screen point (widget-relative) to
  /// [onBoxDrag] during a box drag. Mirrors `_MapLayer.onTapUp`:
  /// `camera.globalToLocal` maps the widget point into world space, then a
  /// floor by [tileSize] gives the tile — clamped to the map so dragging
  /// past the edge sizes the box up to the border instead of freezing it.
  void _dragBoxAt(Vector2 widgetPoint) {
    final world = camera.globalToLocal(widgetPoint);
    final map = _state.map;
    final x = (world.x / tileSize).floor().clamp(0, map.width - 1);
    final y = (world.y / tileSize).floor().clamp(0, map.height - 1);
    onBoxDrag?.call(x, y);
  }

  /// Keeps the visible area inside the map: the camera center may not get
  /// closer to an edge than half the viewport (in world units). When the
  /// whole map fits on one axis, that axis is centered instead.
  void _clampCamera() {
    final zoom = camera.viewfinder.zoom;
    final halfW = size.x / (2 * zoom);
    final halfH = size.y / (2 * zoom);
    final mapW = _state.map.width * tileSize;
    final mapH = _state.map.height * tileSize;
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
        size: Vector2(
          game._state.map.width * tileSize,
          game._state.map.height * tileSize,
        ),
      );

  final MapGame game;

  /// Clock for the pulsing selection ring.
  double _time = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    final picture = game._picture;
    if (picture != null) canvas.drawPicture(picture);
    _renderDragSelection(canvas);
    _renderSelection(canvas);
  }

  /// Box-selection overlay: a translucent fill on every selected tile
  /// (the eligible ones inside the box) plus a dashed frame around the
  /// whole dragged box. Drawn per-frame (not baked into the picture) so
  /// the selection tracks the finger live.
  void _renderDragSelection(Canvas canvas) {
    final base = Color(game.dragSelectColor);
    if (game.dragSelection.isNotEmpty) {
      final width = game._state.map.width;
      final fill = Paint()..color = base.withValues(alpha: 0.33);
      for (final idx in game.dragSelection) {
        final x = idx % width;
        final y = idx ~/ width;
        canvas.drawRect(
          Rect.fromLTWH(x * tileSize, y * tileSize, tileSize, tileSize),
          fill,
        );
      }
    }
    final anchor = game.boxAnchor;
    if (anchor == null) return;
    final corner = game.boxCorner ?? anchor;
    final left = math.min(anchor.$1, corner.$1) * tileSize;
    final top = math.min(anchor.$2, corner.$2) * tileSize;
    final right = (math.max(anchor.$1, corner.$1) + 1) * tileSize;
    final bottom = (math.max(anchor.$2, corner.$2) + 1) * tileSize;
    final frame = Rect.fromLTRB(left, top, right, bottom).deflate(1);
    // White dashes over a wider dark underlay: readable on green land,
    // bright water and shoreline alike (the mode color alone drowned in
    // same-hued terrain — the green frame was invisible on grass).
    _drawDashedRect(
      canvas,
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xB3000000),
    );
    _drawDashedRect(
      canvas,
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );
  }

  /// Dashed rectangle outline (Canvas has no dash support of its own).
  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    void line(Offset from, Offset to) {
      final total = (to - from).distance;
      if (total == 0) return;
      final dir = (to - from) / total;
      var at = 0.0;
      while (at < total) {
        final end = math.min(at + dash, total);
        canvas.drawLine(from + dir * at, from + dir * end, paint);
        at = end + gap;
      }
    }

    line(rect.topLeft, rect.topRight);
    line(rect.topRight, rect.bottomRight);
    line(rect.bottomRight, rect.bottomLeft);
    line(rect.bottomLeft, rect.topLeft);
  }

  /// Pulsing ring around the selected war unit.
  void _renderSelection(Canvas canvas) {
    final selected = game.selectedTile;
    if (selected == null) return;
    final (x, y) = selected;
    final pulse = 0.5 + 0.5 * math.sin(_time * 5);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        x * tileSize,
        y * tileSize,
        tileSize,
        tileSize,
      ).inflate(2 + pulse * 2),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFFFEB3B).withValues(alpha: 0.6 + 0.4 * pulse),
    );
  }

  /// True after a long-press anchored a selection box: the tap-up of that
  /// same press must not also fire [MapGame.onTileTap] (which would open a
  /// tile sheet over the fresh selection).
  bool _swallowTap = false;

  @override
  void onLongTapDown(TapDownEvent event) {
    final x = (event.localPosition.x / tileSize).floor();
    final y = (event.localPosition.y / tileSize).floor();
    final map = game._state.map;
    if (x >= 0 && x < map.width && y >= 0 && y < map.height) {
      _swallowTap = game.onLongPressTile?.call(x, y) ?? false;
    }
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _swallowTap = false;
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (_swallowTap) {
      _swallowTap = false;
      // Lift right after the anchoring long-press (no drag): the box
      // gesture is complete — a single-tile box.
      game.onBoxDragEnd?.call();
      return;
    }
    final x = (event.localPosition.x / tileSize).floor();
    final y = (event.localPosition.y / tileSize).floor();
    final map = game._state.map;
    if (x >= 0 && x < map.width && y >= 0 && y < map.height) {
      game.onTileTap?.call(x, y);
    }
  }
}
