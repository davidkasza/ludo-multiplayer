import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/components/painters/nusantara_board_painter.dart';
import 'package:ludo_game/game/classic_board.dart';
import 'package:ludo_game/game/classic_grid_geometry.dart';
import 'package:ludo_game/game/ludo_animation.dart';
import 'package:ludo_game/game/ludo_board_mapper.dart';
import 'package:ludo_game/game/ludo_board_theme.dart';
import 'package:ludo_game/models/ludo_models.dart';

void main() {
  group('Nusantara geometry compatibility', () {
    final classic = LudoBoardThemeResolver.classic.geometry;
    final nusantara = LudoBoardThemeResolver.nusantara.geometry;
    final mapper = LudoBoardMapper(geometry: nusantara);

    test('uses the exact Classic geometry for every logical destination', () {
      expect(nusantara, isA<ClassicGridGeometry>());
      expect(nusantara.boardExtent, classic.boardExtent);
      expect(nusantara.nominalCellExtent, classic.nominalCellExtent);
      expect(nusantara.pieceHitTestRadius, classic.pieceHitTestRadius);
      expect(nusantara.goalAreaBounds, classic.goalAreaBounds);

      for (int index = 0; index < ClassicBoard.size; index++) {
        expect(
          nusantara.outerTrackCenter(index),
          classic.outerTrackCenter(index),
        );
        expect(
          nusantara.outerTrackCellBounds(index),
          classic.outerTrackCellBounds(index),
        );
      }

      for (int seat = 0; seat < 4; seat++) {
        for (int pieceId = 1; pieceId <= 4; pieceId++) {
          expect(
            nusantara.baseSlotCenter(seat, pieceId),
            classic.baseSlotCenter(seat, pieceId),
          );
        }
        for (int homePosition = 0; homePosition < 5; homePosition++) {
          expect(
            nusantara.homeLaneCenter(seat, homePosition),
            classic.homeLaneCenter(seat, homePosition),
          );
        }
        expect(nusantara.goalCenter(seat), classic.goalCenter(seat));
      }
    });

    test('keeps hit testing and animation endpoints aligned for all seats', () {
      for (int seat = 0; seat < 4; seat++) {
        for (int pieceId = 1; pieceId <= 4; pieceId++) {
          final basePiece = LudoPiece(id: pieceId, pos: -1, inHome: false);
          final baseCenter = mapper.pieceCenter(
            piece: basePiece,
            playerIndex: seat,
          )!;
          expect(baseCenter, nusantara.baseSlotCenter(seat, pieceId));
          expect(
            mapper.hitTestPiece(
              boardPosition: baseCenter,
              piece: basePiece,
              playerIndex: seat,
            ),
            isTrue,
          );

          final baseExit = ActiveMove(
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
          final frame = LudoAnimation.pieceFrame(baseExit, 125);
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
            nusantara.outerTrackCenter(ClassicBoard.startOffsetForSeat(seat)),
          );
        }

        for (int homePosition = 0; homePosition < 5; homePosition++) {
          final piece = LudoPiece(id: 1, pos: homePosition, inHome: true);
          expect(
            mapper.pieceCenter(piece: piece, playerIndex: seat),
            nusantara.homeLaneCenter(seat, homePosition),
          );
        }
        expect(
          mapper.pieceCenter(
            piece: const LudoPiece(id: 1, pos: 5, inHome: true),
            playerIndex: seat,
          ),
          nusantara.goalCenter(seat),
        );
      }
    });

    test('uses opposite seats for duel mode without separate geometry', () {
      expect(LudoGame.seatLayoutForMaxPlayers(2), const [0, 2]);
      expect(
        LudoBoardThemeResolver.nusantara.geometry.runtimeType,
        LudoBoardThemeResolver.classic.geometry.runtimeType,
      );
    });
  });

  group('Nusantara static presentation', () {
    const colors = ['red', 'yellow', 'green', 'blue'];

    test(
      'the arena is green while movement pads remain high contrast',
      () async {
        final image = await _paintNusantara(
          seatColorIds: colors,
          activeSeats: const {0, 1, 2, 3},
        );
        try {
          final greenSurface = await _pixelAt(image, const Offset(220, 180));
          final pathSurface = await _pixelAt(
            image,
            LudoBoardThemeResolver.nusantara.geometry.outerTrackCenter(4),
          );

          expect(greenSurface.green, greaterThan(greenSurface.red));
          expect(greenSurface.green, greaterThan(greenSurface.blue));
          expect(
            _luminanceDistance(pathSurface, greenSurface),
            greaterThan(0.25),
          );
        } finally {
          image.dispose();
        }
      },
    );

    test('all physical courtyards use their runtime seat color', () async {
      final baseline = await _paintNusantara(
        seatColorIds: colors,
        activeSeats: const {0, 1, 2, 3},
      );
      try {
        for (int seat = 0; seat < 4; seat++) {
          final changedColors = List<String>.from(colors);
          changedColors[seat] = colors[(seat + 2) % 4];
          final changed = await _paintNusantara(
            seatColorIds: changedColors,
            activeSeats: const {0, 1, 2, 3},
          );
          try {
            expect(
              _colorDistance(
                await _pixelAt(baseline, _socketAccentSample(seat)),
                await _pixelAt(changed, _socketAccentSample(seat)),
              ),
              greaterThan(25),
              reason: 'seat $seat must use its runtime courtyard color',
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
      'duel mode emphasizes seats 0 and 2 and dormants seats 1 and 3',
      () async {
        final duel = await _paintNusantara(
          seatColorIds: colors,
          activeSeats: LudoGame.seatLayoutForMaxPlayers(2).toSet(),
        );
        final fourPlayer = await _paintNusantara(
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

    test('safe rosettes and launch gateways stay visually distinct', () async {
      final image = await _paintNusantara(
        seatColorIds: colors,
        activeSeats: const {0, 1, 2, 3},
      );
      try {
        final geometry = LudoBoardThemeResolver.nusantara.geometry;
        final safeCenter = geometry.outerTrackCenter(3);
        final normalCenter = geometry.outerTrackCenter(4);
        expect(
          _colorDistance(
            await _pixelAt(image, safeCenter),
            await _pixelAt(image, normalCenter),
          ),
          greaterThan(45),
        );

        final startCenter = geometry.outerTrackCenter(
          ClassicBoard.startOffsetForSeat(0),
        );
        expect(
          _colorDistance(
            await _pixelAt(image, startCenter.translate(-6, 0)),
            await _pixelAt(image, safeCenter.translate(-6, 0)),
          ),
          greaterThan(25),
        );
      } finally {
        image.dispose();
      }
    });
  });
}

Future<ui.Image> _paintNusantara({
  required List<String> seatColorIds,
  required Set<int> activeSeats,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  NusantaraBoardPainter(
    seatColorIds: seatColorIds,
    geometry: LudoBoardThemeResolver.nusantara.geometry,
    activeSeats: activeSeats,
  ).paint(canvas, const Size.square(600));
  return recorder.endRecording().toImage(600, 600);
}

Offset _socketAccentSample(int seat) {
  final geometry = LudoBoardThemeResolver.nusantara.geometry;
  return geometry
      .baseSlotCenter(seat, 1)
      .translate(geometry.nominalCellExtent * 0.31, 0);
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

double _luminanceDistance(Color first, Color second) {
  return (first.computeLuminance() - second.computeLuminance()).abs();
}
