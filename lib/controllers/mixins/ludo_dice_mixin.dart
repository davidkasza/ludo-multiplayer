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

  void syncDiceRollAnimation(ActiveDiceRoll? remoteRoll);
  void stopDiceRollAnimation();

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

  Timestamp _rollDeadline() {
    return Timestamp.fromDate(
      DateTime.now().toUtc().add(const Duration(seconds: 10)),
    );
  }

  Timestamp _moveDeadline() {
    return Timestamp.fromDate(
      DateTime.now().toUtc().add(const Duration(seconds: 30)),
    );
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
    final currentUser = user;
    final currentGameId = gameId;
    if (currentUser == null || currentGameId.isEmpty) return;

    final gameReference = db.collection('games').doc(currentGameId);
    const animationDurationMs = 800;
    const resultWriteDelayMs = 600;

    final value = forcedValue > 0 && game?.isTestModeActive == true
        ? forcedValue
        : random.nextInt(6) + 1;

    ActiveDiceRoll? activeDiceRoll;

    try {
      activeDiceRoll = await db.runTransaction<ActiveDiceRoll?>((transaction) async {
        final snapshot = await transaction.get(gameReference);
        if (!snapshot.exists || snapshot.data() == null) return null;

        final latest = LudoGame.fromMap(snapshot.data()!);
        if (latest.status != 'playing' ||
            latest.currentTurn != playerId ||
            latest.finishOrder.contains(playerId) ||
            latest.hasRolled ||
            latest.turnPhase != LudoGame.waitingForRoll ||
            latest.activeMove != null ||
            latest.activeDiceRoll != null) {
          return null;
        }

        final actingForSelf = currentUser.uid == playerId;
        final lease = latest.automationLease;
        final ownsAutomationLease = lease != null &&
            lease.ownerUid == currentUser.uid &&
            lease.turnVersion == latest.turnVersion &&
            !lease.isExpired;

        final deadlineExpired = latest.turnDeadlineAt != null &&
            !latest.turnDeadlineAt!.toDate().isAfter(DateTime.now());

        if (actingForSelf &&
            (latest.aiControlledPlayers.contains(playerId) || deadlineExpired) &&
            !ownsAutomationLease) {
          return null;
        }

        if (!actingForSelf && !ownsAutomationLease) return null;

        final roll = ActiveDiceRoll(
          playerId: playerId,
          startedAt: DateTime.now().millisecondsSinceEpoch,
          durationMs: animationDurationMs,
        );

        transaction.update(gameReference, {
          'activeDiceRoll': roll.toMap(),
          ..._activeGameActivityFields(),
        });

        return roll;
      });

      if (activeDiceRoll == null) return;

      syncDiceRollAnimation(activeDiceRoll);

      await Future.delayed(
        const Duration(milliseconds: resultWriteDelayMs),
      );

      final result = await db.runTransaction<_DiceFinalization?>((transaction) async {
        final snapshot = await transaction.get(gameReference);
        if (!snapshot.exists || snapshot.data() == null) return null;

        final latest = LudoGame.fromMap(snapshot.data()!);
        if (latest.status != 'playing' ||
            latest.currentTurn != playerId ||
            latest.hasRolled ||
            latest.activeDiceRoll?.key != activeDiceRoll!.key) {
          return null;
        }

        final pieces = latest.pieces[playerId] ?? const <LudoPiece>[];
        final hasValidMove = pieces.any(
              (piece) => isValidMove(piece: piece, diceValue: value),
        );

        final aiControlled = List<String>.from(latest.aiControlledPlayers);
        final pending = List<String>.from(latest.pendingReconnectPlayers);
        final reconnectNow = pending.contains(playerId) &&
            !latest.forfeitedPlayers.contains(playerId);

        GameSystemEvent? reconnectEvent;
        if (reconnectNow) {
          aiControlled.remove(playerId);
          pending.remove(playerId);
          final eventTime = DateTime.now().millisecondsSinceEpoch;
          reconnectEvent = GameSystemEvent(
            id: 'reconnected_${playerId}_${latest.turnVersion}_$eventTime',
            type: GameSystemEvent.playerReconnected,
            playerId: playerId,
            createdAtMs: eventTime,
          );
        }

        final update = <String, dynamic>{
          'diceValue': value,
          'activeDiceRoll': null,
          'automationLease': null,
          'aiControlledPlayers': aiControlled,
          'pendingReconnectPlayers': pending,
          ..._activeGameActivityFields(),
        };

        String message;
        if (!hasValidMove) {
          if (value == 6) {
            update.addAll({
              'hasRolled': false,
              'currentTurn': playerId,
              'turnPhase': LudoGame.waitingForRoll,
              'turnDeadlineAt': _rollDeadline(),
              'turnVersion': latest.turnVersion + 1,
            });
            message =
            '🎲 ${getPlayerDisplayTitle(playerId)} rolled a 6, but has no valid move. Roll again!';
          } else {
            final nextPlayer = _nextActivePlayer(latest, playerId);
            update.addAll({
              'hasRolled': false,
              'currentTurn': nextPlayer,
              'turnPhase': LudoGame.waitingForRoll,
              'turnDeadlineAt': _rollDeadline(),
              'turnVersion': latest.turnVersion + 1,
            });
            message =
            '🎲 ${getPlayerDisplayTitle(playerId)} rolled $value. No available move; turn skipped.';
          }
        } else {
          update.addAll({
            'hasRolled': true,
            'turnPhase': LudoGame.waitingForMove,
            'turnDeadlineAt': _moveDeadline(),
            'turnVersion': latest.turnVersion + 1,
          });
          message = '';
        }

        if (reconnectEvent != null) {
          update['systemEvent'] = reconnectEvent.toMap();
        }

        transaction.update(gameReference, update);
        return _DiceFinalization(message: message);
      });

      if (result != null) {
        statusMessage = result.message;
        notifyListeners();
      }
    } catch (error) {
      statusMessage = '❌ Could not roll the dice.';
      stopDiceRollAnimation();
      notifyListeners();

      if (currentGameId.isNotEmpty) {
        try {
          await gameReference.update({
            'activeDiceRoll': null,
            'automationLease': null,
            ..._activeGameActivityFields(),
          });
        } catch (_) {
          // Preserve the useful original error.
        }
      }
    }
  }

  String _nextActivePlayer(LudoGame latest, String currentPlayerId) {
    if (latest.players.isEmpty) return '';

    final finished = latest.finishOrder.toSet();
    final currentIndex = latest.players.indexOf(currentPlayerId);
    final startIndex = currentIndex < 0 ? -1 : currentIndex;

    for (int offset = 1; offset <= latest.players.length; offset++) {
      final candidate =
      latest.players[(startIndex + offset) % latest.players.length];
      if (!finished.contains(candidate)) return candidate;
    }

    return '';
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

class _DiceFinalization {
  final String message;

  const _DiceFinalization({required this.message});
}