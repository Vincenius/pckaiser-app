import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;

/// Visual identity per realm slot (1–30): a color plus a pattern index —
/// color is never the only channel (PROJECT_REQUIREMENTS accessibility).
class RealmPalette {
  /// 30 well-separated colors that read clearly on the green terrain:
  /// hues run 170°–430° (mod 360) — blues, purples, reds, oranges,
  /// yellows — deliberately skipping the 70°–170° green band. A coprime
  /// stride spreads consecutive slots far apart on the wheel, and
  /// alternating lightness doubles the effective separation.
  static Color colorFor(int slot) {
    final hue = (170.0 + ((slot * 11) % 30) / 30.0 * 260.0) % 360.0;
    final lightness = slot.isEven ? 0.58 : 0.44;
    return HSLColor.fromAHSL(1.0, hue, 0.85, lightness).toColor();
  }

  /// Marks a realm's capital: a flag pole with a pennant in the realm
  /// color (no suitable sprite exists in the original tile set).
  static void paintCapital(Canvas canvas, Rect cell, int slot) {
    final s = cell.width;
    final pole = Paint()
      ..color = const Color(0xFF222222)
      ..strokeWidth = s / 12;
    canvas.drawLine(
      Offset(cell.left + s * 0.35, cell.top + s * 0.15),
      Offset(cell.left + s * 0.35, cell.top + s * 0.85),
      pole,
    );
    final pennant = Path()
      ..moveTo(cell.left + s * 0.38, cell.top + s * 0.15)
      ..lineTo(cell.left + s * 0.85, cell.top + s * 0.28)
      ..lineTo(cell.left + s * 0.38, cell.top + s * 0.45)
      ..close();
    canvas.drawPath(pennant, Paint()..color = colorFor(slot));
    canvas.drawPath(
      pennant,
      Paint()
        ..color = const Color(0xFF222222)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s / 24,
    );
  }

  /// Paints the ownership overlay for one tile cell: a subtle tint that
  /// keeps the terrain art readable, plus solid country-border strokes
  /// along every edge whose neighbor belongs to someone else. Together
  /// with the country-name captions, the borders keep color from being
  /// the only ownership channel (accessibility).
  static void paintOwnership(
    Canvas canvas,
    Rect cell,
    int slot, {
    required bool left,
    required bool top,
    required bool right,
    required bool bottom,
  }) {
    final color = colorFor(slot);
    canvas.drawRect(cell, Paint()..color = color.withValues(alpha: 0.16));

    if (!(left || top || right || bottom)) return;
    final border = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..strokeWidth = cell.width / 8
      ..strokeCap = StrokeCap.square;
    // Inset by half the stroke width so the line stays inside the tile
    // and meets the neighbor's stroke into one continuous border.
    final inner = cell.deflate(cell.width / 16);
    if (left) canvas.drawLine(inner.topLeft, inner.bottomLeft, border);
    if (top) canvas.drawLine(inner.topLeft, inner.topRight, border);
    if (right) canvas.drawLine(inner.topRight, inner.bottomRight, border);
    if (bottom) {
      canvas.drawLine(inner.bottomLeft, inner.bottomRight, border);
    }
  }
}
