import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../game/ludo_rules.dart';
import '../../models/ludo_models.dart';
import '../../services/gameplay_functions.dart';

class PowerUpActionFeedback {
  final bool succeeded;
  final String message;

  const PowerUpActionFeedback({required this.succeeded, required this.message});
}

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

  Future<PowerUpActionFeedback> useReroll() async {
    if (_rerollActionPending) {
      return const PowerUpActionFeedback(
        succeeded: false,
        message: 'Reroll is already being processed.',
      );
    }
    final currentUser = user;
    final currentGame = game;
    final currentRoll = currentGame?.activeDiceRoll;
    if (currentUser == null ||
        currentGame == null ||
        currentRoll == null ||
        gameId.isEmpty) {
      return const PowerUpActionFeedback(
        succeeded: false,
        message: 'The dice result is no longer available.',
      );
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
      if (result['duplicate'] == true) {
        return const PowerUpActionFeedback(
          succeeded: true,
          message: 'Reroll was already applied.',
        );
      }
      final charged = (result['chargedCoins'] as num?)?.toInt() ?? 0;
      return PowerUpActionFeedback(
        succeeded: true,
        message: 'Rerolled for $charged coins.',
      );
    } on FirebaseFunctionsException catch (error) {
      final details = error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : const <String, dynamic>{};
      final balance = details['coinBalance'];
      if (balance is num) profileCoins = balance.toInt().clamp(0, 1 << 31);
      return PowerUpActionFeedback(
        succeeded: false,
        message: _rerollFailureMessage(error.code, details['reason']),
      );
    } catch (error, stackTrace) {
      debugPrint('Reroll action failed: $error\n$stackTrace');
      return const PowerUpActionFeedback(
        succeeded: false,
        message: 'Could not use Reroll. Please try again.',
      );
    } finally {
      _rerollActionPending = false;
      notifyListeners();
    }
  }

  Future<PowerUpActionFeedback> passNoValidMove() async {
    if (_rerollActionPending) {
      return const PowerUpActionFeedback(
        succeeded: false,
        message: 'An action is already being processed.',
      );
    }
    final currentGame = game;
    final currentRoll = currentGame?.activeDiceRoll;
    if (currentGame == null || currentRoll == null || gameId.isEmpty) {
      return const PowerUpActionFeedback(
        succeeded: false,
        message: 'The turn has already changed.',
      );
    }

    _rerollActionPending = true;
    notifyListeners();
    try {
      await gameplayFunctions.passNoValidMove(
        roomCode: gameId,
        expectedTurnVersion: currentGame.turnVersion,
        expectedActionId: currentRoll.actionId,
        actionId: db.collection('_actionIds').doc().id,
      );
      return const PowerUpActionFeedback(
        succeeded: true,
        message: 'Turn continued without spending coins.',
      );
    } on FirebaseFunctionsException catch (error) {
      return PowerUpActionFeedback(
        succeeded: false,
        message: error.code == 'aborted'
            ? 'The turn already changed.'
            : 'Could not continue this turn.',
      );
    } catch (error, stackTrace) {
      debugPrint('No-move pass failed: $error\n$stackTrace');
      return const PowerUpActionFeedback(
        succeeded: false,
        message: 'Could not continue this turn.',
      );
    } finally {
      _rerollActionPending = false;
      notifyListeners();
    }
  }

  String _rerollFailureMessage(String code, Object? reason) {
    switch (reason) {
      case 'insufficient-coins':
        return 'Not enough coins for this Reroll.';
      case 'reroll-limit-reached':
        return 'Reroll limit reached for this match.';
      case 'stale-action':
      case 'deadline-expired':
        return 'The turn already changed.';
      case 'ai-controlled':
        return 'AI-controlled players cannot use Reroll.';
    }
    if (code == 'aborted') return 'The turn already changed.';
    return 'Reroll is no longer available.';
  }

  bool isValidMove({required LudoPiece piece, required int diceValue}) {
    return LudoRules.isValidMove(piece, diceValue);
  }
}
