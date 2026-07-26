import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/ludo_models.dart';

mixin LudoDiceMixin on ChangeNotifier {
  FirebaseFirestore get db;
  Random get random;

  User? get user;
  String get gameId;
  LudoGame? get game;

  String get statusMessage;
  set statusMessage(String value);

  bool get isDiceRolling;
  set isDiceRolling(bool value);

  bool get canRoll;

  List<LudoPiece> getPiecesForPlayer(String playerId);
  String getNextPlayerId(String currentPlayerId);
  String getPlayerDisplayTitle(String playerId);

  Map<String, dynamic> _activeGameActivityFields() {
    return {
      'lastActivityAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().toUtc().add(const Duration(hours: 24)),
      ),
    };
  }

  Future<void> rollDice(int cheatDiceValue) async {
    if (!canRoll || user == null) return;

    await rollDiceForPlayer(
      user!.uid,
      forcedValue: cheatDiceValue,
      animateLocally: true,
    );
  }

  Future<void> rollDiceForPlayer(
      String playerId, {
        int forcedValue = 0,
        bool animateLocally = false,
      }) async {
    final currentGame = game;

    if (gameId.isEmpty ||
        currentGame == null ||
        currentGame.status != 'playing' ||
        currentGame.currentTurn != playerId ||
        currentGame.hasRolled ||
        currentGame.activeMove != null) {
      return;
    }

    if (animateLocally) {
      isDiceRolling = true;
      notifyListeners();
    }

    final value = forcedValue > 0 && currentGame.isTestModeActive
        ? forcedValue
        : random.nextInt(6) + 1;

    await Future.delayed(
      Duration(milliseconds: animateLocally ? 600 : 500),
    );

    if (animateLocally) {
      isDiceRolling = false;
    }

    final latestGame = game;
    if (latestGame == null ||
        latestGame.currentTurn != playerId ||
        latestGame.hasRolled ||
        latestGame.status != 'playing') {
      notifyListeners();
      return;
    }

    final pieces = getPiecesForPlayer(playerId);
    final hasValidMove = pieces.any(
          (piece) => isValidMove(piece: piece, diceValue: value),
    );

    if (!hasValidMove) {
      if (value == 6) {
        statusMessage =
        '🎲 ${getPlayerDisplayTitle(playerId)} rolled a 6, but has no valid move. Roll again!';

        await db.collection('games').doc(gameId).update({
          'diceValue': value,
          'hasRolled': false,
          'currentTurn': playerId,
          ..._activeGameActivityFields(),
        });
      } else {
        final nextPlayer = getNextPlayerId(playerId);

        statusMessage =
        '🎲 ${getPlayerDisplayTitle(playerId)} rolled $value. No available move; turn skipped.';

        await db.collection('games').doc(gameId).update({
          'diceValue': value,
          'hasRolled': false,
          'currentTurn': nextPlayer,
          ..._activeGameActivityFields(),
        });
      }

      notifyListeners();
      return;
    }

    statusMessage = '';
    notifyListeners();

    await db.collection('games').doc(gameId).update({
      'diceValue': value,
      'hasRolled': true,
      ..._activeGameActivityFields(),
    });
  }

  bool isValidMove({
    required LudoPiece piece,
    required int diceValue,
  }) {
    if (piece.pos == 5 && piece.inHome) return false;
    if (piece.pos == -1) return diceValue == 6;
    if (piece.inHome) return piece.pos + diceValue <= 5;
    return true;
  }
}