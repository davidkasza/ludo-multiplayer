import 'dart:math';
import 'package:flutter/material.dart';
import '../controllers/ludo_controller.dart';
import '../game/ludo_board_mapper.dart';
import '../models/ludo_models.dart';
import '../theme/app_colors.dart';
import 'painters/board_painters.dart';

class GameBoard extends StatelessWidget {
  final LudoController controller;
  const GameBoard({super.key, required this.controller});

  static const double maxBoardSize = 500.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boardSize = min(maxBoardSize, min(constraints.maxWidth, constraints.maxHeight));

        return Center(
          child: GestureDetector(
            onTapDown: (details) => _handleTap(details, boardSize),
            child: Container(
              width: boardSize,
              height: boardSize,
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: const Color(0xff2d3748), width: 5),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 35, offset: const Offset(0, 12))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        size: Size.square(boardSize),
                        painter: const StaticBoardPainter(),
                      ),
                    ),
                    // Animated token layers
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: controller,
                        builder: (context, _) {
                          return CustomPaint(
                            size: Size.square(boardSize),
                            painter: DynamicPiecesPainter(
                              gameData: controller.gameData,
                              currentUserId: controller.user?.uid,
                              myPlayerIndex: controller.myPlayerIndex,
                              isMyTurn: controller.isMyTurn,
                              localMovingPiece: controller.localMovingPiece,
                              hopFrame: controller.hopFrame,
                            ),
                          );
                        },
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
    if (controller.gameData == null || !controller.isMyTurn) return;

    double scale = LudoBoardMapper.baseResolution / boardSize;
    double canvasX = details.localPosition.dx * scale;
    double canvasY = details.localPosition.dy * scale;

    List<LudoPiece> pieces = controller.getMyPieces();
    for (var p in pieces) {
      var coords = LudoBoardMapper.getPieceCanvasCoords(
        piece: p,
        isPlayerOne: controller.myPlayerIndex == 0,
        isCurrentPlayer: true,
        isMyTurn: controller.isMyTurn,
        localMovingPiece: controller.localMovingPiece,
      );
      if (coords == null) continue;

      double cx = ((coords.dx - 20) / 50).roundToDouble() * LudoBoardMapper.cellSize + LudoBoardMapper.cellSize / 2;
      double cy = ((coords.dy - 20) / 50).roundToDouble() * LudoBoardMapper.cellSize + LudoBoardMapper.cellSize / 2;

      if (p.inHome && p.pos == 5) {
        cx = LudoBoardMapper.baseResolution / 2;
        cy = controller.myPlayerIndex == 0 ? (LudoBoardMapper.cellSize * 6.5) : (LudoBoardMapper.cellSize * 8.5);
      }

      double distance = sqrt(pow(canvasX - cx, 2) + pow(canvasY - cy, 2));
      if (distance <= LudoBoardMapper.cellSize * 0.55) {
        controller.movePiece(p.id);
        break;
      }
    }
  }
}