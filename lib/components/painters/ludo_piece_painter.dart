import 'package:flutter/material.dart';

class LudoPiecePainter {
  const LudoPiecePainter._();

  static void draw({
    required Canvas canvas,
    required Offset center,
    required Color bright,
    required Color dark,
    required double cellSize,
    required bool isAtGoal,
    required double scale,
  }) {
    final double scaledCell = cellSize * scale;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          center.dx,
          center.dy + scaledCell * 0.34,
        ),
        width: scaledCell * 0.68,
        height: scaledCell * 0.20,
      ),
      Paint()..color = Colors.black.withOpacity(0.30),
    );

    if (isAtGoal) {
      canvas.drawCircle(
        center,
        scaledCell * 0.48,
        Paint()
          ..color = Colors.white.withOpacity(0.18)
          ..style = PaintingStyle.fill,
      );
    }

    final Rect bodyRect = Rect.fromCenter(
      center: Offset(
        center.dx,
        center.dy + scaledCell * 0.08,
      ),
      width: scaledCell * 0.78,
      height: scaledCell * 0.86,
    );

    final Paint bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          bright,
          dark,
        ],
      ).createShader(bodyRect);

    final Path bodyPath = Path()
      ..moveTo(
        center.dx,
        center.dy - scaledCell * 0.34,
      )
      ..cubicTo(
        center.dx - scaledCell * 0.34,
        center.dy - scaledCell * 0.18,
        center.dx - scaledCell * 0.36,
        center.dy + scaledCell * 0.28,
        center.dx,
        center.dy + scaledCell * 0.42,
      )
      ..cubicTo(
        center.dx + scaledCell * 0.36,
        center.dy + scaledCell * 0.28,
        center.dx + scaledCell * 0.34,
        center.dy - scaledCell * 0.18,
        center.dx,
        center.dy - scaledCell * 0.34,
      )
      ..close();

    canvas.drawPath(bodyPath, bodyPaint);

    canvas.drawCircle(
      Offset(
        center.dx,
        center.dy - scaledCell * 0.25,
      ),
      scaledCell * 0.22,
      bodyPaint,
    );

    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = Colors.white.withOpacity(0.62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    canvas.drawCircle(
      Offset(
        center.dx,
        center.dy - scaledCell * 0.25,
      ),
      scaledCell * 0.22,
      Paint()
        ..color = Colors.white.withOpacity(0.62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    canvas.drawCircle(
      Offset(
        center.dx - scaledCell * 0.09,
        center.dy - scaledCell * 0.32,
      ),
      scaledCell * 0.055,
      Paint()..color = Colors.white.withOpacity(0.55),
    );
  }
}