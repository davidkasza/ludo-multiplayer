/// Shared gameplay topology for the original Ludo rules.
///
/// Canvas coordinates deliberately live in a `LudoBoardGeometry`
/// implementation so future visual layouts cannot redefine movement rules.
class ClassicBoard {
  static const int size = 52;

  /// Stable player-seat start indexes on the shared 52-position path.
  /// Geometry implementations decide where those seats and indexes appear.
  /// A piece advances by subtracting its relative position from its start.
  static const List<int> startOffsets = [11, 24, 37, 50];

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
