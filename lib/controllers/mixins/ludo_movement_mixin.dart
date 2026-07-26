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
  int get myPlayerIndex;

  List<int> get globalSafePlaces;

  List<LudoPiece> getMyPieces();
  List<LudoPiece> getPiecesForPlayer(String playerId);
  int getPlayerIndex(String playerId);
  int getStartOffsetForIndex(int playerIndex);
  int getGlobalPathIndexForIndex(int playerIndex, int relativePos);
  String getNextPlayerId(String currentPlayerId);
  String getPlayerDisplayTitle(String playerId);

  void syncVisualActiveMove(ActiveMove? remoteMove);

  Future<void> movePiece(int pieceId) async {
    if (user == null || !isMyTurn) return;
    await movePieceForPlayer(user!.uid, pieceId);
  }

  Future<void> movePieceForPlayer(String playerId, int pieceId) async {
    final currentGame = game;

    if (gameId.isEmpty ||
        currentGame == null ||
        currentGame.status != 'playing' ||
        currentGame.currentTurn != playerId ||
        !currentGame.hasRolled ||
        localMovingPiece != null ||
        currentGame.activeMove != null) {
      return;
    }

    final pieces = getPiecesForPlayer(playerId);
    LudoPiece? targetPiece;

    for (final piece in pieces) {
      if (piece.id == pieceId) {
        targetPiece = piece;
        break;
      }
    }

    if (targetPiece == null) return;
    final movingPiece = targetPiece;

    final dice = currentGame.diceValue;

    if (movingPiece.pos == 5 && movingPiece.inHome) return;

    if (movingPiece.pos == -1 && dice != 6) {
      statusMessage = '⚠️ A piece can only leave the base after rolling a 6.';
      notifyListeners();
      return;
    }

    if (movingPiece.inHome && (movingPiece.pos + dice) > 5) {
      statusMessage = '⚠️ The goal must be reached with an exact roll.';
      notifyListeners();
      return;
    }

    statusMessage = '';

    final steps = _buildMoveSteps(
      piece: movingPiece,
      dice: dice,
    );

    const stepDurationMs = 250;

    final activeMove = ActiveMove(
      playerId: playerId,
      pieceId: pieceId,
      startedAt: DateTime.now().millisecondsSinceEpoch,
      stepDurationMs: stepDurationMs,
      steps: steps,
    );

    final isLocalHumanMove = playerId == user?.uid;
    if (isLocalHumanMove) {
      localMovingPiece = LocalMovingPiece(
        id: pieceId,
        currentVisualPos: movingPiece.pos,
        inHome: movingPiece.inHome,
        stepCount: steps.length - 1,
      );
    }

    syncVisualActiveMove(activeMove);
    notifyListeners();

    try {
      await db.collection('games').doc(gameId).update({
        'activeMove': activeMove.toMap(),
      });

      await Future.delayed(
        Duration(milliseconds: activeMove.totalDurationMs + 60),
      );

      if (gameId.isEmpty || game == null) return;

      if (isLocalHumanMove) {
        localMovingPiece = null;
        notifyListeners();
      }

      final lastStep = steps.last;

      await _finalizeFirebaseMove(
        playerId: playerId,
        pieceId: pieceId,
        finalPos: lastStep.pos,
        finalInHome: lastStep.inHome,
        targetPiece: movingPiece,
        dice: dice,
      );
    } catch (error) {
      if (isLocalHumanMove) {
        localMovingPiece = null;
      }

      statusMessage = '❌ Could not move the piece.';
      syncVisualActiveMove(null);
      notifyListeners();

      if (gameId.isNotEmpty) {
        await db.collection('games').doc(gameId).update({
          'activeMove': null,
        });
      }
    }
  }

  List<ActiveMoveStep> _buildMoveSteps({
    required LudoPiece piece,
    required int dice,
  }) {
    final steps = <ActiveMoveStep>[
      ActiveMoveStep(
        pos: piece.pos,
        inHome: piece.inHome,
      ),
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
        ActiveMoveStep(
          pos: virtualPos,
          inHome: virtualInHome,
        ),
      );
    }

    return steps;
  }

  Future<void> _finalizeFirebaseMove({
    required String playerId,
    required int pieceId,
    required int finalPos,
    required bool finalInHome,
    required LudoPiece targetPiece,
    required int dice,
  }) async {
    final currentGame = game;
    if (currentGame == null) return;

    final pieces = getPiecesForPlayer(playerId);

    final updatedPieces = pieces.map((piece) {
      if (piece.id != pieceId) return piece.toMap();

      return piece
          .copyWith(
        pos: finalPos,
        inHome: finalInHome,
      )
          .toMap();
    }).toList();

    bool didCapture = false;
    final allPieces = <String, dynamic>{};

    currentGame.pieces.forEach((uid, pieceList) {
      allPieces[uid] = pieceList.map((piece) => piece.toMap()).toList();
    });

    allPieces[playerId] = updatedPieces;

    if (!finalInHome) {
      final playerIndex = getPlayerIndex(playerId);
      final myGlobalPos = getGlobalPathIndexForIndex(
        playerIndex,
        finalPos,
      );

      if (!globalSafePlaces.contains(myGlobalPos)) {
        for (final opponentId in currentGame.players) {
          if (opponentId == playerId) continue;

          final opponentIndex = getPlayerIndex(opponentId);
          final opponentPieces = currentGame.pieces[opponentId] ?? const [];

          final updatedOpponentPieces = opponentPieces.map((opponentPiece) {
            if (opponentPiece.pos == -1 || opponentPiece.inHome) {
              return opponentPiece.toMap();
            }

            final opponentGlobalPos = getGlobalPathIndexForIndex(
              opponentIndex,
              opponentPiece.pos,
            );

            if (opponentGlobalPos == myGlobalPos) {
              didCapture = true;
              return opponentPiece
                  .copyWith(
                pos: -1,
                inHome: false,
              )
                  .toMap();
            }

            return opponentPiece.toMap();
          }).toList();

          allPieces[opponentId] = updatedOpponentPieces;
        }
      }
    }

    final isWinner = updatedPieces.every(
          (piece) => piece['inHome'] == true && piece['pos'] == 5,
    );

    final didReachGoal = finalInHome &&
        finalPos == 5 &&
        !(targetPiece.inHome && targetPiece.pos == 5);

    String nextPlayer = getNextPlayerId(playerId);

    if (dice == 6 || didCapture || didReachGoal) {
      nextPlayer = playerId;

      if (dice == 6) {
        statusMessage =
        '✨ ${getPlayerDisplayTitle(playerId)} rolled a 6 and plays again.';
      }

      if (didCapture) {
        statusMessage =
        '💥 ${getPlayerDisplayTitle(playerId)} captured a piece and plays again.';
      }

      if (didReachGoal) {
        statusMessage =
        '🎉 ${getPlayerDisplayTitle(playerId)} reached the goal and plays again.';
      }
    }

    final expiryDuration = isWinner
        ? const Duration(hours: 1)
        : const Duration(hours: 24);

    await db.collection('games').doc(gameId).update({
      'pieces': allPieces,
      'currentTurn': isWinner ? playerId : nextPlayer,
      'hasRolled': false,
      'status': isWinner ? 'finished' : 'playing',
      'winnerUid': isWinner ? playerId : '',
      'activeMove': null,
      'matchmakingOpen': false,
      'lastActivityAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().toUtc().add(expiryDuration),
      ),
    });
  }
}