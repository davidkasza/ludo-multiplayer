import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/classic_board.dart';
import '../../game/ludo_board_mapper.dart';
import '../../models/ludo_models.dart';
import '../../theme/app_colors.dart';
import 'drawable_piece.dart';
import 'ludo_piece_painter.dart';
import 'selectable_glow_painter.dart';

class DynamicPiecesPainter extends CustomPainter {
  final LudoGame? game;
  final String? currentUserId;
  final int myPlayerIndex;
  final bool isMyTurn;
  final LocalMovingPiece? localMovingPiece;
  final double hopFrame;
  final ActiveMove? visualActiveMove;
  final int visualMoveElapsedMs;

  const DynamicPiecesPainter({
    required this.game,
    required this.currentUserId,
    required this.myPlayerIndex,
    required this.isMyTurn,
    required this.localMovingPiece,
    required this.hopFrame,
    required this.visualActiveMove,
    required this.visualMoveElapsedMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (game == null || game!.pieces.isEmpty) return;

    const double baseRes = LudoBoardMapper.baseResolution;
    const double cellSize = LudoBoardMapper.cellSize;

    canvas.save();
    canvas.scale(size.width / baseRes);

    final List<DrawablePiece> drawables = [];

    for (final playerId in game!.players) {
      final piecesList = game!.pieces[playerId] ?? [];

      int playerIndex = game!.players.indexOf(playerId);

      if (playerIndex == -1) {
        playerIndex = 0;
      }

      final bool isPlayerOne = playerIndex == 0;
      final bool isCurrentPlayer = playerId == currentUserId;

      final Color colorBright =
      isPlayerOne ? AppColors.blueBright : AppColors.redBright;

      final Color colorDark =
      isPlayerOne ? AppColors.blueDark : AppColors.redDark;

      for (final piece in piecesList) {
        final activeMove = visualActiveMove;

        final bool isSharedMoving = activeMove != null &&
            activeMove.playerId == playerId &&
            activeMove.pieceId == piece.id;

        final LudoPiece displayPiece;

        if (isSharedMoving) {
          final activeStep = activeMove.stepAtElapsed(visualMoveElapsedMs);

          displayPiece = piece.copyWith(
            pos: activeStep.pos,
            inHome: activeStep.inHome,
          );
        } else {
          displayPiece = piece;
        }

        final Offset? coords = LudoBoardMapper.getPieceCanvasCoords(
          piece: displayPiece,
          isPlayerOne: isPlayerOne,
          isCurrentPlayer: isCurrentPlayer,
          isMyTurn: isMyTurn,
          localMovingPiece: null,
        );

        if (coords == null) continue;

        final Offset center = _resolvePieceCenter(
          coords: coords,
          piece: displayPiece,
          isPlayerOne: isPlayerOne,
        );

        drawables.add(
          DrawablePiece(
            playerId: playerId,
            playerIndex: playerIndex,
            piece: displayPiece,
            isCurrentPlayer: isCurrentPlayer,
            isSharedMoving: isSharedMoving,
            center: center,
            colorBright: colorBright,
            colorDark: colorDark,
          ),
        );
      }
    }

    final Map<String, List<DrawablePiece>> groupedPieces = {};

    for (final drawable in drawables) {
      final String key =
          '${drawable.center.dx.round()}_${drawable.center.dy.round()}';

      groupedPieces.putIfAbsent(key, () => []);
      groupedPieces[key]!.add(drawable);
    }

    for (final group in groupedPieces.values) {
      group.sort((a, b) {
        if (a.isSharedMoving != b.isSharedMoving) {
          return a.isSharedMoving ? 1 : -1;
        }

        final playerCompare = a.playerIndex.compareTo(b.playerIndex);

        if (playerCompare != 0) {
          return playerCompare;
        }

        return a.piece.id.compareTo(b.piece.id);
      });

      for (int index = 0; index < group.length; index++) {
        final drawable = group[index];

        Offset center = drawable.center;

        final Offset offset = _getStackOffset(
          index: index,
          count: group.length,
          cellSize: cellSize,
        );

        center = center + offset;

        final bool isStillMoving =
            drawable.isSharedMoving &&
                visualActiveMove != null &&
                visualMoveElapsedMs < visualActiveMove!.totalDurationMs;

        if (isStillMoving) {
          center = Offset(
            center.dx,
            center.dy - sin(hopFrame).abs() * (cellSize * 0.45),
          );
        }

        final bool isAtGoal = drawable.piece.inHome && drawable.piece.pos == 5;

        final bool isSelectable = drawable.isCurrentPlayer &&
            isMyTurn &&
            game!.hasRolled &&
            game!.activeMove == null &&
            visualActiveMove == null &&
            _isValidMove(
              piece: drawable.piece,
              diceValue: game!.diceValue,
            );

        if (isSelectable) {
          SelectableGlowPainter.draw(
            canvas: canvas,
            center: center,
            color: drawable.colorBright,
            cellSize: cellSize,
          );
        }

        LudoPiecePainter.draw(
          canvas: canvas,
          center: center,
          bright: drawable.colorBright,
          dark: drawable.colorDark,
          cellSize: cellSize,
          isAtGoal: isAtGoal,
          scale: group.length > 1 ? 0.88 : 1.0,
        );
      }
    }

    canvas.restore();
  }

  Offset _resolvePieceCenter({
    required Offset coords,
    required LudoPiece piece,
    required bool isPlayerOne,
  }) {
    const double cellSize = LudoBoardMapper.cellSize;
    const double baseRes = LudoBoardMapper.baseResolution;

    double cx = ((coords.dx - ClassicBoard.offset) / ClassicBoard.step)
        .roundToDouble() *
        cellSize +
        cellSize / 2;

    double cy = ((coords.dy - ClassicBoard.offset) / ClassicBoard.step)
        .roundToDouble() *
        cellSize +
        cellSize / 2;

    if (piece.inHome && piece.pos == 5) {
      cx = baseRes / 2;
      cy = isPlayerOne ? cellSize * 6.5 : cellSize * 8.5;
    }

    return Offset(cx, cy);
  }

  Offset _getStackOffset({
    required int index,
    required int count,
    required double cellSize,
  }) {
    if (count <= 1) {
      return Offset.zero;
    }

    final List<Offset> offsets = [
      Offset(-cellSize * 0.13, -cellSize * 0.13),
      Offset(cellSize * 0.13, -cellSize * 0.13),
      Offset(-cellSize * 0.13, cellSize * 0.13),
      Offset(cellSize * 0.13, cellSize * 0.13),
    ];

    return offsets[index % offsets.length];
  }

  bool _isValidMove({
    required LudoPiece piece,
    required int diceValue,
  }) {
    if (piece.pos == 5 && piece.inHome) return false;
    if (piece.pos == -1) return diceValue == 6;
    if (piece.inHome) return piece.pos + diceValue <= 5;

    return true;
  }

  @override
  bool shouldRepaint(covariant DynamicPiecesPainter oldDelegate) {
    return oldDelegate.game != game ||
        oldDelegate.currentUserId != currentUserId ||
        oldDelegate.myPlayerIndex != myPlayerIndex ||
        oldDelegate.isMyTurn != isMyTurn ||
        oldDelegate.localMovingPiece != localMovingPiece ||
        oldDelegate.hopFrame != hopFrame ||
        oldDelegate.visualActiveMove != visualActiveMove ||
        oldDelegate.visualMoveElapsedMs != visualMoveElapsedMs;
  }
}