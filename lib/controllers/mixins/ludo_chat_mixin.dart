import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../../models/ludo_models.dart';

mixin LudoChatMixin on ChangeNotifier {
  FirebaseFirestore get db;
  FirebaseDatabase get realtimeDb;
  User? get user;
  String get gameId;

  StreamSubscription<DatabaseEvent>? _chatSubscription;
  String? _chatRoomId;
  LudoChat? _realtimeChat;

  LudoChat? get realtimeChat => _realtimeChat;

  void startChatTracking(String roomId) {
    if (roomId.isEmpty || _chatRoomId == roomId) return;
    stopChatTracking();
    _chatRoomId = roomId;
    _chatSubscription = realtimeDb
        .ref('gameChat/$roomId/latest')
        .onValue
        .listen(
          (event) {
            if (_chatRoomId != roomId) return;
            final value = event.snapshot.value;
            if (value is! Map) return;
            _realtimeChat = LudoChat.fromMap(Map<String, dynamic>.from(value));
            notifyListeners();
          },
          onError: (Object error) =>
              debugPrint('RTDB chat listener failed: $error'),
        );
  }

  void stopChatTracking() {
    _chatSubscription?.cancel();
    _chatSubscription = null;
    _chatRoomId = null;
    _realtimeChat = null;
  }

  Future<void> sendQuickChat(String message) async {
    final currentUser = user;
    final roomId = gameId;
    final trimmed = message.trim();
    if (currentUser == null || roomId.isEmpty || trimmed.isEmpty) return;

    try {
      await realtimeDb.ref('gameChat/$roomId/latest').set({
        'sender': currentUser.uid,
        'message': trimmed.substring(
          0,
          trimmed.length > 120 ? 120 : trimmed.length,
        ),
        'timestamp': ServerValue.timestamp,
        'messageId': realtimeDb.ref('gameChat/$roomId/messages').push().key,
      });
    } catch (error) {
      debugPrint('RTDB chat send failed: $error');
      // Compatibility fallback while RTDB/rules are being enabled. Once
      // configured, normal chat traffic never touches the game document.
      await db.collection('games').doc(roomId).update({
        'activeChat': {
          'sender': currentUser.uid,
          'message': trimmed.substring(
            0,
            trimmed.length > 120 ? 120 : trimmed.length,
          ),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        'lastActivityAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
