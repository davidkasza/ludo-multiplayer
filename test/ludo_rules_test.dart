import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/game/ludo_rules.dart';
import 'package:ludo_game/models/ludo_models.dart';

void main() {
  group('movement', () {
    test('a six leaves base and uses one visual step', () {
      const piece = LudoPiece(id: 1, pos: -1, inHome: false);
      expect(LudoRules.isValidMove(piece, 5), isFalse);
      expect(LudoRules.isValidMove(piece, 6), isTrue);
      expect(LudoRules.buildMoveSteps(piece, 6), hasLength(2));
      expect(LudoRules.destination(piece, 6).pos, 0);
    });

    test('normal movement advances by the dice value', () {
      const piece = LudoPiece(id: 1, pos: 10, inHome: false);
      final steps = LudoRules.buildMoveSteps(piece, 4);
      expect(steps, hasLength(5));
      expect(steps.last.pos, 14);
      expect(steps.last.inHome, isFalse);
    });

    test('movement enters and advances through the home lane', () {
      const piece = LudoPiece(id: 1, pos: 50, inHome: false);
      final destination = LudoRules.destination(piece, 4);
      expect(destination.pos, 2);
      expect(destination.inHome, isTrue);
    });

    test('finishing requires an exact roll', () {
      const piece = LudoPiece(id: 1, pos: 3, inHome: true);
      expect(LudoRules.isValidMove(piece, 2), isTrue);
      expect(LudoRules.destination(piece, 2).pos, 5);
      expect(LudoRules.isValidMove(piece, 3), isFalse);
    });

    test('reports no valid move when all pieces are blocked', () {
      const pieces = [
        LudoPiece(id: 1, pos: -1, inHome: false),
        LudoPiece(id: 2, pos: 4, inHome: true),
        LudoPiece(id: 3, pos: 5, inHome: true),
        LudoPiece(id: 4, pos: 5, inHome: true),
      ];
      expect(LudoRules.hasValidMove(pieces, 2), isFalse);
    });
  });

  group('captures', () {
    test('captures an opponent on an unsafe square', () {
      final result = LudoRules.applyCaptures(
        pieces: const {
          'a': [LudoPiece(id: 1, pos: 1, inHome: false)],
          'b': [LudoPiece(id: 1, pos: 27, inHome: false)],
        },
        playerSeats: const {'a': 0, 'b': 2},
        players: const ['a', 'b'],
        movingPlayerId: 'a',
        destination: const ActiveMoveStep(pos: 1, inHome: false),
      );
      expect(result.didCapture, isTrue);
      expect(result.pieces['b']!.single.pos, -1);
    });

    test('does not capture on a safe square', () {
      final result = LudoRules.applyCaptures(
        pieces: const {
          'a': [LudoPiece(id: 1, pos: 3, inHome: false)],
          'b': [LudoPiece(id: 1, pos: 29, inHome: false)],
        },
        playerSeats: const {'a': 0, 'b': 2},
        players: const ['a', 'b'],
        movingPlayerId: 'a',
        destination: const ActiveMoveStep(pos: 3, inHome: false),
      );
      expect(result.didCapture, isFalse);
      expect(result.pieces['b']!.single.pos, 29);
    });
  });

  group('turn and finish rules', () {
    test('six, capture, and reaching goal each grant an extra turn', () {
      expect(
        LudoRules.grantsExtraTurn(
          diceValue: 6,
          didCapture: false,
          didReachGoal: false,
        ),
        isTrue,
      );
      expect(
        LudoRules.grantsExtraTurn(
          diceValue: 2,
          didCapture: true,
          didReachGoal: false,
        ),
        isTrue,
      );
      expect(
        LudoRules.grantsExtraTurn(
          diceValue: 2,
          didCapture: false,
          didReachGoal: true,
        ),
        isTrue,
      );
    });

    test('next player skips finished players', () {
      expect(
        LudoRules.nextActivePlayer(
          players: const ['a', 'b', 'c', 'd'],
          currentPlayerId: 'a',
          finishedPlayers: const ['b', 'c'],
        ),
        'd',
      );
    });

    test('no-valid-move turn advances unless the roll is six', () {
      final ordinary = LudoRules.resolveNoValidMove(
        players: const ['a', 'b'],
        currentPlayerId: 'a',
        finishedPlayers: const [],
        diceValue: 3,
      );
      final six = LudoRules.resolveNoValidMove(
        players: const ['a', 'b'],
        currentPlayerId: 'a',
        finishedPlayers: const [],
        diceValue: 6,
      );
      expect(ordinary.nextPlayerId, 'b');
      expect(ordinary.keepsTurn, isFalse);
      expect(six.nextPlayerId, 'a');
      expect(six.keepsTurn, isTrue);
    });

    test('finish order adds the final remaining player', () {
      expect(
        LudoRules.finishOrderAfterMove(
          players: const ['a', 'b', 'c'],
          currentFinishOrder: const ['a'],
          movingPlayerId: 'b',
          movingPlayerFinished: true,
        ),
        const ['a', 'b', 'c'],
      );
    });
  });

  test('legacy action recovery distinguishes applied actions', () {
    final legacy = ActiveMove(
      playerId: 'a',
      pieceId: 1,
      startedAt: 1,
      stepDurationMs: 250,
      steps: const [
        ActiveMoveStep(pos: 0, inHome: false),
        ActiveMoveStep(pos: 1, inHome: false),
      ],
    );
    final applied = ActiveMove(
      actionId: 'move-1',
      playerId: 'a',
      pieceId: 1,
      startedAt: 1,
      stepDurationMs: 250,
      steps: legacy.steps,
      stateApplied: true,
    );
    expect(legacy.stateApplied, isFalse);
    expect(applied.stateApplied, isTrue);
    expect(legacy.key, isNot(applied.key));
    expect(LudoRules.needsActionRecovery(activeMove: legacy), isTrue);
    expect(LudoRules.needsActionRecovery(activeMove: applied), isFalse);
  });

  test('legacy and partially malformed data is normalized safely', () {
    final game = LudoGame.fromMap({
      'players': ['a', 42],
      'currentTurn': 'a',
      'diceValue': 99,
      'status': 'legacy-value',
      'pieces': {
        'a': [
          {'id': 'bad', 'pos': 200, 'inHome': false},
          'not-a-map',
        ],
      },
      'activeMove': 'invalid',
      'finishOrder': ['missing'],
    });

    expect(game.players, ['a']);
    expect(game.status, 'waiting');
    expect(game.diceValue, 6);
    expect(game.activeMove, isNull);
    expect(game.pieces['a']!.single.pos, 51);
  });

  test('server-authored turn start takes precedence over legacy deadline', () {
    final game = LudoGame.fromMap({
      'players': ['a', 'b'],
      'currentTurn': 'a',
      'status': 'waiting',
      'turnStartedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
      'turnDurationSeconds': 10,
      'turnDeadlineAt': Timestamp.fromMillisecondsSinceEpoch(999999),
    });

    expect(game.effectiveTurnDeadline!.millisecondsSinceEpoch, 11000);
  });

  test('invalid authoritative playing state is rejected', () {
    expect(
      () => LudoGame.fromMap({
        'players': ['a', 'b'],
        'currentTurn': 'not-a-player',
        'status': 'playing',
      }),
      throwsFormatException,
    );
  });

  test('malformed authoritative piece state is rejected', () {
    expect(
      () => LudoGame.fromMap({
        'players': ['a', 'b'],
        'currentTurn': 'a',
        'status': 'playing',
        'pieces': {
          'a': [
            {'id': 1, 'pos': -1, 'inHome': false},
          ],
          'b': [
            {'id': 1, 'pos': -1, 'inHome': false},
            {'id': 2, 'pos': -1, 'inHome': false},
            {'id': 3, 'pos': -1, 'inHome': false},
            {'id': 4, 'pos': -1, 'inHome': false},
          ],
        },
      }),
      throwsFormatException,
    );
  });
}
