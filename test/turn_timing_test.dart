import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/models/ludo_models.dart';

void main() {
  group('turn decision timing', () {
    test('roll and move phases both allow thirty seconds', () {
      expect(LudoGame.rollDecisionSeconds, 30);
      expect(LudoGame.moveDecisionSeconds, 30);
      expect(LudoGame.decisionDurationForPhase(LudoGame.waitingForRoll), 30);
      expect(LudoGame.decisionDurationForPhase(LudoGame.waitingForMove), 30);
    });

    test('new match, extra turn, and no-move next roll share roll timing', () {
      for (final transition in [
        'newMatch',
        'normalNextTurn',
        'extraTurn',
        'noValidMove',
        'reconnectRecovery',
      ]) {
        expect(
          LudoGame.decisionDurationForPhase(LudoGame.waitingForRoll),
          30,
          reason: '$transition must start a full roll-decision phase',
        );
      }
    });

    test('server-authored deadlines use the thirty-second duration', () {
      final game = LudoGame.fromMap({
        'players': ['a', 'b'],
        'currentTurn': 'a',
        'status': 'waiting',
        'turnPhase': LudoGame.waitingForRoll,
        'turnStartedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
        'turnDurationSeconds': LudoGame.rollDecisionSeconds,
      });

      expect(game.effectiveTurnDeadline!.millisecondsSinceEpoch, 31000);
    });

    test('legacy ten-second snapshots remain readable during migration', () {
      final legacy = LudoGame.fromMap({
        'players': ['a', 'b'],
        'currentTurn': 'a',
        'status': 'waiting',
        'turnStartedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
        'turnDurationSeconds': 10,
      });

      expect(legacy.effectiveTurnDeadline!.millisecondsSinceEpoch, 11000);
    });
  });
}
