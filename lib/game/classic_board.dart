class BoardPoint {
  final int x;
  final int y;
  const BoardPoint(this.x, this.y);
}

class ClassicBoard {
  static const double step = 50.0;
  static const double offset = 20.0;
  static const int size = 52;

  static const List<BoardPoint> gridPath = [
    BoardPoint(6, 0), BoardPoint(6, 1), BoardPoint(6, 2), BoardPoint(6, 3), BoardPoint(6, 4), BoardPoint(6, 5),

    BoardPoint(5, 6), BoardPoint(4, 6), BoardPoint(3, 6), BoardPoint(2, 6), BoardPoint(1, 6), BoardPoint(0, 6),
    BoardPoint(0, 7),
    BoardPoint(0, 8), BoardPoint(1, 8), BoardPoint(2, 8), BoardPoint(3, 8), BoardPoint(4, 8), BoardPoint(5, 8),

    BoardPoint(6, 9), BoardPoint(6, 10), BoardPoint(6, 11), BoardPoint(6, 12), BoardPoint(6, 13), BoardPoint(6, 14),
    BoardPoint(7, 14),
    BoardPoint(8, 14), BoardPoint(8, 13), BoardPoint(8, 12), BoardPoint(8, 11), BoardPoint(8, 10), BoardPoint(8, 9),

    BoardPoint(9, 8), BoardPoint(10, 8), BoardPoint(11, 8), BoardPoint(12, 8), BoardPoint(13, 8), BoardPoint(14, 8),
    BoardPoint(14, 7),
    BoardPoint(14, 6), BoardPoint(13, 6), BoardPoint(12, 6), BoardPoint(11, 6), BoardPoint(10, 6), BoardPoint(9, 6),

    BoardPoint(8, 5), BoardPoint(8, 4), BoardPoint(8, 3), BoardPoint(8, 2), BoardPoint(8, 1), BoardPoint(8, 0),
    BoardPoint(7, 0)
  ];

  static const List<BoardPoint> player1BaseGrid = [BoardPoint(2, 2), BoardPoint(3, 2), BoardPoint(2, 3), BoardPoint(3, 3)];
  static const List<BoardPoint> player2BaseGrid = [BoardPoint(11, 11), BoardPoint(12, 11), BoardPoint(11, 12), BoardPoint(12, 12)];

  static const List<BoardPoint> p1HomeGrid = [
    BoardPoint(7, 1), BoardPoint(7, 2), BoardPoint(7, 3), BoardPoint(7, 4), BoardPoint(7, 5), BoardPoint(7, 6)
  ];

  static const List<BoardPoint> p2HomeGrid = [
    BoardPoint(7, 13), BoardPoint(7, 12), BoardPoint(7, 11), BoardPoint(7, 10), BoardPoint(7, 9), BoardPoint(7, 8)
  ];
}