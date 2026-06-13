import 'package:flutter/material.dart';

class SelectableGlowPainter {
  const SelectableGlowPainter._();

  static void draw({
    required Canvas canvas,
    required Offset center,
    required Color color,
    required double cellSize,
  }) {
    canvas.drawCircle(
      center,
      cellSize * 0.48,
      Paint()
        ..color = color.withOpacity(0.20)
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(
      center,
      cellSize * 0.48,
      Paint()
        ..color = color.withOpacity(0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}