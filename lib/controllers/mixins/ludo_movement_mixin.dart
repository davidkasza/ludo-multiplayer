import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/ludo_models.dart';
import '../../services/gameplay_functions.dart';

mixin LudoMovementMixin on ChangeNotifier {
  FirebaseFirestore get db;
  GameplayFunctions get gameplayFunctions;

  User? get user;
  String get gameId;
  LudoGame? get game;

  String get statusMessage;
  set statusMessage(String value);

  bool get isMyTurn;

  Future<void> movePiece(int pieceId) async {
    if (user == null || !isMyTurn) return;
    await movePieceForPlayer(user!.uid, pieceId);
  }

  Future<void> movePieceForPlayer(String playerId, int pieceId) async {
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
        await gameplayFunctions.movePiece(
          roomCode: currentGameId,
          pieceId: pieceId,
          expectedTurnVersion: currentGame.turnVersion,
          actionId: actionId,
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
      debugPrint('Move callable failed: ${error.code}: ${error.message}');
      statusMessage = '❌ Could not move the piece.';
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('Move action failed: $error\n$stackTrace');
      statusMessage = '❌ Could not move the piece.';
      notifyListeners();
    }
  }
}
