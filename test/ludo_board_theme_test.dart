import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/components/painters/aurora_circuit_board_painter.dart';
import 'package:ludo_game/components/painters/selectable_glow_painter.dart';
import 'package:ludo_game/game/classic_board.dart';
import 'package:ludo_game/game/classic_grid_geometry.dart';
import 'package:ludo_game/game/ludo_animation.dart';
import 'package:ludo_game/game/ludo_board_mapper.dart';
import 'package:ludo_game/game/ludo_board_theme.dart';
import 'package:ludo_game/game/ludo_palette.dart';
import 'package:ludo_game/models/ludo_models.dart';

void main() {
  group('board theme resolution', () {
    test('resolves all stable board theme IDs', () {
      expect(
        LudoBoardThemeResolver.resolve('classic'),
        same(LudoBoardThemeResolver.classic),
      );
      expect(
        LudoBoardThemeResolver.resolve('auroraCircuit'),
        same(LudoBoardThemeResolver.auroraCircuit),
      );
      expect(
        LudoBoardThemeResolver.resolve(' AURORACIRCUIT '),
        same(LudoBoardThemeResolver.auroraCircuit),
      );
      expect(
        LudoBoardThemeResolver.resolve('solarisTemple'),
        same(LudoBoardThemeResolver.solarisTemple),
      );
      expect(
        LudoBoardThemeResolver.resolve(' SOLARISTEMPLE '),
        same(LudoBoardThemeResolver.solarisTemple),
      );
      expect(LudoBoardThemeResolver.selectionLabels, {
        'classic': 'Classic',
        'auroraCircuit': 'Aurora Circuit',
        'solarisTemple': 'Solaris Temple',
      });
    });

    test('falls back to Classic for missing, legacy, or malformed IDs', () {
      for (final boardId in <String?>[
        null,
        '',
        'legacy',
        'aurora-circuit',
        'solaris-temple',
        'unknown',
      ]) {
        expect(
          LudoBoardThemeResolver.resolve(boardId),
          same(LudoBoardThemeResolver.classic),
        );
        expect(LudoBoardThemeResolver.normalizeId(boardId), 'classic');
      }
    });
  });

  group('Aurora Circuit geometry compatibility', () {
    final classic = LudoBoardThemeResolver.classic.geometry;
    final aurora = LudoBoardThemeResolver.auroraCircuit.geometry;
    final mapper = LudoBoardMapper(geometry: aurora);

    test('reuses the exact Classic geometry contract', () {
      expect(classic, isA<ClassicGridGeometry>());
      expect(aurora, isA<ClassicGridGeometry>());
      expect(aurora.boardExtent, classic.boardExtent);
      expect(aurora.nominalCellExtent, classic.nominalCellExtent);
      expect(aurora.pieceHitTestRadius, classic.pieceHitTestRadius);
      expect(aurora.goalAreaBounds, classic.goalAreaBounds);

      for (int index = 0; index < ClassicBoard.size; index++) {
        expect(aurora.outerTrackCenter(index), classic.outerTrackCenter(index));
        expect(
          aurora.outerTrackCellBounds(index),
          classic.outerTrackCellBounds(index),
        );
      }

      for (int seat = 0; seat < 4; seat++) {
        for (int pieceId = 1; pieceId <= 4; pieceId++) {
          expect(
            aurora.baseSlotCenter(seat, pieceId),
            classic.baseSlotCenter(seat, pieceId),
          );
        }
        for (int position = 0; position < 5; position++) {
          expect(
            aurora.homeLaneCenter(seat, position),
            classic.homeLaneCenter(seat, position),
          );
        }
        expect(aurora.goalCenter(seat), classic.goalCenter(seat));
      }
    });

    test('keeps Base, Home, goal, and hit-test mapping aligned', () {
      const pieces = <LudoPiece>[
        LudoPiece(id: 4, pos: -1, inHome: false),
        LudoPiece(id: 1, pos: 0, inHome: false),
        LudoPiece(id: 2, pos: 31, inHome: false),
        LudoPiece(id: 3, pos: 2, inHome: true),
        LudoPiece(id: 1, pos: 5, inHome: true),
      ];

      for (int seat = 0; seat < 4; seat++) {
        for (final piece in pieces) {
          final center = mapper.pieceCenter(piece: piece, playerIndex: seat);
          expect(center, isNotNull);
          expect(
            mapper.hitTestPiece(
              boardPosition: center!,
              piece: piece,
              playerIndex: seat,
            ),
            isTrue,
          );
        }
      }
    });

    test('preserves movement and Base-exit animation endpoints', () {
      for (int seat = 0; seat < 4; seat++) {
        final normalMove = ActiveMove(
          playerId: 'player',
          pieceId: 1,
          startedAt: 0,
          stepDurationMs: 250,
          steps: const [
            ActiveMoveStep(pos: 14, inHome: false),
            ActiveMoveStep(pos: 15, inHome: false),
          ],
          stateApplied: true,
        );
        final normalFrame = LudoAnimation.pieceFrame(normalMove, 125);
        final normalFrom = mapper.pieceCenter(
          piece: LudoPiece(
            id: 1,
            pos: normalFrame.from.pos,
            inHome: normalFrame.from.inHome,
          ),
          playerIndex: seat,
        );
        final normalTo = mapper.pieceCenter(
          piece: LudoPiece(
            id: 1,
            pos: normalFrame.to.pos,
            inHome: normalFrame.to.inHome,
          ),
          playerIndex: seat,
        );

        expect(
          normalFrom,
          aurora.outerTrackCenter(
            ClassicBoard.globalPathIndexForSeat(seat, 14),
          ),
        );
        expect(
          normalTo,
          aurora.outerTrackCenter(
            ClassicBoard.globalPathIndexForSeat(seat, 15),
          ),
        );

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

          expect(exitFrame.isBaseExit, isTrue);
          expect(
            mapper.pieceCenter(
              piece: LudoPiece(
                id: pieceId,
                pos: exitFrame.from.pos,
                inHome: exitFrame.from.inHome,
              ),
              playerIndex: seat,
            ),
            aurora.baseSlotCenter(seat, pieceId),
          );
          expect(
            mapper.pieceCenter(
              piece: LudoPiece(
                id: pieceId,
                pos: exitFrame.to.pos,
                inHome: exitFrame.to.inHome,
              ),
              playerIndex: seat,
            ),
            aurora.outerTrackCenter(ClassicBoard.startOffsetForSeat(seat)),
          );
        }
      }
    });

    test('keeps two-player seats opposite without a separate geometry', () {
      expect(LudoGame.seatLayoutForMaxPlayers(2), [0, 2]);
      expect(LudoGame.seatLayoutForMaxPlayers(4), [0, 1, 2, 3]);
      expect(
        LudoBoardThemeResolver.resolve('auroraCircuit').geometry.runtimeType,
        LudoBoardThemeResolver.resolve('classic').geometry.runtimeType,
      );
    });
  });

  group('Aurora Circuit static presentation', () {
    const colors = ['red', 'yellow', 'green', 'blue'];

    test(
      'maps all four runtime seat colors into active docking bays',
      () async {
        final image = await _paintAurora(
          seatColorIds: colors,
          activeSeats: const {0, 1, 2, 3},
        );

        try {
          for (int seat = 0; seat < 4; seat++) {
            final actual = await _pixelAt(image, _dockMarkCenter(seat));
            final expected = LudoPalette.style(colors[seat]).bright;
            final otherDistances = <int>[
              for (int otherSeat = 0; otherSeat < 4; otherSeat++)
                if (otherSeat != seat)
                  _colorDistance(
                    actual,
                    LudoPalette.style(colors[otherSeat]).bright,
                  ),
            ];

            expect(
              _colorDistance(actual, expected),
              lessThan(otherDistances.reduce(min)),
              reason: 'physical seat $seat must use its runtime color',
            );
          }
        } finally {
          image.dispose();
        }
      },
    );

    test(
      'dims seats 1 and 3 while preserving active duel seats 0 and 2',
      () async {
        final duel = await _paintAurora(
          seatColorIds: colors,
          activeSeats: LudoGame.seatLayoutForMaxPlayers(2).toSet(),
        );
        final fourPlayer = await _paintAurora(
          seatColorIds: colors,
          activeSeats: LudoGame.seatLayoutForMaxPlayers(4).toSet(),
        );

        try {
          for (final activeSeat in const [0, 2]) {
            expect(
              await _pixelAt(duel, _dockMarkCenter(activeSeat)),
              await _pixelAt(fourPlayer, _dockMarkCenter(activeSeat)),
            );
          }
          for (final dormantSeat in const [1, 3]) {
            final duelColor = await _pixelAt(
              duel,
              _dockMarkCenter(dormantSeat),
            );
            final fourPlayerColor = await _pixelAt(
              fourPlayer,
              _dockMarkCenter(dormantSeat),
            );
            expect(_colorDistance(duelColor, fourPlayerColor), greaterThan(45));
          }
        } finally {
          duel.dispose();
          fourPlayer.dispose();
        }
      },
    );

    test('safe stations and launch gates are visually distinct', () async {
      final redStart = await _paintAurora(
        seatColorIds: colors,
        activeSeats: const {0, 1, 2, 3},
      );
      final blueStart = await _paintAurora(
        seatColorIds: const ['blue', 'yellow', 'green', 'red'],
        activeSeats: const {0, 1, 2, 3},
      );

      try {
        final ordinarySafe = await _pixelAt(
          redStart,
          _offsetToPixel(
            LudoBoardThemeResolver.auroraCircuit.geometry.outerTrackCenter(3),
          ),
        );
        final ordinaryPad = await _pixelAt(
          redStart,
          _offsetToPixel(
            LudoBoardThemeResolver.auroraCircuit.geometry.outerTrackCenter(4),
          ),
        );
        expect(_colorDistance(ordinarySafe, ordinaryPad), greaterThan(20));

        final startIndex = ClassicBoard.startOffsetForSeat(0);
        final startPixel = _offsetToPixel(
          LudoBoardThemeResolver.auroraCircuit.geometry.outerTrackCenter(
            startIndex,
          ),
        );
        expect(
          _colorDistance(
            await _pixelAt(redStart, startPixel),
            await _pixelAt(blueStart, startPixel),
          ),
          greaterThan(35),
        );
      } finally {
        redStart.dispose();
        blueStart.dispose();
      }
    });

    test('selectable glow remains visible on the dark circuit pads', () async {
      final center = LudoBoardThemeResolver.auroraCircuit.geometry
          .outerTrackCenter(4);
      final withoutGlow = await _paintAurora(
        seatColorIds: colors,
        activeSeats: const {0, 1, 2, 3},
      );
      final withGlow = await _paintAurora(
        seatColorIds: colors,
        activeSeats: const {0, 1, 2, 3},
        glowCenter: center,
        glowColor: LudoPalette.style(colors.first).bright,
      );

      try {
        final ringPoint = _offsetToPixel(center.translate(22, 0));
        expect(
          _colorDistance(
            await _pixelAt(withoutGlow, ringPoint),
            await _pixelAt(withGlow, ringPoint),
          ),
          greaterThan(100),
        );
      } finally {
        withoutGlow.dispose();
        withGlow.dispose();
      }
    });
  });
}

Future<ui.Image> _paintAurora({
  required List<String> seatColorIds,
  required Set<int> activeSeats,
  Offset? glowCenter,
  Color? glowColor,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  AuroraCircuitBoardPainter(
    seatColorIds: seatColorIds,
    geometry: LudoBoardThemeResolver.auroraCircuit.geometry,
    activeSeats: activeSeats,
  ).paint(canvas, const Size.square(600));
  if (glowCenter != null && glowColor != null) {
    SelectableGlowPainter.draw(
      canvas: canvas,
      center: glowCenter,
      color: glowColor,
      cellSize: LudoBoardThemeResolver.auroraCircuit.geometry.nominalCellExtent,
    );
  }
  return recorder.endRecording().toImage(600, 600);
}

Offset _dockMarkCenter(int seat) {
  final bounds = LudoBoardThemeResolver.auroraCircuit.geometry
      .baseAreaBounds(seat)
      .deflate(40 * 0.28);
  return Offset(bounds.center.dx, bounds.top + 40 * 0.35);
}

(int, int) _offsetToPixel(Offset offset) {
  return (offset.dx.round(), offset.dy.round());
}

Future<Color> _pixelAt(ui.Image image, Object point) async {
  final (int x, int y) = switch (point) {
    Offset value => (value.dx.round(), value.dy.round()),
    (int, int) value => value,
    _ => throw ArgumentError.value(point, 'point'),
  };
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final offset = (y * image.width + x) * 4;
  return Color.fromARGB(
    bytes!.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

int _colorDistance(Color first, Color second) {
  return (first.red - second.red).abs() +
      (first.green - second.green).abs() +
      (first.blue - second.blue).abs();
}
