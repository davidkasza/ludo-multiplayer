import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/ludo_models.dart';

mixin LudoSandboxMixin on ChangeNotifier {
  FirebaseFirestore get db;
  User? get user;
  String get gameId;
  DateTime get estimatedServerNow;

  Future<void> teleportPiece(int pieceId, String value) async {
    final currentUser = user;
    if (gameId.isEmpty || currentUser == null) return;

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

    final reference = db.collection('games').doc(gameId);
    await db.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return;
      final latest = LudoGame.fromMap(data);
      if (!latest.isTestModeActive ||
          !latest.players.contains(currentUser.uid)) {
        return;
      }
      final pieces = latest.pieces[currentUser.uid] ?? const <LudoPiece>[];
      if (!pieces.any((piece) => piece.id == pieceId)) return;
      transaction.update(reference, {
        'pieces.${currentUser.uid}': pieces
            .map(
              (piece) => piece.id == pieceId
                  ? piece.copyWith(pos: newPosition, inHome: inHome).toMap()
                  : piece.toMap(),
            )
            .toList(),
        'lastActivityAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          estimatedServerNow.toUtc().add(const Duration(hours: 24)),
        ),
      });
    });
  }
}
