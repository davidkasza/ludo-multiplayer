import 'dart:math';

import 'package:flutter/material.dart';

import 'dice_painter.dart';

class RollingDiceUI extends StatefulWidget {
  final int value;
  final bool isRolling;
  final double size;

  const RollingDiceUI({
    super.key,
    required this.value,
    required this.isRolling,
    this.size = 38.0,
  });

  @override
  State<RollingDiceUI> createState() => _RollingDiceUIState();
}

class _RollingDiceUIState extends State<RollingDiceUI>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  final Random _random = Random();

  int _randomFace = 6;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() {
      if (widget.isRolling && _random.nextDouble() > 0.7) {
        setState(() {
          _randomFace = _random.nextInt(6) + 1;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant RollingDiceUI oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isRolling && !oldWidget.isRolling) {
      _animController.repeat();
    } else if (!widget.isRolling && oldWidget.isRolling) {
      _animController.stop();
      _animController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = widget.isRolling
        ? _randomFace
        : widget.value == 0
        ? 6
        : widget.value;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final animValue = widget.isRolling ? _animController.value : 0.0;
        final angleX = widget.isRolling ? animValue * pi * 4 : 0.0;
        final angleY = widget.isRolling ? animValue * pi * 2 : 0.0;
        final angleZ = widget.isRolling ? animValue * pi * 2 : 0.0;
        final elevation = widget.isRolling ? sin(animValue * pi) : 0.0;
        final jumpY = -elevation * 35.0;

        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.003)
            ..translate(0.0, jumpY, 0.0)
            ..rotateX(angleX)
            ..rotateY(angleY)
            ..rotateZ(angleZ),
          alignment: Alignment.center,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(widget.size * 0.15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 6.0 + elevation * 8,
                  offset: Offset(0, 4.0 + elevation * 12),
                ),
              ],
            ),
            child: CustomPaint(
              painter: DicePainter(displayValue),
            ),
          ),
        );
      },
    );
  }
}