import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/game/classic_board.dart';
import 'package:ludo_game/game/classic_grid_geometry.dart';
import 'package:ludo_game/game/ludo_animation.dart';
import 'package:ludo_game/game/ludo_board_geometry_resolver.dart';
import 'package:ludo_game/game/ludo_board_mapper.dart';
import 'package:ludo_game/game/ludo_rules.dart';
import 'package:ludo_game/models/ludo_models.dart';

const _geometry = ClassicGridGeometry();
const _mapper = LudoBoardMapper(geometry: _geometry);

const _outerTrackGrid = <(int, int)>[
  (6, 0),
  (6, 1),
  (6, 2),
  (6, 3),
  (6, 4),
  (6, 5),
  (5, 6),
  (4, 6),
  (3, 6),
  (2, 6),
  (1, 6),
  (0, 6),
  (0, 7),
  (0, 8),
  (1, 8),
  (2, 8),
  (3, 8),
  (4, 8),
  (5, 8),
  (6, 9),
  (6, 10),
  (6, 11),
  (6, 12),
  (6, 13),
  (6, 14),
  (7, 14),
  (8, 14),
  (8, 13),
  (8, 12),
  (8, 11),
  (8, 10),
  (8, 9),
  (9, 8),
  (10, 8),
  (11, 8),
  (12, 8),
  (13, 8),
  (14, 8),
  (14, 7),
  (14, 6),
  (13, 6),
  (12, 6),
  (11, 6),
  (10, 6),
  (9, 6),
  (8, 5),
  (8, 4),
  (8, 3),
  (8, 2),
  (8, 1),
  (8, 0),
  (7, 0),
];

const _baseSlotGrid = <List<(int, int)>>[
  [(2, 2), (3, 2), (2, 3), (3, 3)],
  [(2, 11), (3, 11), (2, 12), (3, 12)],
  [(11, 11), (12, 11), (11, 12), (12, 12)],
  [(11, 2), (12, 2), (11, 3), (12, 3)],
];

const _homeLaneGrid = <List<(int, int)>>[
  [(1, 7), (2, 7), (3, 7), (4, 7), (5, 7)],
  [(7, 13), (7, 12), (7, 11), (7, 10), (7, 9)],
  [(13, 7), (12, 7), (11, 7), (10, 7), (9, 7)],
  [(7, 1), (7, 2), (7, 3), (7, 4), (7, 5)],
];

const _goalCenters = <Offset>[
  Offset(260, 300),
  Offset(300, 340),
  Offset(340, 300),
  Offset(300, 260),
];

void main() {
  group('Classic geometry regression contract', () {
    test('keeps the original board scale and resolves safe fallbacks', () {
      expect(_geometry.boardId, 'classic');
      expect(_geometry.boardExtent, 600);
      expect(_geometry.nominalCellExtent, 40);
      expect(_geometry.pieceHitTestRadius, 26);
      expect(_geometry.boardCenter, const Offset(300, 300));
      expect(_geometry.goalAreaBounds, const Rect.fromLTWH(240, 240, 120, 120));

      for (final boardId in <String?>[
        null,
        '',
        'classic',
        ' CLASSIC ',
        'legacy',
        'unknown-theme',
      ]) {
        expect(
          LudoBoardGeometryResolver.resolve(boardId),
          same(LudoBoardGeometryResolver.classic),
        );
      }
    });

    test('preserves all 52 outer-track cells and centers', () {
      expect(_outerTrackGrid, hasLength(ClassicBoard.size));

      for (int index = 0; index < _outerTrackGrid.length; index++) {
        final expectedCenter = _gridCenter(_outerTrackGrid[index]);
        expect(
          _geometry.outerTrackCenter(index),
          expectedCenter,
          reason: 'global outer-track index $index moved',
        );
        expect(
          _geometry.outerTrackCellBounds(index).center,
          expectedCenter,
          reason: 'cell bounds and center diverged at index $index',
        );
      }
    });

    test('maps every relative track position for all four seats', () {
      for (int seat = 0; seat < 4; seat++) {
        for (
          int relativePosition = 0;
          relativePosition < ClassicBoard.size;
          relativePosition++
        ) {
          final globalIndex =
              (ClassicBoard.startOffsets[seat] - relativePosition) %
              ClassicBoard.size;
          final piece = LudoPiece(id: 1, pos: relativePosition, inHome: false);

          expect(
            _mapper.pieceCenter(piece: piece, playerIndex: seat),
            _gridCenter(_outerTrackGrid[globalIndex]),
            reason: 'seat $seat relative position $relativePosition moved',
          );
        }
      }
    });

    test('preserves every piece-specific Base slot', () {
      for (int seat = 0; seat < 4; seat++) {
        for (int pieceId = 1; pieceId <= 4; pieceId++) {
          final expected = _gridCenter(_baseSlotGrid[seat][pieceId - 1]);
          final piece = LudoPiece(
            id: pieceId,
            pos: LudoRules.basePosition,
            inHome: false,
          );

          expect(_geometry.baseSlotCenter(seat, pieceId), expected);
          expect(
            _mapper.pieceCenter(piece: piece, playerIndex: seat),
            expected,
            reason: 'seat $seat piece $pieceId Base slot moved',
          );
        }
      }
    });

    test('preserves every Home-lane and goal center', () {
      for (int seat = 0; seat < 4; seat++) {
        for (int homePosition = 0; homePosition < 5; homePosition++) {
          final expected = _gridCenter(_homeLaneGrid[seat][homePosition]);
          final piece = LudoPiece(id: 1, pos: homePosition, inHome: true);

          expect(_geometry.homeLaneCenter(seat, homePosition), expected);
          expect(
            _geometry.homeLaneCellBounds(seat, homePosition).center,
            expected,
          );
          expect(
            _mapper.pieceCenter(piece: piece, playerIndex: seat),
            expected,
          );
        }

        final goalPiece = LudoPiece(
          id: 1,
          pos: LudoRules.goalPosition,
          inHome: true,
        );
        expect(_geometry.goalCenter(seat), _goalCenters[seat]);
        expect(
          _mapper.pieceCenter(piece: goalPiece, playerIndex: seat),
          _goalCenters[seat],
        );
      }
    });

    test(
      'keeps start cells, safe positions, and two-player seats unchanged',
      () {
        expect(ClassicBoard.startOffsets, [11, 24, 37, 50]);
        expect(LudoGame.seatLayoutForMaxPlayers(2), [0, 2]);
        expect(LudoRules.safeGlobalPositions, {
          3,
          8,
          11,
          16,
          21,
          24,
          29,
          34,
          37,
          42,
          47,
          50,
        });

        for (int seat = 0; seat < 4; seat++) {
          expect(
            _mapper.pieceCenter(
              piece: const LudoPiece(id: 1, pos: 0, inHome: false),
              playerIndex: seat,
            ),
            _gridCenter(_outerTrackGrid[ClassicBoard.startOffsets[seat]]),
          );
        }

        for (final safeIndex in LudoRules.safeGlobalPositions) {
          expect(
            _geometry.outerTrackCenter(safeIndex),
            _gridCenter(_outerTrackGrid[safeIndex]),
          );
        }
      },
    );
  });

  group('geometry consumers', () {
    test('normal movement endpoints use mapped adjacent centers', () {
      final move = ActiveMove(
        playerId: 'player',
        pieceId: 1,
        startedAt: 0,
        stepDurationMs: 250,
        steps: const [
          ActiveMoveStep(pos: 10, inHome: false),
          ActiveMoveStep(pos: 11, inHome: false),
        ],
        stateApplied: true,
      );
      final frame = LudoAnimation.pieceFrame(move, 125);

      final fromCenter = _mapper.pieceCenter(
        piece: LudoPiece(id: 1, pos: frame.from.pos, inHome: frame.from.inHome),
        playerIndex: 2,
      );
      final toCenter = _mapper.pieceCenter(
        piece: LudoPiece(id: 1, pos: frame.to.pos, inHome: frame.to.inHome),
        playerIndex: 2,
      );

      expect(fromCenter, _geometry.outerTrackCenter(27));
      expect(toCenter, _geometry.outerTrackCenter(26));
    });

    test('Base exit and capture return resolve exact Base endpoints', () {
      for (int seat = 0; seat < 4; seat++) {
        for (int pieceId = 1; pieceId <= 4; pieceId++) {
          final exitMove = ActiveMove(
            playerId: 'player',
            pieceId: pieceId,
            startedAt: 0,
            stepDurationMs: 250,
            steps: const [
              ActiveMoveStep(pos: -1, inHome: false),
              ActiveMoveStep(pos: 0, inHome: false),
            ],
            stateApplied: true,
          );
          final exitFrame = LudoAnimation.pieceFrame(exitMove, 125);
          final basePiece = LudoPiece(
            id: pieceId,
            pos: exitFrame.from.pos,
            inHome: exitFrame.from.inHome,
          );
          final startPiece = LudoPiece(
            id: pieceId,
            pos: exitFrame.to.pos,
            inHome: exitFrame.to.inHome,
          );
          final captured = ActiveMoveCapture(
            playerId: 'captured',
            pieceId: pieceId,
            from: const ActiveMoveStep(pos: 18, inHome: false),
          );
          final returnedPiece = LudoPiece(
            id: captured.pieceId,
            pos: LudoRules.basePosition,
            inHome: false,
          );

          expect(exitFrame.isBaseExit, isTrue);
          expect(
            _mapper.pieceCenter(piece: basePiece, playerIndex: seat),
            _geometry.baseSlotCenter(seat, pieceId),
          );
          expect(
            _mapper.pieceCenter(piece: startPiece, playerIndex: seat),
            _geometry.outerTrackCenter(ClassicBoard.startOffsets[seat]),
          );
          expect(
            _mapper.pieceCenter(piece: returnedPiece, playerIndex: seat),
            _geometry.baseSlotCenter(seat, captured.pieceId),
          );
        }
      }
    });

    test('drawing centers and hit-test centers cannot diverge', () {
      final pieces = <LudoPiece>[
        const LudoPiece(id: 3, pos: -1, inHome: false),
        const LudoPiece(id: 1, pos: 0, inHome: false),
        const LudoPiece(id: 2, pos: 24, inHome: false),
        const LudoPiece(id: 4, pos: 3, inHome: true),
        const LudoPiece(id: 1, pos: 5, inHome: true),
      ];

      for (int seat = 0; seat < 4; seat++) {
        for (final piece in pieces) {
          final renderCenter = _mapper.pieceCenter(
            piece: piece,
            playerIndex: seat,
          )!;

          expect(
            _mapper.hitTestPiece(
              boardPosition: renderCenter,
              piece: piece,
              playerIndex: seat,
            ),
            isTrue,
          );
          expect(
            _mapper.hitTestPiece(
              boardPosition: renderCenter.translate(
                _geometry.pieceHitTestRadius + 0.01,
                0,
              ),
              piece: piece,
              playerIndex: seat,
            ),
            isFalse,
          );
        }
      }
    });

    test('rendered-board taps scale into the same logical geometry', () {
      const renderedExtent = 300.0;
      const localPosition = Offset(130, 150);
      final boardPosition = _mapper.boardPointFromLocal(
        localPosition: localPosition,
        renderedBoardExtent: renderedExtent,
      );
      const goalPiece = LudoPiece(id: 1, pos: 5, inHome: true);

      expect(boardPosition, const Offset(260, 300));
      expect(
        _mapper.hitTestPiece(
          boardPosition: boardPosition,
          piece: goalPiece,
          playerIndex: 0,
        ),
        isTrue,
      );
    });
  });
}

Offset _gridCenter((int, int) point) {
  return Offset(point.$1 * 40 + 20, point.$2 * 40 + 20);
}
