import 'package:flutter/material.dart';
import '../models/ludo_models.dart';
import 'classic_board.dart';

class LudoBoardMapper {
  static const double baseResolution = 600.0;
  static const double cellSize = baseResolution / 15.0;

  static Offset? getPieceCanvasCoords({
    required LudoPiece piece,
    required bool isPlayerOne,
    required bool isCurrentPlayer,
    required bool isMyTurn,
    LocalMovingPiece? localMovingPiece,
  }) {
    int visualPos = piece.pos;
    bool inHome = piece.inHome;

    if (isMyTurn && isCurrentPlayer && localMovingPiece != null && localMovingPiece.id == piece.id) {
      visualPos = localMovingPiece.currentVisualPos;
      inHome = localMovingPiece.inHome;
    }

    const double step = ClassicBoard.step;
    const double offset = ClassicBoard.offset;

    if (visualPos == -1) {
      var pt = isPlayerOne ? ClassicBoard.player1BaseGrid[piece.id - 1] : ClassicBoard.player2BaseGrid[piece.id - 1];
      return Offset(offset + pt.x * step, offset + pt.y * step);
    } else if (inHome) {
      if (visualPos == 5) {
        return isPlayerOne
            ? Offset(offset + 7.0 * step, offset + 6.5 * step)
            : Offset(offset + 7.0 * step, offset + 8.5 * step);
      }
      var pt = isPlayerOne ? ClassicBoard.p1HomeGrid[visualPos] : ClassicBoard.p2HomeGrid[visualPos];
      return Offset(offset + pt.x * step, offset + pt.y * step);
    } else {
      int actualIndex = isPlayerOne ? visualPos : (visualPos + 26) % 52;
      var pt = ClassicBoard.gridPath[actualIndex];
      return Offset(offset + pt.x * step, offset + pt.y * step);
    }
  }
}