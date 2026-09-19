import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/ludo_animation.dart';
import '../../game/dice_skin.dart';
import 'dice_painter.dart';

class RollingDiceUI extends StatefulWidget {
  final int value;
  final bool isRolling;
  final String? animationKey;
  final double initialProgress;
  final Duration rollDuration;
  final double size;
  final DiceSkinDefinition skin;

  const RollingDiceUI({
    super.key,
    required this.value,
    required this.isRolling,
    required this.animationKey,
    required this.initialProgress,
    required this.rollDuration,
    this.size = 38.0,
    this.skin = DiceSkinResolver.classic,
  });

  @override
  State<RollingDiceUI> createState() => _RollingDiceUIState();
}

class _RollingDiceUIState extends State<RollingDiceUI>
    with TickerProviderStateMixin {
  late final AnimationController _animController;
  late final AnimationController _specialController;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: widget.rollDuration,
    );
    _specialController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    if (widget.isRolling) _startRoll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion && !_reduceMotion) {
      _specialController
        ..stop()
        ..value = 0;
    }
    _reduceMotion = reduceMotion;
  }

  @override
  void didUpdateWidget(covariant RollingDiceUI oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isRolling &&
        (!oldWidget.isRolling ||
            oldWidget.animationKey != widget.animationKey)) {
      _startRoll();
    } else if (!widget.isRolling && oldWidget.isRolling) {
      _animController.stop();
      _animController.value = 0.0;
      _startSpecialFeedback();
    }
  }

  void _startRoll() {
    _specialController
      ..stop()
      ..value = 0;
    _animController
      ..stop()
      ..duration = widget.rollDuration
      ..value = widget.initialProgress.clamp(0.0, 1.0);
    if (_animController.value < 1) {
      _animController.forward();
    }
  }

  void _startSpecialFeedback() {
    if (_reduceMotion || widget.value != 6 || widget.animationKey == null) {
      return;
    }
    _specialController.forward(from: 0);
  }

  @override
  void dispose() {
    _animController.dispose();
    _specialController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_animController, _specialController]),
      builder: (context, child) {
        final result = widget.value >= 1 && widget.value <= 6
            ? widget.value
            : 6;
        final motion = widget.isRolling
            ? LudoAnimation.diceFrame(_animController.value, result)
            : LudoAnimation.diceFrame(1, result);
        final jumpY = -motion.lift * widget.size * 0.78;
        final specialProgress = _specialController.value;
        final specialPulse = sin(specialProgress * pi);

        return SizedBox.square(
          dimension: widget.size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: Offset(
                  motion.horizontalDrift * widget.size,
                  widget.size * 0.43,
                ),
                child: Transform.scale(
                  scaleX: motion.shadowScale,
                  scaleY: 0.42,
                  child: Container(
                    width: widget.size * 0.78,
                    height: widget.size * 0.22,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(motion.shadowOpacity),
                      borderRadius: BorderRadius.circular(widget.size),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(
                            motion.shadowOpacity * 0.55,
                          ),
                          blurRadius: widget.size * 0.16,
                          spreadRadius: widget.size * 0.025,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!_reduceMotion && _specialController.isAnimating)
                CustomPaint(
                  size: Size.square(widget.size * 1.72),
                  painter: _DiceSpecialPainter(
                    progress: specialProgress,
                    pulse: specialPulse,
                    color: widget.skin.border,
                  ),
                ),
              Transform.translate(
                offset: Offset(motion.horizontalDrift * widget.size, jumpY),
                child: Transform.scale(
                  scale: motion.scale * (1 + specialPulse * 0.08),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0035)
                      ..rotateX(motion.rotationX)
                      ..rotateY(motion.rotationY)
                      ..rotateZ(motion.rotationZ),
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [widget.skin.faceStart, widget.skin.faceEnd],
                        ),
                        borderRadius: BorderRadius.circular(widget.size * 0.18),
                        border: Border.all(
                          color: widget.skin.border.withOpacity(0.78),
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.24),
                            blurRadius: widget.size * 0.10,
                            offset: Offset(0, widget.size * 0.06),
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        painter: DicePainter(
                          motion.face,
                          pipColor: widget.skin.pip,
                          pipShadowColor: widget.skin.pipShadow,
                          pipHighlightColor: widget.skin.pipHighlight,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DiceSpecialPainter extends CustomPainter {
  final double progress;
  final double pulse;
  final Color color;

  const _DiceSpecialPainter({
    required this.progress,
    required this.pulse,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final opacity = (1 - progress).clamp(0.0, 1.0);
    final radius = size.shortestSide * (0.25 + progress * 0.22);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withOpacity(opacity * 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.035,
    );

    for (int index = 0; index < 6; index++) {
      final angle = index * pi / 3;
      final distance = size.shortestSide * (0.28 + progress * 0.20);
      canvas.drawCircle(
        center + Offset(cos(angle), sin(angle)) * distance,
        size.shortestSide * (0.025 + pulse * 0.012),
        Paint()..color = color.withOpacity(opacity * 0.86),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DiceSpecialPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulse != pulse ||
        oldDelegate.color != color;
  }
}
