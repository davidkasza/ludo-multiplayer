import 'dart:ui';

import 'ludo_board_geometry.dart';

/// The original 15-by-15 Classic board geometry in 600 logical pixels.
///
/// These coordinates intentionally preserve every center and cell boundary
/// used by the existing Classic renderer.
class ClassicGridGeometry extends LudoBoardGeometry {
  const ClassicGridGeometry();

  static const double _boardExtent = 600;
  static const double _cellExtent = _boardExtent / 15;

  static const List<_GridPoint> _outerTrack = [
    _GridPoint(6, 0),
    _GridPoint(6, 1),
    _GridPoint(6, 2),
    _GridPoint(6, 3),
    _GridPoint(6, 4),
    _GridPoint(6, 5),
    _GridPoint(5, 6),
    _GridPoint(4, 6),
    _GridPoint(3, 6),
    _GridPoint(2, 6),
    _GridPoint(1, 6),
    _GridPoint(0, 6),
    _GridPoint(0, 7),
    _GridPoint(0, 8),
    _GridPoint(1, 8),
    _GridPoint(2, 8),
    _GridPoint(3, 8),
    _GridPoint(4, 8),
    _GridPoint(5, 8),
    _GridPoint(6, 9),
    _GridPoint(6, 10),
    _GridPoint(6, 11),
    _GridPoint(6, 12),
    _GridPoint(6, 13),
    _GridPoint(6, 14),
    _GridPoint(7, 14),
    _GridPoint(8, 14),
    _GridPoint(8, 13),
    _GridPoint(8, 12),
    _GridPoint(8, 11),
    _GridPoint(8, 10),
    _GridPoint(8, 9),
    _GridPoint(9, 8),
    _GridPoint(10, 8),
    _GridPoint(11, 8),
    _GridPoint(12, 8),
    _GridPoint(13, 8),
    _GridPoint(14, 8),
    _GridPoint(14, 7),
    _GridPoint(14, 6),
    _GridPoint(13, 6),
    _GridPoint(12, 6),
    _GridPoint(11, 6),
    _GridPoint(10, 6),
    _GridPoint(9, 6),
    _GridPoint(8, 5),
    _GridPoint(8, 4),
    _GridPoint(8, 3),
    _GridPoint(8, 2),
    _GridPoint(8, 1),
    _GridPoint(8, 0),
    _GridPoint(7, 0),
  ];

  static const List<List<_GridPoint>> _baseSlots = [
    [_GridPoint(2, 2), _GridPoint(3, 2), _GridPoint(2, 3), _GridPoint(3, 3)],
    [
      _GridPoint(2, 11),
      _GridPoint(3, 11),
      _GridPoint(2, 12),
      _GridPoint(3, 12),
    ],
    [
      _GridPoint(11, 11),
      _GridPoint(12, 11),
      _GridPoint(11, 12),
      _GridPoint(12, 12),
    ],
    [
      _GridPoint(11, 2),
      _GridPoint(12, 2),
      _GridPoint(11, 3),
      _GridPoint(12, 3),
    ],
  ];

  static const List<List<_GridPoint>> _homeLanes = [
    [
      _GridPoint(1, 7),
      _GridPoint(2, 7),
      _GridPoint(3, 7),
      _GridPoint(4, 7),
      _GridPoint(5, 7),
    ],
    [
      _GridPoint(7, 13),
      _GridPoint(7, 12),
      _GridPoint(7, 11),
      _GridPoint(7, 10),
      _GridPoint(7, 9),
    ],
    [
      _GridPoint(13, 7),
      _GridPoint(12, 7),
      _GridPoint(11, 7),
      _GridPoint(10, 7),
      _GridPoint(9, 7),
    ],
    [
      _GridPoint(7, 1),
      _GridPoint(7, 2),
      _GridPoint(7, 3),
      _GridPoint(7, 4),
      _GridPoint(7, 5),
    ],
  ];

  static const List<_GridPoint> _baseOrigins = [
    _GridPoint(0, 0),
    _GridPoint(0, 9),
    _GridPoint(9, 9),
    _GridPoint(9, 0),
  ];

  static const List<Offset> _goalCenters = [
    Offset(260, 300),
    Offset(300, 340),
    Offset(340, 300),
    Offset(300, 260),
  ];

  @override
  String get boardId => 'classic';

  @override
  double get boardExtent => _boardExtent;

  @override
  double get nominalCellExtent => _cellExtent;

  @override
  double get pieceHitTestRadius => _cellExtent * 0.65;

  @override
  Offset get boardCenter => const Offset(300, 300);

  @override
  Rect get goalAreaBounds => const Rect.fromLTWH(240, 240, 120, 120);

  @override
  Rect baseAreaBounds(int seatIndex) {
    final origin = _baseOrigins[_safeSeat(seatIndex)];
    return Rect.fromLTWH(
      origin.x * _cellExtent,
      origin.y * _cellExtent,
      _cellExtent * 6,
      _cellExtent * 6,
    );
  }

  @override
  Rect outerTrackCellBounds(int globalPathIndex) {
    RangeError.checkValidIndex(globalPathIndex, _outerTrack, 'globalPathIndex');
    return _cellBounds(_outerTrack[globalPathIndex]);
  }

  @override
  Offset outerTrackCenter(int globalPathIndex) {
    return outerTrackCellBounds(globalPathIndex).center;
  }

  @override
  Offset baseSlotCenter(int seatIndex, int pieceId) {
    final slots = _baseSlots[_safeSeat(seatIndex)];
    final pieceIndex = pieceId - 1;
    RangeError.checkValidIndex(pieceIndex, slots, 'pieceId');
    return _cellBounds(slots[pieceIndex]).center;
  }

  @override
  Rect homeLaneCellBounds(int seatIndex, int homePosition) {
    final lane = _homeLanes[_safeSeat(seatIndex)];
    RangeError.checkValidIndex(homePosition, lane, 'homePosition');
    return _cellBounds(lane[homePosition]);
  }

  @override
  Offset homeLaneCenter(int seatIndex, int homePosition) {
    return homeLaneCellBounds(seatIndex, homePosition).center;
  }

  @override
  Offset goalCenter(int seatIndex) {
    return _goalCenters[_safeSeat(seatIndex)];
  }

  Rect _cellBounds(_GridPoint point) {
    return Rect.fromLTWH(
      point.x * _cellExtent,
      point.y * _cellExtent,
      _cellExtent,
      _cellExtent,
    );
  }

  int _safeSeat(int seatIndex) => seatIndex.clamp(0, 3).toInt();
}

class _GridPoint {
  final int x;
  final int y;

  const _GridPoint(this.x, this.y);
}
