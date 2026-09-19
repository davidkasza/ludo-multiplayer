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

  group('finish presentation', () {
    final move = ActiveMove(
      actionId: 'goal-action',
      playerId: 'blue',
      pieceId: 4,
      startedAt: 0,
      stepDurationMs: 250,
      steps: const [
        ActiveMoveStep(pos: 3, inHome: true),
        ActiveMoveStep(pos: 4, inHome: true),
        ActiveMoveStep(pos: 5, inHome: true),
      ],
      stateApplied: true,
    );

    test('starts only after the final normal movement step', () {
      final beforeLanding = LudoPresentation.finishFrame(
        move: move,
        elapsedMs: move.totalDurationMs - 1,
      );
      final landed = LudoPresentation.finishFrame(
        move: move,
        elapsedMs: move.totalDurationMs,
      );

      expect(LudoPresentation.moveReachesGoal(move), isTrue);
      expect(beforeLanding.phase, FinishPresentationPhase.approaching);
      expect(landed.phase, FinishPresentationPhase.celebrating);
      expect(landed.progress, 0);
      expect(
        LudoPresentation.movePresentationDurationMs(move),
        move.totalDurationMs + LudoPresentation.finishCelebrationMs,
      );
    });

    test('pulses briefly and reconnect skips an expired finish effect', () {
      final middle = LudoPresentation.finishFrame(
        move: move,
        elapsedMs:
            move.totalDurationMs + LudoPresentation.finishCelebrationMs ~/ 2,
      );
      final expired = LudoPresentation.finishFrame(
        move: move,
        elapsedMs: LudoPresentation.movePresentationDurationMs(move),
      );

      expect(middle.phase, FinishPresentationPhase.celebrating);
      expect(middle.pulse, closeTo(1, 0.0001));
      expect(expired.phase, FinishPresentationPhase.complete);
    });

    test('presentation calculations never mutate the authoritative action', () {
      final originalSteps = List<ActiveMoveStep>.from(move.steps);
      LudoPresentation.finishFrame(move: move, elapsedMs: 625);
      LudoPresentation.captureFrame(move: move, elapsedMs: 625);

      expect(move.steps, orderedEquals(originalSteps));
      expect(move.stateApplied, isTrue);
      expect(move.playerId, 'blue');
    });
  });

  group('extra-turn feedback', () {
    ActiveMove move({
      List<ActiveMoveStep> steps = const [
        ActiveMoveStep(pos: 1, inHome: false),
        ActiveMoveStep(pos: 2, inHome: false),
      ],
      List<ActiveMoveCapture> captures = const [],
    }) {
      return ActiveMove(
        playerId: 'blue',
        pieceId: 1,
        startedAt: 0,
        stepDurationMs: 250,
        steps: steps,
        capturedPieces: captures,
        stateApplied: true,
      );
    }

    test('is shown only for an action owned by the local human', () {
      expect(
        LudoPresentation.shouldShowLocalExtraTurnFeedback(
          actionPlayerId: 'local',
          localPlayerId: 'local',
          actionPlayerIsAiControlled: false,
        ),
        isTrue,
      );
      expect(
        LudoPresentation.shouldShowLocalExtraTurnFeedback(
          actionPlayerId: 'remote',
          localPlayerId: 'local',
          actionPlayerIsAiControlled: false,
        ),
        isFalse,
        reason: 'a remote human extra turn belongs only on their client',
      );
      expect(
        LudoPresentation.shouldShowLocalExtraTurnFeedback(
          actionPlayerId: 'local',
          localPlayerId: 'local',
          actionPlayerIsAiControlled: true,
        ),
        isFalse,
        reason: 'AI takeover actions are not local-human feedback',
      );
    });

    test('new dice or movement presentation dismisses the feedback', () {
      expect(
        LudoPresentation.shouldDismissExtraTurnFeedback(
          hasActiveMovePresentation: false,
          hasActiveDicePresentation: false,
        ),
        isFalse,
      );
      expect(
        LudoPresentation.shouldDismissExtraTurnFeedback(
          hasActiveMovePresentation: true,
          hasActiveDicePresentation: false,
        ),
        isTrue,
      );
      expect(
        LudoPresentation.shouldDismissExtraTurnFeedback(
          hasActiveMovePresentation: false,
          hasActiveDicePresentation: true,
        ),
        isTrue,
      );
      expect(LudoPresentation.extraTurnFeedbackDurationMs, 1500);
    });

    test('uses the most meaningful committed extra-turn reason', () {
      expect(
        LudoPresentation.extraTurnReasonAfterMove(
          move: move(
            steps: const [
              ActiveMoveStep(pos: 4, inHome: true),
              ActiveMoveStep(pos: 5, inHome: true),
            ],
          ),
          authoritativeTurnPlayerId: 'blue',
          matchFinished: false,
          movingPlayerFinished: false,
        ),
        ExtraTurnReason.goal,
      );
      expect(
        LudoPresentation.extraTurnReasonAfterMove(
          move: move(
            captures: const [
              ActiveMoveCapture(
                playerId: 'red',
                pieceId: 2,
                from: ActiveMoveStep(pos: 8, inHome: false),
              ),
            ],
          ),
          authoritativeTurnPlayerId: 'blue',
          matchFinished: false,
          movingPlayerFinished: false,
        ),
        ExtraTurnReason.capture,
      );
      expect(
        LudoPresentation.extraTurnReasonAfterMove(
          move: move(
            steps: const [
              ActiveMoveStep(pos: 0, inHome: false),
              ActiveMoveStep(pos: 1, inHome: false),
              ActiveMoveStep(pos: 2, inHome: false),
              ActiveMoveStep(pos: 3, inHome: false),
              ActiveMoveStep(pos: 4, inHome: false),
              ActiveMoveStep(pos: 5, inHome: false),
              ActiveMoveStep(pos: 6, inHome: false),
            ],
          ),
          authoritativeTurnPlayerId: 'blue',
          matchFinished: false,
          movingPlayerFinished: false,
        ),
        ExtraTurnReason.six,
      );

      final baseExit = move(
        steps: const [
          ActiveMoveStep(pos: -1, inHome: false),
          ActiveMoveStep(pos: 0, inHome: false),
        ],
      );
      expect(LudoPresentation.moveWasRolledSix(baseExit), isTrue);
    });

    test('non-extra turns and finished players do not show feedback', () {
      expect(
        LudoPresentation.extraTurnReasonAfterMove(
          move: move(),
          authoritativeTurnPlayerId: 'blue',
          matchFinished: false,
          movingPlayerFinished: false,
        ),
        isNull,
        reason: 'the move path, not a mutable room dice value, drives this',
      );
      expect(
        LudoPresentation.extraTurnReasonAfterMove(
          move: move(),
          authoritativeTurnPlayerId: 'red',
          matchFinished: false,
          movingPlayerFinished: false,
        ),
        isNull,
      );
      expect(
        LudoPresentation.extraTurnReasonAfterMove(
          move: move(),
          authoritativeTurnPlayerId: 'blue',
          matchFinished: false,
          movingPlayerFinished: true,
        ),
        isNull,
      );
    });

    test('a six with no legal move produces roll-again feedback', () {
      const roll = ActiveDiceRoll(
        playerId: 'blue',
        startedAt: 0,
        durationMs: 800,
        result: 6,
        stateApplied: true,
      );
      expect(
        LudoPresentation.extraTurnReasonAfterRoll(
          roll: roll,
          authoritativeTurnPlayerId: 'blue',
          matchFinished: false,
          hasValidMove: false,
        ),
        ExtraTurnReason.six,
      );
      expect(
        LudoPresentation.extraTurnReasonAfterRoll(
          roll: roll,
          authoritativeTurnPlayerId: 'blue',
          matchFinished: false,
          hasValidMove: true,
        ),
        isNull,
      );
    });

    test('stale or superseded actions cannot emit delayed feedback', () {
      expect(
        LudoPresentation.isCurrentActionForFeedback(
          actionTurnVersion: 8,
          currentTurnVersion: 8,
          lastActionType: 'move',
          expectedActionType: 'move',
        ),
        isTrue,
      );
      expect(
        LudoPresentation.isCurrentActionForFeedback(
          actionTurnVersion: 8,
          currentTurnVersion: 9,
          lastActionType: 'dice',
          expectedActionType: 'move',
        ),
        isFalse,
      );
      expect(
        LudoPresentation.isCurrentActionForFeedback(
          actionTurnVersion: 8,
          currentTurnVersion: 8,
          lastActionType: 'move',
          expectedActionType: 'dice',
        ),
        isFalse,
      );
      expect(
        LudoPresentation.isCurrentActionForFeedback(
          actionTurnVersion: 0,
          currentTurnVersion: 9,
          lastActionType: 'dice',
          expectedActionType: 'move',
        ),
        isFalse,
        reason: 'a newer typed action must supersede a legacy descriptor',
      );
      expect(
        LudoPresentation.isCurrentActionForFeedback(
          actionTurnVersion: 0,
          currentTurnVersion: 0,
          lastActionType: '',
          expectedActionType: 'move',
        ),
        isTrue,
        reason: 'fully legacy rooms remain presentation-compatible',
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

    test('reduced motion keeps a stable selectable indication', () {
      expect(
        LudoPresentation.selectablePulse(0, reduceMotion: true),
        LudoPresentation.selectablePulse(0.8, reduceMotion: true),
      );
      expect(
        LudoPresentation.selectablePulse(0.5, reduceMotion: false),
        greaterThan(LudoPresentation.selectablePulse(0, reduceMotion: false)),
      );
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

    test('celebrates only a match observed locally before it finished', () {
      expect(
        LudoPresentation.shouldCelebrateVictory(
          matchWasObservedInProgress: true,
          authoritativeMatchFinished: true,
          presentationComplete: true,
          localPlayerWon: true,
        ),
        isTrue,
      );
      expect(
        LudoPresentation.shouldCelebrateVictory(
          matchWasObservedInProgress: true,
          authoritativeMatchFinished: true,
          presentationComplete: true,
          localPlayerWon: false,
        ),
        isFalse,
        reason: 'losing clients keep the normal static result screen',
      );
      expect(
        LudoPresentation.shouldCelebrateVictory(
          matchWasObservedInProgress: false,
          authoritativeMatchFinished: true,
          presentationComplete: true,
          localPlayerWon: true,
        ),
        isFalse,
        reason: 'an already-finished reconnect must not replay celebration',
      );
      expect(LudoPresentation.victoryFireworksDurationMs, 4000);
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

  group('quick-chat presentation', () {
    test('accepts recent messages and rejects stale reconnect values', () {
      const recent = LudoChat(
        sender: 'blue',
        message: 'Good luck!',
        timestamp: 9000,
      );
      const stale = LudoChat(sender: 'red', message: 'Ouch!', timestamp: 1000);

      expect(
        LudoPresentation.shouldPresentQuickChat(chat: recent, nowMs: 10000),
        isTrue,
      );
      expect(
        LudoPresentation.shouldPresentQuickChat(chat: stale, nowMs: 20000),
        isFalse,
      );
    });
  });
}
