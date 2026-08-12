import 'dart:ui';

/// Visual geometry for a board that represents the shared Ludo topology.
///
/// Implementations decide only where logical positions are drawn and hit
/// tested. Movement order, safe positions, captures, and all other game rules
/// remain outside this layer.
abstract class LudoBoardGeometry {
  const LudoBoardGeometry();

  String get boardId;

  double get boardExtent;

  double get nominalCellExtent;

  double get pieceHitTestRadius;

  Offset get boardCenter;

  Rect get goalAreaBounds;

  Rect baseAreaBounds(int seatIndex);

  Rect outerTrackCellBounds(int globalPathIndex);

  Offset outerTrackCenter(int globalPathIndex);

  Offset baseSlotCenter(int seatIndex, int pieceId);

  Rect homeLaneCellBounds(int seatIndex, int homePosition);

  Offset homeLaneCenter(int seatIndex, int homePosition);

  Offset goalCenter(int seatIndex);

  bool containsPieceHitTarget({
    required Offset boardPosition,
    required Offset pieceCenter,
  }) {
    return (boardPosition - pieceCenter).distance <= pieceHitTestRadius;
  }
}
