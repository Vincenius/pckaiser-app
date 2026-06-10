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

  /// Pattern overlay kind (0–3): stripes ╱, stripes ╲, dots, crosshatch.
  /// Neighboring slots rarely share both hue and pattern.
  static int patternFor(int slot) => slot % 4;

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

  /// Paints the ownership overlay for one tile cell: translucent tint plus
  /// the pattern in a darker shade.
  static void paintOwnership(Canvas canvas, Rect cell, int slot) {
    final color = colorFor(slot);
    canvas.drawRect(cell, Paint()..color = color.withValues(alpha: 0.45));

    final pattern = Paint()
      ..color = color.withValues(alpha: 0.95)
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
