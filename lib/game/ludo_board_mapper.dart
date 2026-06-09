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

    if (visualPos == -1) {
      var pt = isPlayerOne ? ClassicBoard.player1BaseGrid[piece.id - 1] : ClassicBoard.player2BaseGrid[piece.id - 1];
      return Offset(20.0 + pt.x * 50.0, 20.0 + pt.y * 50.0);
    } else if (inHome) {
      if (visualPos == 5) {
        return isPlayerOne
            ? const Offset(20.0 + 7.0 * 50.0, 20.0 + 6.5 * 50.0)
            : const Offset(20.0 + 7.0 * 50.0, 20.0 + 8.5 * 50.0);
      }
      var pt = isPlayerOne ? ClassicBoard.p1HomeGrid[visualPos] : ClassicBoard.p2HomeGrid[visualPos];
      return Offset(20.0 + pt.x * 50.0, 20.0 + pt.y * 50.0);
    } else {
      int actualIndex = isPlayerOne ? visualPos : (visualPos + 26) % 52;
      var pt = ClassicBoard.gridPath[actualIndex];
      return Offset(20.0 + pt.x * 50.0, 20.0 + pt.y * 50.0);
    }
  }
}