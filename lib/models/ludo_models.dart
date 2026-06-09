class LudoPiece {
  final int id;
  final int pos;
  final bool inHome;

  const LudoPiece({
    required this.id,
    required this.pos,
    required this.inHome,
  });

  factory LudoPiece.fromMap(Map<String, dynamic> map) {
    return LudoPiece(
      id: map['id'] as int,
      pos: map['pos'] as int,
      inHome: map['inHome'] as bool,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pos': pos,
      'inHome': inHome,
    };
  }
}

class LocalMovingPiece {
  final int id;
  int currentVisualPos;
  bool inHome;
  int stepCount;

  LocalMovingPiece({
    required this.id,
    required this.currentVisualPos,
    required this.inHome,
    required this.stepCount
  });
}