import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../game/ludo_palette.dart';
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

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  get gameSubscription;
  set gameSubscription(
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? value,
      );

  bool get isHost;

  List<Map<String, dynamic>> createDefaultPieces(int initialPos);
  void syncVisualActiveMove(ActiveMove? remoteMove);
  void syncBotTurn();
  void cancelBotTurn();

  static const String _roomCodeChars =
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static const Duration waitingRoomLease = Duration(minutes: 2);
  static const Duration activeGameLease = Duration(hours: 24);
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  Timer? _roomHeartbeatTimer;
  String? _heartbeatRoomId;

  Timestamp _expiresAfter(Duration duration) {
    return Timestamp.fromDate(
      DateTime.now().toUtc().add(duration),
    );
  }

  bool _hasActiveWaitingLease(Map<String, dynamic> data) {
    final rawExpiresAt = data['expiresAt'];
    if (rawExpiresAt is! Timestamp) return false;

    return rawExpiresAt.toDate().toUtc().isAfter(DateTime.now().toUtc());
  }

  void syncRoomHeartbeat() {
    final shouldRun = gameId.isNotEmpty &&
        game?.status == 'waiting' &&
        isHost;

    if (!shouldRun) {
      stopRoomHeartbeat();
      return;
    }

    if (_heartbeatRoomId == gameId &&
        _roomHeartbeatTimer?.isActive == true) {
      return;
    }

    stopRoomHeartbeat();
    _heartbeatRoomId = gameId;
    unawaited(_refreshWaitingRoomLease());

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
      await db.collection('games').doc(currentId).update({
        'lastActivityAt': FieldValue.serverTimestamp(),
        'expiresAt': _expiresAfter(waitingRoomLease),
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
      for (int index = 0;
      index < players.length && index < layout.length;
      index++) {
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
      for (int index = 0; index < layout.length; index++)
        layout[index]: index,
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
      if (LudoGame.normalizeSeatType(seatTypes[seat]) ==
          LudoGame.humanSeat &&
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
    gameSubscription?.cancel();

    gameSubscription = db.collection('games').doc(id).snapshots().listen(
          (snap) {
        if (!snap.exists || snap.data() == null) {
          if (gameId == id) {
            _resetLocalGame(
              message: 'The room no longer exists.',
            );
          }
          return;
        }

        final nextGame = LudoGame.fromMap(snap.data()!);

        syncVisualActiveMove(nextGame.activeMove);
        game = nextGame;
        syncRoomHeartbeat();
        notifyListeners();
        syncBotTurn();
      },
      onError: (Object error) {
        statusMessage = '❌ Lost connection to the room.';
        notifyListeners();
      },
    );
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
    final playerSeats = <String, int>{};
    final pieces = <String, dynamic>{};

    for (int slotIndex = 0; slotIndex < layout.length; slotIndex++) {
      final physicalSeat = layout[slotIndex];
      final seatType = normalizedSeatTypes[physicalSeat]!;

      if (slotIndex == 0) {
        final playerId = user!.uid;
        players.add(playerId);
        playerNames[playerId] = playerName.trim();
        preferredColors[playerId] =
            LudoPalette.defaultForSeat(physicalSeat);
        playerSeats[playerId] = physicalSeat;
        pieces[playerId] = createDefaultPieces(initialPos);
        continue;
      }

      if (seatType == LudoGame.computerSeat) {
        final botId = _botIdForSeat(physicalSeat);
        players.add(botId);
        playerNames[botId] = 'Computer ${slotIndex + 1}';
        preferredColors[botId] = LudoPalette.defaultForSeat(physicalSeat);
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
    final hasHumanOpponentSeat = layout.skip(1).any(
          (seat) => normalizedSeatTypes[seat] == LudoGame.humanSeat,
    );
    final effectivePublic = isPublic && hasHumanOpponentSeat;

    final gameData = <String, dynamic>{
      'players': players,
      'playerNames': playerNames,
      'preferredColors': preferredColors,
      'playerSeats': playerSeats,
      'seatTypes': _seatTypesToFirestore(normalizedSeatTypes),
      'hostUid': user!.uid,
      'currentTurn': players.first,
      'diceValue': 0,
      'hasRolled': false,
      'status': 'waiting',
      'winnerUid': '',
      'boardId': selectedBoard,
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
    };

    try {
      final roomCode = await _createGameWithUniqueRoomCode(gameData);

      gameId = roomCode;
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
      seatTypes: const {
        0: LudoGame.humanSeat,
        2: LudoGame.computerSeat,
      },
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
      final players = List<String>.from(data['players'] ?? []);
      final maxPlayers =
      (data['maxPlayers'] as int? ?? 2).clamp(2, 4).toInt();
      final status = data['status'] as String? ?? 'waiting';

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
            !rawExpiresAt.toDate().toUtc().isAfter(DateTime.now().toUtc())) {
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

      final playerNames = Map<String, dynamic>.from(
        data['playerNames'] ?? {},
      );
      playerNames[currentUser.uid] = playerName;

      final preferredColors = Map<String, dynamic>.from(
        data['preferredColors'] ?? {},
      );
      preferredColors[currentUser.uid] =
          LudoPalette.defaultForSeat(availableSeat);
      playerSeats[currentUser.uid] = availableSeat;

      final pieces = Map<String, dynamic>.from(data['pieces'] ?? {});
      pieces[currentUser.uid] = createDefaultPieces(initialPos);

      final updatedPlayers = _sortPlayersBySeat(
        playerIds: [...players, currentUser.uid],
        playerSeats: playerSeats,
        maxPlayers: maxPlayers,
      );
      final openSeats = maxPlayers - updatedPlayers.length;
      final openHumanSeats = _countOpenHumanSeats(
        maxPlayers: maxPlayers,
        seatTypes: seatTypes,
        playerSeats: playerSeats,
        playerIds: updatedPlayers,
      );
      final isPublic = data['isPublic'] as bool? ?? true;
      final hostUid = data['hostUid'] as String? ??
          (players.isNotEmpty ? players.first : currentUser.uid);

      transaction.update(ref, {
        'players': updatedPlayers,
        'playerNames': playerNames,
        'preferredColors': preferredColors,
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
      final now = Timestamp.now();
      QuerySnapshot<Map<String, dynamic>> query;

      try {
        query = await db
            .collection('games')
            .where('status', isEqualTo: 'waiting')
            .where('matchmakingOpen', isEqualTo: true)
            .where('expiresAt', isGreaterThan: now)
            .orderBy('expiresAt', descending: true)
            .limit(20)
            .get();
      } on FirebaseException catch (error) {
        // This fallback keeps matchmaking usable until the composite index
        // from firestore.indexes.json has finished building.
        if (error.code != 'failed-precondition') rethrow;

        query = await db
            .collection('games')
            .where('matchmakingOpen', isEqualTo: true)
            .limit(100)
            .get();
      }

      final candidates = query.docs.where((candidate) {
        final data = candidate.data();
        return data['status'] == 'waiting' &&
            data['isPublic'] != false &&
            data['matchmakingOpen'] == true &&
            _hasActiveWaitingLease(data);
      }).toList()
        ..sort((left, right) {
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
        seatTypes: const {
          0: LudoGame.humanSeat,
          2: LudoGame.humanSeat,
        },
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

  Future<void> updateWaitingRoomSettings({
    required String selectedBoard,
    required bool isTestMode,
    required int maxPlayers,
    required Map<int, String> seatTypes,
    required bool isPublic,
  }) async {
    if (gameId.isEmpty || game == null || !isHost) return;
    if (game!.status != 'waiting') return;

    final safeMaxPlayers = maxPlayers.clamp(2, 4).toInt();
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
        final hostUid = data['hostUid'] as String? ?? '';
        if (hostUid != user?.uid) {
          throw Exception('Only the host can update settings');
        }

        final currentPlayers = List<String>.from(data['players'] ?? []);
        final oldMaxPlayers =
        (data['maxPlayers'] as int? ?? 2).clamp(2, 4).toInt();
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

        final playerNames = Map<String, dynamic>.from(
          data['playerNames'] ?? {},
        )..removeWhere((key, _) => _isBotId(key));
        final preferredColors = Map<String, dynamic>.from(
          data['preferredColors'] ?? {},
        )..removeWhere((key, _) => _isBotId(key));

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

        for (int slotIndex = 1;
        slotIndex < newLayout.length;
        slotIndex++) {
          final physicalSeat = newLayout[slotIndex];

          if (normalizedSeatTypes[physicalSeat] ==
              LudoGame.computerSeat) {
            final botId = _botIdForSeat(physicalSeat);
            occupiedPlayers.add(botId);
            playerNames[botId] = 'Computer ${slotIndex + 1}';
            preferredColors[botId] =
                LudoPalette.defaultForSeat(physicalSeat);
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
        final hasHumanOpponentSeat = newLayout.skip(1).any(
              (seat) =>
          normalizedSeatTypes[seat] == LudoGame.humanSeat,
        );
        final effectivePublic = isPublic && hasHumanOpponentSeat;

        transaction.update(ref, {
          'players': updatedPlayers,
          'playerNames': playerNames,
          'preferredColors': preferredColors,
          'playerSeats': updatedPlayerSeats,
          'seatTypes': _seatTypesToFirestore(normalizedSeatTypes),
          'pieces': updatedPieces,
          'boardId': selectedBoard,
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
          'currentTurn': updatedPlayers.isNotEmpty
              ? updatedPlayers.first
              : '',
          'activeMove': null,
          'lastActivityAt': FieldValue.serverTimestamp(),
          'expiresAt': _expiresAfter(waitingRoomLease),
        });
      });

      statusMessage = '';
      notifyListeners();
    } catch (error) {
      statusMessage = error.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  Future<void> updateMyPreferredColor(String colorId) async {
    if (gameId.isEmpty || game == null || user == null) return;
    if (game!.status != 'waiting') return;

    final normalizedColor = LudoPalette.normalize(colorId);

    await db.collection('games').doc(gameId).update({
      'preferredColors.${user!.uid}': normalizedColor,
      'lastActivityAt': FieldValue.serverTimestamp(),
      'expiresAt': _expiresAfter(waitingRoomLease),
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

    await db.collection('games').doc(gameId).update({
      'status': 'playing',
      'currentTurn': game!.players.first,
      'diceValue': 0,
      'hasRolled': false,
      'activeMove': null,
      'matchmakingOpen': false,
      'openSeats': 0,
      'lastActivityAt': FieldValue.serverTimestamp(),
      'expiresAt': _expiresAfter(activeGameLease),
    });
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

      try {
        await db.runTransaction((transaction) async {
          final snap = await transaction.get(ref);
          if (!snap.exists || snap.data() == null) return;

          final data = Map<String, dynamic>.from(snap.data()!);
          final hostUid = data['hostUid'] as String? ??
              (List<String>.from(data['players'] ?? []).isNotEmpty
                  ? List<String>.from(data['players'] ?? []).first
                  : '');

          if (hostUid == currentUser.uid) {
            transaction.delete(ref);
            return;
          }

          final players = List<String>.from(data['players'] ?? [])
            ..remove(currentUser.uid);
          final maxPlayers =
          (data['maxPlayers'] as int? ?? 2).clamp(2, 4).toInt();
          final seatTypes = LudoGame.parseSeatTypes(data, maxPlayers);

          final playerNames = Map<String, dynamic>.from(
            data['playerNames'] ?? {},
          )..remove(currentUser.uid);
          final preferredColors = Map<String, dynamic>.from(
            data['preferredColors'] ?? {},
          )..remove(currentUser.uid);
          final playerSeats = Map<String, dynamic>.from(
            data['playerSeats'] ?? {},
          )..remove(currentUser.uid);
          final pieces = Map<String, dynamic>.from(data['pieces'] ?? {})
            ..remove(currentUser.uid);

          final typedPlayerSeats = <String, int>{};
          playerSeats.forEach((playerId, value) {
            if (value is num) {
              typedPlayerSeats[playerId] = value.toInt();
            }
          });

          final isPublic = data['isPublic'] as bool? ?? true;
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
            'playerSeats': playerSeats,
            'seatTypes': _seatTypesToFirestore(seatTypes),
            'pieces': pieces,
            'openSeats': openSeats,
            'matchmakingOpen': isPublic && openHumanSeats > 0,
            'currentTurn': players.isNotEmpty ? players.first : '',
            'lastActivityAt': FieldValue.serverTimestamp(),
            'expiresAt': _expiresAfter(waitingRoomLease),
          });
        });
      } catch (error) {
        if (kDebugMode) {
          print('Leave room error: $error');
        }
      }
    }

    _resetLocalGame();
  }

  void quitToMenu() {
    _resetLocalGame();
  }

  void _resetLocalGame({String message = ''}) {
    gameSubscription?.cancel();
    gameSubscription = null;
    stopRoomHeartbeat();
    cancelBotTurn();
    gameId = '';
    game = null;
    statusMessage = message;
    syncVisualActiveMove(null);
    notifyListeners();
  }
}