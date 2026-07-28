import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/ludo_models.dart';

mixin LudoPresenceMixin on ChangeNotifier {
  FirebaseFirestore get db;
  User? get user;
  String get gameId;
  LudoGame? get game;

  String get localConnectionState;
  set localConnectionState(String value);

  static const Duration presenceHeartbeatInterval = Duration(seconds: 15);
  static const Duration presenceStaleAfter = Duration(seconds: 40);

  Timer? _presenceHeartbeatTimer;
  Timer? _presenceUiTimer;
  String? _presenceRoomId;
  String? _presenceSessionId;

  String get _sessionId {
    return _presenceSessionId ??=
    '${DateTime.now().microsecondsSinceEpoch}_${user?.uid ?? 'guest'}';
  }

  bool get isLocallyReconnecting =>
      localConnectionState == PlayerPresence.reconnecting;

  void startPresenceTracking() {
    final currentUser = user;
    final currentGame = game;
    final currentRoomId = gameId;

    if (currentUser == null ||
        currentRoomId.isEmpty ||
        currentGame == null ||
        !currentGame.players.contains(currentUser.uid)) {
      stopPresenceTracking();
      return;
    }

    if (_presenceRoomId == currentRoomId &&
        _presenceHeartbeatTimer?.isActive == true) {
      return;
    }

    stopPresenceTracking();
    _presenceRoomId = currentRoomId;
    localConnectionState = PlayerPresence.online;
    unawaited(_writePresence(PlayerPresence.online, roomId: currentRoomId));

    _presenceHeartbeatTimer = Timer.periodic(
      presenceHeartbeatInterval,
          (_) => unawaited(
        _writePresence(PlayerPresence.online, roomId: currentRoomId),
      ),
    );

    _presenceUiTimer = Timer.periodic(
      const Duration(seconds: 5),
          (_) => notifyListeners(),
    );
  }

  void stopPresenceTracking() {
    _presenceHeartbeatTimer?.cancel();
    _presenceHeartbeatTimer = null;
    _presenceUiTimer?.cancel();
    _presenceUiTimer = null;
    _presenceRoomId = null;
  }

  Future<void> markPresenceOnline() async {
    final currentRoomId = gameId;
    if (currentRoomId.isEmpty) return;

    localConnectionState = PlayerPresence.online;
    notifyListeners();
    await _writePresence(PlayerPresence.online, roomId: currentRoomId);
    startPresenceTracking();
  }

  Future<void> markPresenceReconnecting() async {
    final currentRoomId = gameId;
    localConnectionState = PlayerPresence.reconnecting;
    notifyListeners();

    if (currentRoomId.isNotEmpty) {
      await _writePresence(
        PlayerPresence.reconnecting,
        roomId: currentRoomId,
      );
    }
  }

  Future<void> markPresenceOffline({String? roomId}) async {
    final targetRoomId = roomId ?? gameId;
    if (targetRoomId.isEmpty) return;

    stopPresenceTracking();
    localConnectionState = PlayerPresence.offline;
    notifyListeners();
    await _writePresence(PlayerPresence.offline, roomId: targetRoomId);
  }

  void noteConnectionError() {
    localConnectionState = PlayerPresence.reconnecting;
    notifyListeners();
  }

  void noteConnectionRestored() {
    if (localConnectionState != PlayerPresence.online) {
      localConnectionState = PlayerPresence.online;
      notifyListeners();
    }
    startPresenceTracking();
  }

  Future<void> _writePresence(
      String state, {
        required String roomId,
      }) async {
    final currentUser = user;
    if (currentUser == null || roomId.isEmpty) return;

    try {
      await db.collection('games').doc(roomId).update({
        'playerPresence.${currentUser.uid}': {
          'state': state,
          'lastSeenAt': FieldValue.serverTimestamp(),
          'sessionId': _sessionId,
        },
      });
    } catch (error) {
      if (state == PlayerPresence.online) {
        localConnectionState = PlayerPresence.reconnecting;
        notifyListeners();
      }
      if (kDebugMode) print('Presence update error: $error');
    }
  }

  String resolvedPresenceState(String playerId) {
    final currentGame = game;
    if (currentGame == null || playerId.isEmpty) {
      return PlayerPresence.offline;
    }

    if (playerId.startsWith('bot_')) return PlayerPresence.ai;
    if (currentGame.forfeitedPlayers.contains(playerId)) {
      return PlayerPresence.forfeited;
    }
    if (currentGame.aiControlledPlayers.contains(playerId)) {
      return PlayerPresence.ai;
    }

    if (playerId == user?.uid && isLocallyReconnecting) {
      return PlayerPresence.reconnecting;
    }

    final presence = currentGame.playerPresence[playerId];
    if (presence == null) return PlayerPresence.offline;

    if (presence.state == PlayerPresence.reconnecting) {
      return PlayerPresence.reconnecting;
    }

    final lastSeen = presence.lastSeenAt?.toDate();
    if (lastSeen == null ||
        DateTime.now().difference(lastSeen) > presenceStaleAfter) {
      return PlayerPresence.offline;
    }

    if (presence.state == PlayerPresence.offline) {
      return PlayerPresence.offline;
    }

    return PlayerPresence.online;
  }

  String presenceLabelForPlayer(String playerId) {
    switch (resolvedPresenceState(playerId)) {
      case PlayerPresence.online:
        return 'Online';
      case PlayerPresence.reconnecting:
        return 'Reconnecting';
      case PlayerPresence.ai:
        return playerId.startsWith('bot_') ? 'AI player' : 'AI controlling';
      case PlayerPresence.forfeited:
        return 'Forfeited';
      default:
        return 'Connection lost';
    }
  }
}