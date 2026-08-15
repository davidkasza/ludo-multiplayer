import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/components/painters/solaris_temple_board_painter.dart';
import 'package:ludo_game/game/classic_board.dart';
import 'package:ludo_game/game/classic_grid_geometry.dart';
import 'package:ludo_game/game/ludo_animation.dart';
import 'package:ludo_game/game/ludo_board_mapper.dart';
import 'package:ludo_game/game/ludo_board_theme.dart';
import 'package:ludo_game/models/ludo_models.dart';

void main() {
  group('Solaris Temple geometry compatibility', () {
    final classic = LudoBoardThemeResolver.classic.geometry;
    final solaris = LudoBoardThemeResolver.solarisTemple.geometry;
    final mapper = LudoBoardMapper(geometry: solaris);

    test('uses exact Classic geometry for every logical destination', () {
      expect(solaris, isA<ClassicGridGeometry>());
      expect(solaris.boardExtent, classic.boardExtent);
      expect(solaris.nominalCellExtent, classic.nominalCellExtent);
      expect(solaris.pieceHitTestRadius, classic.pieceHitTestRadius);
      expect(solaris.goalAreaBounds, classic.goalAreaBounds);

      for (int index = 0; index < ClassicBoard.size; index++) {
        expect(
          solaris.outerTrackCenter(index),
          classic.outerTrackCenter(index),
        );
        expect(
          solaris.outerTrackCellBounds(index),
          classic.outerTrackCellBounds(index),
        );
      }

      for (int seat = 0; seat < 4; seat++) {
        for (int pieceId = 1; pieceId <= 4; pieceId++) {
          expect(
            solaris.baseSlotCenter(seat, pieceId),
            classic.baseSlotCenter(seat, pieceId),
          );
        }
        for (int homePosition = 0; homePosition < 5; homePosition++) {
          expect(
            solaris.homeLaneCenter(seat, homePosition),
            classic.homeLaneCenter(seat, homePosition),
          );
        }
        expect(solaris.goalCenter(seat), classic.goalCenter(seat));
      }
    });

    test('keeps hit tests and animation endpoints aligned for all seats', () {
      for (int seat = 0; seat < 4; seat++) {
        for (int pieceId = 1; pieceId <= 4; pieceId++) {
          final basePiece = LudoPiece(id: pieceId, pos: -1, inHome: false);
          final baseCenter = mapper.pieceCenter(
            piece: basePiece,
            playerIndex: seat,
          )!;
          expect(baseCenter, solaris.baseSlotCenter(seat, pieceId));
          expect(
            mapper.hitTestPiece(
              boardPosition: baseCenter,
              piece: basePiece,
              playerIndex: seat,
            ),
            isTrue,
          );

          final exit = ActiveMove(
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
          final frame = LudoAnimation.pieceFrame(exit, 125);
          expect(frame.isBaseExit, isTrue);
          expect(
            mapper.pieceCenter(
              piece: LudoPiece(
                id: pieceId,
                pos: frame.to.pos,
                inHome: frame.to.inHome,
              ),
              playerIndex: seat,
            ),
            solaris.outerTrackCenter(ClassicBoard.startOffsetForSeat(seat)),
          );
        }

        for (int homePosition = 0; homePosition < 5; homePosition++) {
          final homePiece = LudoPiece(id: 1, pos: homePosition, inHome: true);
          expect(
            mapper.pieceCenter(piece: homePiece, playerIndex: seat),
            solaris.homeLaneCenter(seat, homePosition),
          );
        }

        const goalPiece = LudoPiece(id: 1, pos: 5, inHome: true);
        expect(
          mapper.pieceCenter(piece: goalPiece, playerIndex: seat),
          solaris.goalCenter(seat),
        );
      }
    });

    test('two-player mode keeps opposite seats on the same geometry', () {
      expect(LudoGame.seatLayoutForMaxPlayers(2), const [0, 2]);
      expect(LudoGame.seatLayoutForMaxPlayers(4), const [0, 1, 2, 3]);
      expect(
        LudoBoardThemeResolver.solarisTemple.geometry.runtimeType,
        LudoBoardThemeResolver.classic.geometry.runtimeType,
      );
    });
  });

  group('Solaris Temple static presentation', () {
    const colors = ['red', 'yellow', 'green', 'blue'];

    test('all runtime seat colors affect their physical courtyards', () async {
      final baseline = await _paintSolaris(
        seatColorIds: colors,
        activeSeats: const {0, 1, 2, 3},
      );

      try {
        for (int seat = 0; seat < 4; seat++) {
          final changedColors = List<String>.from(colors);
          changedColors[seat] = colors[(seat + 2) % 4];
          final changed = await _paintSolaris(
            seatColorIds: changedColors,
            activeSeats: const {0, 1, 2, 3},
          );
          try {
            final sample = _socketAccentSample(seat);
            expect(
              _colorDistance(
                await _pixelAt(baseline, sample),
                await _pixelAt(changed, sample),
              ),
              greaterThan(25),
              reason: 'seat $seat must use its runtime enamel color',
            );
          } finally {
            changed.dispose();
          }
        }
      } finally {
        baseline.dispose();
      }
    });

    test(
      'duel mode keeps seats 0 and 2 active and dims seats 1 and 3',
      () async {
        final duel = await _paintSolaris(
          seatColorIds: colors,
          activeSeats: LudoGame.seatLayoutForMaxPlayers(2).toSet(),
        );
        final fourPlayer = await _paintSolaris(
          seatColorIds: colors,
          activeSeats: LudoGame.seatLayoutForMaxPlayers(4).toSet(),
        );

        try {
          for (final activeSeat in const [0, 2]) {
            expect(
              await _pixelAt(duel, _socketAccentSample(activeSeat)),
              await _pixelAt(fourPlayer, _socketAccentSample(activeSeat)),
            );
          }
          for (final dormantSeat in const [1, 3]) {
            expect(
              _colorDistance(
                await _pixelAt(duel, _socketAccentSample(dormantSeat)),
                await _pixelAt(fourPlayer, _socketAccentSample(dormantSeat)),
              ),
              greaterThan(35),
            );
          }
        } finally {
          duel.dispose();
          fourPlayer.dispose();
        }
      },
    );

    test(
      'safe medallions and launch gateways remain visually distinct',
      () async {
        final image = await _paintSolaris(
          seatColorIds: colors,
          activeSeats: const {0, 1, 2, 3},
        );
        try {
          final geometry = LudoBoardThemeResolver.solarisTemple.geometry;
          final safeCenter = geometry.outerTrackCenter(3);
          final normalCenter = geometry.outerTrackCenter(4);
          expect(
            _colorDistance(
              await _pixelAt(image, safeCenter),
              await _pixelAt(image, normalCenter),
            ),
            greaterThan(35),
          );

          final startCenter = geometry.outerTrackCenter(
            ClassicBoard.startOffsetForSeat(0),
          );
          expect(
            _colorDistance(
              await _pixelAt(image, startCenter),
              await _pixelAt(image, safeCenter),
            ),
            greaterThan(25),
          );
        } finally {
          image.dispose();
        }
      },
    );
  });
}

Future<ui.Image> _paintSolaris({
  required List<String> seatColorIds,
  required Set<int> activeSeats,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  SolarisTempleBoardPainter(
    seatColorIds: seatColorIds,
    geometry: LudoBoardThemeResolver.solarisTemple.geometry,
    activeSeats: activeSeats,
  ).paint(canvas, const Size.square(600));
  return recorder.endRecording().toImage(600, 600);
}

Offset _socketAccentSample(int seat) {
  final geometry = LudoBoardThemeResolver.solarisTemple.geometry;
  return geometry
      .baseSlotCenter(seat, 1)
      .translate(geometry.nominalCellExtent * 0.27, 0);
}

Future<Color> _pixelAt(ui.Image image, Offset point) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final x = point.dx.round().clamp(0, image.width - 1);
  final y = point.dy.round().clamp(0, image.height - 1);
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
