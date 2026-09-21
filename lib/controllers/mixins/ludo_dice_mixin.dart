import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../game/ludo_rules.dart';
import '../../models/ludo_models.dart';
import '../../services/gameplay_functions.dart';

mixin LudoDiceMixin on ChangeNotifier {
  FirebaseFirestore get db;
  GameplayFunctions get gameplayFunctions;

  User? get user;
  String get gameId;
  LudoGame? get game;

  String get statusMessage;
  set statusMessage(String value);

  bool get canRoll;
  bool get canUseSandbox;

  void stopDiceRollAnimation();

  Future<void> rollDice(int cheatDiceValue) async {
    if (!canRoll || user == null) return;
    await rollDiceForPlayer(user!.uid, forcedValue: cheatDiceValue);
  }

  Future<void> rollDiceForPlayer(
    String playerId, {
    int forcedValue = 0,
    bool animateLocally = false,
  }) async {
    final currentUser = user;
    final currentGame = game;
    final currentGameId = gameId;
    if (currentUser == null || currentGame == null || currentGameId.isEmpty) {
      return;
    }

    final actionId = db.collection('_actionIds').doc().id;
    try {
      if (playerId == currentUser.uid &&
          !currentGame.isAiControlled(playerId)) {
        await gameplayFunctions.rollDice(
          roomCode: currentGameId,
          expectedTurnVersion: currentGame.turnVersion,
          actionId: actionId,
          forcedValue: currentGame.isTestModeActive && canUseSandbox
              ? forcedValue
              : 0,
        );
      } else {
        await gameplayFunctions.processTurnTimeout(
          roomCode: currentGameId,
          expectedTurnVersion: currentGame.turnVersion,
          actionId: actionId,
        );
      }
      statusMessage = '';
      notifyListeners();
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'aborted' || error.code == 'failed-precondition') {
        return;
      }
      debugPrint('Dice callable failed: ${error.code}: ${error.message}');
      statusMessage = '❌ Could not roll the dice.';
      stopDiceRollAnimation();
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('Dice action failed: $error\n$stackTrace');
      statusMessage = '❌ Could not roll the dice.';
      stopDiceRollAnimation();
      notifyListeners();
    }
  }

  bool isValidMove({required LudoPiece piece, required int diceValue}) {
    return LudoRules.isValidMove(piece, diceValue);
  }
}
