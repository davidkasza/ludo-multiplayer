import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../controllers/ludo_controller.dart';
import '../game/ludo_board_mapper.dart';
import '../game/ludo_board_theme.dart';
import '../models/ludo_models.dart';
import '../theme/app_colors.dart';
import 'presentation/quick_chat_bubble.dart';
import 'painters/board_painters.dart';

class GameBoard extends StatefulWidget {
  final LudoController controller;

  const GameBoard({super.key, required this.controller});

  static const double maxBoardSize = 500.0;

  @override
  State<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends State<GameBoard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _selectionController;
  bool _reduceMotion = false;
  bool _selectionPending = false;
  int? _selectionTurnVersion;

  LudoController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _selectionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    controller.addListener(_handleControllerChanged);
    _syncSelectionAnimation();
  }

  @override
  void didUpdateWidget(covariant GameBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      controller.addListener(_handleControllerChanged);
      _selectionPending = false;
      _selectionTurnVersion = null;
      _syncSelectionAnimation();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (_reduceMotion != reduceMotion) {
      _reduceMotion = reduceMotion;
      _syncSelectionAnimation();
    }
  }

  void _handleControllerChanged() {
    if (_selectionPending &&
        (controller.visualActiveMove != null ||
            controller.game?.turnVersion != _selectionTurnVersion ||
            !controller.canSelectPiece)) {
      _selectionPending = false;
      _selectionTurnVersion = null;
    }
    _syncSelectionAnimation();
  }

  void _syncSelectionAnimation() {
    final shouldAnimate =
        _hasSelectablePiece && !_selectionPending && !_reduceMotion;
    if (shouldAnimate && !_selectionController.isAnimating) {
      _selectionController.repeat();
    } else if (!shouldAnimate && _selectionController.isAnimating) {
      _selectionController
        ..stop()
        ..value = 0;
    }
  }

  bool get _hasSelectablePiece {
    final game = controller.game;
    if (game == null || !controller.canSelectPiece) return false;
    return controller.getMyPieces().any(
      (piece) =>
          controller.isValidMove(piece: piece, diceValue: game.diceValue),
    );
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    _selectionController.dispose();
    super.dispose();
  }

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
          GameBoard.maxBoardSize,
          min(constraints.maxWidth, constraints.maxHeight),
        );
        final chat = controller.realtimeChat ?? controller.game?.activeChat;
        final chatSeat = chat == null
            ? 0
            : controller.getPlayerIndex(chat.sender);
        final chatStyle = controller.colorStyleForSeat(
          chatSeat < 0 ? 0 : chatSeat,
        );

        return Center(
          child: GestureDetector(
            onTapDown: (details) =>
                unawaited(_handleTap(details, boardSize, boardMapper)),
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
                            _selectionController,
                          ]),
                          builder: (context, _) {
                            return CustomPaint(
                              size: Size.square(boardSize),
                              painter: DynamicPiecesPainter(
                                game: controller.game,
                                currentUserId: controller.user?.uid,
                                myPlayerIndex: controller.myPlayerIndex,
                                canSelectPieces:
                                    controller.canSelectPiece &&
                                    !_selectionPending,
                                animationFrame:
                                    controller.moveAnimationFrameNotifier.value,
                                visualActiveMove: controller.visualActiveMove,
                                visualMoveElapsedMs:
                                    controller.visualMoveElapsedMs,
                                selectionProgress: _selectionController.value,
                                reduceMotion: _reduceMotion,
                                seatColorIds: controller.seatColorIds,
                                boardMapper: boardMapper,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: QuickChatBubble(
                        roomId: controller.gameId,
                        chat: chat,
                        nowMs: controller
                            .estimatedServerNow
                            .millisecondsSinceEpoch,
                        senderSeat: chatSeat,
                        senderName: chat == null
                            ? ''
                            : controller.getPlayerDisplayTitle(chat.sender),
                        color: chatStyle.bright,
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
      case LudoBoardSkin.nusantara:
        return NusantaraBoardPainter(
          seatColorIds: controller.seatColorIds,
          geometry: boardTheme.geometry,
          activeSeats: activeSeats,
        );
    }
  }

  Future<void> _handleTap(
    TapDownDetails details,
    double boardSize,
    LudoBoardMapper boardMapper,
  ) async {
    final game = controller.game;

    if (game == null || !controller.canSelectPiece) return;
    if (controller.myPlayerIndex < 0) return;

    final boardPosition = boardMapper.boardPointFromLocal(
      localPosition: details.localPosition,
      renderedBoardExtent: boardSize,
    );

    int? selectedPieceId;
    for (final piece in controller.getMyPieces()) {
      if (!controller.isValidMove(piece: piece, diceValue: game.diceValue)) {
        continue;
      }

      if (boardMapper.hitTestPiece(
        boardPosition: boardPosition,
        piece: piece,
        playerIndex: controller.myPlayerIndex,
      )) {
        selectedPieceId = piece.id;
        break;
      }
    }

    if (selectedPieceId == null || _selectionPending) return;
    _selectionPending = true;
    _selectionTurnVersion = game.turnVersion;
    _syncSelectionAnimation();
    if (mounted) setState(() {});

    await controller.movePiece(selectedPieceId);
    if (!mounted ||
        controller.visualActiveMove != null ||
        controller.game?.turnVersion != _selectionTurnVersion) {
      return;
    }

    _selectionPending = false;
    _selectionTurnVersion = null;
    _syncSelectionAnimation();
    setState(() {});
  }
}
