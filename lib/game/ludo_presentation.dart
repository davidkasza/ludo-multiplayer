import 'dart:math';

import '../models/ludo_models.dart';
import 'ludo_rules.dart';

/// Pure helpers for sequencing visual game presentation independently from
/// authoritative multiplayer state.
class LudoPresentation {
  const LudoPresentation._();

  /// Time the landed dice result remains visible after the rolling motion.
  static const int diceResultHoldMs = 650;

  /// Capture timings begin only after the attacker's normal movement path.
  static const int captureImpactMs = 180;
  static const int captureReturnMs = 520;

  /// A short success beat after a piece has visibly reached the final goal.
  static const int finishCelebrationMs = 520;

  static const int extraTurnFeedbackDurationMs = 1500;
  static const int victoryFireworksDurationMs = 4000;

  static DicePresentationFrame diceFrame({
    required int elapsedMs,
    required int rollDurationMs,
  }) {
    final elapsed = elapsedMs < 0 ? 0 : elapsedMs;
    final rollingDuration = rollDurationMs < 0 ? 0 : rollDurationMs;

    if (elapsed < rollingDuration) {
      return DicePresentationFrame(
        phase: DicePresentationPhase.rolling,
        remainingMs: rollingDuration - elapsed,
      );
    }

    final resultElapsed = elapsed - rollingDuration;
    if (resultElapsed < diceResultHoldMs) {
      return DicePresentationFrame(
        phase: DicePresentationPhase.result,
        remainingMs: diceResultHoldMs - resultElapsed,
      );
    }

    return const DicePresentationFrame(
      phase: DicePresentationPhase.complete,
      remainingMs: 0,
    );
  }

  static int movePresentationDurationMs(ActiveMove move) {
    var duration = move.totalDurationMs;
    if (move.capturedPieces.isNotEmpty) {
      duration += captureImpactMs + captureReturnMs;
    }
    if (moveReachesGoal(move)) duration += finishCelebrationMs;
    return duration;
  }

  static bool moveReachesGoal(ActiveMove move) {
    if (move.steps.length < 2) return false;
    final before = move.steps[move.steps.length - 2];
    final destination = move.steps.last;
    return destination.inHome &&
        destination.pos == LudoRules.goalPosition &&
        !(before.inHome && before.pos == LudoRules.goalPosition);
  }

  /// Infers the committed roll from the immutable visual path.
  ///
  /// A normal six contains six adjacent steps. Leaving Base is the one
  /// exception: it is represented by a single Base-to-start step, but the
  /// rules only permit that transition after a six.
  static bool moveWasRolledSix(ActiveMove move) {
    if (move.steps.length < 2) return false;
    final origin = move.steps.first;
    return (!origin.inHome && origin.pos == LudoRules.basePosition) ||
        move.steps.length - 1 == 6;
  }

  static int _finishPresentationStartMs(ActiveMove move) {
    return move.totalDurationMs +
        (move.capturedPieces.isEmpty ? 0 : captureImpactMs + captureReturnMs);
  }

  static FinishPresentationFrame finishFrame({
    required ActiveMove move,
    required int elapsedMs,
  }) {
    if (!moveReachesGoal(move)) {
      return const FinishPresentationFrame.complete();
    }

    final elapsed = elapsedMs.clamp(0, movePresentationDurationMs(move));
    final startMs = _finishPresentationStartMs(move);
    if (elapsed < startMs) {
      return const FinishPresentationFrame(
        phase: FinishPresentationPhase.approaching,
      );
    }

    final celebrationElapsed = elapsed - startMs;
    if (celebrationElapsed < finishCelebrationMs) {
      final progress = celebrationElapsed / finishCelebrationMs;
      return FinishPresentationFrame(
        phase: FinishPresentationPhase.celebrating,
        progress: progress,
        pulse: sin(progress * pi),
        glowOpacity: 1 - progress,
      );
    }

    return const FinishPresentationFrame.complete();
  }

  static CapturePresentationFrame captureFrame({
    required ActiveMove move,
    required int elapsedMs,
  }) {
    if (move.capturedPieces.isEmpty) {
      return const CapturePresentationFrame.complete();
    }

    final elapsed = elapsedMs.clamp(0, movePresentationDurationMs(move));
    if (elapsed < move.totalDurationMs) {
      return const CapturePresentationFrame(
        phase: CapturePresentationPhase.approaching,
      );
    }

    final captureElapsed = elapsed - move.totalDurationMs;
    if (captureElapsed < captureImpactMs) {
      final progress = captureElapsed / captureImpactMs;
      return CapturePresentationFrame(
        phase: CapturePresentationPhase.impact,
        impactProgress: progress,
        impactPulse: _pulse(progress),
        impactShake: _impactShake(progress),
      );
    }

    final returnElapsed = captureElapsed - captureImpactMs;
    if (returnElapsed < captureReturnMs) {
      final progress = returnElapsed / captureReturnMs;
      return CapturePresentationFrame(
        phase: CapturePresentationPhase.returning,
        returnProgress: _smoothStep(progress),
      );
    }

    return const CapturePresentationFrame.complete();
  }

  static bool canSelectPiece({
    required bool isPlaying,
    required bool isAuthoritativeTurn,
    required bool hasRolled,
    required bool isWaitingForMove,
    required bool isDiceRolling,
    required bool hasActiveMovePresentation,
  }) {
    return isPlaying &&
        isAuthoritativeTurn &&
        hasRolled &&
        isWaitingForMove &&
        !isDiceRolling &&
        !hasActiveMovePresentation;
  }

  static bool isPieceSelectable({
    required bool canSelectPieces,
    required LudoPiece piece,
    required int diceValue,
  }) {
    return canSelectPieces && LudoRules.isValidMove(piece, diceValue);
  }

  static double selectablePulse(
    double controllerProgress, {
    required bool reduceMotion,
  }) {
    if (reduceMotion) return 0.45;
    final normalized = controllerProgress.clamp(0.0, 1.0);
    return 0.5 - 0.5 * cos(normalized * pi * 2);
  }

  static ExtraTurnReason? extraTurnReasonAfterMove({
    required ActiveMove move,
    required String authoritativeTurnPlayerId,
    required bool matchFinished,
    required bool movingPlayerFinished,
  }) {
    if (matchFinished ||
        movingPlayerFinished ||
        authoritativeTurnPlayerId != move.playerId) {
      return null;
    }
    if (moveReachesGoal(move)) return ExtraTurnReason.goal;
    if (move.capturedPieces.isNotEmpty) return ExtraTurnReason.capture;
    if (moveWasRolledSix(move)) return ExtraTurnReason.six;
    return null;
  }

  static ExtraTurnReason? extraTurnReasonAfterRoll({
    required ActiveDiceRoll roll,
    required String authoritativeTurnPlayerId,
    required bool matchFinished,
    required bool hasValidMove,
  }) {
    if (!matchFinished &&
        !hasValidMove &&
        roll.result == 6 &&
        authoritativeTurnPlayerId == roll.playerId) {
      return ExtraTurnReason.six;
    }
    return null;
  }

  static bool isCurrentActionForFeedback({
    required int actionTurnVersion,
    required int currentTurnVersion,
    required String lastActionType,
    required String expectedActionType,
  }) {
    if (actionTurnVersion == 0) {
      // Legacy descriptors have no version. Accept them only while the room
      // still describes the same action type (or predates lastActionType), so
      // a newer action cannot revive stale feedback.
      return lastActionType.isEmpty || lastActionType == expectedActionType;
    }
    return actionTurnVersion == currentTurnVersion &&
        lastActionType == expectedActionType;
  }

  static bool shouldShowLocalExtraTurnFeedback({
    required String actionPlayerId,
    required String localPlayerId,
    required bool actionPlayerIsAiControlled,
  }) {
    return localPlayerId.isNotEmpty &&
        actionPlayerId == localPlayerId &&
        !actionPlayerIsAiControlled;
  }

  static bool shouldDismissExtraTurnFeedback({
    required bool hasActiveMovePresentation,
    required bool hasActiveDicePresentation,
  }) {
    return hasActiveMovePresentation || hasActiveDicePresentation;
  }

  static bool shouldPresentQuickChat({
    required LudoChat chat,
    required int nowMs,
    int maxAgeMs = 12000,
  }) {
    if (chat.sender.isEmpty || chat.message.isEmpty || chat.timestamp <= 0) {
      return false;
    }
    final age = nowMs - chat.timestamp;
    return age >= -2000 && age <= maxAgeMs;
  }

  static bool shouldCelebrateVictory({
    required bool matchWasObservedInProgress,
    required bool authoritativeMatchFinished,
    required bool presentationComplete,
    required bool localPlayerWon,
  }) {
    return matchWasObservedInProgress &&
        authoritativeMatchFinished &&
        presentationComplete &&
        localPlayerWon;
  }

  static double _smoothStep(double value) {
    return value * value * (3 - 2 * value);
  }

  static double _pulse(double progress) {
    // A parabola gives a single clean impact beat without another timer.
    return 4 * progress * (1 - progress);
  }

  static double _impactShake(double progress) {
    final direction = progress < 0.25
        ? 1.0
        : progress < 0.5
        ? -1.0
        : progress < 0.75
        ? 0.55
        : -0.25;
    return direction * (1 - progress);
  }

  static String visualTurnPlayerId({
    required String authoritativeTurnPlayerId,
    String? dicePlayerId,
    String? movingPlayerId,
  }) {
    if (movingPlayerId != null && movingPlayerId.isNotEmpty) {
      return movingPlayerId;
    }
    if (dicePlayerId != null && dicePlayerId.isNotEmpty) {
      return dicePlayerId;
    }
    return authoritativeTurnPlayerId;
  }

  static bool shouldShowEndGame({
    required bool authoritativeMatchFinished,
    required bool hasActiveMovePresentation,
    required bool hasActiveDicePresentation,
  }) {
    return authoritativeMatchFinished &&
        !hasActiveMovePresentation &&
        !hasActiveDicePresentation;
  }

  static bool isVisuallyFinished({
    required bool authoritativelyFinished,
    required String playerId,
    String? movingPlayerId,
  }) {
    return authoritativelyFinished && movingPlayerId != playerId;
  }
}

enum DicePresentationPhase { rolling, result, complete }

class DicePresentationFrame {
  final DicePresentationPhase phase;
  final int remainingMs;

  const DicePresentationFrame({required this.phase, required this.remainingMs});
}

enum CapturePresentationPhase { approaching, impact, returning, complete }

class CapturePresentationFrame {
  final CapturePresentationPhase phase;
  final double impactProgress;
  final double impactPulse;
  final double impactShake;
  final double returnProgress;

  const CapturePresentationFrame({
    required this.phase,
    this.impactProgress = 0,
    this.impactPulse = 0,
    this.impactShake = 0,
    this.returnProgress = 0,
  });

  const CapturePresentationFrame.complete()
    : phase = CapturePresentationPhase.complete,
      impactProgress = 0,
      impactPulse = 0,
      impactShake = 0,
      returnProgress = 1;
}

enum FinishPresentationPhase { approaching, celebrating, complete }

class FinishPresentationFrame {
  final FinishPresentationPhase phase;
  final double progress;
  final double pulse;
  final double glowOpacity;

  const FinishPresentationFrame({
    required this.phase,
    this.progress = 0,
    this.pulse = 0,
    this.glowOpacity = 0,
  });

  const FinishPresentationFrame.complete()
    : phase = FinishPresentationPhase.complete,
      progress = 1,
      pulse = 0,
      glowOpacity = 0;
}

enum ExtraTurnReason { six, capture, goal }
