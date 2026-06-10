import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;

/// Visual identity per realm slot (1–30): a color plus a pattern index —
/// color is never the only channel (PROJECT_REQUIREMENTS accessibility).
class RealmPalette {
  /// Golden-angle hue spread gives 30 well-separated colors.
  static Color colorFor(int slot) {
    final hue = (slot * 137.508) % 360.0;
    return HSLColor.fromAHSL(1.0, hue, 0.65, 0.45).toColor();
  }

  /// Pattern overlay kind (0–3): stripes ╱, stripes ╲, dots, crosshatch.
  /// Neighboring slots rarely share both hue and pattern.
  static int patternFor(int slot) => slot % 4;

  /// Paints the ownership overlay for one tile cell: translucent tint plus
  /// the pattern in a darker shade.
  static void paintOwnership(Canvas canvas, Rect cell, int slot) {
    final color = colorFor(slot);
    canvas.drawRect(cell, Paint()..color = color.withValues(alpha: 0.30));

    final pattern = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = cell.width / 16
      ..style = PaintingStyle.stroke;
    final s = cell.width;
    switch (patternFor(slot)) {
      case 0: // ╱ stripes
        for (var i = 1; i < 3; i++) {
          canvas.drawLine(
            Offset(cell.left, cell.top + s * i / 3 + s / 6),
            Offset(cell.left + s * i / 3 + s / 6, cell.top),
            pattern,
          );
        }
      case 1: // ╲ stripes
        for (var i = 1; i < 3; i++) {
          canvas.drawLine(
            Offset(cell.right, cell.top + s * i / 3 + s / 6),
            Offset(cell.right - s * i / 3 - s / 6, cell.top),
            pattern,
          );
        }
      case 2: // dots
        final dot = Paint()..color = pattern.color;
        for (final dx in [0.3, 0.7]) {
          for (final dy in [0.3, 0.7]) {
            canvas.drawCircle(
                Offset(cell.left + s * dx, cell.top + s * dy), s / 14, dot);
          }
        }
      case 3: // crosshatch corner ticks
        canvas.drawLine(Offset(cell.left + s * 0.2, cell.top + s * 0.5),
            Offset(cell.left + s * 0.8, cell.top + s * 0.5), pattern);
        canvas.drawLine(Offset(cell.left + s * 0.5, cell.top + s * 0.2),
            Offset(cell.left + s * 0.5, cell.top + s * 0.8), pattern);
    }
  }
}
