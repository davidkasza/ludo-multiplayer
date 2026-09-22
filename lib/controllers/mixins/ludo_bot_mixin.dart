import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/ludo_models.dart';
import '../../services/gameplay_functions.dart';

mixin LudoBotMixin on ChangeNotifier {
  FirebaseFirestore get db;
  GameplayFunctions get gameplayFunctions;
  User? get user;
  String get gameId;
  LudoGame? get game;
  ActiveMove? get visualActiveMove;
  bool get isDicePresentationActive;
  DateTime get estimatedServerNow;

  String get statusMessage;
  set statusMessage(String value);

  Timer? _botTurnTimer;
  String? _scheduledAutomationStateKey;
  bool _automationBusy = false;

  void cancelBotTurn() {
    _botTurnTimer?.cancel();
    _botTurnTimer = null;
    _scheduledAutomationStateKey = null;
    _automationBusy = false;
  }

  void syncBotTurn() {
    final currentGame = game;
    final currentUser = user;
    if (currentGame == null ||
        currentUser == null ||
        gameId.isEmpty ||
        currentGame.status != 'playing' ||
        currentGame.currentTurn.isEmpty ||
        currentGame.finishOrder.contains(currentGame.currentTurn) ||
        visualActiveMove != null ||
        isDicePresentationActive) {
      _cancelScheduledAutomation();
      return;
    }

    final humanControllers = currentGame.players
        .where((playerId) => !playerId.startsWith('bot_'))
        .toList();
    final controllerRank = humanControllers.indexOf(currentUser.uid);
    if (controllerRank < 0) {
      _cancelScheduledAutomation();
      return;
    }

    final playerId = currentGame.currentTurn;
    final automated = currentGame.isAiControlled(playerId);
    final deadline = _automationDeadline(currentGame);
    if (!automated && deadline == null) {
      _cancelScheduledAutomation();
      return;
    }

    final stateKey = _automationStateKey(currentGame);
    if (_automationBusy) return;
    if (_botTurnTimer != null && _scheduledAutomationStateKey != stateKey) {
      _cancelScheduledAutomation();
    }
    if (_botTurnTimer != null || _scheduledAutomationStateKey == stateKey) {
      return;
    }

    final recoveryStagger = Duration(milliseconds: controllerRank * 600);
    final Duration delay;
    if (automated) {
      delay = const Duration(milliseconds: 650) + recoveryStagger;
    } else {
      final remaining = deadline!.difference(estimatedServerNow);
      delay =
          (remaining.isNegative
              ? const Duration(milliseconds: 120)
              : remaining + const Duration(milliseconds: 120)) +
          recoveryStagger;
    }

    _scheduledAutomationStateKey = stateKey;
    _botTurnTimer = Timer(delay, () async {
      _botTurnTimer = null;
      await _runAutomation(stateKey);
    });
  }

  void _cancelScheduledAutomation() {
    _botTurnTimer?.cancel();
    _botTurnTimer = null;
    _scheduledAutomationStateKey = null;
  }

  String _automationStateKey(LudoGame currentGame) {
    return [
      gameId,
      currentGame.currentTurn,
      currentGame.turnPhase,
      currentGame.turnVersion,
      currentGame.hasRolled,
      currentGame.diceValue,
      _automationDeadline(currentGame)?.millisecondsSinceEpoch ?? 0,
      currentGame.isAiControlled(currentGame.currentTurn),
    ].join('|');
  }

  Future<void> _runAutomation(String expectedStateKey) async {
    if (_automationBusy || gameId.isEmpty || user == null) return;
    final currentGame = game;
    if (currentGame == null ||
        _automationStateKey(currentGame) != expectedStateKey) {
      return;
    }

    final deadline = _automationDeadline(currentGame);
    if (!currentGame.isAiControlled(currentGame.currentTurn) &&
        (deadline == null || deadline.isAfter(estimatedServerNow))) {
      return;
    }

    _automationBusy = true;
    try {
      await gameplayFunctions.processTurnTimeout(
        roomCode: gameId,
        expectedTurnVersion: currentGame.turnVersion,
        actionId: db.collection('_actionIds').doc().id,
      );
    } on FirebaseFunctionsException catch (error) {
      if (error.code != 'aborted' && error.code != 'failed-precondition') {
        debugPrint(
          'Automated turn callable failed: ${error.code}: ${error.message}',
        );
        statusMessage = 'Automated turn failed. Retrying...';
        notifyListeners();
      }
    } catch (error, stackTrace) {
      debugPrint('Automated turn failed: $error\n$stackTrace');
      statusMessage = 'Automated turn failed. Retrying...';
      notifyListeners();
    } finally {
      _automationBusy = false;
      _scheduledAutomationStateKey = null;
      Future<void>.delayed(const Duration(milliseconds: 180), syncBotTurn);
    }
  }

  DateTime? _automationDeadline(LudoGame currentGame) {
    if (currentGame.turnPhase == LudoGame.waitingForRerollDecision &&
        currentGame.hasRolled) {
      return currentGame.rerollDeadlineAt?.toDate() ??
          currentGame.effectiveTurnDeadline;
    }
    return currentGame.effectiveTurnDeadline;
  }

  Future<bool> requestTakeBackControl() async {
    final currentUser = user;
    final currentGame = game;
    if (currentUser == null || currentGame == null || gameId.isEmpty) {
      return false;
    }
    try {
      final result = await gameplayFunctions.requestTakeBackControl(
        roomCode: gameId,
        expectedTurnVersion: currentGame.turnVersion,
        actionId: db.collection('_actionIds').doc().id,
      );
      final deferred = result['deferred'] == true;
      statusMessage = deferred
          ? 'Control will return after the interrupted legacy action recovers.'
          : 'You are back in control.';
      notifyListeners();
      return true;
    } catch (error) {
      debugPrint('Take-back control failed: $error');
      return false;
    }
  }

  Future<bool> markMyselfForfeit() async {
    final currentUser = user;
    final currentGame = game;
    if (currentUser == null || currentGame == null || gameId.isEmpty) {
      return false;
    }
    try {
      await gameplayFunctions.forfeitMatch(
        roomCode: gameId,
        expectedTurnVersion: currentGame.turnVersion,
        actionId: db.collection('_actionIds').doc().id,
      );
      return true;
    } catch (error) {
      debugPrint('Forfeit failed: $error');
      return false;
    }
  }
}
