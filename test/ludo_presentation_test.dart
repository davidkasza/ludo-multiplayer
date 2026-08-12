import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/game/ludo_presentation.dart';
import 'package:ludo_game/models/ludo_models.dart';

void main() {
  group('dice presentation', () {
    test('keeps rolling until the motion duration completes', () {
      final frame = LudoPresentation.diceFrame(
        elapsedMs: 799,
        rollDurationMs: 800,
      );

      expect(frame.phase, DicePresentationPhase.rolling);
      expect(frame.remainingMs, 1);
    });

    test('shows the landed result before completing presentation', () {
      final landed = LudoPresentation.diceFrame(
        elapsedMs: 800,
        rollDurationMs: 800,
      );
      final reconnectMidResult = LudoPresentation.diceFrame(
        elapsedMs: 1100,
        rollDurationMs: 800,
      );

      expect(landed.phase, DicePresentationPhase.result);
      expect(landed.remainingMs, LudoPresentation.diceResultHoldMs);
      expect(reconnectMidResult.phase, DicePresentationPhase.result);
      expect(
        reconnectMidResult.remainingMs,
        LudoPresentation.diceResultHoldMs - 300,
      );
    });

    test('skips an animation that already completed before reconnect', () {
      final frame = LudoPresentation.diceFrame(
        elapsedMs: 800 + LudoPresentation.diceResultHoldMs,
        rollDurationMs: 800,
      );

      expect(frame.phase, DicePresentationPhase.complete);
      expect(frame.remainingMs, 0);
    });
  });

  group('visual turn sequencing', () {
    test('keeps the roller visible after authority advances', () {
      expect(
        LudoPresentation.visualTurnPlayerId(
          authoritativeTurnPlayerId: 'red',
          dicePlayerId: 'blue',
        ),
        'blue',
      );
    });

    test('moving player takes precedence over dice and next turn', () {
      expect(
        LudoPresentation.visualTurnPlayerId(
          authoritativeTurnPlayerId: 'red',
          dicePlayerId: 'yellow',
          movingPlayerId: 'blue',
        ),
        'blue',
      );
    });

    test('uses authoritative turn after visual actions complete', () {
      expect(
        LudoPresentation.visualTurnPlayerId(authoritativeTurnPlayerId: 'red'),
        'red',
      );
    });

    test('extra turn remains on the same visual player', () {
      expect(
        LudoPresentation.visualTurnPlayerId(
          authoritativeTurnPlayerId: 'blue',
          dicePlayerId: 'blue',
        ),
        'blue',
      );
    });

    test('no-valid-move transition is hidden until presentation ends', () {
      final duringResult = LudoPresentation.visualTurnPlayerId(
        authoritativeTurnPlayerId: 'red',
        dicePlayerId: 'blue',
      );
      final afterResult = LudoPresentation.visualTurnPlayerId(
        authoritativeTurnPlayerId: 'red',
      );

      expect(duringResult, 'blue');
      expect(afterResult, 'red');
    });
  });

  group('capture presentation', () {
    final move = ActiveMove(
      actionId: 'capture-action',
      playerId: 'red',
      pieceId: 1,
      startedAt: 0,
      stepDurationMs: 250,
      steps: const [
        ActiveMoveStep(pos: 10, inHome: false),
        ActiveMoveStep(pos: 11, inHome: false),
        ActiveMoveStep(pos: 12, inHome: false),
      ],
      capturedPieces: const [
        ActiveMoveCapture(
          playerId: 'blue',
          pieceId: 3,
          from: ActiveMoveStep(pos: 25, inHome: false),
        ),
      ],
      stateApplied: true,
    );

    test('keeps the victim in place while the attacker approaches', () {
      final frame = LudoPresentation.captureFrame(
        move: move,
        elapsedMs: move.totalDurationMs - 1,
      );

      expect(frame.phase, CapturePresentationPhase.approaching);
      expect(frame.returnProgress, 0);
    });

    test('plays impact before starting the return glide', () {
      final impact = LudoPresentation.captureFrame(
        move: move,
        elapsedMs: move.totalDurationMs + LudoPresentation.captureImpactMs ~/ 2,
      );
      final returnStart = LudoPresentation.captureFrame(
        move: move,
        elapsedMs: move.totalDurationMs + LudoPresentation.captureImpactMs,
      );

      expect(impact.phase, CapturePresentationPhase.impact);
      expect(impact.impactPulse, greaterThan(0.9));
      expect(returnStart.phase, CapturePresentationPhase.returning);
      expect(returnStart.returnProgress, 0);
    });

    test('resumes return progress and skips a fully elapsed capture', () {
      final midReturn = LudoPresentation.captureFrame(
        move: move,
        elapsedMs:
            move.totalDurationMs +
            LudoPresentation.captureImpactMs +
            LudoPresentation.captureReturnMs ~/ 2,
      );
      final complete = LudoPresentation.captureFrame(
        move: move,
        elapsedMs: LudoPresentation.movePresentationDurationMs(move),
      );

      expect(midReturn.phase, CapturePresentationPhase.returning);
      expect(midReturn.returnProgress, closeTo(0.5, 0.0001));
      expect(complete.phase, CapturePresentationPhase.complete);
      expect(complete.returnProgress, 1);
    });

    test('does not extend ordinary move presentation timing', () {
      final ordinaryMove = ActiveMove(
        playerId: 'red',
        pieceId: 1,
        startedAt: 0,
        stepDurationMs: 250,
        steps: move.steps,
        stateApplied: true,
      );

      expect(
        LudoPresentation.movePresentationDurationMs(ordinaryMove),
        ordinaryMove.totalDurationMs,
      );
      expect(
        LudoPresentation.captureFrame(move: ordinaryMove, elapsedMs: 0).phase,
        CapturePresentationPhase.complete,
      );
    });
  });

  group('piece selection sequencing', () {
    bool canSelect({
      bool isPlaying = true,
      bool isAuthoritativeTurn = true,
      bool hasRolled = true,
      bool isWaitingForMove = true,
      bool isDiceRolling = false,
      bool hasActiveMovePresentation = false,
    }) {
      return LudoPresentation.canSelectPiece(
        isPlaying: isPlaying,
        isAuthoritativeTurn: isAuthoritativeTurn,
        hasRolled: hasRolled,
        isWaitingForMove: isWaitingForMove,
        isDiceRolling: isDiceRolling,
        hasActiveMovePresentation: hasActiveMovePresentation,
      );
    }

    test('enables selection as soon as the dice has landed', () {
      expect(canSelect(), isTrue);
    });

    test('blocks selection while dice motion or piece motion is active', () {
      expect(canSelect(isDiceRolling: true), isFalse);
      expect(canSelect(hasActiveMovePresentation: true), isFalse);
    });

    test('blocks no-move and non-current-player states', () {
      expect(canSelect(hasRolled: false), isFalse);
      expect(canSelect(isWaitingForMove: false), isFalse);
      expect(canSelect(isAuthoritativeTurn: false), isFalse);
    });
  });

  group('end-game sequencing', () {
    test('holds the game screen while the final move is visible', () {
      expect(
        LudoPresentation.shouldShowEndGame(
          authoritativeMatchFinished: true,
          hasActiveMovePresentation: true,
          hasActiveDicePresentation: false,
        ),
        isFalse,
      );
    });

    test('shows end game after the final presentation completes', () {
      expect(
        LudoPresentation.shouldShowEndGame(
          authoritativeMatchFinished: true,
          hasActiveMovePresentation: false,
          hasActiveDicePresentation: false,
        ),
        isTrue,
      );
    });

    test('does not visually finish the moving player early', () {
      expect(
        LudoPresentation.isVisuallyFinished(
          authoritativelyFinished: true,
          playerId: 'blue',
          movingPlayerId: 'blue',
        ),
        isFalse,
      );
      expect(
        LudoPresentation.isVisuallyFinished(
          authoritativelyFinished: true,
          playerId: 'blue',
        ),
        isTrue,
      );
    });
  });
}
