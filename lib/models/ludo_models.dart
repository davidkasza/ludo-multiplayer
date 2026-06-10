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

  LudoPiece copyWith({
    int? pos,
    bool? inHome,
  }) {
    return LudoPiece(
      id: id,
      pos: pos ?? this.pos,
      inHome: inHome ?? this.inHome,
    );
  }
}

class LocalMovingPiece {
  final int id;
  final int currentVisualPos;
  final bool inHome;
  final int stepCount;

  const LocalMovingPiece({
    required this.id,
    required this.currentVisualPos,
    required this.inHome,
    required this.stepCount,
  });

  LocalMovingPiece copyWith({
    int? currentVisualPos,
    bool? inHome,
    int? stepCount,
  }) {
    return LocalMovingPiece(
      id: id,
      currentVisualPos: currentVisualPos ?? this.currentVisualPos,
      inHome: inHome ?? this.inHome,
      stepCount: stepCount ?? this.stepCount,
    );
  }
}

class LudoChat {
  final String sender;
  final String message;
  final int timestamp;

  const LudoChat({
    required this.sender,
    required this.message,
    required this.timestamp,
  });

  factory LudoChat.fromMap(Map<String, dynamic> map) {
    return LudoChat(
      sender: map['sender'] as String? ?? '',
      message: map['message'] as String? ?? '',
      timestamp: map['timestamp'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'sender': sender,
    'message': message,
    'timestamp': timestamp,
  };
}

class LudoGame {
  final List<String> players;
  final Map<String, String> playerNames;
  final String currentTurn;
  final int diceValue;
  final bool hasRolled;
  final String status;
  final String winnerUid;
  final String boardId;
  final bool isTestModeActive;
  final LudoChat activeChat;
  final Map<String, List<LudoPiece>> pieces;

  const LudoGame({
    required this.players,
    required this.playerNames,
    required this.currentTurn,
    required this.diceValue,
    required this.hasRolled,
    required this.status,
    required this.winnerUid,
    required this.boardId,
    required this.isTestModeActive,
    required this.activeChat,
    required this.pieces,
  });

  factory LudoGame.fromMap(Map<String, dynamic> map) {
    var piecesMap = <String, List<LudoPiece>>{};
    if (map['pieces'] != null) {
      (map['pieces'] as Map<String, dynamic>).forEach((uid, piecesList) {
        piecesMap[uid] = (piecesList as List)
            .map((p) => LudoPiece.fromMap(p as Map<String, dynamic>))
            .toList();
      });
    }

    return LudoGame(
      players: List<String>.from(map['players'] ?? []),
      playerNames: Map<String, String>.from(map['playerNames'] ?? {}),
      currentTurn: map['currentTurn'] as String? ?? '',
      diceValue: map['diceValue'] as int? ?? 0,
      hasRolled: map['hasRolled'] as bool? ?? false,
      status: map['status'] as String? ?? 'waiting',
      winnerUid: map['winnerUid'] as String? ?? '',
      boardId: map['boardId'] as String? ?? 'classic',
      isTestModeActive: map['isTestModeActive'] as bool? ?? false,
      activeChat: LudoChat.fromMap(map['activeChat'] ?? {}),
      pieces: piecesMap,
    );
  }

  Map<String, dynamic> toMap() {
    var piecesMap = <String, dynamic>{};
    pieces.forEach((uid, pieceList) {
      piecesMap[uid] = pieceList.map((p) => p.toMap()).toList();
    });

    return {
      'players': players,
      'playerNames': playerNames,
      'currentTurn': currentTurn,
      'diceValue': diceValue,
      'hasRolled': hasRolled,
      'status': status,
      'winnerUid': winnerUid,
      'boardId': boardId,
      'isTestModeActive': isTestModeActive,
      'activeChat': activeChat.toMap(),
      'pieces': piecesMap,
    };
  }
}