import 'package:flutter/material.dart';

import '../models/ludo_models.dart';
import 'classic_board.dart';

class LudoBoardMapper {
  static const double baseResolution = 600.0;
  static const double cellSize = baseResolution / 15.0;

  static Offset? getPieceCanvasCoords({
    required LudoPiece piece,
    required int playerIndex,
  }) {
    int visualPos = piece.pos;
    bool inHome = piece.inHome;

    const double step = ClassicBoard.step;
    const double offset = ClassicBoard.offset;
    final safePlayerIndex = playerIndex.clamp(0, 3).toInt();

    if (visualPos == -1) {
      final pt = ClassicBoard.baseForSeat(safePlayerIndex)[piece.id - 1];
      return Offset(offset + pt.x * step, offset + pt.y * step);
    }

    if (inHome) {
      if (visualPos == 5) {
        return goalCanvasCoords(safePlayerIndex);
      }

      final pt = ClassicBoard.homeForSeat(safePlayerIndex)[visualPos];
      return Offset(offset + pt.x * step, offset + pt.y * step);
    }

    final actualIndex = ClassicBoard.globalPathIndexForSeat(
      safePlayerIndex,
      visualPos,
    );
    final pt = ClassicBoard.gridPath[actualIndex];
    return Offset(offset + pt.x * step, offset + pt.y * step);
  }

  static Offset goalCanvasCoords(int playerIndex) {
    const double step = ClassicBoard.step;
    const double offset = ClassicBoard.offset;

    switch (playerIndex.clamp(0, 3).toInt()) {
      case 0:
        return Offset(offset + 6.5 * step, offset + 7.0 * step);
      case 1:
        return Offset(offset + 7.0 * step, offset + 8.5 * step);
      case 2:
        return Offset(offset + 8.5 * step, offset + 7.0 * step);
      case 3:
        return Offset(offset + 7.0 * step, offset + 6.5 * step);
      default:
        return Offset.zero;
    }
  }

  static Offset goalBoardCenter(int playerIndex) {
    switch (playerIndex.clamp(0, 3).toInt()) {
      case 0:
        return const Offset(260, 300);
      case 1:
        return const Offset(300, 340);
      case 2:
        return const Offset(340, 300);
      case 3:
        return const Offset(300, 260);
      default:
        return Offset.zero;
    }
  }
}
