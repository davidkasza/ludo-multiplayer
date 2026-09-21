import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/ludo_models.dart';
import '../../services/gameplay_functions.dart';

mixin LudoSandboxMixin on ChangeNotifier {
  FirebaseFirestore get db;
  GameplayFunctions get gameplayFunctions;
  User? get user;
  String get gameId;
  LudoGame? get game;
  bool get canUseSandbox;

  Future<void> teleportPiece(int pieceId, String value) async {
    final currentUser = user;
    final currentGame = game;
    if (gameId.isEmpty ||
        currentUser == null ||
        currentGame == null ||
        !canUseSandbox ||
        !currentGame.isTestModeActive) {
      return;
    }

    var newPosition = -1;
    var inHome = false;
    if (value == '-1') {
      newPosition = -1;
    } else if (value.startsWith('H')) {
      newPosition = int.tryParse(value.substring(1)) ?? -2;
      inHome = true;
    } else {
      newPosition = int.tryParse(value) ?? -2;
    }
    if (pieceId < 1 ||
        pieceId > 4 ||
        (inHome
            ? newPosition < 0 || newPosition > 5
            : newPosition < -1 || newPosition > 51)) {
      return;
    }

    try {
      await gameplayFunctions.sandboxTeleportPiece(
        roomCode: gameId,
        pieceId: pieceId,
        pos: newPosition,
        inHome: inHome,
        expectedTurnVersion: currentGame.turnVersion,
        actionId: db.collection('_actionIds').doc().id,
      );
    } catch (error) {
      debugPrint('Sandbox teleport failed: $error');
    }
  }
}
