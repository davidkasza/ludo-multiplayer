import 'package:flutter/material.dart';

class DicePainter extends CustomPainter {
  final int value;
  final Color pipColor;
  final Color pipShadowColor;
  final Color pipHighlightColor;

  const DicePainter(
    this.value, {
    this.pipColor = const Color(0xff111827),
    this.pipShadowColor = const Color(0x33000000),
    this.pipHighlightColor = const Color(0x2effffff),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()
      ..color = pipShadowColor
      ..style = PaintingStyle.fill;
    final pipPaint = Paint()
      ..color = pipColor
      ..style = PaintingStyle.fill;
    final highlightPaint = Paint()
      ..color = pipHighlightColor
      ..style = PaintingStyle.fill;

    final r = size.width * 0.095;
    final p1 = size.width * 0.27;
    final p2 = size.width * 0.5;
    final p3 = size.width * 0.73;

    void drawDot(double x, double y) {
      canvas.drawCircle(
        Offset(x + size.width * 0.018, y + size.width * 0.024),
        r,
        shadowPaint,
      );
      canvas.drawCircle(Offset(x, y), r, pipPaint);
      canvas.drawCircle(
        Offset(x - r * 0.28, y - r * 0.30),
        r * 0.28,
        highlightPaint,
      );
    }

    if (value.isOdd) drawDot(p2, p2);

    if (value > 1) {
      drawDot(p1, p1);
      drawDot(p3, p3);
    }

    if (value > 3) {
      drawDot(p1, p3);
      drawDot(p3, p1);
    }

    if (value == 6) {
      drawDot(p1, p2);
      drawDot(p3, p2);
    }
  }

  @override
  bool shouldRepaint(covariant DicePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.pipColor != pipColor ||
        oldDelegate.pipShadowColor != pipShadowColor ||
        oldDelegate.pipHighlightColor != pipHighlightColor;
  }
}
