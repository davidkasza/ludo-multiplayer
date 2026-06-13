import 'dart:math';

import 'package:flutter/material.dart';

import '../controllers/ludo_controller.dart';
import '../game/ludo_board_mapper.dart';
import '../models/ludo_models.dart';
import '../theme/app_colors.dart';
import 'painters/board_painters.dart';

class GameBoard extends StatelessWidget {
  final LudoController controller;

  const GameBoard({
    super.key,
    required this.controller,
  });

  static const double maxBoardSize = 500.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boardSize = min(
          maxBoardSize,
          min(constraints.maxWidth, constraints.maxHeight),
        );

        return Center(
          child: GestureDetector(
            onTapDown: (details) => _handleTap(details, boardSize),
            child: Container(
              width: boardSize,
              height: boardSize,
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(
                  color: const Color(0xff2d3748),
                  width: 5,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 35,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size.square(boardSize),
                          painter: const StaticBoardPainter(),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: Listenable.merge([
                            controller,
                            controller.hopFrameNotifier,
                          ]),
                          builder: (context, _) {
                            return CustomPaint(
                              size: Size.square(boardSize),
                              painter: DynamicPiecesPainter(
                                game: controller.game,
                                currentUserId: controller.user?.uid,
                                myPlayerIndex: controller.myPlayerIndex,
                                isMyTurn: controller.isMyTurn,
                                localMovingPiece: controller.localMovingPiece,
                                hopFrame: controller.hopFrameNotifier.value,
                                visualActiveMove: controller.visualActiveMove,
                                visualMoveElapsedMs:
                                controller.visualMoveElapsedMs,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleTap(TapDownDetails details, double boardSize) {
    if (controller.game == null || !controller.isMyTurn) return;
    if (controller.game?.hasRolled != true) return;
    if (controller.game?.activeMove != null) return;
    if (controller.visualActiveMove != null) return;
    if (controller.localMovingPiece != null) return;

    final scale = LudoBoardMapper.baseResolution / boardSize;
    final canvasX = details.localPosition.dx * scale;
    final canvasY = details.localPosition.dy * scale;

    final pieces = controller.getMyPieces();

    for (final p in pieces) {
      final coords = LudoBoardMapper.getPieceCanvasCoords(
        piece: p,
        isPlayerOne: controller.myPlayerIndex == 0,
        isCurrentPlayer: true,
        isMyTurn: controller.isMyTurn,
        localMovingPiece: null,
      );

      if (coords == null) continue;

      double cx = ((coords.dx - 20) / 50).roundToDouble() *
          LudoBoardMapper.cellSize +
          LudoBoardMapper.cellSize / 2;

      double cy = ((coords.dy - 20) / 50).roundToDouble() *
          LudoBoardMapper.cellSize +
          LudoBoardMapper.cellSize / 2;

      if (p.inHome && p.pos == 5) {
        cx = LudoBoardMapper.baseResolution / 2;
        cy = controller.myPlayerIndex == 0
            ? LudoBoardMapper.cellSize * 6.5
            : LudoBoardMapper.cellSize * 8.5;
      }

      final distance = sqrt(
        pow(canvasX - cx, 2) + pow(canvasY - cy, 2),
      );

      if (distance <= LudoBoardMapper.cellSize * 0.65) {
        controller.movePiece(p.id);
        break;
      }
    }
  }
}