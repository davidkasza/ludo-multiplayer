import 'package:flutter/material.dart';

class SelectableGlowPainter {
  const SelectableGlowPainter._();

  static void draw({
    required Canvas canvas,
    required Offset center,
    required Color color,
    required double cellSize,
    double pulse = 0,
  }) {
    final radius = cellSize * (0.53 + pulse * 0.055);
    final opacityBoost = 0.78 + pulse * 0.22;

    // A neutral blurred edge keeps the selection indicator visible on both
    // white track cells and player-coloured start/Home-lane cells.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black.withOpacity(0.26 + pulse * 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.12
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.08),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withOpacity(0.76 * opacityBoost)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.075,
    );

    canvas.drawCircle(
      center,
      radius - cellSize * 0.055,
      Paint()
        ..color = color.withOpacity(0.82 * opacityBoost)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.055,
    );
  }
}
