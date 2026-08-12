import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/components/painters/selectable_glow_painter.dart';
import 'package:ludo_game/game/ludo_board_mapper.dart';
import 'package:ludo_game/game/ludo_palette.dart';
import 'package:ludo_game/game/ludo_presentation.dart';
import 'package:ludo_game/models/ludo_models.dart';

void main() {
  bool isSelectable(LudoPiece piece, int diceValue) {
    return LudoPresentation.isPieceSelectable(
      canSelectPieces: true,
      piece: piece,
      diceValue: diceValue,
    );
  }

  group('selectable piece rules', () {
    test('Base piece is selectable only for a six', () {
      const piece = LudoPiece(id: 1, pos: -1, inHome: false);

      for (var dice = 1; dice <= 5; dice++) {
        expect(isSelectable(piece, dice), isFalse);
      }
      expect(isSelectable(piece, 6), isTrue);
    });

    test('start and ordinary board cells remain selectable', () {
      const start = LudoPiece(id: 1, pos: 0, inHome: false);
      const ordinary = LudoPiece(id: 2, pos: 18, inHome: false);
      const safe = LudoPiece(id: 3, pos: 3, inHome: false);

      for (var dice = 1; dice <= 6; dice++) {
        expect(isSelectable(start, dice), isTrue);
        expect(isSelectable(ordinary, dice), isTrue);
        expect(isSelectable(safe, dice), isTrue);
      }
    });

    test('every Home-lane position follows exact-finish validation', () {
      for (var position = 0; position < 5; position++) {
        final piece = LudoPiece(id: 1, pos: position, inHome: true);
        final exactRoll = 5 - position;

        expect(isSelectable(piece, exactRoll), isTrue);
        if (exactRoll < 6) {
          expect(isSelectable(piece, exactRoll + 1), isFalse);
        }
      }

      const finished = LudoPiece(id: 1, pos: 5, inHome: true);
      for (var dice = 1; dice <= 6; dice++) {
        expect(isSelectable(finished, dice), isFalse);
      }
    });

    test('all and only valid pieces are recognized together', () {
      const pieces = [
        LudoPiece(id: 1, pos: -1, inHome: false),
        LudoPiece(id: 2, pos: 0, inHome: false),
        LudoPiece(id: 3, pos: 4, inHome: true),
        LudoPiece(id: 4, pos: 5, inHome: true),
      ];

      final validForOne = pieces
          .where((piece) => isSelectable(piece, 1))
          .map((piece) => piece.id)
          .toList();
      final validForSix = pieces
          .where((piece) => isSelectable(piece, 6))
          .map((piece) => piece.id)
          .toList();

      expect(validForOne, [2, 3]);
      expect(validForSix, [1, 2]);
    });

    test('exactly one and no-valid-move sets are recognized', () {
      const oneValid = [
        LudoPiece(id: 1, pos: -1, inHome: false),
        LudoPiece(id: 2, pos: 0, inHome: true),
        LudoPiece(id: 3, pos: 1, inHome: true),
        LudoPiece(id: 4, pos: 5, inHome: true),
      ];
      const noValid = [
        LudoPiece(id: 1, pos: -1, inHome: false),
        LudoPiece(id: 2, pos: -1, inHome: false),
        LudoPiece(id: 3, pos: 5, inHome: true),
        LudoPiece(id: 4, pos: 5, inHome: true),
      ];

      expect(
        oneValid
            .where((piece) => isSelectable(piece, 5))
            .map((piece) => piece.id),
        [2],
      );
      expect(noValid.where((piece) => isSelectable(piece, 5)), isEmpty);
    });

    test('stacked valid pieces are all recognized', () {
      const stack = [
        LudoPiece(id: 1, pos: 12, inHome: false),
        LudoPiece(id: 2, pos: 12, inHome: false),
      ];

      expect(stack.where((piece) => isSelectable(piece, 4)), hasLength(2));
    });

    test('board-to-Home-lane entry remains selectable', () {
      const piece = LudoPiece(id: 1, pos: 51, inHome: false);

      expect(isSelectable(piece, 1), isTrue);
    });

    test('global presentation gating cannot suggest an illegal move', () {
      const piece = LudoPiece(id: 1, pos: 0, inHome: false);

      expect(
        LudoPresentation.isPieceSelectable(
          canSelectPieces: false,
          piece: piece,
          diceValue: 3,
        ),
        isFalse,
      );
      expect(
        LudoPresentation.canSelectPiece(
          isPlaying: true,
          isAuthoritativeTurn: true,
          hasRolled: true,
          isWaitingForMove: true,
          isDiceRolling: false,
          hasActiveMovePresentation: false,
        ),
        isTrue,
      );
    });

    test('landed extra-turn and reconnect states restore selection', () {
      bool canSelect({bool isDiceRolling = false}) {
        return LudoPresentation.canSelectPiece(
          isPlaying: true,
          isAuthoritativeTurn: true,
          hasRolled: true,
          isWaitingForMove: true,
          isDiceRolling: isDiceRolling,
          hasActiveMovePresentation: false,
        );
      }

      expect(canSelect(isDiceRolling: true), isFalse);
      expect(canSelect(), isTrue);
      expect(canSelect(), isTrue);
    });
  });

  group('selectable coordinates', () {
    test('all four seats map start, Home lane, goal, and every Base slot', () {
      for (var seat = 0; seat < 4; seat++) {
        for (var pieceId = 1; pieceId <= 4; pieceId++) {
          expect(
            LudoBoardMapper.getPieceCanvasCoords(
              piece: LudoPiece(id: pieceId, pos: -1, inHome: false),
              playerIndex: seat,
            ),
            isNotNull,
          );
        }

        expect(
          LudoBoardMapper.getPieceCanvasCoords(
            piece: const LudoPiece(id: 1, pos: 0, inHome: false),
            playerIndex: seat,
          ),
          isNotNull,
        );
        expect(
          LudoBoardMapper.getPieceCanvasCoords(
            piece: const LudoPiece(id: 1, pos: 51, inHome: false),
            playerIndex: seat,
          ),
          isNotNull,
        );

        for (var position = 0; position <= 5; position++) {
          expect(
            LudoBoardMapper.getPieceCanvasCoords(
              piece: LudoPiece(id: 1, pos: position, inHome: true),
              playerIndex: seat,
            ),
            isNotNull,
          );
        }

        expect(
          isSelectable(const LudoPiece(id: 1, pos: 0, inHome: false), 3),
          isTrue,
        );
        expect(
          isSelectable(const LudoPiece(id: 1, pos: 4, inHome: true), 1),
          isTrue,
        );
      }
    });
  });

  group('selectable glow contrast', () {
    testWidgets('remains visible on white and player-coloured cells', (
      tester,
    ) async {
      for (final colorId in LudoPalette.colorIds) {
        final playerColor = LudoPalette.style(colorId).bright;
        final pixels = (await tester.runAsync(() async {
          final whiteCell = await _paintGlow(Colors.white, playerColor);
          final colouredCell = await _paintGlow(playerColor, playerColor);
          final colouredRing = await _pixelAt(whiteCell, 70, 50);
          final neutralRing = await _pixelAt(colouredCell, 72, 50);
          whiteCell.dispose();
          colouredCell.dispose();
          return (colouredRing, neutralRing);
        }))!;

        expect(
          _colorDistance(pixels.$1, Colors.white),
          greaterThan(40),
          reason: '$colorId indicator should contrast with a white cell',
        );
        expect(
          _colorDistance(pixels.$2, playerColor),
          greaterThan(40),
          reason: '$colorId indicator should contrast with its Home lane',
        );
      }
    });
  });
}

Future<ui.Image> _paintGlow(Color background, Color playerColor) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 100, 100),
    Paint()..color = background,
  );
  SelectableGlowPainter.draw(
    canvas: canvas,
    center: const Offset(50, 50),
    color: playerColor,
    cellSize: 40,
  );
  return recorder.endRecording().toImage(100, 100);
}

Future<Color> _pixelAt(ui.Image image, int x, int y) async {
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
