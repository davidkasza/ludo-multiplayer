import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

mixin LudoChatMixin on ChangeNotifier {
  FirebaseFirestore get db;

  User? get user;

  String get gameId;

  Future<void> sendQuickChat(String msg) async {
    if (gameId.isEmpty) return;

    await db.collection('games').doc(gameId).update({
      'activeChat': {
        'sender': user?.uid ?? '',
        'message': msg,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
  }
}