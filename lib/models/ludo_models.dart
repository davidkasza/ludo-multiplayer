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

class ActiveMoveStep {
  final int pos;
  final bool inHome;

  const ActiveMoveStep({
    required this.pos,
    required this.inHome,
  });

  factory ActiveMoveStep.fromMap(Map<String, dynamic> map) {
    return ActiveMoveStep(
      pos: map['pos'] as int? ?? -1,
      inHome: map['inHome'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'pos': pos,
      'inHome': inHome,
    };
  }
}

class ActiveMove {
  final String playerId;
  final int pieceId;
  final int startedAt;
  final int stepDurationMs;
  final List<ActiveMoveStep> steps;

  const ActiveMove({
    required this.playerId,
    required this.pieceId,
    required this.startedAt,
    required this.stepDurationMs,
    required this.steps,
  });

  int get totalDurationMs {
    if (steps.length <= 1) return 0;
    return (steps.length - 1) * stepDurationMs;
  }

  ActiveMoveStep stepAtElapsed(int elapsedMs) {
    if (steps.isEmpty) {
      return const ActiveMoveStep(pos: -1, inHome: false);
    }

    if (stepDurationMs <= 0) {
      return steps.last;
    }

    if (elapsedMs <= 0) {
      return steps.first;
    }

    final rawIndex = elapsedMs ~/ stepDurationMs;
    final index = rawIndex.clamp(0, steps.length - 1).toInt();

    return steps[index];
  }

  factory ActiveMove.fromMap(Map<String, dynamic> map) {
    final rawSteps = map['steps'];

    final parsedSteps = rawSteps is List
        ? rawSteps
        .map(
          (s) => ActiveMoveStep.fromMap(
        Map<String, dynamic>.from(s),
      ),
    )
        .toList()
        : <ActiveMoveStep>[];

    return ActiveMove(
      playerId: map['playerId'] as String? ?? '',
      pieceId: map['pieceId'] as int? ?? 0,
      startedAt: map['startedAt'] as int? ??
          DateTime.now().millisecondsSinceEpoch,
      stepDurationMs: map['stepDurationMs'] as int? ?? 250,
      steps: parsedSteps.isNotEmpty
          ? parsedSteps
          : [
        ActiveMoveStep(
          pos: map['currentVisualPos'] as int? ?? -1,
          inHome: map['inHome'] as bool? ?? false,
        ),
      ],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'playerId': playerId,
      'pieceId': pieceId,
      'startedAt': startedAt,
      'stepDurationMs': stepDurationMs,
      'steps': steps.map((s) => s.toMap()).toList(),
    };
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

  Map<String, dynamic> toMap() {
    return {
      'sender': sender,
      'message': message,
      'timestamp': timestamp,
    };
  }
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
  final ActiveMove? activeMove;

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
    required this.activeMove,
  });

  factory LudoGame.fromMap(Map<String, dynamic> map) {
    final piecesMap = <String, List<LudoPiece>>{};

    if (map['pieces'] != null) {
      (map['pieces'] as Map<String, dynamic>).forEach((uid, piecesList) {
        piecesMap[uid] = (piecesList as List)
            .map(
              (p) => LudoPiece.fromMap(
            Map<String, dynamic>.from(p),
          ),
        )
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
      activeChat: LudoChat.fromMap(
        Map<String, dynamic>.from(map['activeChat'] ?? {}),
      ),
      pieces: piecesMap,
      activeMove: map['activeMove'] == null
          ? null
          : ActiveMove.fromMap(
        Map<String, dynamic>.from(map['activeMove']),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    final piecesMap = <String, dynamic>{};

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
      'activeMove': activeMove?.toMap(),
    };
  }
}