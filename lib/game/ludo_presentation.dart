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
    if (move.capturedPieces.isEmpty) return move.totalDurationMs;
    return move.totalDurationMs + captureImpactMs + captureReturnMs;
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
