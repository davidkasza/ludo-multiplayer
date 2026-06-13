import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/ludo_models.dart';

mixin LudoSandboxMixin on ChangeNotifier {
  FirebaseFirestore get db;

  User? get user;

  String get gameId;

  LudoGame? get game;

  List<LudoPiece> getMyPieces();

  Future<void> teleportPiece(int pieceId, String valueStr) async {
    if (gameId.isEmpty || user == null || game == null) return;

    final pieces = getMyPieces();

    int newPos = -1;
    bool newInHome = false;

    if (valueStr == "-1") {
      newPos = -1;
      newInHome = false;
    } else if (valueStr.startsWith("H")) {
      newPos = int.parse(valueStr.replaceAll("H", ""));
      newInHome = true;
    } else {
      newPos = int.parse(valueStr);
      newInHome = false;
    }

    final updatedPieces = pieces.map((p) {
      if (p.id != pieceId) return p.toMap();

      return p.copyWith(
        pos: newPos,
        inHome: newInHome,
      ).toMap();
    }).toList();

    await db.collection('games').doc(gameId).update({
      'pieces.${user!.uid}': updatedPieces,
    });
  }
}