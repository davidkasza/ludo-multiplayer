/// Pure helpers for sequencing visual game presentation independently from
/// authoritative multiplayer state.
class LudoPresentation {
  const LudoPresentation._();

  /// Time the landed dice result remains visible after the rolling motion.
  static const int diceResultHoldMs = 650;

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
