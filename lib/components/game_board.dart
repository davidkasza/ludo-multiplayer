import 'dart:math';

import 'package:flutter/material.dart';

import '../controllers/ludo_controller.dart';
import '../game/ludo_board_mapper.dart';
import '../game/ludo_board_theme.dart';
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
        final boardTheme = LudoBoardThemeResolver.resolve(
          controller.game?.boardId,
        );
        final geometry = boardTheme.geometry;
        final boardMapper = LudoBoardMapper(geometry: geometry);
        final activeSeats = LudoGame.seatLayoutForMaxPlayers(
          controller.game?.maxPlayers ?? 4,
        ).toSet();
        final boardSize = min(
          maxBoardSize,
          min(constraints.maxWidth, constraints.maxHeight),
        );

        return Center(
          child: GestureDetector(
            onTapDown: (details) => _handleTap(details, boardSize, boardMapper),
            child: Container(
              width: boardSize,
              height: boardSize,
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: const Color(0xff2d3748), width: 5),
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
                          painter: _staticPainter(
                            boardTheme: boardTheme,
                            activeSeats: activeSeats,
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
                                canSelectPieces: controller.canSelectPiece,
                                animationFrame:
                                    controller.moveAnimationFrameNotifier.value,
                                visualActiveMove: controller.visualActiveMove,
                                visualMoveElapsedMs:
                                    controller.visualMoveElapsedMs,
                                seatColorIds: controller.seatColorIds,
                                boardMapper: boardMapper,
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

  CustomPainter _staticPainter({
    required LudoBoardThemeDefinition boardTheme,
    required Set<int> activeSeats,
  }) {
    switch (boardTheme.skin) {
      case LudoBoardSkin.classic:
        return StaticBoardPainter(
          seatColorIds: controller.seatColorIds,
          geometry: boardTheme.geometry,
        );
      case LudoBoardSkin.auroraCircuit:
        return AuroraCircuitBoardPainter(
          seatColorIds: controller.seatColorIds,
          geometry: boardTheme.geometry,
          activeSeats: activeSeats,
        );
      case LudoBoardSkin.solarisTemple:
        return SolarisTempleBoardPainter(
          seatColorIds: controller.seatColorIds,
          geometry: boardTheme.geometry,
          activeSeats: activeSeats,
        );
    }
  }

  void _handleTap(
    TapDownDetails details,
    double boardSize,
    LudoBoardMapper boardMapper,
  ) {
    final game = controller.game;

    if (game == null || !controller.canSelectPiece) return;
    if (controller.myPlayerIndex < 0) return;

    final boardPosition = boardMapper.boardPointFromLocal(
      localPosition: details.localPosition,
      renderedBoardExtent: boardSize,
    );

    for (final piece in controller.getMyPieces()) {
      if (!controller.isValidMove(piece: piece, diceValue: game.diceValue)) {
        continue;
      }

      if (boardMapper.hitTestPiece(
        boardPosition: boardPosition,
        piece: piece,
        playerIndex: controller.myPlayerIndex,
      )) {
        controller.movePiece(piece.id);
        break;
      }
    }
  }
}
