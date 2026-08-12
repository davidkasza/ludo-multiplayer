import 'dart:ui';

import '../models/ludo_models.dart';
import 'classic_board.dart';
import 'ludo_board_geometry.dart';
import 'ludo_rules.dart';

/// Maps serialized logical piece positions onto a selected visual geometry.
class LudoBoardMapper {
  final LudoBoardGeometry geometry;

  const LudoBoardMapper({required this.geometry});

  Offset? pieceCenter({required LudoPiece piece, required int playerIndex}) {
    final seatIndex = playerIndex.clamp(0, 3).toInt();

    if (piece.pos == LudoRules.basePosition) {
      if (piece.id < 1 || piece.id > 4) return null;
      return geometry.baseSlotCenter(seatIndex, piece.id);
    }

    if (piece.inHome) {
      if (piece.pos == LudoRules.goalPosition) {
        return geometry.goalCenter(seatIndex);
      }
      if (piece.pos < 0 || piece.pos >= LudoRules.goalPosition) return null;
      return geometry.homeLaneCenter(seatIndex, piece.pos);
    }

    if (piece.pos < 0 || piece.pos >= ClassicBoard.size) return null;
    final globalPathIndex = ClassicBoard.globalPathIndexForSeat(
      seatIndex,
      piece.pos,
    );
    return geometry.outerTrackCenter(globalPathIndex);
  }

  Offset boardPointFromLocal({
    required Offset localPosition,
    required double renderedBoardExtent,
  }) {
    final scale = geometry.boardExtent / renderedBoardExtent;
    return Offset(localPosition.dx * scale, localPosition.dy * scale);
  }

  bool hitTestPiece({
    required Offset boardPosition,
    required LudoPiece piece,
    required int playerIndex,
  }) {
    final center = pieceCenter(piece: piece, playerIndex: playerIndex);
    return center != null &&
        geometry.containsPieceHitTarget(
          boardPosition: boardPosition,
          pieceCenter: center,
        );
  }
}
