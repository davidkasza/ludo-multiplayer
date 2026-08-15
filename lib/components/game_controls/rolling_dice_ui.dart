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
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: widget.rollDuration,
    );
    if (widget.isRolling) _startRoll();
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
    }
  }

  void _startRoll() {
    _animController
      ..stop()
      ..duration = widget.rollDuration
      ..value = widget.initialProgress.clamp(0.0, 1.0);
    if (_animController.value < 1) {
      _animController.forward();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final result = widget.value >= 1 && widget.value <= 6
            ? widget.value
            : 6;
        final motion = widget.isRolling
            ? LudoAnimation.diceFrame(_animController.value, result)
            : LudoAnimation.diceFrame(1, result);
        final jumpY = -motion.lift * widget.size * 0.78;

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
              Transform.translate(
                offset: Offset(motion.horizontalDrift * widget.size, jumpY),
                child: Transform.scale(
                  scale: motion.scale,
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
