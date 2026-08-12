import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/game/ludo_presentation.dart';

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
