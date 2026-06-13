import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  List<LudoPiece> getMyPieces();

  Future<void> rollDice(int cheatDiceValue) async {
    if (!canRoll) return;

    isDiceRolling = true;
    notifyListeners();

    final value = cheatDiceValue > 0 && game?.isTestModeActive == true
        ? cheatDiceValue
        : random.nextInt(6) + 1;

    await Future.delayed(const Duration(milliseconds: 600));

    isDiceRolling = false;

    final myPieces = getMyPieces();

    final hasValidMove = myPieces.any((p) {
      if (p.pos == 5 && p.inHome) return false;
      if (p.pos == -1) return value == 6;
      if (p.inHome) return (p.pos + value) <= 5;
      return true;
    });

    if (!hasValidMove) {
      if (value == 6) {
        statusMessage =
        "🎲 You rolled a 6, but you have no valid moves. Roll again!";
        notifyListeners();

        await db.collection('games').doc(gameId).update({
          'diceValue': value,
          'hasRolled': false,
          'currentTurn': user!.uid,
        });
      } else {
        final nextPlayer = game!.players.firstWhere(
              (p) => p != user!.uid,
          orElse: () => user!.uid,
        );

        statusMessage = "🎲 Rolled: $value. No available moves, turn skipped.";
        notifyListeners();

        await db.collection('games').doc(gameId).update({
          'diceValue': value,
          'hasRolled': false,
          'currentTurn': nextPlayer,
        });
      }
    } else {
      await db.collection('games').doc(gameId).update({
        'diceValue': value,
        'hasRolled': true,
      });
    }
  }
}