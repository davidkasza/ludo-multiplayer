import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/ludo_models.dart';

mixin LudoMovementMixin on ChangeNotifier {
  FirebaseFirestore get db;

  User? get user;
  String get gameId;
  LudoGame? get game;

  String get statusMessage;
  set statusMessage(String value);

  LocalMovingPiece? get localMovingPiece;
  set localMovingPiece(LocalMovingPiece? value);

  bool get isMyTurn;

  List<int> get globalSafePlaces;

  List<LudoPiece> getMyPieces();
  int getGlobalPathIndexForIndex(int playerIndex, int relativePos);
  String getPlayerDisplayTitle(String playerId);

  void syncVisualActiveMove(ActiveMove? remoteMove);

  Timestamp _nextRollDeadline() {
    return Timestamp.fromDate(
      DateTime.now().toUtc().add(const Duration(seconds: 10)),
    );
  }

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

    _MoveStart? moveStart;

    try {
      moveStart = await db.runTransaction<_MoveStart?>((transaction) async {
        final snapshot = await transaction.get(gameReference);
        if (!snapshot.exists || snapshot.data() == null) return null;

        final latest = LudoGame.fromMap(snapshot.data()!);
        if (latest.status != 'playing' ||
            latest.currentTurn != playerId ||
            latest.finishOrder.contains(playerId) ||
            !latest.hasRolled ||
            latest.turnPhase != LudoGame.waitingForMove ||
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

        final pieces = latest.pieces[playerId] ?? const <LudoPiece>[];
        LudoPiece? targetPiece;
        for (final piece in pieces) {
          if (piece.id == pieceId) {
            targetPiece = piece;
            break;
          }
        }

        if (targetPiece == null ||
            !_isValidMove(targetPiece, latest.diceValue)) {
          return null;
        }

        final steps = _buildMoveSteps(
          piece: targetPiece,
          dice: latest.diceValue,
        );

        const stepDurationMs = 250;
        final activeMove = ActiveMove(
          playerId: playerId,
          pieceId: pieceId,
          startedAt: DateTime.now().millisecondsSinceEpoch,
          stepDurationMs: stepDurationMs,
          steps: steps,
        );

        transaction.update(gameReference, {
          'activeMove': activeMove.toMap(),
          'lastActivityAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(
            DateTime.now().toUtc().add(const Duration(hours: 24)),
          ),
        });

        return _MoveStart(
          piece: targetPiece,
          activeMove: activeMove,
          dice: latest.diceValue,
        );
      });

      if (moveStart == null) return;

      statusMessage = '';
      final isLocalHumanMove = playerId == currentUser.uid;
      if (isLocalHumanMove) {
        localMovingPiece = LocalMovingPiece(
          id: pieceId,
          currentVisualPos: moveStart.piece.pos,
          inHome: moveStart.piece.inHome,
          stepCount: moveStart.activeMove.steps.length - 1,
        );
      }

      syncVisualActiveMove(moveStart.activeMove);
      notifyListeners();

      await Future.delayed(
        Duration(milliseconds: moveStart.activeMove.totalDurationMs + 60),
      );

      if (isLocalHumanMove) {
        localMovingPiece = null;
        notifyListeners();
      }

      final result = await _finalizeFirebaseMove(
        gameReference: gameReference,
        resultReference: resultReference,
        playerId: playerId,
        moveStart: moveStart,
      );

      if (result != null) {
        statusMessage = result.statusMessage;
        notifyListeners();
      }
    } catch (error) {
      if (playerId == currentUser.uid) {
        localMovingPiece = null;
      }

      statusMessage = '❌ Could not move the piece.';
      syncVisualActiveMove(null);
      notifyListeners();

      try {
        await gameReference.update({
          'activeMove': null,
          'automationLease': null,
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Preserve the original failure.
      }
    }
  }

  bool _isValidMove(LudoPiece piece, int diceValue) {
    if (piece.pos == 5 && piece.inHome) return false;
    if (piece.pos == -1) return diceValue == 6;
    if (piece.inHome) return piece.pos + diceValue <= 5;
    return true;
  }

  List<ActiveMoveStep> _buildMoveSteps({
    required LudoPiece piece,
    required int dice,
  }) {
    final steps = <ActiveMoveStep>[
      ActiveMoveStep(pos: piece.pos, inHome: piece.inHome),
    ];

    int remainingSteps = piece.pos == -1 ? 1 : dice;
    int virtualPos = piece.pos;
    bool virtualInHome = piece.inHome;

    while (remainingSteps > 0) {
      remainingSteps--;

      if (virtualPos == -1) {
        virtualPos = 0;
        virtualInHome = false;
      } else if (virtualInHome) {
        virtualPos++;
      } else {
        virtualPos++;
        if (virtualPos > 51) {
          virtualPos = 0;
          virtualInHome = true;
        }
      }

      steps.add(
        ActiveMoveStep(pos: virtualPos, inHome: virtualInHome),
      );
    }

    return steps;
  }

  Future<_MoveFinalizationResult?> _finalizeFirebaseMove({
    required DocumentReference<Map<String, dynamic>> gameReference,
    required DocumentReference<Map<String, dynamic>> resultReference,
    required String playerId,
    required _MoveStart moveStart,
  }) {
    return db.runTransaction<_MoveFinalizationResult?>((transaction) async {
      final snapshot = await transaction.get(gameReference);
      if (!snapshot.exists || snapshot.data() == null) return null;

      final latestGame = LudoGame.fromMap(snapshot.data()!);
      final remoteMove = latestGame.activeMove;
      if (latestGame.status != 'playing' ||
          latestGame.currentTurn != playerId ||
          latestGame.finishOrder.contains(playerId) ||
          remoteMove == null ||
          remoteMove.playerId != moveStart.activeMove.playerId ||
          remoteMove.pieceId != moveStart.activeMove.pieceId ||
          remoteMove.startedAt != moveStart.activeMove.startedAt) {
        return null;
      }

      final originalPieces = latestGame.pieces[playerId] ?? const <LudoPiece>[];
      LudoPiece? originalTarget;
      for (final piece in originalPieces) {
        if (piece.id == moveStart.piece.id) {
          originalTarget = piece;
          break;
        }
      }
      if (originalTarget == null) return null;

      final finalStep = moveStart.activeMove.steps.last;
      final updatedPlayerPieces = originalPieces.map((piece) {
        if (piece.id != moveStart.piece.id) return piece;
        return piece.copyWith(
          pos: finalStep.pos,
          inHome: finalStep.inHome,
        );
      }).toList();

      bool didCapture = false;
      final allPieces = <String, dynamic>{};
      latestGame.pieces.forEach((uid, pieceList) {
        allPieces[uid] = pieceList.map((piece) => piece.toMap()).toList();
      });
      allPieces[playerId] =
          updatedPlayerPieces.map((piece) => piece.toMap()).toList();

      if (!finalStep.inHome) {
        final playerSeat = _playerSeat(latestGame, playerId);
        final destination = getGlobalPathIndexForIndex(
          playerSeat,
          finalStep.pos,
        );

        if (!globalSafePlaces.contains(destination)) {
          for (final opponentId in latestGame.players) {
            if (opponentId == playerId) continue;

            final opponentSeat = _playerSeat(latestGame, opponentId);
            final opponentPieces =
                latestGame.pieces[opponentId] ?? const <LudoPiece>[];

            final updatedOpponentPieces = opponentPieces.map((opponentPiece) {
              if (opponentPiece.pos == -1 || opponentPiece.inHome) {
                return opponentPiece;
              }

              final opponentPosition = getGlobalPathIndexForIndex(
                opponentSeat,
                opponentPiece.pos,
              );

              if (opponentPosition == destination) {
                didCapture = true;
                return opponentPiece.copyWith(pos: -1, inHome: false);
              }

              return opponentPiece;
            }).toList();

            allPieces[opponentId] = updatedOpponentPieces
                .map((piece) => piece.toMap())
                .toList();
          }
        }
      }

      final completedAllPieces = updatedPlayerPieces.every(
            (piece) => piece.inHome && piece.pos == 5,
      );
      final didReachGoal = finalStep.inHome &&
          finalStep.pos == 5 &&
          !(originalTarget.inHome && originalTarget.pos == 5);

      final finishOrder = List<String>.from(latestGame.finishOrder);
      final playerFinishedNow =
          completedAllPieces && !finishOrder.contains(playerId);
      if (playerFinishedNow) finishOrder.add(playerId);

      final unfinishedPlayers = latestGame.players
          .where((id) => !finishOrder.contains(id))
          .toList();
      final matchFinished = unfinishedPlayers.length <= 1;
      if (matchFinished && unfinishedPlayers.isNotEmpty) {
        finishOrder.add(unfinishedPlayers.single);
      }

      final extraTurn =
          moveStart.dice == 6 || didCapture || didReachGoal;
      final nextPlayer = matchFinished
          ? ''
          : playerFinishedNow
          ? _nextActivePlayer(
        latestGame.players,
        playerId,
        finishOrder,
      )
          : extraTurn
          ? playerId
          : _nextActivePlayer(
        latestGame.players,
        playerId,
        finishOrder,
      );

      final aiControlled = List<String>.from(latestGame.aiControlledPlayers);
      final pending = List<String>.from(latestGame.pendingReconnectPlayers);
      final reconnectNow = pending.contains(playerId) &&
          !latestGame.forfeitedPlayers.contains(playerId);

      GameSystemEvent? reconnectEvent;
      if (reconnectNow) {
        aiControlled.remove(playerId);
        pending.remove(playerId);
        final eventTime = DateTime.now().millisecondsSinceEpoch;
        reconnectEvent = GameSystemEvent(
          id: 'reconnected_${playerId}_${latestGame.turnVersion}_$eventTime',
          type: GameSystemEvent.playerReconnected,
          playerId: playerId,
          createdAtMs: eventTime,
        );
      }

      final update = <String, dynamic>{
        'pieces': allPieces,
        'currentTurn': nextPlayer,
        'hasRolled': false,
        'status': matchFinished ? 'finished' : 'playing',
        'winnerUid': finishOrder.isEmpty ? '' : finishOrder.first,
        'finishOrder': finishOrder,
        'activeMove': null,
        'activeDiceRoll': null,
        'automationLease': null,
        'aiControlledPlayers': aiControlled,
        'pendingReconnectPlayers': pending,
        'turnPhase': LudoGame.waitingForRoll,
        'turnDeadlineAt': matchFinished ? null : _nextRollDeadline(),
        'turnVersion': latestGame.turnVersion + 1,
        'matchmakingOpen': false,
        'lastActivityAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().toUtc().add(
            matchFinished
                ? const Duration(hours: 1)
                : const Duration(hours: 24),
          ),
        ),
      };

      if (reconnectEvent != null) {
        update['systemEvent'] = reconnectEvent.toMap();
      }
      if (matchFinished) update['finishedAt'] = FieldValue.serverTimestamp();

      transaction.update(gameReference, update);

      if (matchFinished) {
        final humanPlayerCount = latestGame.players
            .where((id) => !id.startsWith('bot_'))
            .length;

        transaction.set(
          resultReference,
          {
            'participantIds': latestGame.players,
            'ranking': finishOrder,
            'playerNames': latestGame.playerNames,
            'preferredColors': latestGame.preferredColors,
            'playerSeats': latestGame.playerSeats,
            'boardId': latestGame.boardId,
            'playerCount': latestGame.players.length,
            'humanPlayerCount': humanPlayerCount,
            'botPlayerCount': latestGame.players.length - humanPlayerCount,
            'startedAt': latestGame.startedAt ?? FieldValue.serverTimestamp(),
            'finishedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      return _MoveFinalizationResult(
        statusMessage: _buildStatusMessage(
          latestGame: latestGame,
          playerId: playerId,
          playerFinishedNow: playerFinishedNow,
          placement: finishOrder.indexOf(playerId) + 1,
          matchFinished: matchFinished,
          didCapture: didCapture,
          didReachGoal: didReachGoal,
          rolledSix: moveStart.dice == 6,
        ),
      );
    });
  }

  int _playerSeat(LudoGame currentGame, String playerId) {
    return currentGame.playerSeats[playerId] ??
        currentGame.players.indexOf(playerId).clamp(0, 3).toInt();
  }

  String _nextActivePlayer(
      List<String> players,
      String currentPlayerId,
      List<String> finishOrder,
      ) {
    if (players.isEmpty) return '';

    final finished = finishOrder.toSet();
    final currentIndex = players.indexOf(currentPlayerId);
    final startIndex = currentIndex < 0 ? -1 : currentIndex;

    for (int offset = 1; offset <= players.length; offset++) {
      final candidate = players[(startIndex + offset) % players.length];
      if (!finished.contains(candidate)) return candidate;
    }

    return '';
  }

  String _buildStatusMessage({
    required LudoGame latestGame,
    required String playerId,
    required bool playerFinishedNow,
    required int placement,
    required bool matchFinished,
    required bool didCapture,
    required bool didReachGoal,
    required bool rolledSix,
  }) {
    final name = latestGame.playerNames[playerId] ?? 'Player';

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

    switch (value % 10) {
      case 1:
        return '${value}st';
      case 2:
        return '${value}nd';
      case 3:
        return '${value}rd';
      default:
        return '${value}th';
    }
  }
}

class _MoveStart {
  final LudoPiece piece;
  final ActiveMove activeMove;
  final int dice;

  const _MoveStart({
    required this.piece,
    required this.activeMove,
    required this.dice,
  });
}

class _MoveFinalizationResult {
  final String statusMessage;

  const _MoveFinalizationResult({required this.statusMessage});
}