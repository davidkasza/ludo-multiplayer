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
          (step) => ActiveMoveStep.fromMap(
        Map<String, dynamic>.from(step),
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
      'steps': steps.map((step) => step.toMap()).toList(),
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
  static const String humanOpponents = 'human';
  static const String computerOpponents = 'computer';
  static const String mixedOpponents = 'mixed';

  static const String humanSeat = 'human';
  static const String computerSeat = 'computer';

  final List<String> players;
  final Map<String, String> playerNames;
  final Map<String, String> preferredColors;
  final Map<String, int> playerSeats;
  final Map<int, String> seatTypes;
  final String hostUid;
  final String currentTurn;
  final int diceValue;
  final bool hasRolled;
  final String status;
  final String winnerUid;
  final String boardId;
  final bool isTestModeActive;
  final int maxPlayers;
  final String opponentType;
  final bool isPublic;
  final bool matchmakingOpen;
  final LudoChat activeChat;
  final Map<String, List<LudoPiece>> pieces;
  final ActiveMove? activeMove;

  const LudoGame({
    required this.players,
    required this.playerNames,
    required this.preferredColors,
    required this.playerSeats,
    required this.seatTypes,
    required this.hostUid,
    required this.currentTurn,
    required this.diceValue,
    required this.hasRolled,
    required this.status,
    required this.winnerUid,
    required this.boardId,
    required this.isTestModeActive,
    required this.maxPlayers,
    required this.opponentType,
    required this.isPublic,
    required this.matchmakingOpen,
    required this.activeChat,
    required this.pieces,
    required this.activeMove,
  });

  static List<int> seatLayoutForMaxPlayers(int maxPlayers) {
    switch (maxPlayers.clamp(2, 4).toInt()) {
      case 2:
        return const [0, 2];
      case 3:
        return const [0, 1, 2];
      case 4:
        return const [0, 1, 2, 3];
      default:
        return const [0, 2];
    }
  }

  static String normalizeSeatType(String? value) {
    return value == computerSeat ? computerSeat : humanSeat;
  }

  static Map<int, String> parseSeatTypes(
      Map<String, dynamic> map,
      int maxPlayers,
      ) {
    final result = <int, String>{};
    final rawSeatTypes = map['seatTypes'];

    if (rawSeatTypes is Map) {
      Map<String, dynamic>.from(rawSeatTypes).forEach((rawKey, rawValue) {
        final seat = int.tryParse(rawKey);
        if (seat == null || seat < 0 || seat > 3) return;
        result[seat] = normalizeSeatType(rawValue?.toString());
      });
    }

    final layout = seatLayoutForMaxPlayers(maxPlayers);
    final legacyOpponentType =
        map['opponentType'] as String? ?? humanOpponents;

    for (int index = 0; index < layout.length; index++) {
      final seat = layout[index];

      if (index == 0) {
        result[seat] = humanSeat;
        continue;
      }

      result.putIfAbsent(
        seat,
            () => legacyOpponentType == computerOpponents
            ? computerSeat
            : humanSeat,
      );
    }

    result.removeWhere((seat, _) => !layout.contains(seat));
    return result;
  }

  static String deriveOpponentType({
    required Map<int, String> seatTypes,
    required int maxPlayers,
  }) {
    final opponentSeats = seatLayoutForMaxPlayers(maxPlayers).skip(1).toList();
    if (opponentSeats.isEmpty) return humanOpponents;

    final types = opponentSeats
        .map((seat) => normalizeSeatType(seatTypes[seat]))
        .toList();

    if (types.every((type) => type == computerSeat)) {
      return computerOpponents;
    }

    if (types.every((type) => type == humanSeat)) {
      return humanOpponents;
    }

    return mixedOpponents;
  }

  String seatTypeForSeat(int physicalSeat) {
    return normalizeSeatType(seatTypes[physicalSeat]);
  }

  String? playerIdForSeat(int physicalSeat) {
    for (final entry in playerSeats.entries) {
      if (entry.value == physicalSeat && players.contains(entry.key)) {
        return entry.key;
      }
    }
    return null;
  }

  int get openSeats => (maxPlayers - players.length).clamp(0, 4).toInt();

  int get openHumanSeats {
    final occupiedSeats = playerSeats.entries
        .where((entry) => players.contains(entry.key))
        .map((entry) => entry.value)
        .toSet();

    int count = 0;
    for (final seat in seatLayoutForMaxPlayers(maxPlayers)) {
      if (seatTypeForSeat(seat) == humanSeat &&
          !occupiedSeats.contains(seat)) {
        count++;
      }
    }
    return count;
  }

  bool get isReady {
    if (players.length != maxPlayers) return false;

    for (final seat in seatLayoutForMaxPlayers(maxPlayers)) {
      if (playerIdForSeat(seat) == null) return false;
    }

    return true;
  }

  factory LudoGame.fromMap(Map<String, dynamic> map) {
    final players = List<String>.from(map['players'] ?? []);
    final piecesMap = <String, List<LudoPiece>>{};

    final rawPieces = map['pieces'];
    if (rawPieces is Map) {
      Map<String, dynamic>.from(rawPieces).forEach((uid, piecesList) {
        if (piecesList is! List) return;

        piecesMap[uid] = piecesList
            .map(
              (piece) => LudoPiece.fromMap(
            Map<String, dynamic>.from(piece),
          ),
        )
            .toList();
      });
    }

    final playerNames = <String, String>{};
    final rawNames = map['playerNames'];
    if (rawNames is Map) {
      Map<String, dynamic>.from(rawNames).forEach((key, value) {
        playerNames[key] = value.toString();
      });
    }

    final preferredColors = <String, String>{};
    final rawColors = map['preferredColors'];
    if (rawColors is Map) {
      Map<String, dynamic>.from(rawColors).forEach((key, value) {
        preferredColors[key] = value.toString();
      });
    }

    final maxPlayers = (map['maxPlayers'] as int? ?? 2).clamp(2, 4).toInt();
    final layout = seatLayoutForMaxPlayers(maxPlayers);

    final playerSeats = <String, int>{};
    final rawSeats = map['playerSeats'];
    if (rawSeats is Map) {
      Map<String, dynamic>.from(rawSeats).forEach((key, value) {
        if (value is num) {
          playerSeats[key] = value.toInt().clamp(0, 3).toInt();
        }
      });
    }

    if (playerSeats.isEmpty) {
      for (int index = 0;
      index < players.length && index < layout.length;
      index++) {
        playerSeats[players[index]] = layout[index];
      }
    }

    final seatTypes = parseSeatTypes(map, maxPlayers);
    final derivedOpponentType = deriveOpponentType(
      seatTypes: seatTypes,
      maxPlayers: maxPlayers,
    );
    final status = map['status'] as String? ?? 'waiting';
    final isPublic = map['isPublic'] as bool? ?? true;

    final parsedGame = LudoGame(
      players: players,
      playerNames: playerNames,
      preferredColors: preferredColors,
      playerSeats: playerSeats,
      seatTypes: seatTypes,
      hostUid: map['hostUid'] as String? ??
          (players.isNotEmpty ? players.first : ''),
      currentTurn: map['currentTurn'] as String? ?? '',
      diceValue: map['diceValue'] as int? ?? 0,
      hasRolled: map['hasRolled'] as bool? ?? false,
      status: status,
      winnerUid: map['winnerUid'] as String? ?? '',
      boardId: map['boardId'] as String? ?? 'classic',
      isTestModeActive: map['isTestModeActive'] as bool? ?? false,
      maxPlayers: maxPlayers,
      opponentType: derivedOpponentType,
      isPublic: isPublic,
      matchmakingOpen: map['matchmakingOpen'] as bool? ?? false,
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

    return LudoGame(
      players: parsedGame.players,
      playerNames: parsedGame.playerNames,
      preferredColors: parsedGame.preferredColors,
      playerSeats: parsedGame.playerSeats,
      seatTypes: parsedGame.seatTypes,
      hostUid: parsedGame.hostUid,
      currentTurn: parsedGame.currentTurn,
      diceValue: parsedGame.diceValue,
      hasRolled: parsedGame.hasRolled,
      status: parsedGame.status,
      winnerUid: parsedGame.winnerUid,
      boardId: parsedGame.boardId,
      isTestModeActive: parsedGame.isTestModeActive,
      maxPlayers: parsedGame.maxPlayers,
      opponentType: parsedGame.opponentType,
      isPublic: parsedGame.isPublic,
      matchmakingOpen: map['matchmakingOpen'] as bool? ??
          (status == 'waiting' &&
              isPublic &&
              parsedGame.openHumanSeats > 0),
      activeChat: parsedGame.activeChat,
      pieces: parsedGame.pieces,
      activeMove: parsedGame.activeMove,
    );
  }

  Map<String, dynamic> toMap() {
    final piecesMap = <String, dynamic>{};

    pieces.forEach((uid, pieceList) {
      piecesMap[uid] = pieceList.map((piece) => piece.toMap()).toList();
    });

    return {
      'players': players,
      'playerNames': playerNames,
      'preferredColors': preferredColors,
      'playerSeats': playerSeats,
      'seatTypes': {
        for (final entry in seatTypes.entries)
          entry.key.toString(): normalizeSeatType(entry.value),
      },
      'hostUid': hostUid,
      'currentTurn': currentTurn,
      'diceValue': diceValue,
      'hasRolled': hasRolled,
      'status': status,
      'winnerUid': winnerUid,
      'boardId': boardId,
      'isTestModeActive': isTestModeActive,
      'maxPlayers': maxPlayers,
      'opponentType': deriveOpponentType(
        seatTypes: seatTypes,
        maxPlayers: maxPlayers,
      ),
      'isPublic': isPublic,
      'matchmakingOpen': matchmakingOpen,
      'activeChat': activeChat.toMap(),
      'pieces': piecesMap,
      'activeMove': activeMove?.toMap(),
    };
  }
}