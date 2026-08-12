import 'dart:math' as math;

import '../models/ludo_models.dart';
import 'ludo_rules.dart';

/// Pure local animation math. Nothing here changes or delays authoritative
/// game state; it only interprets already-committed action descriptors.
class LudoAnimation {
  const LudoAnimation._();

  static PieceMotionFrame pieceFrame(ActiveMove move, int elapsedMs) {
    if (move.steps.isEmpty) {
      const fallback = ActiveMoveStep(pos: -1, inHome: false);
      return const PieceMotionFrame(
        from: fallback,
        to: fallback,
        stepIndex: 0,
        progress: 1,
        easedProgress: 1,
        isBaseExit: false,
        isComplete: true,
      );
    }

    if (move.steps.length == 1 || move.stepDurationMs <= 0) {
      return PieceMotionFrame.completed(
        move.steps.last,
        stepIndex: move.steps.length - 1,
      );
    }

    final totalDuration = move.totalDurationMs;
    final elapsed = elapsedMs.clamp(0, totalDuration).toInt();
    if (elapsed >= totalDuration) {
      return PieceMotionFrame.completed(
        move.steps.last,
        stepIndex: move.steps.length - 1,
      );
    }

    final stepIndex = elapsed ~/ move.stepDurationMs;
    final stepElapsed = elapsed - stepIndex * move.stepDurationMs;
    final progress = (stepElapsed / move.stepDurationMs).clamp(0.0, 1.0);
    final easedProgress = _smoothStep(progress);
    final from = move.steps[stepIndex];
    final to = move.steps[stepIndex + 1];

    return PieceMotionFrame(
      from: from,
      to: to,
      stepIndex: stepIndex,
      progress: progress,
      easedProgress: easedProgress,
      isBaseExit:
          from.pos == LudoRules.basePosition &&
          !from.inHome &&
          to.pos == 0 &&
          !to.inHome,
      isComplete: false,
    );
  }

  static DiceMotionFrame diceFrame(double rawProgress, int result) {
    final progress = rawProgress.clamp(0.0, 1.0);
    final normalizedResult = result >= 1 && result <= 6 ? result : 6;
    const flightEnd = 0.78;

    final double lift;
    final double landingPulse;
    if (progress < flightEnd) {
      final flightProgress = progress / flightEnd;
      lift = math.sin(flightProgress * math.pi);
      landingPulse = 0;
    } else {
      final bounceProgress = (progress - flightEnd) / (1 - flightEnd);
      lift = math.sin(bounceProgress * math.pi) * 0.14;
      landingPulse = math.sin(bounceProgress * math.pi);
    }

    final rotationProgress = _smoothStep(progress);
    final horizontalDrift =
        math.sin(progress * math.pi * 2) * (1 - progress) * 0.10;

    return DiceMotionFrame(
      progress: progress,
      lift: lift,
      horizontalDrift: horizontalDrift,
      rotationX: rotationProgress * math.pi * 4,
      rotationY: rotationProgress * math.pi * 2,
      rotationZ: rotationProgress * math.pi * 2,
      scale: 1 + landingPulse * 0.055,
      shadowScale: 1 - lift * 0.34,
      shadowOpacity: 0.36 - lift * 0.16,
      face: _diceFaceForProgress(progress, normalizedResult),
    );
  }

  static double _smoothStep(double value) {
    return value * value * (3 - 2 * value);
  }

  static int _diceFaceForProgress(double progress, int result) {
    if (progress < 0.20) return _offsetFace(result, 2);
    if (progress < 0.42) return _offsetFace(result, 4);
    if (progress < 0.64) return _offsetFace(result, 1);
    if (progress < 0.80) return _offsetFace(result, 3);
    return result;
  }

  static int _offsetFace(int value, int offset) {
    return ((value - 1 + offset) % 6) + 1;
  }
}

class PieceMotionFrame {
  final ActiveMoveStep from;
  final ActiveMoveStep to;
  final int stepIndex;
  final double progress;
  final double easedProgress;
  final bool isBaseExit;
  final bool isComplete;

  const PieceMotionFrame({
    required this.from,
    required this.to,
    required this.stepIndex,
    required this.progress,
    required this.easedProgress,
    required this.isBaseExit,
    required this.isComplete,
  });

  factory PieceMotionFrame.completed(
    ActiveMoveStep step, {
    required int stepIndex,
  }) {
    return PieceMotionFrame(
      from: step,
      to: step,
      stepIndex: stepIndex,
      progress: 1,
      easedProgress: 1,
      isBaseExit: false,
      isComplete: true,
    );
  }

  double get hopProgress => isBaseExit || isComplete ? 0 : progress;
}

class DiceMotionFrame {
  final double progress;
  final double lift;
  final double horizontalDrift;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double scale;
  final double shadowScale;
  final double shadowOpacity;
  final int face;

  const DiceMotionFrame({
    required this.progress,
    required this.lift,
    required this.horizontalDrift,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.scale,
    required this.shadowScale,
    required this.shadowOpacity,
    required this.face,
  });
}
