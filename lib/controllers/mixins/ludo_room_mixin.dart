import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  StreamSubscription<DocumentSnapshot>? get gameSubscription;
  set gameSubscription(StreamSubscription<DocumentSnapshot>? value);

  bool get isHost;

  List<Map<String, dynamic>> createDefaultPieces(int initialPos);

  void syncVisualActiveMove(ActiveMove? remoteMove);

  static const String _roomCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  String _generateRoomCode() {
    final random = Random.secure();

    return List.generate(
      5,
          (_) => _roomCodeChars[random.nextInt(_roomCodeChars.length)],
    ).join();
  }

  Future<String> _createGameWithUniqueRoomCode(
      Map<String, dynamic> gameData,
      ) async {
    for (int attempt = 0; attempt < 10; attempt++) {
      final roomCode = _generateRoomCode();
      final ref = db.collection('games').doc(roomCode);

      final created = await db.runTransaction<bool>((transaction) async {
        final snap = await transaction.get(ref);

        if (snap.exists) {
          return false;
        }

        transaction.set(ref, gameData);
        return true;
      });

      if (created) {
        return roomCode;
      }
    }

    throw Exception("Could not generate unique room code");
  }

  void listenGame(String id) {
    gameSubscription?.cancel();

    gameSubscription = db.collection('games').doc(id).snapshots().listen(
          (snap) {
        if (snap.exists && snap.data() != null) {
          final nextGame = LudoGame.fromMap(snap.data()!);

          syncVisualActiveMove(nextGame.activeMove);

          game = nextGame;
          notifyListeners();
        }
      },
    );
  }

  Future<void> createGame(
      String playerName,
      String selectedBoard,
      bool isTestMode,
      ) async {
    if (user == null || playerName.trim().isEmpty) return;

    statusMessage = "";
    notifyListeners();

    final initialPos = isTestMode ? 49 : -1;
    final defaultPieces = createDefaultPieces(initialPos);

    final gameData = {
      'players': [user!.uid],
      'playerNames': {user!.uid: playerName.trim()},
      'currentTurn': user!.uid,
      'diceValue': 0,
      'hasRolled': false,
      'status': 'waiting',
      'winnerUid': '',
      'boardId': selectedBoard,
      'isTestModeActive': isTestMode,
      'activeChat': const LudoChat(
        sender: '',
        message: '',
        timestamp: 0,
      ).toMap(),
      'pieces': {
        user!.uid: defaultPieces,
      },
      'activeMove': null,
    };

    try {
      final roomCode = await _createGameWithUniqueRoomCode(gameData);

      gameId = roomCode;
      listenGame(gameId);
    } catch (e) {
      statusMessage = "❌ Could not create room!";
      notifyListeners();

      if (kDebugMode) {
        print("Create room error: $e");
      }
    }
  }

  Future<void> joinGame(String playerName, String inputId) async {
    if (user == null || playerName.trim().isEmpty) return;

    final cleanInputId = inputId.trim().toUpperCase();

    if (cleanInputId.isEmpty) {
      statusMessage = "❌ Please enter a room code!";
      notifyListeners();
      return;
    }

    statusMessage = "";
    notifyListeners();

    final ref = db.collection('games').doc(cleanInputId);

    try {
      await db.runTransaction((transaction) async {
        final snap = await transaction.get(ref);

        if (!snap.exists || snap.data() == null) {
          throw Exception("Game not found");
        }

        final data = snap.data()!;
        final players = List<String>.from(data['players'] ?? []);

        if (players.contains(user!.uid)) {
          return;
        }

        if (players.length >= 2) {
          throw Exception("This room is already full");
        }

        final isTestModeActive = data['isTestModeActive'] == true;
        final initialPos = isTestModeActive ? 49 : -1;
        final defaultPieces = createDefaultPieces(initialPos);

        final playerNames = Map<String, dynamic>.from(
          data['playerNames'] ?? {},
        );
        playerNames[user!.uid] = playerName.trim();

        final pieces = Map<String, dynamic>.from(
          data['pieces'] ?? {},
        );
        pieces[user!.uid] = defaultPieces;

        transaction.update(ref, {
          'players': [...players, user!.uid],
          'playerNames': playerNames,
          'pieces': pieces,
          'status': 'waiting',
          'activeMove': null,
        });
      });

      gameId = cleanInputId;
      listenGame(cleanInputId);
    } catch (e) {
      final message = e.toString();

      if (message.contains("Game not found")) {
        statusMessage = "❌ Game not found!";
      } else if (message.contains("already full")) {
        statusMessage = "❌ This room is already full!";
      } else {
        statusMessage = "❌ Could not join the room!";
      }

      notifyListeners();
    }
  }

  Future<void> updateWaitingRoomSettings({
    required String selectedBoard,
    required bool isTestMode,
  }) async {
    if (gameId.isEmpty || game == null || !isHost) return;
    if (game!.status != 'waiting') return;

    final initialPos = isTestMode ? 49 : -1;

    final updatedPieces = <String, dynamic>{};

    for (final playerUid in game!.players) {
      updatedPieces[playerUid] = createDefaultPieces(initialPos);
    }

    await db.collection('games').doc(gameId).update({
      'boardId': selectedBoard,
      'isTestModeActive': isTestMode,
      'pieces': updatedPieces,
      'diceValue': 0,
      'hasRolled': false,
      'currentTurn': game!.players.isNotEmpty ? game!.players.first : '',
      'activeMove': null,
    });
  }

  Future<void> startGame() async {
    if (gameId.isEmpty || game == null || !isHost) return;

    if (game!.players.length < 2) {
      statusMessage = "⚠️ Waiting for another player!";
      notifyListeners();
      return;
    }

    statusMessage = "";
    notifyListeners();

    await db.collection('games').doc(gameId).update({
      'status': 'playing',
      'currentTurn': game!.players.first,
      'diceValue': 0,
      'hasRolled': false,
      'activeMove': null,
    });
  }

  void quitToMenu() {
    gameId = "";
    game = null;
    statusMessage = "";
    syncVisualActiveMove(null);
    notifyListeners();
  }
}