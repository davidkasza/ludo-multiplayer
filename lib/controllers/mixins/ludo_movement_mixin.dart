import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../game/ludo_rules.dart';
import '../../models/ludo_models.dart';

mixin LudoMovementMixin on ChangeNotifier {
  FirebaseFirestore get db;

  User? get user;
  String get gameId;
  LudoGame? get game;
  DateTime get estimatedServerNow;

  String get statusMessage;
  set statusMessage(String value);

  bool get isMyTurn;
  String getPlayerDisplayTitle(String playerId);
  void syncVisualActiveMove(ActiveMove? remoteMove);

  Future<void> movePiece(int pieceId) async {
    if (user == null || !isMyTurn) return;
    await movePieceForPlayer(user!.uid, pieceId);
  }

  Future<void> movePieceForPlayer(String playerId, int pieceId) async {
    final currentUser = user;
    final currentGameId = gameId;
    if (currentUser == null || currentGameId.isEmpty) return;

    final gameReference = db.collection('games').doc(currentGameId);
    final resultReference = db.collection('matchResults').doc(currentGameId);
    final actionId = db.collection('_actionIds').doc().id;

    try {
      final result = await db.runTransaction<_MoveResult?>((transaction) async {
        final snapshot = await transaction.get(gameReference);
        final data = snapshot.data();
        if (!snapshot.exists || data == null) return null;

        final latest = LudoGame.fromMap(data);
        if (latest.lastActionId == actionId) return null;
        if (latest.status != 'playing' ||
            latest.currentTurn != playerId ||
            latest.finishOrder.contains(playerId) ||
            !latest.hasRolled ||
            latest.turnPhase != LudoGame.waitingForMove) {
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

        final originalPieces = latest.pieces[playerId] ?? const <LudoPiece>[];
        LudoPiece? target;
        for (final piece in originalPieces) {
          if (piece.id == pieceId) {
            target = piece;
            break;
          }
        }
        if (target == null ||
            !LudoRules.isValidMove(target, latest.diceValue)) {
          return null;
        }

        final steps = LudoRules.buildMoveSteps(target, latest.diceValue);
        if (steps.length < 2) return null;
        final destination = steps.last;
        final nextVersion = latest.turnVersion + 1;
        final activeMove = ActiveMove(
          actionId: actionId,
          turnVersion: nextVersion,
          playerId: playerId,
          pieceId: pieceId,
          startedAt: estimatedServerNow.millisecondsSinceEpoch,
          stepDurationMs: 250,
          steps: steps,
          stateApplied: true,
        );

        final movedPieces = <String, List<LudoPiece>>{
          for (final entry in latest.pieces.entries)
            entry.key: List<LudoPiece>.from(entry.value),
        };
        final updatedPlayerPieces = originalPieces
            .map(
              (piece) => piece.id == pieceId
                  ? piece.copyWith(
                      pos: destination.pos,
                      inHome: destination.inHome,
                    )
                  : piece,
            )
            .toList();
        movedPieces[playerId] = updatedPlayerPieces;

        final capture = LudoRules.applyCaptures(
          pieces: movedPieces,
          playerSeats: latest.playerSeats,
          players: latest.players,
          movingPlayerId: playerId,
          destination: destination,
        );
        final didReachGoal = LudoRules.reachesGoal(target, destination);
        final playerFinished = LudoRules.hasCompletedAllPieces(
          updatedPlayerPieces,
        );
        final finishOrder = LudoRules.finishOrderAfterMove(
          players: latest.players,
          currentFinishOrder: latest.finishOrder,
          movingPlayerId: playerId,
          movingPlayerFinished: playerFinished,
        );
        final matchFinished = LudoRules.isMatchFinished(
          players: latest.players,
          finishOrder: finishOrder,
        );
        final extraTurn = LudoRules.grantsExtraTurn(
          diceValue: latest.diceValue,
          didCapture: capture.didCapture,
          didReachGoal: didReachGoal,
        );
        final playerFinishedNow =
            playerFinished && !latest.finishOrder.contains(playerId);
        final nextPlayer = matchFinished
            ? ''
            : playerFinishedNow || !extraTurn
            ? LudoRules.nextActivePlayer(
                players: latest.players,
                currentPlayerId: playerId,
                finishedPlayers: finishOrder,
              )
            : playerId;

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

        final moveMap = activeMove.toMap()
          ..['committedAt'] = FieldValue.serverTimestamp();
        final update = <String, dynamic>{
          'pieces': {
            for (final entry in capture.pieces.entries)
              entry.key: entry.value.map((piece) => piece.toMap()).toList(),
          },
          'currentTurn': nextPlayer,
          'hasRolled': false,
          'status': matchFinished ? 'finished' : 'playing',
          'winnerUid': finishOrder.isEmpty ? '' : finishOrder.first,
          'finishOrder': finishOrder,
          'activeMove': moveMap,
          'activeDiceRoll': null,
          'automationLease': null,
          'aiControlledPlayers': aiControlled.toSet().toList(),
          'pendingReconnectPlayers': pending.toSet().toList(),
          'turnPhase': LudoGame.waitingForRoll,
          'turnStartedAt': matchFinished ? null : FieldValue.serverTimestamp(),
          'turnDurationSeconds': matchFinished ? 0 : 10,
          'turnDeadlineAt': matchFinished
              ? null
              : Timestamp.fromDate(
                  estimatedServerNow.toUtc().add(const Duration(seconds: 10)),
                ),
          'turnVersion': nextVersion,
          'lastActionId': actionId,
          'lastActionType': 'move',
          'matchmakingOpen': false,
          'lastActivityAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(
            estimatedServerNow.toUtc().add(
              matchFinished
                  ? const Duration(hours: 1)
                  : const Duration(hours: 24),
            ),
          ),
        };
        if (systemEvent != null) {
          update['systemEvent'] = systemEvent.toMap();
        }
        if (matchFinished) update['finishedAt'] = FieldValue.serverTimestamp();
        transaction.update(gameReference, update);

        if (matchFinished) {
          final humanCount = latest.players
              .where((id) => !id.startsWith('bot_'))
              .length;
          transaction.set(resultReference, {
            'participantIds': latest.players,
            'ranking': finishOrder,
            'playerNames': latest.playerNames,
            'preferredColors': latest.preferredColors,
            'playerSeats': latest.playerSeats,
            'boardId': latest.boardId,
            'isTestModeActive': latest.isTestModeActive,
            'playerCount': latest.players.length,
            'humanPlayerCount': humanCount,
            'botPlayerCount': latest.players.length - humanCount,
            'startedAt': latest.startedAt ?? FieldValue.serverTimestamp(),
            'finishedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        return _MoveResult(
          activeMove: activeMove,
          message: _buildStatusMessage(
            latest: latest,
            playerId: playerId,
            playerFinishedNow: playerFinishedNow,
            placement: finishOrder.indexOf(playerId) + 1,
            matchFinished: matchFinished,
            didCapture: capture.didCapture,
            didReachGoal: didReachGoal,
            rolledSix: latest.diceValue == 6,
          ),
        );
      });

      if (result == null) return;
      syncVisualActiveMove(result.activeMove);
      statusMessage = result.message;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('Move action failed: $error\n$stackTrace');
      statusMessage = '❌ Could not move the piece.';
      notifyListeners();
    }
  }

  String _buildStatusMessage({
    required LudoGame latest,
    required String playerId,
    required bool playerFinishedNow,
    required int placement,
    required bool matchFinished,
    required bool didCapture,
    required bool didReachGoal,
    required bool rolledSix,
  }) {
    final name = latest.playerNames[playerId] ?? 'Player';
    if (playerFinishedNow) {
      return matchFinished
          ? '🏆 $name finished in ${_ordinal(placement)} place. Match complete!'
          : '🏁 $name finished in ${_ordinal(placement)} place!';
    }
    if (didReachGoal) return '🎉 $name reached the goal and plays again.';
    if (didCapture) return '💥 $name captured a piece and plays again.';
    if (rolledSix) return '✨ $name rolled a 6 and plays again.';
    return '';
  }

  String _ordinal(int value) {
    final mod100 = value % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${value}th';
    return switch (value % 10) {
      1 => '${value}st',
      2 => '${value}nd',
      3 => '${value}rd',
      _ => '${value}th',
    };
  }
}

class _MoveResult {
  final ActiveMove activeMove;
  final String message;

  const _MoveResult({required this.activeMove, required this.message});
}
