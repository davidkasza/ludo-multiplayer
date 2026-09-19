import 'dart:math';

import 'package:flutter/material.dart';

/// A short, presentation-only celebration around an already finished match.
class VictoryCelebration extends StatefulWidget {
  final bool enabled;
  final Color winnerColor;
  final Widget child;

  const VictoryCelebration({
    super.key,
    required this.enabled,
    required this.winnerColor,
    required this.child,
  });

  @override
  State<VictoryCelebration> createState() => _VictoryCelebrationState();
}

class _VictoryCelebrationState extends State<VictoryCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion && !_reduceMotion) {
      _controller
        ..stop()
        ..value = 0;
      if (widget.enabled) _started = true;
    }
    _reduceMotion = reduceMotion;
    _startIfNeeded();
  }

  @override
  void didUpdateWidget(covariant VictoryCelebration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _controller
        ..stop()
        ..value = 0;
      _started = false;
    } else if (!oldWidget.enabled) {
      _started = false;
      _startIfNeeded();
    }
  }

  void _startIfNeeded() {
    if (_started || !widget.enabled) return;
    if (_reduceMotion) {
      _controller
        ..stop()
        ..value = 0;
      _started = true;
      return;
    }
    _started = true;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _reduceMotion) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final entrance = Curves.easeOutCubic.transform(
          (_controller.value / 0.38).clamp(0.0, 1.0),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: entrance,
              child: Transform.scale(
                scale: 0.97 + entrance * 0.03,
                child: child,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _VictoryParticlePainter(
                      progress: _controller.value,
                      winnerColor: widget.winnerColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VictoryParticlePainter extends CustomPainter {
  final double progress;
  final Color winnerColor;

  const _VictoryParticlePainter({
    required this.progress,
    required this.winnerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final glowOpacity = (1 - progress).clamp(0.0, 1.0) * 0.18;
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide * (0.20 + progress * 0.50),
      Paint()..color = winnerColor.withOpacity(glowOpacity),
    );

    const particleCount = 24;
    for (int index = 0; index < particleCount; index++) {
      final delay = (index % 6) * 0.035;
      final local = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final lane = ((index * 37) % 101) / 100;
      final sway = sin(local * pi * 2 + index) * size.width * 0.025;
      final x = lane * size.width + sway;
      final y = -18 + Curves.easeIn.transform(local) * (size.height + 36);
      final opacity = local > 0.82 ? (1 - local) / 0.18 : 0.88;
      final color = switch (index % 3) {
        0 => winnerColor,
        1 => const Color(0xffffd166),
        _ => Colors.white,
      };

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(local * pi * (1.5 + (index % 4) * 0.35));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: 5 + (index % 3) * 1.5,
            height: 10 + (index % 2) * 3,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = color.withOpacity(opacity.clamp(0.0, 1.0)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _VictoryParticlePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.winnerColor != winnerColor;
  }
}
