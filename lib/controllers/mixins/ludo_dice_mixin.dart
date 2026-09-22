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

  int get profileCoins;
  set profileCoins(int value);

  bool _rerollActionPending = false;
  bool get rerollActionPending => _rerollActionPending;

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

  /// Returns a user-facing message only for an abnormal failure that still
  /// needs explanation. Normal success and stale presentation races are quiet.
  Future<String?> useReroll() async {
    if (_rerollActionPending) {
      return null;
    }
    final currentUser = user;
    final currentGame = game;
    final currentRoll = currentGame?.activeDiceRoll;
    if (currentUser == null ||
        currentGame == null ||
        currentRoll == null ||
        gameId.isEmpty) {
      return null;
    }

    _rerollActionPending = true;
    notifyListeners();
    try {
      final result = await gameplayFunctions.useReroll(
        roomCode: gameId,
        expectedTurnVersion: currentGame.turnVersion,
        expectedActionId: currentRoll.actionId,
        actionId: db.collection('_actionIds').doc().id,
      );
      final balance = result['coinBalance'];
      if (balance is num) profileCoins = balance.toInt().clamp(0, 1 << 31);
      return null;
    } on FirebaseFunctionsException catch (error) {
      final details = error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : const <String, dynamic>{};
      final balance = details['coinBalance'];
      if (balance is num) profileCoins = balance.toInt().clamp(0, 1 << 31);
      return _rerollFailureMessage(error.code, details['reason']);
    } catch (error, stackTrace) {
      debugPrint('Reroll action failed: $error\n$stackTrace');
      return 'Could not use Reroll. Please try again.';
    } finally {
      _rerollActionPending = false;
      notifyListeners();
    }
  }

  String? _rerollFailureMessage(String code, Object? reason) {
    switch (reason) {
      case 'insufficient-coins':
        return 'Not enough coins for this Reroll.';
      case 'reroll-limit-reached':
        return 'Reroll limit reached for this match.';
      case 'stale-action':
      case 'deadline-expired':
      case 'reroll-window-expired':
      case 'reroll-unavailable':
        return null;
      case 'ai-controlled':
        return 'AI-controlled players cannot use Reroll.';
    }
    if (code == 'aborted') return null;
    return 'Could not use Reroll. Please try again.';
  }

  bool isValidMove({required LudoPiece piece, required int diceValue}) {
    return LudoRules.isValidMove(piece, diceValue);
  }
}
