import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  int getPlayerIndex(String uid);

  void syncVisualActiveMove(ActiveMove? remoteMove);

  Future<void> movePiece(int pieceId) async {
    if (gameId.isEmpty ||
        user == null ||
        game == null ||
        !isMyTurn ||
        !game!.hasRolled ||
        localMovingPiece != null ||
        game!.activeMove != null) {
      return;
    }

    final pieces = getMyPieces();
    final targetPiece = pieces.firstWhere((p) => p.id == pieceId);
    final dice = game!.diceValue;

    if (targetPiece.pos == 5 && targetPiece.inHome) return;

    if (targetPiece.pos == -1 && dice != 6) {
      statusMessage = "⚠️ You can only leave the base by rolling a 6!";
      notifyListeners();
      return;
    }

    if (targetPiece.inHome && (targetPiece.pos + dice) > 5) {
      statusMessage = "⚠️ Roll too high! You must enter the goal precisely.";
      notifyListeners();
      return;
    }

    statusMessage = "";

    final steps = _buildMoveSteps(
      piece: targetPiece,
      dice: dice,
    );

    const stepDurationMs = 250;

    final activeMove = ActiveMove(
      playerId: user!.uid,
      pieceId: pieceId,
      startedAt: DateTime.now().millisecondsSinceEpoch,
      stepDurationMs: stepDurationMs,
      steps: steps,
    );

    localMovingPiece = LocalMovingPiece(
      id: pieceId,
      currentVisualPos: targetPiece.pos,
      inHome: targetPiece.inHome,
      stepCount: steps.length - 1,
    );

    syncVisualActiveMove(activeMove);
    notifyListeners();

    try {
      await db.collection('games').doc(gameId).update({
        'activeMove': activeMove.toMap(),
      });

      await Future.delayed(
        Duration(milliseconds: activeMove.totalDurationMs + 60),
      );

      if (gameId.isEmpty || user == null || game == null) return;

      localMovingPiece = null;
      notifyListeners();

      final lastStep = steps.last;

      await _finalizeFirebaseMove(
        pieceId,
        lastStep.pos,
        lastStep.inHome,
        targetPiece,
      );
    } catch (e) {
      localMovingPiece = null;
      statusMessage = "❌ Could not move piece!";
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

  Future<void> _finalizeFirebaseMove(
      int pieceId,
      int finalPos,
      bool finalInHome,
      LudoPiece targetPiece,
      ) async {
    final pieces = getMyPieces();
    final dice = game!.diceValue;

    final updatedPieces = pieces.map((p) {
      if (p.id != pieceId) return p.toMap();

      return p.copyWith(
        pos: finalPos,
        inHome: finalInHome,
      ).toMap();
    }).toList();

    bool didCapture = false;

    final opponentUid = game!.players.firstWhere(
          (p) => p != user!.uid,
      orElse: () => '',
    );

    final opponentPieces =
    opponentUid.isNotEmpty ? game!.pieces[opponentUid] : null;

    List<Map<String, dynamic>>? updatedOpponentPieces;

    if (opponentPieces != null && !finalInHome) {
      final myGlobalPos =
      myPlayerIndex == 0 ? finalPos : (finalPos + 26) % 52;

      if (!globalSafePlaces.contains(myGlobalPos)) {
        final opponentPlayerIndex = getPlayerIndex(opponentUid);

        updatedOpponentPieces = opponentPieces.map((op) {
          if (op.pos == -1 || op.inHome) return op.toMap();

          final opGlobalPos =
          opponentPlayerIndex == 0 ? op.pos : (op.pos + 26) % 52;

          if (opGlobalPos == myGlobalPos) {
            didCapture = true;
            return op.copyWith(pos: -1, inHome: false).toMap();
          }

          return op.toMap();
        }).toList();
      }
    }

    final isWinner = updatedPieces.every(
          (p) => p['inHome'] == true && p['pos'] == 5,
    );

    String nextPlayer = game!.players.firstWhere(
          (p) => p != user!.uid,
      orElse: () => user!.uid,
    );

    final didReachGoal =
        finalInHome && finalPos == 5 && !(targetPiece.inHome && targetPiece.pos == 5);

    if (dice == 6 || didCapture || didReachGoal) {
      nextPlayer = user!.uid;

      if (dice == 6) {
        statusMessage = "✨ You rolled a 6! You get an extra roll as a reward!";
      }

      if (didCapture) {
        statusMessage = "💥 You captured an opponent! Extra roll awarded!";
      }

      if (didReachGoal) {
        statusMessage =
        "🎉 You reached the goal! You get an extra roll as a reward!";
      }
    }

    final finalAllPieces = <String, dynamic>{};

    game!.pieces.forEach((uid, pieceList) {
      finalAllPieces[uid] = pieceList.map((p) => p.toMap()).toList();
    });

    finalAllPieces[user!.uid] = updatedPieces;

    if (opponentUid.isNotEmpty && updatedOpponentPieces != null) {
      finalAllPieces[opponentUid] = updatedOpponentPieces;
    }

    await db.collection('games').doc(gameId).update({
      'pieces': finalAllPieces,
      'currentTurn': isWinner ? user!.uid : nextPlayer,
      'hasRolled': false,
      'status': isWinner ? 'finished' : 'playing',
      'winnerUid': isWinner ? user!.uid : '',
      'activeMove': null,
    });
  }
}