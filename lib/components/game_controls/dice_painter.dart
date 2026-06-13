import 'package:flutter/material.dart';

class DicePainter extends CustomPainter {
  final int value;

  const DicePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;

    final r = size.width * 0.11;
    final p1 = size.width * 0.25;
    final p2 = size.width * 0.5;
    final p3 = size.width * 0.75;

    void drawDot(double x, double y) {
      canvas.drawCircle(Offset(x, y), r, paint);
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
    return oldDelegate.value != value;
  }
}