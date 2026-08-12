import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../../models/ludo_models.dart';

/// Session-based presence backed by Realtime Database.
///
/// Each app instance owns one session node. RTDB removes that node when its
/// connection closes, so closing one of several tabs cannot mark all of a
/// user's sessions offline and no heartbeat writes are required.
mixin LudoPresenceMixin on ChangeNotifier {
  FirebaseDatabase get realtimeDb;
  User? get user;
  String get gameId;
  LudoGame? get game;

  String get localConnectionState;
  set localConnectionState(String value);

  StreamSubscription<DatabaseEvent>? _connectedSubscription;
  StreamSubscription<DatabaseEvent>? _presenceSubscription;
  StreamSubscription<DatabaseEvent>? _serverOffsetSubscription;
  DatabaseReference? _sessionReference;
  String? _presenceRoomId;
  String? _presenceSessionId;
  final Stopwatch _serverClock = Stopwatch();
  DateTime? _serverClockAnchor;
  bool _hasRealtimePresenceSnapshot = false;
  Map<String, String> _realtimePresence = const {};

  DateTime get estimatedServerNow {
    final anchor = _serverClockAnchor;
    return anchor == null ? DateTime.now() : anchor.add(_serverClock.elapsed);
  }

  String get _sessionId => _presenceSessionId ??=
      '${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}';

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
        _presenceSubscription != null &&
        _connectedSubscription != null) {
      return;
    }

    stopPresenceTracking();
    _presenceRoomId = currentRoomId;
    localConnectionState = PlayerPresence.online;

    final sessionReference = realtimeDb.ref(
      'gamePresence/$currentRoomId/${currentUser.uid}/sessions/$_sessionId',
    );
    _sessionReference = sessionReference;

    _serverOffsetSubscription = realtimeDb
        .ref('.info/serverTimeOffset')
        .onValue
        .listen(
          (event) {
            if (_presenceRoomId != currentRoomId) return;
            final value = event.snapshot.value;
            if (value is num) {
              _serverClockAnchor = DateTime.now().add(
                Duration(milliseconds: value.toInt()),
              );
              _serverClock
                ..reset()
                ..start();
            }
          },
          onError: (Object error) =>
              debugPrint('RTDB server time offset unavailable: $error'),
        );

    _presenceSubscription = realtimeDb
        .ref('gamePresence/$currentRoomId')
        .onValue
        .listen(
          (event) {
            if (_presenceRoomId != currentRoomId) return;
            final resolved = _parsePresence(event.snapshot.value);
            _hasRealtimePresenceSnapshot = true;
            if (!mapEquals(resolved, _realtimePresence)) {
              _realtimePresence = resolved;
              notifyListeners();
            }
          },
          onError: (Object error) {
            _hasRealtimePresenceSnapshot = false;
            debugPrint('RTDB presence listener failed: $error');
          },
        );

    _connectedSubscription = realtimeDb
        .ref('.info/connected')
        .onValue
        .listen(
          (event) {
            if (_presenceRoomId != currentRoomId) return;
            final connected = event.snapshot.value == true;
            if (!connected) {
              if (localConnectionState != PlayerPresence.reconnecting) {
                localConnectionState = PlayerPresence.reconnecting;
                notifyListeners();
              }
              return;
            }
            localConnectionState = PlayerPresence.online;
            unawaited(_publishSession(PlayerPresence.online));
            notifyListeners();
          },
          onError: (Object error) {
            localConnectionState = PlayerPresence.reconnecting;
            debugPrint('RTDB connection listener failed: $error');
            notifyListeners();
          },
        );
  }

  Map<String, String> _parsePresence(Object? value) {
    if (value is! Map) return const {};
    final result = <String, String>{};
    for (final playerEntry in value.entries) {
      final playerId = playerEntry.key.toString();
      final playerValue = playerEntry.value;
      if (playerValue is! Map) continue;
      final sessions = playerValue['sessions'];
      if (sessions is! Map || sessions.isEmpty) continue;
      var state = PlayerPresence.offline;
      for (final session in sessions.values) {
        if (session is! Map) continue;
        final sessionState = session['state'];
        if (sessionState == PlayerPresence.online) {
          state = PlayerPresence.online;
          break;
        }
        if (sessionState == PlayerPresence.reconnecting) {
          state = PlayerPresence.reconnecting;
        }
      }
      result[playerId] = state;
    }
    return result;
  }

  Future<void> _publishSession(String state) async {
    final reference = _sessionReference;
    if (reference == null) return;
    try {
      await reference.onDisconnect().remove();
      await reference.set({
        'state': state,
        'lastChanged': ServerValue.timestamp,
      });
    } catch (error) {
      localConnectionState = PlayerPresence.reconnecting;
      debugPrint('RTDB presence update failed: $error');
      notifyListeners();
    }
  }

  void stopPresenceTracking() {
    final reference = _sessionReference;
    _connectedSubscription?.cancel();
    _presenceSubscription?.cancel();
    _serverOffsetSubscription?.cancel();
    _connectedSubscription = null;
    _presenceSubscription = null;
    _serverOffsetSubscription = null;
    _sessionReference = null;
    _presenceRoomId = null;
    _presenceSessionId = null;
    _hasRealtimePresenceSnapshot = false;
    _realtimePresence = const {};
    if (reference != null) {
      unawaited(reference.onDisconnect().cancel());
      unawaited(reference.remove());
    }
  }

  Future<void> markPresenceOnline() async {
    localConnectionState = PlayerPresence.online;
    startPresenceTracking();
    await _publishSession(PlayerPresence.online);
    notifyListeners();
  }

  Future<void> markPresenceReconnecting() async {
    localConnectionState = PlayerPresence.reconnecting;
    await _publishSession(PlayerPresence.reconnecting);
    notifyListeners();
  }

  Future<void> markPresenceOffline({String? roomId}) async {
    final reference = _sessionReference;
    if (reference != null) {
      try {
        await reference.onDisconnect().cancel();
        await reference.remove();
      } catch (error) {
        debugPrint('RTDB presence cleanup failed: $error');
      }
    }
    _sessionReference = null;
    stopPresenceTracking();
    localConnectionState = PlayerPresence.offline;
    notifyListeners();
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
    if (playerId == user?.uid &&
        localConnectionState == PlayerPresence.online) {
      return PlayerPresence.online;
    }
    if (_hasRealtimePresenceSnapshot) {
      return _realtimePresence[playerId] ?? PlayerPresence.offline;
    }

    // Read-only compatibility fallback for rooms created by older clients.
    final legacy = currentGame.playerPresence[playerId];
    if (legacy == null) return PlayerPresence.offline;
    final lastSeen = legacy.lastSeenAt?.toDate();
    if (lastSeen == null ||
        estimatedServerNow.difference(lastSeen) > const Duration(seconds: 40)) {
      return PlayerPresence.offline;
    }
    return legacy.state;
  }

  String presenceLabelForPlayer(String playerId) {
    return switch (resolvedPresenceState(playerId)) {
      PlayerPresence.online => 'Online',
      PlayerPresence.reconnecting => 'Reconnecting',
      PlayerPresence.ai =>
        playerId.startsWith('bot_') ? 'AI player' : 'AI controlling',
      PlayerPresence.forfeited => 'Forfeited',
      _ => 'Connection lost',
    };
  }
}
