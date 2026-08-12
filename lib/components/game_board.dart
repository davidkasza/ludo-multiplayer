import 'dart:math';

import 'package:flutter/material.dart';

import '../controllers/ludo_controller.dart';
import '../game/classic_board.dart';
import '../game/ludo_board_mapper.dart';
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
                          painter: StaticBoardPainter(
                            seatColorIds: controller.seatColorIds,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: Listenable.merge([
                            controller,
                            controller.moveAnimationFrameNotifier,
                          ]),
                          builder: (context, _) {
                            return CustomPaint(
                              size: Size.square(boardSize),
                              painter: DynamicPiecesPainter(
                                game: controller.game,
                                currentUserId: controller.user?.uid,
                                myPlayerIndex: controller.myPlayerIndex,
                                isMyTurn:
                                    controller.isMyTurn &&
                                    !controller.isDicePresentationActive,
                                animationFrame:
                                    controller.moveAnimationFrameNotifier.value,
                                visualActiveMove:
                                controller.visualActiveMove,
                                visualMoveElapsedMs:
                                controller.visualMoveElapsedMs,
                                seatColorIds: controller.seatColorIds,
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
    final game = controller.game;

    if (game == null || !controller.isMyTurn) return;
    if (!game.hasRolled) return;
    if (controller.visualActiveMove != null ||
        controller.isDicePresentationActive) {
      return;
    }
    if (controller.myPlayerIndex < 0) return;

    final scale = LudoBoardMapper.baseResolution / boardSize;
    final canvasX = details.localPosition.dx * scale;
    final canvasY = details.localPosition.dy * scale;

    for (final piece in controller.getMyPieces()) {
      if (!controller.isValidMove(piece: piece, diceValue: game.diceValue)) {
        continue;
      }

      final coords = LudoBoardMapper.getPieceCanvasCoords(
        piece: piece,
        playerIndex: controller.myPlayerIndex,
      );

      if (coords == null) continue;

      double centerX;
      double centerY;

      if (piece.inHome && piece.pos == 5) {
        final goal = LudoBoardMapper.goalBoardCenter(
          controller.myPlayerIndex,
        );
        centerX = goal.dx;
        centerY = goal.dy;
      } else {
        centerX = ((coords.dx - ClassicBoard.offset) / ClassicBoard.step)
            .roundToDouble() *
            LudoBoardMapper.cellSize +
            LudoBoardMapper.cellSize / 2;

        centerY = ((coords.dy - ClassicBoard.offset) / ClassicBoard.step)
            .roundToDouble() *
            LudoBoardMapper.cellSize +
            LudoBoardMapper.cellSize / 2;
      }

      final distance = sqrt(
        pow(canvasX - centerX, 2) + pow(canvasY - centerY, 2),
      );

      if (distance <= LudoBoardMapper.cellSize * 0.65) {
        controller.movePiece(piece.id);
        break;
      }
    }
  }

}
