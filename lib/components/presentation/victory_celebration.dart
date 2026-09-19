import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/ludo_presentation.dart';

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
      duration: const Duration(
        milliseconds: LudoPresentation.victoryFireworksDurationMs,
      ),
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
          (_controller.value / 0.11).clamp(0.0, 1.0),
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
                    painter: _VictoryFireworksPainter(
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

class _VictoryFireworksPainter extends CustomPainter {
  final double progress;
  final Color winnerColor;

  const _VictoryFireworksPainter({
    required this.progress,
    required this.winnerColor,
  });

  static const List<_FireworkBurst> _bursts = [
    _FireworkBurst(0.20, 0.23, 0.00, 0.22, 0.82, 0, 14),
    _FireworkBurst(0.78, 0.19, 0.11, 0.22, 1.00, 1, 16),
    _FireworkBurst(0.49, 0.34, 0.25, 0.20, 0.90, 2, 14),
    _FireworkBurst(0.16, 0.54, 0.38, 0.22, 0.74, 3, 12),
    _FireworkBurst(0.83, 0.49, 0.51, 0.22, 0.88, 0, 14),
    _FireworkBurst(0.36, 0.17, 0.64, 0.21, 0.76, 1, 12),
    _FireworkBurst(0.67, 0.63, 0.78, 0.22, 0.92, 2, 16),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final shortestSide = size.shortestSide;
    final winnerLight = Color.lerp(winnerColor, Colors.white, 0.42)!;
    final winnerWarm = Color.lerp(winnerColor, const Color(0xffffd166), 0.34)!;
    final sparkPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final sparkFillPaint = Paint()..style = PaintingStyle.fill;

    for (int burstIndex = 0; burstIndex < _bursts.length; burstIndex++) {
      final burst = _bursts[burstIndex];
      final rawProgress = (progress - burst.delay) / burst.duration;
      if (rawProgress <= 0 || rawProgress >= 1) continue;

      final local = rawProgress.clamp(0.0, 1.0);
      final expansion = Curves.easeOutCubic.transform(local);
      final ignition = (local / 0.06).clamp(0.0, 1.0);
      final opacity = ignition * pow(1 - local, 1.25).toDouble();
      final center = Offset(size.width * burst.x, size.height * burst.y);
      final baseRadius = shortestSide * 0.17 * burst.scale;

      if (local < 0.24) {
        final ringProgress = local / 0.24;
        canvas.drawCircle(
          center,
          baseRadius * 0.24 * ringProgress,
          Paint()
            ..color = winnerLight.withOpacity((1 - ringProgress) * 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }

      for (int spark = 0; spark < burst.sparkCount; spark++) {
        final angle = (spark * 2 * pi / burst.sparkCount) + burstIndex * 0.37;
        final direction = Offset(cos(angle), sin(angle));
        final speedVariation =
            0.82 + ((spark * 17 + burstIndex * 11) % 7) * 0.05;
        final distance = baseRadius * expansion * speedVariation;
        final gravity = shortestSide * 0.038 * local * local;
        final point =
            center +
            direction * distance +
            Offset(0, gravity * (0.75 + speedVariation * 0.25));
        final trailLength = shortestSide * 0.026 * (1 - local);
        final color = switch ((spark + burst.colorOffset) % 4) {
          0 => winnerColor,
          1 => winnerLight,
          2 => winnerWarm,
          _ => Colors.white,
        };

        sparkPaint
          ..color = color.withOpacity(opacity.clamp(0.0, 1.0))
          ..strokeWidth = 1.1 + (spark % 3) * 0.35;
        sparkFillPaint.color = color.withOpacity(opacity.clamp(0.0, 1.0));
        canvas.drawLine(point - direction * trailLength, point, sparkPaint);
        canvas.drawCircle(point, 1.1 + (spark % 2) * 0.55, sparkFillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VictoryFireworksPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.winnerColor != winnerColor;
  }
}

class _FireworkBurst {
  final double x;
  final double y;
  final double delay;
  final double duration;
  final double scale;
  final int colorOffset;
  final int sparkCount;

  const _FireworkBurst(
    this.x,
    this.y,
    this.delay,
    this.duration,
    this.scale,
    this.colorOffset,
    this.sparkCount,
  );
}
