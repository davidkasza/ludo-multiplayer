import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/classic_board.dart';
import '../../game/ludo_animation.dart';
import '../../game/ludo_board_mapper.dart';
import '../../game/ludo_palette.dart';
import '../../game/ludo_presentation.dart';
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
    final activeMove = visualActiveMove;
    final captureFrame = activeMove == null
        ? const CapturePresentationFrame.complete()
        : LudoPresentation.captureFrame(
            move: activeMove,
            elapsedMs: visualMoveElapsedMs,
          );

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
        final isSharedMoving = activeMove != null &&
            activeMove.playerId == playerId &&
            activeMove.pieceId == piece.id;
        final capturedPiece = _capturedPiece(
          activeMove?.capturedPieces ?? const <ActiveMoveCapture>[],
          playerId,
          piece.id,
        );

        LudoPiece displayPiece = piece;
        Offset? groundCenter;
        var elevation = 0.0;
        var motionScale = 1.0;
        var isMotionActive = false;
        var rotation = 0.0;
        String? animationGroupKey;

        if (isSharedMoving) {
          final frame = LudoAnimation.pieceFrame(
            activeMove,
            visualMoveElapsedMs,
          );
          isMotionActive = !frame.isComplete;
          if (isMotionActive) {
            animationGroupKey = 'moving_${activeMove.playerId}_${piece.id}';
          }
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

        if (capturedPiece != null &&
            captureFrame.phase != CapturePresentationPhase.complete) {
          final capturedDisplayPiece = piece.copyWith(
            pos: capturedPiece.from.pos,
            inHome: capturedPiece.from.inHome,
          );
          final basePiece = piece.copyWith(
            pos: LudoRules.basePosition,
            inHome: false,
          );
          final captureCenter = _pieceCenter(
            piece: capturedDisplayPiece,
            playerIndex: playerIndex,
          );
          final baseCenter = _pieceCenter(
            piece: basePiece,
            playerIndex: playerIndex,
          );

          if (captureCenter != null && baseCenter != null) {
            displayPiece = capturedDisplayPiece;
            isMotionActive = true;
            elevation = 0;

            switch (captureFrame.phase) {
              case CapturePresentationPhase.approaching:
                groundCenter = captureCenter;
                animationGroupKey =
                    'capture_${captureCenter.dx.round()}_${captureCenter.dy.round()}';
                break;
              case CapturePresentationPhase.impact:
                groundCenter = captureCenter.translate(
                  captureFrame.impactShake * cellSize * 0.075,
                  0,
                );
                animationGroupKey =
                    'capture_${captureCenter.dx.round()}_${captureCenter.dy.round()}';
                motionScale = 1 - captureFrame.impactPulse * 0.12;
                rotation = captureFrame.impactShake * 0.08;
                break;
              case CapturePresentationPhase.returning:
                groundCenter = Offset.lerp(
                  captureCenter,
                  baseCenter,
                  captureFrame.returnProgress,
                );
                animationGroupKey =
                    'return_${capturedPiece.playerId}_${capturedPiece.pieceId}';
                break;
              case CapturePresentationPhase.complete:
                break;
            }
          }
        }

        if (isSharedMoving &&
            captureFrame.phase == CapturePresentationPhase.impact) {
          motionScale *= 1 + captureFrame.impactPulse * 0.10;
          isMotionActive = true;
          animationGroupKey = 'attacker_${activeMove.playerId}_${piece.id}';
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
            animationGroupKey: animationGroupKey,
            center: center,
            groundCenter: groundCenter,
            elevation: elevation,
            motionScale: motionScale,
            rotation: rotation,
            colorBright: style.bright,
            colorDark: style.dark,
          ),
        );
      }
    }

    final groupedPieces = <String, List<DrawablePiece>>{};

    for (final drawable in drawables) {
      final key =
          drawable.animationGroupKey ??
          '${drawable.groundCenter.dx.round()}_${drawable.groundCenter.dy.round()}';
      groupedPieces.putIfAbsent(key, () => <DrawablePiece>[]);
      groupedPieces[key]!.add(drawable);
    }

    _drawCaptureImpact(
      canvas: canvas,
      activeMove: activeMove,
      frame: captureFrame,
      cellSize: cellSize,
    );

    final groups = groupedPieces.values.toList(growable: false);
    final orderedGroups = <List<DrawablePiece>>[
      ...groups.where((group) => !_containsAttacker(group, activeMove)),
      ...groups.where((group) => _containsAttacker(group, activeMove)),
    ];

    for (final group in orderedGroups) {
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

        if (drawable.rotation != 0) {
          canvas.save();
          canvas.translate(center.dx, center.dy);
          canvas.rotate(drawable.rotation);
          canvas.translate(-center.dx, -center.dy);
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

        if (drawable.rotation != 0) canvas.restore();
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

  ActiveMoveCapture? _capturedPiece(
    List<ActiveMoveCapture> capturedPieces,
    String playerId,
    int pieceId,
  ) {
    for (final captured in capturedPieces) {
      if (captured.playerId == playerId && captured.pieceId == pieceId) {
        return captured;
      }
    }
    return null;
  }

  bool _containsAttacker(List<DrawablePiece> group, ActiveMove? activeMove) {
    if (activeMove == null) return false;
    return group.any(
      (drawable) =>
          drawable.playerId == activeMove.playerId &&
          drawable.piece.id == activeMove.pieceId,
    );
  }

  void _drawCaptureImpact({
    required Canvas canvas,
    required ActiveMove? activeMove,
    required CapturePresentationFrame frame,
    required double cellSize,
  }) {
    if (activeMove == null ||
        activeMove.capturedPieces.isEmpty ||
        frame.phase != CapturePresentationPhase.impact) {
      return;
    }

    final captured = activeMove.capturedPieces.first;
    final playerIndex =
        game!.playerSeats[captured.playerId] ??
        game!.players.indexOf(captured.playerId);
    if (playerIndex < 0) return;

    final capturedPiece = LudoPiece(
      id: captured.pieceId,
      pos: captured.from.pos,
      inHome: captured.from.inHome,
    );
    final center = _pieceCenter(piece: capturedPiece, playerIndex: playerIndex);
    if (center == null) return;

    final attackerIndex =
        game!.playerSeats[activeMove.playerId] ??
        game!.players.indexOf(activeMove.playerId);
    final colorId = attackerIndex >= 0 && seatColorIds.length > attackerIndex
        ? seatColorIds[attackerIndex]
        : LudoPalette.defaultForSeat(attackerIndex.clamp(0, 3));
    final color = LudoPalette.style(colorId).bright;
    final progress = frame.impactProgress;
    final opacity = (1 - progress) * 0.75;
    final radius = cellSize * (0.28 + progress * 0.72);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withOpacity(opacity * 0.16)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.07,
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
