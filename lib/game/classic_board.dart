class BoardPoint {
  final int x;
  final int y;
  const BoardPoint(this.x, this.y);
}

class ClassicBoard {
  static const double step = 50.0;
  static const double offset = 20.0;
  static const int size = 52;

  /// Physical seat order around the board:
  /// 0 = top-left, 1 = bottom-left, 2 = bottom-right, 3 = top-right.
  ///
  /// The coloured start squares, in physical seat order:
  /// 0 = top-left  -> (0, 6), then moves right
  /// 1 = bottom-left -> (6, 14), then moves up
  /// 2 = bottom-right -> (14, 8), then moves left
  /// 3 = top-right -> (8, 0), then moves down
  ///
  /// The shared [gridPath] list is stored in the opposite direction to the
  /// visible movement direction. A piece therefore advances by subtracting
  /// its relative position from the start offset.
  static const List<int> startOffsets = [11, 24, 37, 50];

  static const List<BoardPoint> gridPath = [
    BoardPoint(6, 0),
    BoardPoint(6, 1),
    BoardPoint(6, 2),
    BoardPoint(6, 3),
    BoardPoint(6, 4),
    BoardPoint(6, 5),
    BoardPoint(5, 6),
    BoardPoint(4, 6),
    BoardPoint(3, 6),
    BoardPoint(2, 6),
    BoardPoint(1, 6),
    BoardPoint(0, 6),
    BoardPoint(0, 7),
    BoardPoint(0, 8),
    BoardPoint(1, 8),
    BoardPoint(2, 8),
    BoardPoint(3, 8),
    BoardPoint(4, 8),
    BoardPoint(5, 8),
    BoardPoint(6, 9),
    BoardPoint(6, 10),
    BoardPoint(6, 11),
    BoardPoint(6, 12),
    BoardPoint(6, 13),
    BoardPoint(6, 14),
    BoardPoint(7, 14),
    BoardPoint(8, 14),
    BoardPoint(8, 13),
    BoardPoint(8, 12),
    BoardPoint(8, 11),
    BoardPoint(8, 10),
    BoardPoint(8, 9),
    BoardPoint(9, 8),
    BoardPoint(10, 8),
    BoardPoint(11, 8),
    BoardPoint(12, 8),
    BoardPoint(13, 8),
    BoardPoint(14, 8),
    BoardPoint(14, 7),
    BoardPoint(14, 6),
    BoardPoint(13, 6),
    BoardPoint(12, 6),
    BoardPoint(11, 6),
    BoardPoint(10, 6),
    BoardPoint(9, 6),
    BoardPoint(8, 5),
    BoardPoint(8, 4),
    BoardPoint(8, 3),
    BoardPoint(8, 2),
    BoardPoint(8, 1),
    BoardPoint(8, 0),
    BoardPoint(7, 0),
  ];

  static const List<List<BoardPoint>> baseGrids = [
    [
      BoardPoint(2, 2),
      BoardPoint(3, 2),
      BoardPoint(2, 3),
      BoardPoint(3, 3),
    ],
    [
      BoardPoint(2, 11),
      BoardPoint(3, 11),
      BoardPoint(2, 12),
      BoardPoint(3, 12),
    ],
    [
      BoardPoint(11, 11),
      BoardPoint(12, 11),
      BoardPoint(11, 12),
      BoardPoint(12, 12),
    ],
    [
      BoardPoint(11, 2),
      BoardPoint(12, 2),
      BoardPoint(11, 3),
      BoardPoint(12, 3),
    ],
  ];

  static const List<List<BoardPoint>> homeGrids = [
    // Top-left base: enter the centre from the left.
    [
      BoardPoint(1, 7),
      BoardPoint(2, 7),
      BoardPoint(3, 7),
      BoardPoint(4, 7),
      BoardPoint(5, 7),
      BoardPoint(6, 7),
    ],
    // Bottom-left base: enter the centre from below.
    [
      BoardPoint(7, 13),
      BoardPoint(7, 12),
      BoardPoint(7, 11),
      BoardPoint(7, 10),
      BoardPoint(7, 9),
      BoardPoint(7, 8),
    ],
    // Bottom-right base: enter the centre from the right.
    [
      BoardPoint(13, 7),
      BoardPoint(12, 7),
      BoardPoint(11, 7),
      BoardPoint(10, 7),
      BoardPoint(9, 7),
      BoardPoint(8, 7),
    ],
    // Top-right base: enter the centre from above.
    [
      BoardPoint(7, 1),
      BoardPoint(7, 2),
      BoardPoint(7, 3),
      BoardPoint(7, 4),
      BoardPoint(7, 5),
      BoardPoint(7, 6),
    ],
  ];

  static List<BoardPoint> baseForSeat(int seatIndex) {
    return baseGrids[seatIndex.clamp(0, 3).toInt()];
  }

  static List<BoardPoint> homeForSeat(int seatIndex) {
    return homeGrids[seatIndex.clamp(0, 3).toInt()];
  }

  static int startOffsetForSeat(int seatIndex) {
    return startOffsets[seatIndex.clamp(0, 3).toInt()];
  }

  /// Converts a player's relative track position into the shared 0-51 board
  /// index. Relative position 0 is the coloured start square.
  static int globalPathIndexForSeat(int seatIndex, int relativePos) {
    final start = startOffsetForSeat(seatIndex);
    return (start - relativePos) % size;
  }
}