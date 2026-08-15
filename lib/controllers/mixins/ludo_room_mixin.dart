import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../config/progression_config.dart';
import '../../game/dice_skin.dart';
import '../../game/ludo_board_theme.dart';
import '../../game/ludo_palette.dart';
import '../../game/ludo_rules.dart';
import '../../models/ludo_models.dart';

mixin LudoRoomMixin on ChangeNotifier {
  FirebaseFirestore get db;

  User? get user;

  String get gameId;
  set gameId(String value);

  LudoGame? get game;
  set game(LudoGame? value);

  String get statusMessage;
  set statusMessage(String value);

  String get preferredDiceSkinId;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  get gameSubscription;
  set gameSubscription(
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? value,
  );

  bool get isHost;

  List<Map<String, dynamic>> createDefaultPieces(int initialPos);
  void syncVisualActiveMove(ActiveMove? remoteMove);
  void syncDiceRollAnimation(ActiveDiceRoll? remoteRoll);
  void stopDiceRollAnimation();
  void syncBotTurn();
  void cancelBotTurn();
  void syncTurnClock();
  void startPresenceTracking();
  void stopPresenceTracking();
  void startChatTracking(String roomId);
  void stopChatTracking();
  void noteConnectionError();
  void noteConnectionRestored();
  Future<void> markPresenceOnline();
  Future<void> markPresenceReconnecting();
  Future<void> markPresenceOffline({String? roomId});

  Future<ProgressionReward?> claimProgressionForGame(
    String matchId,
    LudoGame game,
  );
  Future<ProgressionReward?> claimProgressionFromResult(String matchId);

  String get localConnectionState;
  set localConnectionState(String value);
  DateTime get estimatedServerNow;

  String get activeGameId;
  set activeGameId(String value);
  LudoGame? get resumableGame;
  set resumableGame(LudoGame? value);

  Future<void> setMyActiveGame(String roomId);
  Future<void> clearMyActiveGame({String? expectedGameId});
  Future<void> refreshResumableGame();
  Future<bool> markMyselfForfeit();

  static const String _roomCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static const Duration waitingRoomLease = Duration(minutes: 12);
  static const Duration activeGameLease = Duration(hours: 24);
  static const Duration _heartbeatInterval = Duration(minutes: 5);

  Timer? _roomHeartbeatTimer;
  String? _heartbeatRoomId;
  int _listenerGeneration = 0;
  Timer? _legacyRecoveryTimer;
  String? _legacyRecoveryKey;

  List<String> _stringList(Object? value) =>
      value is Iterable ? value.whereType<String>().toList() : <String>[];

  int _integer(Object? value, int fallback) =>
      value is num ? value.toInt() : fallback;

  String _string(Object? value, [String fallback = '']) =>
      value is String ? value : fallback;

  Map<String, dynamic> _dynamicMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Timestamp _expiresAfter(Duration duration) {
    return Timestamp.fromDate(estimatedServerNow.toUtc().add(duration));
  }

  bool _hasActiveWaitingLease(Map<String, dynamic> data) {
    final rawExpiresAt = data['expiresAt'];
    if (rawExpiresAt is! Timestamp) return false;

    return rawExpiresAt.toDate().toUtc().isAfter(estimatedServerNow.toUtc());
  }

  void syncRoomHeartbeat() {
    final shouldRun = gameId.isNotEmpty && game?.status == 'waiting' && isHost;

    if (!shouldRun) {
      stopRoomHeartbeat();
      return;
    }

    if (_heartbeatRoomId == gameId && _roomHeartbeatTimer?.isActive == true) {
      return;
    }

    stopRoomHeartbeat();
    _heartbeatRoomId = gameId;
    _roomHeartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => unawaited(_refreshWaitingRoomLease()),
    );
  }

  void stopRoomHeartbeat() {
    _roomHeartbeatTimer?.cancel();
    _roomHeartbeatTimer = null;
    _heartbeatRoomId = null;
  }

  Future<void> _refreshWaitingRoomLease() async {
    final currentId = gameId;
    final currentGame = game;

    if (currentId.isEmpty ||
        currentGame == null ||
        currentGame.status != 'waiting' ||
        !isHost) {
      stopRoomHeartbeat();
      return;
    }

    try {
      final reference = db.collection('games').doc(currentId);
      await db.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        final data = snapshot.data();
        if (!snapshot.exists || data == null) return;
        final latest = LudoGame.fromMap(data);
        if (latest.status != 'waiting' || latest.hostUid != user?.uid) return;
        transaction.update(reference, {
          'lastActivityAt': FieldValue.serverTimestamp(),
          'expiresAt': _expiresAfter(waitingRoomLease),
        });
      });
    } catch (error) {
      if (kDebugMode) {
        print('Waiting-room heartbeat error: $error');
      }
    }
  }

  String _generateRoomCode() {
    final secureRandom = Random.secure();

    return List.generate(
      5,
      (_) => _roomCodeChars[secureRandom.nextInt(_roomCodeChars.length)],
    ).join();
  }

  String _botIdForSeat(int physicalSeat) => 'bot_seat_$physicalSeat';

  bool _isBotId(String playerId) => playerId.startsWith('bot_');

  Map<int, String> _normalizedSeatTypes({
    required int maxPlayers,
    Map<int, String>? requestedSeatTypes,
    String? legacyOpponentType,
  }) {
    final layout = LudoGame.seatLayoutForMaxPlayers(maxPlayers);
    final result = <int, String>{};

    for (int index = 0; index < layout.length; index++) {
      final seat = layout[index];

      if (index == 0) {
        result[seat] = LudoGame.humanSeat;
        continue;
      }

      final requested = requestedSeatTypes?[seat];
      if (requested != null) {
        result[seat] = LudoGame.normalizeSeatType(requested);
      } else {
        result[seat] = legacyOpponentType == LudoGame.computerOpponents
            ? LudoGame.computerSeat
            : LudoGame.humanSeat;
      }
    }

    return result;
  }

  Map<String, dynamic> _seatTypesToFirestore(Map<int, String> seatTypes) {
    return {
      for (final entry in seatTypes.entries)
        entry.key.toString(): LudoGame.normalizeSeatType(entry.value),
    };
  }

  Map<String, int> _readPlayerSeats({
    required Map<String, dynamic> data,
    required List<String> players,
    required int maxPlayers,
  }) {
    final result = <String, int>{};
    final rawSeats = data['playerSeats'];

    if (rawSeats is Map) {
      Map<String, dynamic>.from(rawSeats).forEach((playerId, value) {
        if (value is num) {
          result[playerId] = value.toInt().clamp(0, 3).toInt();
        }
      });
    }

    if (result.isEmpty) {
      final layout = LudoGame.seatLayoutForMaxPlayers(maxPlayers);
      for (
        int index = 0;
        index < players.length && index < layout.length;
        index++
      ) {
        result[players[index]] = layout[index];
      }
    }

    return result;
  }

  List<String> _sortPlayersBySeat({
    required Iterable<String> playerIds,
    required Map<String, int> playerSeats,
    required int maxPlayers,
  }) {
    final layout = LudoGame.seatLayoutForMaxPlayers(maxPlayers);
    final orderBySeat = <int, int>{
      for (int index = 0; index < layout.length; index++) layout[index]: index,
    };

    final sorted = playerIds.toList();
    sorted.sort((left, right) {
      final leftOrder = orderBySeat[playerSeats[left]] ?? 999;
      final rightOrder = orderBySeat[playerSeats[right]] ?? 999;
      return leftOrder.compareTo(rightOrder);
    });
    return sorted;
  }

  int _countOpenHumanSeats({
    required int maxPlayers,
    required Map<int, String> seatTypes,
    required Map<String, int> playerSeats,
    required Iterable<String> playerIds,
  }) {
    final occupiedSeats = playerIds
        .map((playerId) => playerSeats[playerId])
        .whereType<int>()
        .toSet();

    int open = 0;
    for (final seat in LudoGame.seatLayoutForMaxPlayers(maxPlayers)) {
      if (LudoGame.normalizeSeatType(seatTypes[seat]) == LudoGame.humanSeat &&
          !occupiedSeats.contains(seat)) {
        open++;
      }
    }
    return open;
  }

  Future<String> _createGameWithUniqueRoomCode(
    Map<String, dynamic> gameData,
  ) async {
    for (int attempt = 0; attempt < 10; attempt++) {
      final roomCode = _generateRoomCode();
      final ref = db.collection('games').doc(roomCode);

      final created = await db.runTransaction<bool>((transaction) async {
        final snap = await transaction.get(ref);

        if (snap.exists) return false;

        transaction.set(ref, gameData);
        return true;
      });

      if (created) return roomCode;
    }

    throw Exception('Could not generate a unique room code');
  }

  void listenGame(String id) {
    final generation = ++_listenerGeneration;
    unawaited(gameSubscription?.cancel());
    startChatTracking(id);

    gameSubscription = db
        .collection('games')
        .doc(id)
        .snapshots()
        .listen(
          (snap) {
            if (generation != _listenerGeneration || gameId != id) return;
            if (!snap.exists || snap.data() == null) {
              if (gameId == id) {
                unawaited(claimProgressionFromResult(id));
                unawaited(clearMyActiveGame(expectedGameId: id));
                _resetLocalGame(message: 'The room no longer exists.');
              }
              return;
            }

            LudoGame nextGame;
            try {
              nextGame = LudoGame.fromMap(snap.data()!);
            } catch (error, stackTrace) {
              debugPrint('Invalid game document $id: $error\n$stackTrace');
              statusMessage =
                  'The room data is invalid. Reconnecting safely...';
              notifyListeners();
              return;
            }

            final currentUserId = user?.uid;
            if (currentUserId != null &&
                !nextGame.players.contains(currentUserId)) {
              unawaited(clearMyActiveGame(expectedGameId: id));
              _resetLocalGame(message: 'You are no longer in this room.');
              return;
            }

            syncVisualActiveMove(nextGame.activeMove);
            game = nextGame;
            noteConnectionRestored();
            startPresenceTracking();
            syncDiceRollAnimation(nextGame.activeDiceRoll);
            syncTurnClock();
            syncRoomHeartbeat();
            _scheduleLegacyActionRecovery(id, nextGame);

            if (nextGame.status == 'finished' &&
                currentUserId != null &&
                nextGame.players.contains(currentUserId)) {
              unawaited(claimProgressionForGame(id, nextGame));
              unawaited(clearMyActiveGame(expectedGameId: id));
            } else if (nextGame.status == 'playing' &&
                nextGame.effectiveTurnDeadline == null) {
              unawaited(_ensureTurnStateInitialized(id));
            }

            notifyListeners();
            syncBotTurn();
          },
          onError: (Object error) {
            if (generation != _listenerGeneration || gameId != id) return;
            noteConnectionError();
            statusMessage = 'Connection lost. Reconnecting...';
            notifyListeners();
          },
        );
  }

  void _scheduleLegacyActionRecovery(String roomId, LudoGame nextGame) {
    if (nextGame.status != 'playing' ||
        !LudoRules.needsLegacyActionRecovery(nextGame)) {
      _legacyRecoveryTimer?.cancel();
      _legacyRecoveryTimer = null;
      _legacyRecoveryKey = null;
      return;
    }
    final key = nextGame.activeMove?.key ?? nextGame.activeDiceRoll?.key;
    if (key == null || _legacyRecoveryKey == key) return;
    _legacyRecoveryTimer?.cancel();
    _legacyRecoveryKey = key;
    _legacyRecoveryTimer = Timer(const Duration(seconds: 3), () async {
      final reference = db.collection('games').doc(roomId);
      try {
        await db.runTransaction((transaction) async {
          final snapshot = await transaction.get(reference);
          final data = snapshot.data();
          if (!snapshot.exists || data == null) return;
          final latest = LudoGame.fromMap(data);
          final latestKey =
              latest.activeMove?.key ?? latest.activeDiceRoll?.key;
          if (latest.status != 'playing' ||
              latestKey != key ||
              !LudoRules.needsLegacyActionRecovery(latest)) {
            return;
          }
          final seconds = LudoGame.decisionDurationForPhase(
            latest.hasRolled
                ? LudoGame.waitingForMove
                : LudoGame.waitingForRoll,
          );
          transaction.update(reference, {
            'activeMove': null,
            'activeDiceRoll': null,
            'automationLease': null,
            'turnPhase': latest.hasRolled
                ? LudoGame.waitingForMove
                : LudoGame.waitingForRoll,
            'turnStartedAt': FieldValue.serverTimestamp(),
            'turnDurationSeconds': seconds,
            'turnDeadlineAt': Timestamp.fromDate(
              estimatedServerNow.add(Duration(seconds: seconds)),
            ),
            'turnVersion': latest.turnVersion + 1,
            'lastActivityAt': FieldValue.serverTimestamp(),
          });
        });
      } catch (error) {
        debugPrint('Legacy action recovery failed: $error');
      }
    });
  }

  Future<void> _ensureTurnStateInitialized(String roomId) async {
    final reference = db.collection('games').doc(roomId);

    try {
      await db.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        if (!snapshot.exists || snapshot.data() == null) return;

        final latest = LudoGame.fromMap(snapshot.data()!);
        if (latest.status != 'playing' ||
            latest.effectiveTurnDeadline != null) {
          return;
        }

        final waitingForMove = latest.hasRolled;
        final seconds = LudoGame.decisionDurationForPhase(
          waitingForMove ? LudoGame.waitingForMove : LudoGame.waitingForRoll,
        );
        transaction.update(reference, {
          'turnPhase': waitingForMove
              ? LudoGame.waitingForMove
              : LudoGame.waitingForRoll,
          'turnStartedAt': FieldValue.serverTimestamp(),
          'turnDurationSeconds': seconds,
          'turnDeadlineAt': Timestamp.fromDate(
            estimatedServerNow.toUtc().add(Duration(seconds: seconds)),
          ),
          'turnVersion': latest.turnVersion <= 0 ? 1 : latest.turnVersion,
          'aiControlledPlayers': latest.aiControlledPlayers,
          'pendingReconnectPlayers': latest.pendingReconnectPlayers,
          'forfeitedPlayers': latest.forfeitedPlayers,
          'automationLease': null,
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (error) {
      if (kDebugMode) print('Turn-state migration error: $error');
    }
  }

  Future<void> createGame(
    String playerName,
    String selectedBoard,
    bool isTestMode, {
    int maxPlayers = 2,
    String opponentType = LudoGame.humanOpponents,
    Map<int, String>? seatTypes,
    bool isPublic = true,
  }) async {
    if (user == null || playerName.trim().isEmpty) {
      statusMessage = '❌ Please enter a nickname.';
      notifyListeners();
      return;
    }

    statusMessage = '';
    notifyListeners();

    final safeMaxPlayers = maxPlayers.clamp(2, 4).toInt();
    final safeBoardId = LudoBoardThemeResolver.normalizeId(selectedBoard);
    final layout = LudoGame.seatLayoutForMaxPlayers(safeMaxPlayers);
    final normalizedSeatTypes = _normalizedSeatTypes(
      maxPlayers: safeMaxPlayers,
      requestedSeatTypes: seatTypes,
      legacyOpponentType: opponentType,
    );
    final initialPos = isTestMode ? 49 : -1;

    final players = <String>[];
    final playerNames = <String, String>{};
    final preferredColors = <String, String>{};
    final playerDiceSkins = <String, String>{};
    final playerSeats = <String, int>{};
    final pieces = <String, dynamic>{};

    for (int slotIndex = 0; slotIndex < layout.length; slotIndex++) {
      final physicalSeat = layout[slotIndex];
      final seatType = normalizedSeatTypes[physicalSeat]!;

      if (slotIndex == 0) {
        final playerId = user!.uid;
        players.add(playerId);
        playerNames[playerId] = playerName.trim();
        preferredColors[playerId] = LudoPalette.defaultForSeat(physicalSeat);
        playerDiceSkins[playerId] = DiceSkinResolver.normalizeId(
          preferredDiceSkinId,
        );
        playerSeats[playerId] = physicalSeat;
        pieces[playerId] = createDefaultPieces(initialPos);
        continue;
      }

      if (seatType == LudoGame.computerSeat) {
        final botId = _botIdForSeat(physicalSeat);
        players.add(botId);
        playerNames[botId] = 'Computer ${slotIndex + 1}';
        preferredColors[botId] = LudoPalette.defaultForSeat(physicalSeat);
        playerDiceSkins[botId] = DiceSkinResolver.classicId;
        playerSeats[botId] = physicalSeat;
        pieces[botId] = createDefaultPieces(initialPos);
      }
    }

    final openSeats = safeMaxPlayers - players.length;
    final openHumanSeats = _countOpenHumanSeats(
      maxPlayers: safeMaxPlayers,
      seatTypes: normalizedSeatTypes,
      playerSeats: playerSeats,
      playerIds: players,
    );
    final hasHumanOpponentSeat = layout
        .skip(1)
        .any((seat) => normalizedSeatTypes[seat] == LudoGame.humanSeat);
    final effectivePublic = isPublic && hasHumanOpponentSeat;

    final gameData = <String, dynamic>{
      'players': players,
      'playerNames': playerNames,
      'preferredColors': preferredColors,
      'playerDiceSkins': playerDiceSkins,
      'playerSeats': playerSeats,
      'seatTypes': _seatTypesToFirestore(normalizedSeatTypes),
      'hostUid': user!.uid,
      'currentTurn': players.first,
      'diceValue': 0,
      'hasRolled': false,
      'status': 'waiting',
      'winnerUid': '',
      'finishOrder': const <String>[],
      'startedAt': null,
      'finishedAt': null,
      'boardId': safeBoardId,
      'isTestModeActive': isTestMode,
      'maxPlayers': safeMaxPlayers,
      'opponentType': LudoGame.deriveOpponentType(
        seatTypes: normalizedSeatTypes,
        maxPlayers: safeMaxPlayers,
      ),
      'isPublic': effectivePublic,
      'openSeats': openSeats,
      'matchmakingOpen': effectivePublic && openHumanSeats > 0,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActivityAt': FieldValue.serverTimestamp(),
      'expiresAt': _expiresAfter(waitingRoomLease),
      'activeChat': const LudoChat(
        sender: '',
        message: '',
        timestamp: 0,
      ).toMap(),
      'pieces': pieces,
      'activeMove': null,
      'activeDiceRoll': null,
      'turnPhase': LudoGame.waitingForRoll,
      'turnDeadlineAt': null,
      'turnStartedAt': null,
      'turnDurationSeconds': 0,
      'turnVersion': 0,
      'lastActionId': '',
      'lastActionType': '',
      'aiControlledPlayers': const <String>[],
      'pendingReconnectPlayers': const <String>[],
      'forfeitedPlayers': const <String>[],
      'automationLease': null,
      'systemEvent': null,
      // Legacy clients may still read this map. New session presence lives in
      // RTDB and deliberately does not invalidate the game snapshot.
      'playerPresence': const <String, dynamic>{},
    };

    try {
      final roomCode = await _createGameWithUniqueRoomCode(gameData);

      gameId = roomCode;
      await setMyActiveGame(roomCode);
      listenGame(roomCode);
    } catch (error) {
      statusMessage = '❌ Could not create the room.';
      notifyListeners();

      if (kDebugMode) {
        print('Create room error: $error');
      }
    }
  }

  Future<void> createSoloGame(
    String playerName,
    String selectedBoard,
    bool isTestMode,
  ) {
    return createGame(
      playerName,
      selectedBoard,
      isTestMode,
      maxPlayers: 2,
      seatTypes: const {0: LudoGame.humanSeat, 2: LudoGame.computerSeat},
      isPublic: false,
    );
  }

  Future<bool> joinGame(
    String playerName,
    String inputId, {
    bool showErrors = true,
  }) async {
    if (user == null || playerName.trim().isEmpty) {
      if (showErrors) {
        statusMessage = '❌ Please enter a nickname.';
        notifyListeners();
      }
      return false;
    }

    final cleanInputId = inputId.trim().toUpperCase();

    if (cleanInputId.isEmpty) {
      if (showErrors) {
        statusMessage = '❌ Please enter a room code.';
        notifyListeners();
      }
      return false;
    }

    if (showErrors) {
      statusMessage = '';
      notifyListeners();
    }

    try {
      final joined = await _attemptJoinGame(
        playerName: playerName.trim(),
        roomCode: cleanInputId,
        requirePublicMatchmaking: false,
      );

      if (!joined) return false;

      gameId = cleanInputId;
      await setMyActiveGame(cleanInputId);
      listenGame(cleanInputId);
      return true;
    } catch (error) {
      if (showErrors) {
        final message = error.toString();

        if (message.contains('Game not found')) {
          statusMessage = '❌ Game not found.';
        } else if (message.contains('already full') ||
            message.contains('no open human seat')) {
          statusMessage = '❌ This room has no open human seat.';
        } else if (message.contains('already started')) {
          statusMessage = '❌ This match has already started.';
        } else if (message.contains('expired')) {
          statusMessage = '❌ This room has expired.';
        } else {
          statusMessage = '❌ Could not join the room.';
        }

        notifyListeners();
      }

      return false;
    }
  }

  Future<bool> _attemptJoinGame({
    required String playerName,
    required String roomCode,
    required bool requirePublicMatchmaking,
  }) async {
    final currentUser = user;
    if (currentUser == null) return false;

    final ref = db.collection('games').doc(roomCode);

    await db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);

      if (!snap.exists || snap.data() == null) {
        throw Exception('Game not found');
      }

      final data = Map<String, dynamic>.from(snap.data()!);
      final players = _stringList(data['players']);
      final maxPlayers = _integer(data['maxPlayers'], 2).clamp(2, 4).toInt();
      final status = _string(data['status'], 'waiting');

      if (status != 'waiting') {
        throw Exception('Game already started');
      }

      if (requirePublicMatchmaking) {
        final hasMatchmakingFlag = data.containsKey('matchmakingOpen');
        final hasPublicFlag = data.containsKey('isPublic');

        if (hasMatchmakingFlag && data['matchmakingOpen'] != true) {
          throw Exception('Room is not open for matchmaking');
        }

        if (hasPublicFlag && data['isPublic'] == false) {
          throw Exception('Room is private');
        }

        if (!_hasActiveWaitingLease(data)) {
          throw Exception('Room expired');
        }
      } else {
        final rawExpiresAt = data['expiresAt'];
        if (rawExpiresAt is Timestamp &&
            !rawExpiresAt.toDate().toUtc().isAfter(
              estimatedServerNow.toUtc(),
            )) {
          throw Exception('Room expired');
        }
      }

      if (players.contains(currentUser.uid)) return;

      final layout = LudoGame.seatLayoutForMaxPlayers(maxPlayers);
      final seatTypes = LudoGame.parseSeatTypes(data, maxPlayers);
      final playerSeats = _readPlayerSeats(
        data: data,
        players: players,
        maxPlayers: maxPlayers,
      );
      final occupiedSeats = players
          .map((playerId) => playerSeats[playerId])
          .whereType<int>()
          .toSet();

      int? availableSeat;
      for (final seat in layout) {
        if (seatTypes[seat] == LudoGame.humanSeat &&
            !occupiedSeats.contains(seat)) {
          availableSeat = seat;
          break;
        }
      }

      if (availableSeat == null) {
        if (players.length >= maxPlayers) {
          throw Exception('This room is already full');
        }
        throw Exception('no open human seat');
      }

      final isTestModeActive = data['isTestModeActive'] == true;
      final initialPos = isTestModeActive ? 49 : -1;

      final playerNames = _dynamicMap(data['playerNames']);
      playerNames[currentUser.uid] = playerName;

      final preferredColors = _dynamicMap(data['preferredColors']);
      preferredColors[currentUser.uid] = LudoPalette.defaultForSeat(
        availableSeat,
      );
      final updatedPlayers = _sortPlayersBySeat(
        playerIds: [...players, currentUser.uid],
        playerSeats: {...playerSeats, currentUser.uid: availableSeat},
        maxPlayers: maxPlayers,
      );
      final playerDiceSkins = DiceSkinResolver.withPlayer(
        data['playerDiceSkins'],
        playerIds: updatedPlayers,
        playerId: currentUser.uid,
        skinId: preferredDiceSkinId,
      );
      playerSeats[currentUser.uid] = availableSeat;

      final pieces = _dynamicMap(data['pieces']);
      pieces[currentUser.uid] = createDefaultPieces(initialPos);

      final openSeats = maxPlayers - updatedPlayers.length;
      final openHumanSeats = _countOpenHumanSeats(
        maxPlayers: maxPlayers,
        seatTypes: seatTypes,
        playerSeats: playerSeats,
        playerIds: updatedPlayers,
      );
      final isPublic = data['isPublic'] is bool
          ? data['isPublic'] as bool
          : true;
      final hostUid = _string(data['hostUid']).isNotEmpty
          ? _string(data['hostUid'])
          : (players.isNotEmpty ? players.first : currentUser.uid);
      transaction.update(ref, {
        'players': updatedPlayers,
        'playerNames': playerNames,
        'preferredColors': preferredColors,
        'playerDiceSkins': playerDiceSkins,
        'playerSeats': playerSeats,
        'seatTypes': _seatTypesToFirestore(seatTypes),
        'hostUid': hostUid,
        'pieces': pieces,
        'maxPlayers': maxPlayers,
        'opponentType': LudoGame.deriveOpponentType(
          seatTypes: seatTypes,
          maxPlayers: maxPlayers,
        ),
        'isPublic': isPublic,
        'openSeats': openSeats,
        'matchmakingOpen': isPublic && openHumanSeats > 0,
        'status': 'waiting',
        'activeMove': null,
        'activeDiceRoll': null,
        'lastActivityAt': FieldValue.serverTimestamp(),
        'expiresAt': _expiresAfter(waitingRoomLease),
      });
    });

    return true;
  }

  Future<void> randomJoinGame(
    String playerName,
    String selectedBoard,
    bool isTestMode,
  ) async {
    if (user == null || playerName.trim().isEmpty) {
      statusMessage = '❌ Please enter a nickname.';
      notifyListeners();
      return;
    }

    statusMessage = 'Searching for a public room...';
    notifyListeners();

    try {
      final now = Timestamp.fromDate(estimatedServerNow);
      QuerySnapshot<Map<String, dynamic>> query;

      try {
        query = await db
            .collection('games')
            .where('status', isEqualTo: 'waiting')
            .where('isPublic', isEqualTo: true)
            .where('matchmakingOpen', isEqualTo: true)
            .where('expiresAt', isGreaterThan: now)
            .orderBy('expiresAt', descending: true)
            .limit(5)
            .get();
      } on FirebaseException catch (error) {
        // This fallback keeps matchmaking usable until the composite index
        // from firestore.indexes.json has finished building.
        if (error.code != 'failed-precondition') rethrow;

        query = await db
            .collection('games')
            .where('status', isEqualTo: 'waiting')
            .where('isPublic', isEqualTo: true)
            .where('matchmakingOpen', isEqualTo: true)
            .limit(20)
            .get();
      }

      final candidates =
          query.docs.where((candidate) {
            final data = candidate.data();
            return data['status'] == 'waiting' &&
                data['isPublic'] != false &&
                data['matchmakingOpen'] == true &&
                _hasActiveWaitingLease(data);
          }).toList()..sort((left, right) {
            final leftExpiry = left.data()['expiresAt'];
            final rightExpiry = right.data()['expiresAt'];
            if (leftExpiry is! Timestamp || rightExpiry is! Timestamp) return 0;
            return rightExpiry.toDate().compareTo(leftExpiry.toDate());
          });

      for (final candidate in candidates) {
        final joined = await _attemptJoinGame(
          playerName: playerName.trim(),
          roomCode: candidate.id,
          requirePublicMatchmaking: true,
        ).catchError((_) => false);

        if (joined) {
          gameId = candidate.id;
          await setMyActiveGame(candidate.id);
          listenGame(candidate.id);
          statusMessage = '';
          notifyListeners();
          return;
        }
      }

      await createGame(
        playerName,
        selectedBoard,
        isTestMode,
        maxPlayers: 2,
        seatTypes: const {0: LudoGame.humanSeat, 2: LudoGame.humanSeat},
        isPublic: true,
      );

      if (gameId.isNotEmpty) {
        statusMessage =
            'No open room was available, so a public room was created for you.';
        notifyListeners();
      }
    } catch (error) {
      statusMessage = '❌ Matchmaking failed.';
      notifyListeners();

      if (kDebugMode) {
        print('Matchmaking error: $error');
      }
    }
  }

  Future<bool> updateWaitingRoomSettings({
    required String selectedBoard,
    required bool isTestMode,
    required int maxPlayers,
    required Map<int, String> seatTypes,
    required bool isPublic,
  }) async {
    if (gameId.isEmpty || game == null || !isHost) return false;
    if (game!.status != 'waiting') return false;

    final safeMaxPlayers = maxPlayers.clamp(2, 4).toInt();
    final safeBoardId = LudoBoardThemeResolver.normalizeId(selectedBoard);
    final newLayout = LudoGame.seatLayoutForMaxPlayers(safeMaxPlayers);
    final normalizedSeatTypes = _normalizedSeatTypes(
      maxPlayers: safeMaxPlayers,
      requestedSeatTypes: seatTypes,
    );
    final ref = db.collection('games').doc(gameId);

    try {
      await db.runTransaction((transaction) async {
        final snap = await transaction.get(ref);
        if (!snap.exists || snap.data() == null) {
          throw Exception('Room not found');
        }

        final data = Map<String, dynamic>.from(snap.data()!);
        if (_string(data['status'], 'waiting') != 'waiting') {
          throw Exception('The match has already started');
        }
        final hostUid = _string(data['hostUid']);
        if (hostUid != user?.uid) {
          throw Exception('Only the host can update settings');
        }

        final currentPlayers = _stringList(data['players']);
        final oldMaxPlayers = _integer(
          data['maxPlayers'],
          2,
        ).clamp(2, 4).toInt();
        final oldPlayerSeats = _readPlayerSeats(
          data: data,
          players: currentPlayers,
          maxPlayers: oldMaxPlayers,
        );
        final humanPlayers = currentPlayers
            .where((playerId) => !_isBotId(playerId))
            .toList();

        final humanBySeat = <int, String>{};
        for (final playerId in humanPlayers) {
          final seat = oldPlayerSeats[playerId];
          if (seat == null) continue;
          humanBySeat[seat] = playerId;
        }

        final hostSeat = newLayout.first;
        humanBySeat.removeWhere((_, playerId) => playerId == hostUid);
        humanBySeat[hostSeat] = hostUid;

        for (final entry in humanBySeat.entries) {
          final seat = entry.key;
          final playerId = entry.value;

          if (!newLayout.contains(seat)) {
            throw Exception(
              '${playerId == hostUid ? 'The host' : 'A real player'} occupies a seat removed by the new player count.',
            );
          }

          if (normalizedSeatTypes[seat] != LudoGame.humanSeat) {
            throw Exception(
              'A real player is already sitting in that seat. They must leave before it can become AI.',
            );
          }
        }

        final playerNames = _dynamicMap(data['playerNames'])
          ..removeWhere((key, _) => _isBotId(key));
        final preferredColors = _dynamicMap(data['preferredColors'])
          ..removeWhere((key, _) => _isBotId(key));
        final rawPlayerDiceSkins = _dynamicMap(data['playerDiceSkins']);
        final playerDiceSkins = DiceSkinResolver.normalizePlayerMap(
          rawPlayerDiceSkins,
          humanPlayers,
        );
        if (!rawPlayerDiceSkins.containsKey(hostUid)) {
          playerDiceSkins[hostUid] = DiceSkinResolver.normalizeId(
            preferredDiceSkinId,
          );
        }

        final updatedPlayerSeats = <String, int>{};
        final updatedPieces = <String, dynamic>{};
        final initialPos = isTestMode ? 49 : -1;

        for (final entry in humanBySeat.entries) {
          final seat = entry.key;
          final playerId = entry.value;
          updatedPlayerSeats[playerId] = seat;
          preferredColors.putIfAbsent(
            playerId,
            () => LudoPalette.defaultForSeat(seat),
          );
          updatedPieces[playerId] = createDefaultPieces(initialPos);
        }

        final occupiedPlayers = <String>[...humanBySeat.values];

        for (int slotIndex = 1; slotIndex < newLayout.length; slotIndex++) {
          final physicalSeat = newLayout[slotIndex];

          if (normalizedSeatTypes[physicalSeat] == LudoGame.computerSeat) {
            final botId = _botIdForSeat(physicalSeat);
            occupiedPlayers.add(botId);
            playerNames[botId] = 'Computer ${slotIndex + 1}';
            preferredColors[botId] = LudoPalette.defaultForSeat(physicalSeat);
            playerDiceSkins[botId] = DiceSkinResolver.classicId;
            updatedPlayerSeats[botId] = physicalSeat;
            updatedPieces[botId] = createDefaultPieces(initialPos);
          }
        }

        final updatedPlayers = _sortPlayersBySeat(
          playerIds: occupiedPlayers,
          playerSeats: updatedPlayerSeats,
          maxPlayers: safeMaxPlayers,
        );
        final openSeats = safeMaxPlayers - updatedPlayers.length;
        final openHumanSeats = _countOpenHumanSeats(
          maxPlayers: safeMaxPlayers,
          seatTypes: normalizedSeatTypes,
          playerSeats: updatedPlayerSeats,
          playerIds: updatedPlayers,
        );
        final hasHumanOpponentSeat = newLayout
            .skip(1)
            .any((seat) => normalizedSeatTypes[seat] == LudoGame.humanSeat);
        final effectivePublic = isPublic && hasHumanOpponentSeat;

        transaction.update(ref, {
          'players': updatedPlayers,
          'playerNames': playerNames,
          'preferredColors': preferredColors,
          'playerDiceSkins': playerDiceSkins,
          'playerSeats': updatedPlayerSeats,
          'seatTypes': _seatTypesToFirestore(normalizedSeatTypes),
          'pieces': updatedPieces,
          'boardId': safeBoardId,
          'isTestModeActive': isTestMode,
          'maxPlayers': safeMaxPlayers,
          'opponentType': LudoGame.deriveOpponentType(
            seatTypes: normalizedSeatTypes,
            maxPlayers: safeMaxPlayers,
          ),
          'isPublic': effectivePublic,
          'openSeats': openSeats,
          'matchmakingOpen': effectivePublic && openHumanSeats > 0,
          'diceValue': 0,
          'hasRolled': false,
          'currentTurn': updatedPlayers.isNotEmpty ? updatedPlayers.first : '',
          'winnerUid': '',
          'finishOrder': const <String>[],
          'startedAt': null,
          'finishedAt': null,
          'activeMove': null,
          'activeDiceRoll': null,
          'turnPhase': LudoGame.waitingForRoll,
          'turnDeadlineAt': null,
          'turnStartedAt': null,
          'turnDurationSeconds': 0,
          'turnVersion': 0,
          'lastActionId': '',
          'lastActionType': '',
          'aiControlledPlayers': const <String>[],
          'pendingReconnectPlayers': const <String>[],
          'forfeitedPlayers': const <String>[],
          'automationLease': null,
          'systemEvent': null,
          'lastActivityAt': FieldValue.serverTimestamp(),
          'expiresAt': _expiresAfter(waitingRoomLease),
        });
      });

      statusMessage = '';
      notifyListeners();
      return true;
    } catch (error) {
      statusMessage = error.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<void> updateMyPreferredColor(String colorId) async {
    if (gameId.isEmpty || game == null || user == null) return;
    if (game!.status != 'waiting') return;

    final normalizedColor = LudoPalette.normalize(colorId);

    final reference = db.collection('games').doc(gameId);
    await db.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return;
      final latest = LudoGame.fromMap(data);
      if (latest.status != 'waiting' || !latest.players.contains(user!.uid)) {
        return;
      }
      transaction.update(reference, {
        'preferredColors.${user!.uid}': normalizedColor,
        'lastActivityAt': FieldValue.serverTimestamp(),
        'expiresAt': _expiresAfter(waitingRoomLease),
      });
    });
  }

  Future<void> startGame() async {
    if (gameId.isEmpty || game == null || !isHost) return;

    if (!game!.isReady) {
      statusMessage =
          '⚠️ Waiting for ${game!.openHumanSeats} more real player(s).';
      notifyListeners();
      return;
    }

    statusMessage = '';
    notifyListeners();

    final reference = db.collection('games').doc(gameId);
    try {
      await db.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          throw StateError('Room no longer exists');
        }
        final latest = LudoGame.fromMap(data);
        if (latest.hostUid != user?.uid || latest.status != 'waiting') {
          throw StateError('Only the current host can start this room');
        }
        if (!latest.isReady || latest.players.isEmpty) {
          throw StateError('The room is not ready');
        }
        transaction.update(reference, {
          'status': 'playing',
          'currentTurn': latest.players.first,
          'diceValue': 0,
          'hasRolled': false,
          'winnerUid': '',
          'finishOrder': const <String>[],
          'startedAt': FieldValue.serverTimestamp(),
          'finishedAt': null,
          'activeMove': null,
          'activeDiceRoll': null,
          'turnPhase': LudoGame.waitingForRoll,
          'turnStartedAt': FieldValue.serverTimestamp(),
          'turnDurationSeconds': LudoGame.rollDecisionSeconds,
          'turnDeadlineAt': Timestamp.fromDate(
            estimatedServerNow.toUtc().add(
              const Duration(seconds: LudoGame.rollDecisionSeconds),
            ),
          ),
          'turnVersion': latest.turnVersion + 1,
          'lastActionId': '',
          'lastActionType': '',
          'aiControlledPlayers': const <String>[],
          'pendingReconnectPlayers': const <String>[],
          'forfeitedPlayers': const <String>[],
          'automationLease': null,
          'systemEvent': null,
          'matchmakingOpen': false,
          'openSeats': 0,
          'lastActivityAt': FieldValue.serverTimestamp(),
          'expiresAt': _expiresAfter(activeGameLease),
        });
      });
    } catch (error) {
      statusMessage =
          'Could not start the match: ${error.toString().replaceFirst('Bad state: ', '')}';
      notifyListeners();
    }
  }

  Future<void> leaveGame() async {
    final currentGameId = gameId;
    final currentGame = game;
    final currentUser = user;

    if (currentGameId.isEmpty || currentGame == null || currentUser == null) {
      _resetLocalGame();
      return;
    }

    if (currentGame.status == 'waiting') {
      final ref = db.collection('games').doc(currentGameId);
      var startedWhileLeaving = false;

      try {
        await db.runTransaction((transaction) async {
          final snap = await transaction.get(ref);
          if (!snap.exists || snap.data() == null) return;

          final data = Map<String, dynamic>.from(snap.data()!);
          if (_string(data['status'], 'waiting') != 'waiting') {
            startedWhileLeaving = true;
            return;
          }
          final initialPlayers = _stringList(data['players']);
          final hostUid = _string(data['hostUid']).isNotEmpty
              ? _string(data['hostUid'])
              : (initialPlayers.isNotEmpty ? initialPlayers.first : '');

          if (hostUid == currentUser.uid) {
            transaction.delete(ref);
            return;
          }

          final players = _stringList(data['players'])..remove(currentUser.uid);
          final maxPlayers = _integer(
            data['maxPlayers'],
            2,
          ).clamp(2, 4).toInt();
          final seatTypes = LudoGame.parseSeatTypes(data, maxPlayers);

          final playerNames = _dynamicMap(data['playerNames'])
            ..remove(currentUser.uid);
          final preferredColors = _dynamicMap(data['preferredColors'])
            ..remove(currentUser.uid);
          final playerDiceSkins = _dynamicMap(data['playerDiceSkins'])
            ..remove(currentUser.uid);
          final playerSeats = _dynamicMap(data['playerSeats'])
            ..remove(currentUser.uid);
          final pieces = _dynamicMap(data['pieces'])..remove(currentUser.uid);
          final playerPresence = _dynamicMap(data['playerPresence'])
            ..remove(currentUser.uid);

          final typedPlayerSeats = <String, int>{};
          playerSeats.forEach((playerId, value) {
            if (value is num) {
              typedPlayerSeats[playerId] = value.toInt();
            }
          });

          final isPublic = data['isPublic'] is bool
              ? data['isPublic'] as bool
              : true;
          final openSeats = maxPlayers - players.length;
          final openHumanSeats = _countOpenHumanSeats(
            maxPlayers: maxPlayers,
            seatTypes: seatTypes,
            playerSeats: typedPlayerSeats,
            playerIds: players,
          );

          transaction.update(ref, {
            'players': players,
            'playerNames': playerNames,
            'preferredColors': preferredColors,
            'playerDiceSkins': playerDiceSkins,
            'playerSeats': playerSeats,
            'seatTypes': _seatTypesToFirestore(seatTypes),
            'pieces': pieces,
            'playerPresence': playerPresence,
            'openSeats': openSeats,
            'matchmakingOpen': isPublic && openHumanSeats > 0,
            'currentTurn': players.isNotEmpty ? players.first : '',
            'lastActivityAt': FieldValue.serverTimestamp(),
            'expiresAt': _expiresAfter(waitingRoomLease),
          });
        });
        if (startedWhileLeaving) await markMyselfForfeit();
      } catch (error) {
        if (kDebugMode) {
          print('Leave room error: $error');
        }
      }
    }

    await clearMyActiveGame(expectedGameId: currentGameId);
    _resetLocalGame();
  }

  Future<bool> continueActiveGame() async {
    final currentUser = user;
    final roomId = activeGameId;
    if (currentUser == null || roomId.isEmpty) return false;

    try {
      final snapshot = await db.collection('games').doc(roomId).get();
      if (!snapshot.exists || snapshot.data() == null) {
        await claimProgressionFromResult(roomId);
        await clearMyActiveGame(expectedGameId: roomId);
        return false;
      }

      final candidate = LudoGame.fromMap(snapshot.data()!);
      if (candidate.status == 'finished' &&
          candidate.players.contains(currentUser.uid)) {
        await claimProgressionForGame(roomId, candidate);
        await clearMyActiveGame(expectedGameId: roomId);
        return false;
      }

      if (!candidate.players.contains(currentUser.uid) ||
          (candidate.status != 'waiting' && candidate.status != 'playing')) {
        await clearMyActiveGame(expectedGameId: roomId);
        return false;
      }

      gameId = roomId;
      game = candidate;
      resumableGame = null;
      await markPresenceReconnecting();
      listenGame(roomId);
      notifyListeners();
      return true;
    } catch (error) {
      statusMessage = '\u274C Could not reconnect to the match.';
      notifyListeners();
      return false;
    }
  }

  Future<void> reconnectCurrentGame() async {
    if (gameId.isNotEmpty && game != null) {
      await markPresenceReconnecting();
      listenGame(gameId);
      return;
    }
    await refreshResumableGame();
  }

  void leaveTemporarily() {
    final currentRoomId = gameId;
    if (currentRoomId.isNotEmpty && game != null) {
      activeGameId = currentRoomId;
      resumableGame = game;
      unawaited(markPresenceOffline(roomId: currentRoomId));
    }
    _resetLocalGame();
  }

  Future<void> forfeitAndLeave() async {
    final currentId = gameId;
    final forfeited = await markMyselfForfeit();
    if (!forfeited) {
      statusMessage = '\u274C Could not forfeit the match.';
      notifyListeners();
      return;
    }

    await markPresenceOffline(roomId: currentId);
    await clearMyActiveGame(expectedGameId: currentId);
    _resetLocalGame();
  }

  void quitToMenu() {
    final currentId = gameId;
    if (game?.status == 'finished' && currentId.isNotEmpty) {
      unawaited(clearMyActiveGame(expectedGameId: currentId));
    }
    _resetLocalGame();
  }

  void _resetLocalGame({String message = ''}) {
    _listenerGeneration++;
    unawaited(gameSubscription?.cancel());
    gameSubscription = null;
    _legacyRecoveryTimer?.cancel();
    _legacyRecoveryTimer = null;
    _legacyRecoveryKey = null;
    stopPresenceTracking();
    stopChatTracking();
    localConnectionState = PlayerPresence.offline;
    stopRoomHeartbeat();
    cancelBotTurn();
    stopDiceRollAnimation();
    gameId = '';
    game = null;
    statusMessage = message;
    syncVisualActiveMove(null);
    syncTurnClock();
    notifyListeners();
  }
}
