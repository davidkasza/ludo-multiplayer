import 'package:cloud_firestore/cloud_firestore.dart';

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

class ActiveDiceRoll {
  final String playerId;
  final int startedAt;
  final int durationMs;

  const ActiveDiceRoll({
    required this.playerId,
    required this.startedAt,
    required this.durationMs,
  });

  String get key => '${playerId}_$startedAt';

  factory ActiveDiceRoll.fromMap(Map<String, dynamic> map) {
    return ActiveDiceRoll(
      playerId: map['playerId'] as String? ?? '',
      startedAt: map['startedAt'] as int? ??
          DateTime.now().millisecondsSinceEpoch,
      durationMs: map['durationMs'] as int? ?? 800,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'playerId': playerId,
      'startedAt': startedAt,
      'durationMs': durationMs,
    };
  }
}



class AutomationLease {
  final String ownerUid;
  final int turnVersion;
  final Timestamp expiresAt;

  const AutomationLease({
    required this.ownerUid,
    required this.turnVersion,
    required this.expiresAt,
  });

  bool get isExpired => expiresAt.toDate().isBefore(DateTime.now());

  factory AutomationLease.fromMap(Map<String, dynamic> map) {
    final rawExpiry = map['expiresAt'];
    return AutomationLease(
      ownerUid: map['ownerUid'] as String? ?? '',
      turnVersion: map['turnVersion'] as int? ?? 0,
      expiresAt: rawExpiry is Timestamp ? rawExpiry : Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerUid': ownerUid,
      'turnVersion': turnVersion,
      'expiresAt': expiresAt,
    };
  }
}

class GameSystemEvent {
  static const String aiTakeover = 'aiTakeover';
  static const String playerReconnected = 'playerReconnected';
  static const String playerForfeited = 'playerForfeited';

  final String id;
  final String type;
  final String playerId;
  final int createdAtMs;

  const GameSystemEvent({
    required this.id,
    required this.type,
    required this.playerId,
    required this.createdAtMs,
  });

  factory GameSystemEvent.fromMap(Map<String, dynamic> map) {
    return GameSystemEvent(
      id: map['id'] as String? ?? '',
      type: map['type'] as String? ?? '',
      playerId: map['playerId'] as String? ?? '',
      createdAtMs: map['createdAtMs'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'playerId': playerId,
      'createdAtMs': createdAtMs,
    };
  }
}


class PlayerPresence {
  static const String online = 'online';
  static const String reconnecting = 'reconnecting';
  static const String offline = 'offline';
  static const String ai = 'ai';
  static const String forfeited = 'forfeited';

  final String state;
  final Timestamp? lastSeenAt;
  final String sessionId;

  const PlayerPresence({
    required this.state,
    required this.lastSeenAt,
    required this.sessionId,
  });

  factory PlayerPresence.fromMap(Map<String, dynamic> map) {
    final rawState = map['state'] as String? ?? offline;
    final normalizedState = {
      online,
      reconnecting,
      offline,
      ai,
      forfeited,
    }.contains(rawState)
        ? rawState
        : offline;

    return PlayerPresence(
      state: normalizedState,
      lastSeenAt: map['lastSeenAt'] is Timestamp
          ? map['lastSeenAt'] as Timestamp
          : null,
      sessionId: map['sessionId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'state': state,
      'lastSeenAt': lastSeenAt,
      'sessionId': sessionId,
    };
  }
}

class LudoGame {
  static const String humanOpponents = 'human';
  static const String computerOpponents = 'computer';
  static const String mixedOpponents = 'mixed';

  static const String humanSeat = 'human';
  static const String computerSeat = 'computer';

  static const String waitingForRoll = 'waitingForRoll';
  static const String waitingForMove = 'waitingForMove';

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
  final List<String> finishOrder;
  final Timestamp? startedAt;
  final Timestamp? finishedAt;
  final String boardId;
  final bool isTestModeActive;
  final int maxPlayers;
  final String opponentType;
  final bool isPublic;
  final bool matchmakingOpen;
  final LudoChat activeChat;
  final Map<String, List<LudoPiece>> pieces;
  final ActiveMove? activeMove;
  final ActiveDiceRoll? activeDiceRoll;
  final String turnPhase;
  final Timestamp? turnDeadlineAt;
  final int turnVersion;
  final List<String> aiControlledPlayers;
  final List<String> pendingReconnectPlayers;
  final List<String> forfeitedPlayers;
  final AutomationLease? automationLease;
  final GameSystemEvent? systemEvent;
  final Map<String, PlayerPresence> playerPresence;

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
    required this.finishOrder,
    required this.startedAt,
    required this.finishedAt,
    required this.boardId,
    required this.isTestModeActive,
    required this.maxPlayers,
    required this.opponentType,
    required this.isPublic,
    required this.matchmakingOpen,
    required this.activeChat,
    required this.pieces,
    required this.activeMove,
    required this.activeDiceRoll,
    required this.turnPhase,
    required this.turnDeadlineAt,
    required this.turnVersion,
    required this.aiControlledPlayers,
    required this.pendingReconnectPlayers,
    required this.forfeitedPlayers,
    required this.automationLease,
    required this.systemEvent,
    required this.playerPresence,
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

  bool isPlayerFinished(String playerId) => finishOrder.contains(playerId);

  int placementFor(String playerId) {
    final index = finishOrder.indexOf(playerId);
    return index < 0 ? 0 : index + 1;
  }

  bool isAiControlled(String playerId) {
    return playerId.startsWith('bot_') || aiControlledPlayers.contains(playerId);
  }

  bool isPendingReconnect(String playerId) {
    return pendingReconnectPlayers.contains(playerId);
  }

  bool hasForfeited(String playerId) {
    return forfeitedPlayers.contains(playerId);
  }

  Duration? get matchDuration {
    if (startedAt == null || finishedAt == null) return null;
    final duration = finishedAt!.toDate().difference(startedAt!.toDate());
    return duration.isNegative ? Duration.zero : duration;
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
    final occupiedSeats = playerSeats.entries
        .where((entry) => players.contains(entry.key))
        .map((entry) => entry.value)
        .toSet();
    final hasOpenHumanSeat = layout.any(
          (seat) => seatTypes[seat] == humanSeat && !occupiedSeats.contains(seat),
    );

    final rawFinishOrder = List<String>.from(map['finishOrder'] ?? const []);
    final finishOrder = <String>[];
    for (final playerId in rawFinishOrder) {
      if (players.contains(playerId) && !finishOrder.contains(playerId)) {
        finishOrder.add(playerId);
      }
    }

    final legacyWinner = map['winnerUid'] as String? ?? '';
    if (finishOrder.isEmpty &&
        status == 'finished' &&
        legacyWinner.isNotEmpty &&
        players.contains(legacyWinner)) {
      finishOrder.add(legacyWinner);
      finishOrder.addAll(players.where((id) => id != legacyWinner));
    }

    final aiControlledPlayers = List<String>.from(
      map['aiControlledPlayers'] ?? const <String>[],
    ).where(players.contains).toSet().toList();
    final pendingReconnectPlayers = List<String>.from(
      map['pendingReconnectPlayers'] ?? const <String>[],
    ).where(players.contains).toSet().toList();
    final forfeitedPlayers = List<String>.from(
      map['forfeitedPlayers'] ?? const <String>[],
    ).where(players.contains).toSet().toList();

    final playerPresence = <String, PlayerPresence>{};
    final rawPresence = map['playerPresence'];
    if (rawPresence is Map) {
      Map<String, dynamic>.from(rawPresence).forEach((playerId, value) {
        if (value is! Map || !players.contains(playerId)) return;
        playerPresence[playerId] = PlayerPresence.fromMap(
          Map<String, dynamic>.from(value),
        );
      });
    }

    return LudoGame(
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
      winnerUid: legacyWinner.isNotEmpty
          ? legacyWinner
          : (finishOrder.isNotEmpty ? finishOrder.first : ''),
      finishOrder: finishOrder,
      startedAt: map['startedAt'] is Timestamp
          ? map['startedAt'] as Timestamp
          : null,
      finishedAt: map['finishedAt'] is Timestamp
          ? map['finishedAt'] as Timestamp
          : null,
      boardId: map['boardId'] as String? ?? 'classic',
      isTestModeActive: map['isTestModeActive'] == true,
      maxPlayers: maxPlayers,
      opponentType: derivedOpponentType,
      isPublic: isPublic,
      matchmakingOpen: map['matchmakingOpen'] as bool? ??
          (status == 'waiting' && isPublic && hasOpenHumanSeat),
      activeChat: LudoChat.fromMap(
        Map<String, dynamic>.from(map['activeChat'] ?? {}),
      ),
      pieces: piecesMap,
      activeMove: map['activeMove'] == null
          ? null
          : ActiveMove.fromMap(
        Map<String, dynamic>.from(map['activeMove']),
      ),
      activeDiceRoll: map['activeDiceRoll'] == null
          ? null
          : ActiveDiceRoll.fromMap(
        Map<String, dynamic>.from(map['activeDiceRoll']),
      ),
      turnPhase: map['turnPhase'] as String? ??
          ((map['hasRolled'] as bool? ?? false)
              ? waitingForMove
              : waitingForRoll),
      turnDeadlineAt: map['turnDeadlineAt'] is Timestamp
          ? map['turnDeadlineAt'] as Timestamp
          : null,
      turnVersion: map['turnVersion'] as int? ?? 0,
      aiControlledPlayers: aiControlledPlayers,
      pendingReconnectPlayers: pendingReconnectPlayers,
      forfeitedPlayers: forfeitedPlayers,
      automationLease: map['automationLease'] == null
          ? null
          : AutomationLease.fromMap(
        Map<String, dynamic>.from(map['automationLease']),
      ),
      systemEvent: map['systemEvent'] == null
          ? null
          : GameSystemEvent.fromMap(
        Map<String, dynamic>.from(map['systemEvent']),
      ),
      playerPresence: playerPresence,
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
      'finishOrder': finishOrder,
      'startedAt': startedAt,
      'finishedAt': finishedAt,
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
      'activeDiceRoll': activeDiceRoll?.toMap(),
      'turnPhase': turnPhase,
      'turnDeadlineAt': turnDeadlineAt,
      'turnVersion': turnVersion,
      'aiControlledPlayers': aiControlledPlayers,
      'pendingReconnectPlayers': pendingReconnectPlayers,
      'forfeitedPlayers': forfeitedPlayers,
      'automationLease': automationLease?.toMap(),
      'systemEvent': systemEvent?.toMap(),
      'playerPresence': {
        for (final entry in playerPresence.entries)
          entry.key: entry.value.toMap(),
      },
    };
  }
}