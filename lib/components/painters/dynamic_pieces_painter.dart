import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/classic_board.dart';
import '../../game/ludo_board_mapper.dart';
import '../../game/ludo_palette.dart';
import '../../models/ludo_models.dart';
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
  final List<String> seatColorIds;

  const DynamicPiecesPainter({
    required this.game,
    required this.currentUserId,
    required this.myPlayerIndex,
    required this.isMyTurn,
    required this.localMovingPiece,
    required this.hopFrame,
    required this.visualActiveMove,
    required this.visualMoveElapsedMs,
    required this.seatColorIds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (game == null || game!.pieces.isEmpty) return;

    const double baseRes = LudoBoardMapper.baseResolution;
    const double cellSize = LudoBoardMapper.cellSize;

    canvas.save();
    canvas.scale(size.width / baseRes);

    final drawables = <DrawablePiece>[];

    for (final playerId in game!.players) {
      final piecesList = game!.pieces[playerId] ?? const <LudoPiece>[];
      final rawPlayerIndex =
          game!.playerSeats[playerId] ?? game!.players.indexOf(playerId);
      final playerIndex = rawPlayerIndex < 0
          ? 0
          : rawPlayerIndex.clamp(0, 3).toInt();
      final isCurrentPlayer = playerId == currentUserId;
      final colorId = seatColorIds.length > playerIndex
          ? seatColorIds[playerIndex]
          : LudoPalette.defaultForSeat(playerIndex);
      final style = LudoPalette.style(colorId);

      for (final piece in piecesList) {
        final activeMove = visualActiveMove;
        final isSharedMoving = activeMove != null &&
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

        final coords = LudoBoardMapper.getPieceCanvasCoords(
          piece: displayPiece,
          playerIndex: playerIndex,
          isCurrentPlayer: isCurrentPlayer,
          isMyTurn: isMyTurn,
          // activeMove already contains the current visual step. Passing
          // localMovingPiece here would overwrite it with the original position,
          // so the piece would only bounce in place and jump at the end.
          localMovingPiece: null,
        );

        if (coords == null) continue;

        final center = _resolvePieceCenter(
          coords: coords,
          piece: displayPiece,
          playerIndex: playerIndex,
        );

        drawables.add(
          DrawablePiece(
            playerId: playerId,
            playerIndex: playerIndex,
            piece: displayPiece,
            isCurrentPlayer: isCurrentPlayer,
            isSharedMoving: isSharedMoving,
            center: center,
            colorBright: style.bright,
            colorDark: style.dark,
          ),
        );
      }
    }

    final groupedPieces = <String, List<DrawablePiece>>{};

    for (final drawable in drawables) {
      final key = '${drawable.center.dx.round()}_${drawable.center.dy.round()}';
      groupedPieces.putIfAbsent(key, () => <DrawablePiece>[]);
      groupedPieces[key]!.add(drawable);
    }

    for (final group in groupedPieces.values) {
      group.sort((a, b) {
        if (a.isSharedMoving != b.isSharedMoving) {
          return a.isSharedMoving ? 1 : -1;
        }

        final playerCompare = a.playerIndex.compareTo(b.playerIndex);
        if (playerCompare != 0) return playerCompare;

        return a.piece.id.compareTo(b.piece.id);
      });

      for (int index = 0; index < group.length; index++) {
        final drawable = group[index];
        var center = drawable.center +
            _getStackOffset(
              index: index,
              count: group.length,
              cellSize: cellSize,
            );

        final isStillMoving = drawable.isSharedMoving &&
            visualActiveMove != null &&
            visualMoveElapsedMs < visualActiveMove!.totalDurationMs;

        if (isStillMoving) {
          center = Offset(
            center.dx,
            center.dy - sin(hopFrame).abs() * (cellSize * 0.45),
          );
        }

        final isAtGoal = drawable.piece.inHome && drawable.piece.pos == 5;

        final isSelectable = drawable.isCurrentPlayer &&
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
          scale: group.length > 1 ? 0.84 : 1.0,
        );
      }
    }

    canvas.restore();
  }

  Offset _resolvePieceCenter({
    required Offset coords,
    required LudoPiece piece,
    required int playerIndex,
  }) {
    const double cellSize = LudoBoardMapper.cellSize;

    double cx = ((coords.dx - ClassicBoard.offset) / ClassicBoard.step)
        .roundToDouble() *
        cellSize +
        cellSize / 2;

    double cy = ((coords.dy - ClassicBoard.offset) / ClassicBoard.step)
        .roundToDouble() *
        cellSize +
        cellSize / 2;

    if (piece.inHome && piece.pos == 5) {
      final goal = LudoBoardMapper.goalBoardCenter(playerIndex);
      cx = goal.dx;
      cy = goal.dy;
    }

    return Offset(cx, cy);
  }

  Offset _getStackOffset({
    required int index,
    required int count,
    required double cellSize,
  }) {
    if (count <= 1) return Offset.zero;

    final offsets = <Offset>[
      Offset(-cellSize * 0.14, -cellSize * 0.14),
      Offset(cellSize * 0.14, -cellSize * 0.14),
      Offset(-cellSize * 0.14, cellSize * 0.14),
      Offset(cellSize * 0.14, cellSize * 0.14),
      Offset.zero,
    ];

    if (index < offsets.length) return offsets[index];

    final ring = 1 + index ~/ offsets.length;
    final angle = (index * 2 * pi) / count;
    return Offset(
      cos(angle) * cellSize * 0.12 * ring,
      sin(angle) * cellSize * 0.12 * ring,
    );
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
        oldDelegate.visualMoveElapsedMs != visualMoveElapsedMs ||
        !_sameColors(oldDelegate.seatColorIds, seatColorIds);
  }

  bool _sameColors(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}