import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/classic_board.dart';
import '../../game/ludo_animation.dart';
import '../../game/ludo_board_mapper.dart';
import '../../game/ludo_palette.dart';
import '../../game/ludo_rules.dart';
import '../../models/ludo_models.dart';
import 'drawable_piece.dart';
import 'ludo_piece_painter.dart';
import 'selectable_glow_painter.dart';

class DynamicPiecesPainter extends CustomPainter {
  final LudoGame? game;
  final String? currentUserId;
  final int myPlayerIndex;
  final bool isMyTurn;
  final double animationFrame;
  final ActiveMove? visualActiveMove;
  final int visualMoveElapsedMs;
  final List<String> seatColorIds;

  const DynamicPiecesPainter({
    required this.game,
    required this.currentUserId,
    required this.myPlayerIndex,
    required this.isMyTurn,
    required this.animationFrame,
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

        LudoPiece displayPiece = piece;
        Offset? groundCenter;
        var elevation = 0.0;
        var motionScale = 1.0;
        var isMotionActive = false;

        if (isSharedMoving) {
          final frame = LudoAnimation.pieceFrame(
            activeMove,
            visualMoveElapsedMs,
          );
          isMotionActive = !frame.isComplete;
          final fromPiece = piece.copyWith(
            pos: frame.from.pos,
            inHome: frame.from.inHome,
          );
          final toPiece = piece.copyWith(
            pos: frame.to.pos,
            inHome: frame.to.inHome,
          );
          final fromCenter = _pieceCenter(
            piece: fromPiece,
            playerIndex: playerIndex,
          );
          final toCenter = _pieceCenter(
            piece: toPiece,
            playerIndex: playerIndex,
          );
          if (fromCenter != null && toCenter != null) {
            groundCenter = Offset.lerp(
              fromCenter,
              toCenter,
              frame.easedProgress,
            );
            final hopAmount = sin(frame.hopProgress * pi);
            elevation = hopAmount * cellSize * 0.34;
            motionScale += hopAmount * 0.035;
            displayPiece = frame.isComplete ? toPiece : fromPiece;
          }
        }

        groundCenter ??= _pieceCenter(
          piece: displayPiece,
          playerIndex: playerIndex,
        );
        if (groundCenter == null) continue;
        final center = groundCenter.translate(0, -elevation);

        drawables.add(
          DrawablePiece(
            playerId: playerId,
            playerIndex: playerIndex,
            piece: displayPiece,
            isCurrentPlayer: isCurrentPlayer,
            isSharedMoving: isMotionActive,
            center: center,
            groundCenter: groundCenter,
            elevation: elevation,
            motionScale: motionScale,
            colorBright: style.bright,
            colorDark: style.dark,
          ),
        );
      }
    }

    final groupedPieces = <String, List<DrawablePiece>>{};

    for (final drawable in drawables) {
      final key = drawable.isSharedMoving
          ? 'moving_${drawable.playerId}_${drawable.piece.id}'
          : '${drawable.groundCenter.dx.round()}_${drawable.groundCenter.dy.round()}';
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

        final isAtGoal = drawable.piece.inHome && drawable.piece.pos == 5;

        final isSelectable = drawable.isCurrentPlayer &&
            isMyTurn &&
            game!.hasRolled &&
            visualActiveMove == null &&
            LudoRules.isValidMove(drawable.piece, game!.diceValue);

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
          scale: (group.length > 1 ? 0.84 : 1.0) * drawable.motionScale,
          elevation: drawable.elevation,
        );
      }
    }

    canvas.restore();
  }

  Offset? _pieceCenter({required LudoPiece piece, required int playerIndex}) {
    final coords = LudoBoardMapper.getPieceCanvasCoords(
      piece: piece,
      playerIndex: playerIndex,
    );
    if (coords == null) return null;
    return _resolvePieceCenter(
      coords: coords,
      piece: piece,
      playerIndex: playerIndex,
    );
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

  @override
  bool shouldRepaint(covariant DynamicPiecesPainter oldDelegate) {
    return oldDelegate.game != game ||
        oldDelegate.currentUserId != currentUserId ||
        oldDelegate.myPlayerIndex != myPlayerIndex ||
        oldDelegate.isMyTurn != isMyTurn ||
        oldDelegate.animationFrame != animationFrame ||
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
