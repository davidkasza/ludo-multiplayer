import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/game/classic_grid_geometry.dart';
import 'package:ludo_game/game/ludo_animation.dart';
import 'package:ludo_game/game/ludo_board_mapper.dart';
import 'package:ludo_game/models/ludo_models.dart';

const _boardMapper = LudoBoardMapper(geometry: ClassicGridGeometry());

void main() {
  group('piece motion', () {
    test('interpolates within each individual board step', () {
      final move = _move([
        for (var position = 10; position <= 15; position++)
          ActiveMoveStep(pos: position, inHome: false),
      ]);

      final frame = LudoAnimation.pieceFrame(move, 625);

      expect(frame.stepIndex, 2);
      expect(frame.from.pos, 12);
      expect(frame.to.pos, 13);
      expect(frame.progress, closeTo(0.5, 0.0001));
      expect(frame.easedProgress, closeTo(0.5, 0.0001));
      expect(frame.isBaseExit, isFalse);
    });

    test('eases position while preserving contiguous step boundaries', () {
      final move = _move(const [
        ActiveMoveStep(pos: 2, inHome: false),
        ActiveMoveStep(pos: 3, inHome: false),
        ActiveMoveStep(pos: 4, inHome: false),
      ]);

      final quarterStep = LudoAnimation.pieceFrame(move, 62);
      final beforeBoundary = LudoAnimation.pieceFrame(move, 249);
      final afterBoundary = LudoAnimation.pieceFrame(move, 250);

      expect(quarterStep.easedProgress, lessThan(quarterStep.progress));
      expect(beforeBoundary.to.pos, afterBoundary.from.pos);
      expect(afterBoundary.progress, 0);
      expect(afterBoundary.stepIndex, 1);
    });

    test('detects base exit from the serialized movement path', () {
      final move = _move(const [
        ActiveMoveStep(pos: -1, inHome: false),
        ActiveMoveStep(pos: 0, inHome: false),
      ]);

      final frame = LudoAnimation.pieceFrame(move, 125);

      expect(frame.isBaseExit, isTrue);
      expect(frame.hopProgress, 0);
      expect(frame.easedProgress, closeTo(0.5, 0.0001));
    });

    test('base and start coordinates exist for every player seat', () {
      for (var seat = 0; seat < 4; seat++) {
        for (var pieceId = 1; pieceId <= 4; pieceId++) {
          final base = _boardMapper.pieceCenter(
            piece: LudoPiece(id: pieceId, pos: -1, inHome: false),
            playerIndex: seat,
          );
          final start = _boardMapper.pieceCenter(
            piece: LudoPiece(id: pieceId, pos: 0, inHome: false),
            playerIndex: seat,
          );

          expect(base, isNotNull);
          expect(start, isNotNull);
          expect(base, isNot(start));
        }
      }
    });

    test('settles exactly on the final serialized step', () {
      final move = _move(const [
        ActiveMoveStep(pos: 50, inHome: false),
        ActiveMoveStep(pos: 0, inHome: true),
        ActiveMoveStep(pos: 1, inHome: true),
      ]);

      final frame = LudoAnimation.pieceFrame(move, move.totalDurationMs);

      expect(frame.isComplete, isTrue);
      expect(frame.from.pos, 1);
      expect(frame.from.inHome, isTrue);
      expect(frame.to.pos, 1);
      expect(frame.easedProgress, 1);
    });
  });

  group('dice motion', () {
    test('uses a flight followed by a smaller landing bounce', () {
      final flight = LudoAnimation.diceFrame(0.39, 4);
      final landing = LudoAnimation.diceFrame(0.89, 4);

      expect(flight.lift, greaterThan(0.9));
      expect(landing.lift, greaterThan(0));
      expect(landing.lift, lessThan(flight.lift));
      expect(flight.shadowScale, lessThan(landing.shadowScale));
    });

    test('settles flat on the authoritative result', () {
      final frame = LudoAnimation.diceFrame(1, 5);

      expect(frame.lift, closeTo(0, 0.0001));
      expect(frame.scale, closeTo(1, 0.0001));
      expect(frame.shadowScale, closeTo(1, 0.0001));
      expect(frame.face, 5);
    });

    test('changes faces only during the tumble and lands early on result', () {
      expect(LudoAnimation.diceFrame(0.1, 3).face, isNot(3));
      expect(LudoAnimation.diceFrame(0.81, 3).face, 3);
      expect(LudoAnimation.diceFrame(1, 3).face, 3);
    });
  });
}

ActiveMove _move(List<ActiveMoveStep> steps) {
  return ActiveMove(
    actionId: 'animation-test',
    playerId: 'player',
    pieceId: 1,
    startedAt: 0,
    stepDurationMs: 250,
    steps: steps,
    stateApplied: true,
  );
}
