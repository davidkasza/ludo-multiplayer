import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class CyberBackground extends StatelessWidget {
  final Widget child;
  const CyberBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: AppColors.background)),
        Positioned.fill(
          child: Container(decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(-0.6, -0.6), radius: 0.9, colors: [Color(0x261e88e5), Colors.transparent]),
          )),
        ),
        Positioned.fill(
          child: Container(decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(0.6, 0.6), radius: 0.9, colors: [Color(0x24e53935), Colors.transparent]),
          )),
        ),
        const Positioned.fill(
          child: CustomPaint(painter: _GameGridPainter()),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _GameGridPainter extends CustomPainter {
  const _GameGridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.015)..strokeWidth = 1.0..style = PaintingStyle.stroke;
    const double step = 60.0;
    for (double x = 0; x < size.width; x += step) canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    for (double y = 0; y < size.height; y += step) canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}