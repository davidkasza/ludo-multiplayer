import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../game/ludo_rules.dart';
import '../../models/ludo_models.dart';

mixin LudoDiceMixin on ChangeNotifier {
  FirebaseFirestore get db;
  Random get random;

  User? get user;
  String get gameId;
  LudoGame? get game;
  DateTime get estimatedServerNow;

  String get statusMessage;
  set statusMessage(String value);

  bool get canRoll;

  void syncDiceRollAnimation(ActiveDiceRoll? remoteRoll);
  void stopDiceRollAnimation();
  String getPlayerDisplayTitle(String playerId);

  Map<String, dynamic> _activeGameActivityFields() {
    return {
      'lastActivityAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        estimatedServerNow.toUtc().add(const Duration(hours: 24)),
      ),
    };
  }

  Map<String, dynamic> _turnTimingFields(int seconds) {
    return {
      'turnStartedAt': FieldValue.serverTimestamp(),
      'turnDurationSeconds': seconds,
      // Kept during the backward-compatible migration. New clients prefer
      // turnStartedAt + turnDurationSeconds, whose origin is server-authored.
      'turnDeadlineAt': Timestamp.fromDate(
        estimatedServerNow.toUtc().add(Duration(seconds: seconds)),
      ),
    };
  }

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
    final currentGameId = gameId;
    if (currentUser == null || currentGameId.isEmpty) return;

    final gameReference = db.collection('games').doc(currentGameId);
    final actionId = db.collection('_actionIds').doc().id;
    final rolledValue =
        forcedValue >= 1 && forcedValue <= 6 && game?.isTestModeActive == true
        ? forcedValue
        : random.nextInt(6) + 1;

    try {
      final result = await db.runTransaction<_DiceResult?>((transaction) async {
        final snapshot = await transaction.get(gameReference);
        final data = snapshot.data();
        if (!snapshot.exists || data == null) return null;

        final latest = LudoGame.fromMap(data);
        if (latest.lastActionId == actionId) return null;
        if (latest.status != 'playing' ||
            latest.currentTurn != playerId ||
            latest.finishOrder.contains(playerId) ||
            latest.hasRolled ||
            latest.turnPhase != LudoGame.waitingForRoll) {
          return null;
        }

        final actingForSelf = currentUser.uid == playerId;
        final deadline = latest.effectiveTurnDeadline;
        final deadlineExpired =
            deadline != null && !deadline.isAfter(estimatedServerNow);
        final mayAutomate = latest.isAiControlled(playerId) || deadlineExpired;
        if ((actingForSelf && latest.isAiControlled(playerId)) ||
            (!actingForSelf && !mayAutomate)) {
          return null;
        }

        final nextVersion = latest.turnVersion + 1;
        final roll = ActiveDiceRoll(
          actionId: actionId,
          turnVersion: nextVersion,
          playerId: playerId,
          startedAt: estimatedServerNow.millisecondsSinceEpoch,
          durationMs: 800,
          result: rolledValue,
          stateApplied: true,
        );
        final rollMap = roll.toMap()
          ..['committedAt'] = FieldValue.serverTimestamp();

        final aiControlled = List<String>.from(latest.aiControlledPlayers);
        final pending = List<String>.from(latest.pendingReconnectPlayers);
        final reconnectNow =
            actingForSelf &&
            pending.contains(playerId) &&
            !latest.forfeitedPlayers.contains(playerId);
        GameSystemEvent? systemEvent;
        if (reconnectNow) {
          aiControlled.remove(playerId);
          pending.remove(playerId);
          systemEvent = GameSystemEvent(
            id: 'reconnected_${playerId}_$nextVersion',
            type: GameSystemEvent.playerReconnected,
            playerId: playerId,
            createdAtMs: estimatedServerNow.millisecondsSinceEpoch,
          );
        } else if (deadlineExpired && !latest.isAiControlled(playerId)) {
          aiControlled.add(playerId);
          systemEvent = GameSystemEvent(
            id: 'takeover_${playerId}_$nextVersion',
            type: GameSystemEvent.aiTakeover,
            playerId: playerId,
            createdAtMs: estimatedServerNow.millisecondsSinceEpoch,
          );
        }

        final hasValidMove = LudoRules.hasValidMove(
          latest.pieces[playerId] ?? const <LudoPiece>[],
          rolledValue,
        );
        final update = <String, dynamic>{
          'diceValue': rolledValue,
          'activeDiceRoll': rollMap,
          'activeMove': null,
          'automationLease': null,
          'aiControlledPlayers': aiControlled.toSet().toList(),
          'pendingReconnectPlayers': pending.toSet().toList(),
          'lastActionId': actionId,
          'lastActionType': 'dice',
          'turnVersion': nextVersion,
          ..._activeGameActivityFields(),
        };

        String message = '';
        if (hasValidMove) {
          update.addAll({
            'hasRolled': true,
            'turnPhase': LudoGame.waitingForMove,
            ..._turnTimingFields(30),
          });
        } else {
          final resolution = LudoRules.resolveNoValidMove(
            players: latest.players,
            currentPlayerId: playerId,
            finishedPlayers: latest.finishOrder,
            diceValue: rolledValue,
          );
          update.addAll({
            'hasRolled': false,
            'currentTurn': resolution.nextPlayerId,
            'turnPhase': LudoGame.waitingForRoll,
            ..._turnTimingFields(10),
          });
          message = resolution.keepsTurn
              ? '🎲 ${getPlayerDisplayTitle(playerId)} rolled a 6, but has no valid move. Roll again!'
              : '🎲 ${getPlayerDisplayTitle(playerId)} rolled $rolledValue. No available move; turn skipped.';
        }
        if (systemEvent != null) {
          update['systemEvent'] = systemEvent.toMap();
        }

        transaction.update(gameReference, update);
        return _DiceResult(roll: roll, message: message);
      });

      if (result == null) return;
      syncDiceRollAnimation(result.roll);
      statusMessage = result.message;
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

class _DiceResult {
  final ActiveDiceRoll roll;
  final String message;

  const _DiceResult({required this.roll, required this.message});
}
