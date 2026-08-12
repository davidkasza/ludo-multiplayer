import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

int _readInt(Object? value, int fallback) =>
    value is num ? value.toInt() : fallback;

String _readString(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

bool _readBool(Object? value, [bool fallback = false]) =>
    value is bool ? value : fallback;

List<String> _readStringList(Object? value) {
  if (value is! Iterable) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}

Map<String, dynamic>? _readMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

class LudoPiece {
  final int id;
  final int pos;
  final bool inHome;

  const LudoPiece({required this.id, required this.pos, required this.inHome});

  factory LudoPiece.fromMap(Map<String, dynamic> map) {
    final id = _readInt(map['id'], 0);
    final pos = _readInt(map['pos'], -1);
    final inHome = _readBool(map['inHome']);
    if (id < 1 ||
        id > 4 ||
        (inHome ? pos < 0 || pos > 5 : pos < -1 || pos > 51)) {
      debugPrint('Normalizing malformed Ludo piece: $map');
    }
    return LudoPiece(
      id: id.clamp(1, 4).toInt(),
      pos: inHome ? pos.clamp(0, 5).toInt() : pos.clamp(-1, 51).toInt(),
      inHome: inHome,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'pos': pos, 'inHome': inHome};
  }

  LudoPiece copyWith({int? pos, bool? inHome}) {
    return LudoPiece(
      id: id,
      pos: pos ?? this.pos,
      inHome: inHome ?? this.inHome,
    );
  }
}

class ActiveMoveStep {
  final int pos;
  final bool inHome;

  const ActiveMoveStep({required this.pos, required this.inHome});

  factory ActiveMoveStep.fromMap(Map<String, dynamic> map) {
    return ActiveMoveStep(
      pos: _readInt(map['pos'], -1),
      inHome: _readBool(map['inHome']),
    );
  }

  Map<String, dynamic> toMap() {
    return {'pos': pos, 'inHome': inHome};
  }
}

class ActiveMoveCapture {
  final String playerId;
  final int pieceId;
  final ActiveMoveStep from;

  const ActiveMoveCapture({
    required this.playerId,
    required this.pieceId,
    required this.from,
  });

  factory ActiveMoveCapture.fromMap(Map<String, dynamic> map) {
    final fromMap = _readMap(map['from']);
    return ActiveMoveCapture(
      playerId: _readString(map['playerId']),
      pieceId: _readInt(map['pieceId'], 0),
      from: fromMap == null
          ? const ActiveMoveStep(pos: -1, inHome: false)
          : ActiveMoveStep.fromMap(fromMap),
    );
  }

  Map<String, dynamic> toMap() {
    return {'playerId': playerId, 'pieceId': pieceId, 'from': from.toMap()};
  }
}

class ActiveMove {
  final String actionId;
  final int turnVersion;
  final String playerId;
  final int pieceId;
  final int startedAt;
  final int stepDurationMs;
  final List<ActiveMoveStep> steps;
  final List<ActiveMoveCapture> capturedPieces;
  final bool stateApplied;
  final Timestamp? committedAt;

  const ActiveMove({
    this.actionId = '',
    this.turnVersion = 0,
    required this.playerId,
    required this.pieceId,
    required this.startedAt,
    required this.stepDurationMs,
    required this.steps,
    this.capturedPieces = const <ActiveMoveCapture>[],
    this.stateApplied = false,
    this.committedAt,
  });

  String get key =>
      actionId.isNotEmpty ? actionId : '${playerId}_${pieceId}_$startedAt';

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
              .map(_readMap)
              .whereType<Map<String, dynamic>>()
              .map(ActiveMoveStep.fromMap)
              .toList()
        : <ActiveMoveStep>[];
    final rawCapturedPieces = map['capturedPieces'];
    final parsedCapturedPieces = rawCapturedPieces is List
        ? rawCapturedPieces
              .map(_readMap)
              .whereType<Map<String, dynamic>>()
              .map(ActiveMoveCapture.fromMap)
              .where(
                (capture) =>
                    capture.playerId.isNotEmpty &&
                    capture.pieceId >= 1 &&
                    capture.pieceId <= 4 &&
                    !capture.from.inHome &&
                    capture.from.pos >= 0 &&
                    capture.from.pos <= 51,
              )
              .toList(growable: false)
        : const <ActiveMoveCapture>[];

    return ActiveMove(
      actionId: _readString(map['actionId']),
      turnVersion: _readInt(map['turnVersion'], 0),
      playerId: _readString(map['playerId']),
      pieceId: _readInt(map['pieceId'], 0),
      startedAt: _readInt(map['startedAt'], 0),
      stepDurationMs: _readInt(map['stepDurationMs'], 250),
      steps: parsedSteps.isNotEmpty
          ? parsedSteps
          : [
              ActiveMoveStep(
                pos: _readInt(map['currentVisualPos'], -1),
                inHome: _readBool(map['inHome']),
              ),
            ],
      capturedPieces: parsedCapturedPieces,
      stateApplied: _readBool(map['stateApplied']),
      committedAt: map['committedAt'] is Timestamp
          ? map['committedAt'] as Timestamp
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'actionId': actionId,
      'turnVersion': turnVersion,
      'playerId': playerId,
      'pieceId': pieceId,
      'startedAt': startedAt,
      'stepDurationMs': stepDurationMs,
      'steps': steps.map((step) => step.toMap()).toList(),
      if (capturedPieces.isNotEmpty)
        'capturedPieces': capturedPieces
            .map((capture) => capture.toMap())
            .toList(),
      'stateApplied': stateApplied,
      'committedAt': committedAt,
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
      sender: _readString(map['sender']),
      message: _readString(map['message']),
      timestamp: _readInt(map['timestamp'], 0),
    );
  }

  Map<String, dynamic> toMap() {
    return {'sender': sender, 'message': message, 'timestamp': timestamp};
  }
}

class ActiveDiceRoll {
  final String actionId;
  final int turnVersion;
  final String playerId;
  final int startedAt;
  final int durationMs;
  final int result;
  final bool stateApplied;
  final Timestamp? committedAt;

  const ActiveDiceRoll({
    this.actionId = '',
    this.turnVersion = 0,
    required this.playerId,
    required this.startedAt,
    required this.durationMs,
    this.result = 0,
    this.stateApplied = false,
    this.committedAt,
  });

  String get key => actionId.isNotEmpty ? actionId : '${playerId}_$startedAt';

  factory ActiveDiceRoll.fromMap(Map<String, dynamic> map) {
    return ActiveDiceRoll(
      actionId: _readString(map['actionId']),
      turnVersion: _readInt(map['turnVersion'], 0),
      playerId: _readString(map['playerId']),
      startedAt: _readInt(map['startedAt'], 0),
      durationMs: _readInt(map['durationMs'], 800),
      result: _readInt(map['result'], 0),
      stateApplied: _readBool(map['stateApplied']),
      committedAt: map['committedAt'] is Timestamp
          ? map['committedAt'] as Timestamp
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'actionId': actionId,
      'turnVersion': turnVersion,
      'playerId': playerId,
      'startedAt': startedAt,
      'durationMs': durationMs,
      'result': result,
      'stateApplied': stateApplied,
      'committedAt': committedAt,
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
      ownerUid: _readString(map['ownerUid']),
      turnVersion: _readInt(map['turnVersion'], 0),
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
      id: _readString(map['id']),
      type: _readString(map['type']),
      playerId: _readString(map['playerId']),
      createdAtMs: _readInt(map['createdAtMs'], 0),
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
    final rawState = _readString(map['state'], offline);
    final normalizedState =
        {online, reconnecting, offline, ai, forfeited}.contains(rawState)
        ? rawState
        : offline;

    return PlayerPresence(
      state: normalizedState,
      lastSeenAt: map['lastSeenAt'] is Timestamp
          ? map['lastSeenAt'] as Timestamp
          : null,
      sessionId: _readString(map['sessionId']),
    );
  }

  Map<String, dynamic> toMap() {
    return {'state': state, 'lastSeenAt': lastSeenAt, 'sessionId': sessionId};
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
  final Timestamp? turnStartedAt;
  final int turnDurationSeconds;
  final int turnVersion;
  final String lastActionId;
  final String lastActionType;
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
    required this.turnStartedAt,
    required this.turnDurationSeconds,
    required this.turnVersion,
    required this.lastActionId,
    required this.lastActionType,
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
    final legacyOpponentType = _readString(map['opponentType'], humanOpponents);

    for (int index = 0; index < layout.length; index++) {
      final seat = layout[index];

      if (index == 0) {
        result[seat] = humanSeat;
        continue;
      }

      result.putIfAbsent(
        seat,
        () =>
            legacyOpponentType == computerOpponents ? computerSeat : humanSeat,
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
      if (seatTypeForSeat(seat) == humanSeat && !occupiedSeats.contains(seat)) {
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
    return playerId.startsWith('bot_') ||
        aiControlledPlayers.contains(playerId);
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

  /// Server-authored start time plus a duration is preferred over the legacy
  /// absolute deadline. This keeps shared timing independent of client clocks.
  DateTime? get effectiveTurnDeadline {
    final serverStart = turnStartedAt?.toDate();
    if (serverStart != null && turnDurationSeconds > 0) {
      return serverStart.add(Duration(seconds: turnDurationSeconds));
    }
    return turnDeadlineAt?.toDate();
  }

  factory LudoGame.fromMap(Map<String, dynamic> map) {
    final players = _readStringList(map['players']).toSet().toList();
    final piecesMap = <String, List<LudoPiece>>{};

    final rawPieces = map['pieces'];
    if (rawPieces is Map) {
      Map<String, dynamic>.from(rawPieces).forEach((uid, piecesList) {
        if (piecesList is! List) {
          debugPrint('Ignoring malformed piece list for $uid');
          return;
        }

        piecesMap[uid] = piecesList
            .map(_readMap)
            .whereType<Map<String, dynamic>>()
            .map(LudoPiece.fromMap)
            .toList();
      });
    } else if (rawPieces != null) {
      debugPrint('Ignoring malformed pieces map');
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

    final maxPlayers = _readInt(map['maxPlayers'], 2).clamp(2, 4).toInt();
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
      for (
        int index = 0;
        index < players.length && index < layout.length;
        index++
      ) {
        playerSeats[players[index]] = layout[index];
      }
    }

    final seatTypes = parseSeatTypes(map, maxPlayers);
    final derivedOpponentType = deriveOpponentType(
      seatTypes: seatTypes,
      maxPlayers: maxPlayers,
    );
    final rawStatus = _readString(map['status'], 'waiting');
    final status = const {'waiting', 'playing', 'finished'}.contains(rawStatus)
        ? rawStatus
        : 'waiting';
    if (status != rawStatus) debugPrint('Invalid game status: $rawStatus');
    final isPublic = _readBool(map['isPublic'], true);
    final occupiedSeats = playerSeats.entries
        .where((entry) => players.contains(entry.key))
        .map((entry) => entry.value)
        .toSet();
    final hasOpenHumanSeat = layout.any(
      (seat) => seatTypes[seat] == humanSeat && !occupiedSeats.contains(seat),
    );

    final rawFinishOrder = _readStringList(map['finishOrder']);
    final finishOrder = <String>[];
    for (final playerId in rawFinishOrder) {
      if (players.contains(playerId) && !finishOrder.contains(playerId)) {
        finishOrder.add(playerId);
      }
    }

    final legacyWinner = _readString(map['winnerUid']);
    if (finishOrder.isEmpty &&
        status == 'finished' &&
        legacyWinner.isNotEmpty &&
        players.contains(legacyWinner)) {
      finishOrder.add(legacyWinner);
      finishOrder.addAll(players.where((id) => id != legacyWinner));
    }

    final aiControlledPlayers = _readStringList(
      map['aiControlledPlayers'],
    ).where(players.contains).toSet().toList();
    final pendingReconnectPlayers = _readStringList(
      map['pendingReconnectPlayers'],
    ).where(players.contains).toSet().toList();
    final forfeitedPlayers = _readStringList(
      map['forfeitedPlayers'],
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

    final currentTurn = _readString(map['currentTurn']);
    if (status == 'playing' && !players.contains(currentTurn)) {
      throw const FormatException(
        'Playing game has a current turn that is not a participant',
      );
    }
    final rawDiceValue = _readInt(map['diceValue'], 0);
    if (rawDiceValue < 0 || rawDiceValue > 6) {
      debugPrint('Normalizing invalid dice value: $rawDiceValue');
      if (status == 'playing') {
        throw const FormatException('Playing game has an invalid dice value');
      }
    }
    final activeMoveMap = _readMap(map['activeMove']);
    final activeDiceRollMap = _readMap(map['activeDiceRoll']);
    if (map['activeMove'] != null && activeMoveMap == null) {
      debugPrint('Ignoring malformed activeMove descriptor');
    }
    if (map['activeDiceRoll'] != null && activeDiceRollMap == null) {
      debugPrint('Ignoring malformed activeDiceRoll descriptor');
    }
    final rawTurnPhase = _readString(map['turnPhase']);
    final turnPhase = {waitingForRoll, waitingForMove}.contains(rawTurnPhase)
        ? rawTurnPhase
        : (_readBool(map['hasRolled']) ? waitingForMove : waitingForRoll);
    if (rawTurnPhase.isNotEmpty && rawTurnPhase != turnPhase) {
      debugPrint('Normalizing invalid turn phase: $rawTurnPhase');
    }
    if (status == 'playing') {
      for (final playerId in players) {
        final playerPieces = piecesMap[playerId] ?? const <LudoPiece>[];
        final pieceIds = playerPieces.map((piece) => piece.id).toSet();
        if (playerPieces.length != 4 || pieceIds.length != 4) {
          throw FormatException(
            'Playing game has invalid pieces for participant $playerId',
          );
        }
      }
      final hasRolled = _readBool(map['hasRolled']);
      if ((hasRolled && (rawDiceValue == 0 || turnPhase != waitingForMove)) ||
          (!hasRolled && turnPhase != waitingForRoll)) {
        throw const FormatException('Playing game has an invalid turn phase');
      }
    }
    final rawTurnDuration = _readInt(map['turnDurationSeconds'], 0);
    final turnDurationSeconds = const {0, 10, 30}.contains(rawTurnDuration)
        ? rawTurnDuration
        : 0;
    if (turnDurationSeconds != rawTurnDuration) {
      debugPrint('Ignoring invalid turn duration: $rawTurnDuration');
    }

    return LudoGame(
      players: players,
      playerNames: playerNames,
      preferredColors: preferredColors,
      playerSeats: playerSeats,
      seatTypes: seatTypes,
      hostUid: _readString(map['hostUid']).isNotEmpty
          ? _readString(map['hostUid'])
          : (players.isNotEmpty ? players.first : ''),
      currentTurn: currentTurn,
      diceValue: rawDiceValue.clamp(0, 6).toInt(),
      hasRolled: _readBool(map['hasRolled']),
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
      boardId: _readString(map['boardId'], 'classic'),
      isTestModeActive: map['isTestModeActive'] == true,
      maxPlayers: maxPlayers,
      opponentType: derivedOpponentType,
      isPublic: isPublic,
      matchmakingOpen: map['matchmakingOpen'] is bool
          ? map['matchmakingOpen'] as bool
          : (status == 'waiting' && isPublic && hasOpenHumanSeat),
      activeChat: LudoChat.fromMap(
        _readMap(map['activeChat']) ?? const <String, dynamic>{},
      ),
      pieces: piecesMap,
      activeMove: activeMoveMap == null
          ? null
          : ActiveMove.fromMap(activeMoveMap),
      activeDiceRoll: activeDiceRollMap == null
          ? null
          : ActiveDiceRoll.fromMap(activeDiceRollMap),
      turnPhase: turnPhase,
      turnDeadlineAt: map['turnDeadlineAt'] is Timestamp
          ? map['turnDeadlineAt'] as Timestamp
          : null,
      turnStartedAt: map['turnStartedAt'] is Timestamp
          ? map['turnStartedAt'] as Timestamp
          : null,
      turnDurationSeconds: turnDurationSeconds,
      turnVersion: _readInt(map['turnVersion'], 0),
      lastActionId: _readString(map['lastActionId']),
      lastActionType: _readString(map['lastActionType']),
      aiControlledPlayers: aiControlledPlayers,
      pendingReconnectPlayers: pendingReconnectPlayers,
      forfeitedPlayers: forfeitedPlayers,
      automationLease: _readMap(map['automationLease']) == null
          ? null
          : AutomationLease.fromMap(_readMap(map['automationLease'])!),
      systemEvent: _readMap(map['systemEvent']) == null
          ? null
          : GameSystemEvent.fromMap(_readMap(map['systemEvent'])!),
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
      'turnStartedAt': turnStartedAt,
      'turnDurationSeconds': turnDurationSeconds,
      'turnVersion': turnVersion,
      'lastActionId': lastActionId,
      'lastActionType': lastActionType,
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
