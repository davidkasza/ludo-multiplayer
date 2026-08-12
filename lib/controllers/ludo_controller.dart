import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../config/progression_config.dart';
import '../game/classic_board.dart';
import '../game/ludo_palette.dart';
import '../models/ludo_models.dart';
import 'mixins/ludo_auth_mixin.dart';
import 'mixins/ludo_google_auth_mixin.dart';
import 'mixins/ludo_bot_mixin.dart';
import 'mixins/ludo_chat_mixin.dart';
import 'mixins/ludo_dice_mixin.dart';
import 'mixins/ludo_movement_mixin.dart';
import 'mixins/ludo_presence_mixin.dart';
import 'mixins/ludo_profile_mixin.dart';
import 'mixins/ludo_progression_mixin.dart';
import 'mixins/ludo_room_mixin.dart';
import 'mixins/ludo_sandbox_mixin.dart';

class LudoController extends ChangeNotifier
    with
        LudoAuthMixin,
        LudoProfileMixin,
        LudoProgressionMixin,
        LudoGoogleAuthMixin,
        LudoPresenceMixin,
        LudoRoomMixin,
        LudoDiceMixin,
        LudoMovementMixin,
        LudoChatMixin,
        LudoSandboxMixin,
        LudoBotMixin {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final FirebaseDatabase realtimeDb = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        'https://ludo-app-569c2-default-rtdb.europe-west1.firebasedatabase.app',
  );
  final Random random = Random.secure();

  User? user;
  String gameId = '';
  LudoGame? game;
  String statusMessage = '';

  String profileName = '';
  bool profileLoaded = false;
  String activeGameId = '';
  LudoGame? resumableGame;
  bool activeGameChecked = false;

  ProgressionConfig progressionConfig = ProgressionConfig.defaults;
  bool progressionConfigLoaded = false;
  int profileXp = 0;
  int profileCoins = 0;
  int rewardedMatches = 0;
  int rewardedWins = 0;
  int rewardedPodiums = 0;

  String localConnectionState = PlayerPresence.online;

  final ValueNotifier<int> turnSecondsNotifier = ValueNotifier<int>(0);
  Timer? _turnClockTimer;
  String? _turnClockKey;

  bool isDiceRolling = false;
  String? diceRollingPlayerId;

  Timer? _diceRollAnimationTimer;
  String? _lastSeenDiceRollKey;
  String? _animatingDiceRollKey;

  final ValueNotifier<double> hopFrameNotifier = ValueNotifier<double>(0.0);

  Timer? hopTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? gameSubscription;

  ActiveMove? visualActiveMove;
  String? _visualActiveMoveKey;
  int _visualActiveMoveStartedLocallyAt = 0;
  Timer? _visualActiveMoveClearTimer;

  LudoController() {
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await initAuth();
    await initializeGoogleAuth();
    await loadProgressionConfig();

    if (user != null) {
      await loadMyProfile();
    } else {
      profileLoaded = true;
      activeGameChecked = true;
      notifyListeners();
    }
  }

  int get visualMoveElapsedMs {
    if (visualActiveMove == null) return 0;

    return DateTime.now().millisecondsSinceEpoch -
        _visualActiveMoveStartedLocallyAt;
  }

  void syncVisualActiveMove(ActiveMove? remoteMove) {
    final remoteKey = remoteMove?.key;

    if (remoteMove != null) {
      if (_visualActiveMoveKey != remoteKey) {
        _visualActiveMoveClearTimer?.cancel();
        _visualActiveMoveKey = remoteKey;
        final committedAt = remoteMove.committedAt?.toDate();
        final elapsedMs = committedAt == null
            ? 0
            : estimatedServerNow.difference(committedAt).inMilliseconds;
        final visualElapsedMs = elapsedMs
            .clamp(0, remoteMove.totalDurationMs)
            .toInt();
        final remainingMs = (remoteMove.totalDurationMs - visualElapsedMs)
            .clamp(0, remoteMove.totalDurationMs)
            .toInt();
        if (remainingMs == 0) {
          _visualActiveMoveClearTimer = null;
          visualActiveMove = null;
          hopTimer?.cancel();
          hopTimer = null;
          notifyListeners();
          syncBotTurn();
          return;
        }
        visualActiveMove = remoteMove;
        _visualActiveMoveStartedLocallyAt =
            DateTime.now().millisecondsSinceEpoch - visualElapsedMs;
        startHopAnimation();
        _visualActiveMoveClearTimer = Timer(
          Duration(milliseconds: remainingMs + 120),
          _clearVisualActiveMove,
        );
        notifyListeners();
      }
      return;
    }

    _visualActiveMoveKey = null;
    if (visualActiveMove != null) _clearVisualActiveMove();
  }

  void _clearVisualActiveMove() {
    _visualActiveMoveClearTimer?.cancel();
    _visualActiveMoveClearTimer = null;
    visualActiveMove = null;
    _visualActiveMoveStartedLocallyAt = 0;
    hopTimer?.cancel();
    hopTimer = null;
    notifyListeners();
    syncBotTurn();
  }

  void syncDiceRollAnimation(ActiveDiceRoll? remoteRoll) {
    if (remoteRoll == null) {
      if (isDiceRolling || diceRollingPlayerId != null) {
        stopDiceRollAnimation();
      } else {
        _lastSeenDiceRollKey = null;
      }
      return;
    }

    final key = remoteRoll.key;
    if (_lastSeenDiceRollKey == key) return;

    _lastSeenDiceRollKey = key;
    _diceRollAnimationTimer?.cancel();
    _animatingDiceRollKey = key;
    diceRollingPlayerId = remoteRoll.playerId;
    isDiceRolling = true;
    notifyListeners();

    final committedAt = remoteRoll.committedAt?.toDate();
    final elapsedMs = committedAt == null
        ? 0
        : estimatedServerNow.difference(committedAt).inMilliseconds;
    final remainingMs = (remoteRoll.durationMs - elapsedMs)
        .clamp(0, remoteRoll.durationMs)
        .toInt();
    if (remainingMs == 0) {
      _diceRollAnimationTimer = null;
      _animatingDiceRollKey = null;
      diceRollingPlayerId = null;
      isDiceRolling = false;
      notifyListeners();
      syncBotTurn();
      return;
    }

    _diceRollAnimationTimer = Timer(Duration(milliseconds: remainingMs), () {
      if (_animatingDiceRollKey != key) return;

      _diceRollAnimationTimer = null;
      _animatingDiceRollKey = null;
      diceRollingPlayerId = null;
      isDiceRolling = false;
      notifyListeners();
      syncBotTurn();
    });
  }

  void stopDiceRollAnimation() {
    final hadAnimation = isDiceRolling || diceRollingPlayerId != null;

    _diceRollAnimationTimer?.cancel();
    _diceRollAnimationTimer = null;
    _lastSeenDiceRollKey = null;
    _animatingDiceRollKey = null;
    diceRollingPlayerId = null;
    isDiceRolling = false;

    if (hadAnimation) notifyListeners();
  }

  void syncTurnClock() {
    final currentGame = game;
    final deadline = currentGame?.effectiveTurnDeadline;
    final key = currentGame == null || deadline == null
        ? null
        : '${currentGame.turnVersion}_${deadline.millisecondsSinceEpoch}';

    if (key == null || currentGame?.status != 'playing') {
      _turnClockTimer?.cancel();
      _turnClockTimer = null;
      _turnClockKey = null;
      if (turnSecondsNotifier.value != 0) turnSecondsNotifier.value = 0;
      return;
    }
    final currentDeadline = deadline!;

    void updateRemaining() {
      final milliseconds = currentDeadline
          .difference(estimatedServerNow)
          .inMilliseconds;
      final next = milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
      if (turnSecondsNotifier.value != next) turnSecondsNotifier.value = next;
    }

    updateRemaining();
    if (_turnClockKey == key && _turnClockTimer?.isActive == true) return;

    _turnClockTimer?.cancel();
    _turnClockKey = key;
    _turnClockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => updateRemaining(),
    );
  }

  void startHopAnimation() {
    if (hopTimer?.isActive == true) return;
    hopTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (visualActiveMove != null) {
        hopFrameNotifier.value += 0.2;
      } else {
        timer.cancel();
        hopTimer = null;
      }
    });
  }

  @override
  void dispose() {
    disposeAuth();
    hopTimer?.cancel();
    gameSubscription?.cancel();
    _visualActiveMoveClearTimer?.cancel();
    _diceRollAnimationTimer?.cancel();
    _turnClockTimer?.cancel();
    stopPresenceTracking();
    stopRoomHeartbeat();
    stopChatTracking();
    cancelBotTurn();
    hopFrameNotifier.dispose();
    turnSecondsNotifier.dispose();
    super.dispose();
  }

  int getPlayerIndex(String playerId) {
    if (game == null) return -1;
    return game!.playerSeats[playerId] ?? game!.players.indexOf(playerId);
  }

  int get myPlayerIndex {
    if (user == null) return -1;
    return getPlayerIndex(user!.uid);
  }

  bool get isMyTurn {
    final currentUserId = user?.uid;
    final currentGame = game;

    return currentUserId != null &&
        currentGame != null &&
        currentGame.currentTurn == currentUserId &&
        !currentGame.finishOrder.contains(currentUserId) &&
        !currentGame.aiControlledPlayers.contains(currentUserId);
  }

  bool get canRoll {
    return isMyTurn &&
        game != null &&
        !game!.hasRolled &&
        game!.status == 'playing' &&
        !isDiceRolling &&
        visualActiveMove == null;
  }

  bool get isHost {
    if (game == null || user == null) return false;
    return game!.hostUid == user!.uid;
  }

  bool isBotPlayer(String playerId) {
    return playerId.startsWith('bot_');
  }

  bool isPlayerAiControlled(String playerId) {
    return game?.isAiControlled(playerId) ?? isBotPlayer(playerId);
  }

  bool get isMyPlayerAiControlled {
    final currentUserId = user?.uid;
    return currentUserId != null &&
        game?.aiControlledPlayers.contains(currentUserId) == true;
  }

  bool get isMyReconnectPending {
    final currentUserId = user?.uid;
    return currentUserId != null &&
        game?.pendingReconnectPlayers.contains(currentUserId) == true;
  }

  String getPlayerDisplayTitle(String playerId) {
    if (game?.playerNames.containsKey(playerId) == true) {
      return game!.playerNames[playerId]!;
    }

    if (isBotPlayer(playerId)) return 'Computer';

    final orderIndex = game?.players.indexOf(playerId) ?? -1;
    return orderIndex < 0 ? 'Player' : 'Player ${orderIndex + 1}';
  }

  List<LudoPiece> getPiecesForPlayer(String playerId) {
    return game?.pieces[playerId] ?? const [];
  }

  List<LudoPiece> getMyPieces() {
    if (user == null) return const [];
    return getPiecesForPlayer(user!.uid);
  }

  int getGlobalPathIndexForIndex(int playerIndex, int relativePos) {
    return ClassicBoard.globalPathIndexForSeat(playerIndex, relativePos);
  }

  List<String> get seatColorIds {
    return LudoPalette.buildSeatColorIds(
      players: game?.players ?? const [],
      preferredColors: game?.preferredColors ?? const {},
      playerSeats: game?.playerSeats ?? const {},
      viewerId: user?.uid,
    );
  }

  LudoColorStyle colorStyleForSeat(int seatIndex) {
    final colors = seatColorIds;
    final safeIndex = seatIndex.clamp(0, 3).toInt();
    return LudoPalette.style(colors[safeIndex]);
  }

  LudoColorStyle colorStyleForPlayer(String playerId) {
    final index = getPlayerIndex(playerId);
    return colorStyleForSeat(index < 0 ? 0 : index);
  }

  String getPlayerColorName(String playerId) {
    return colorStyleForPlayer(playerId).label.toUpperCase();
  }

  List<Map<String, dynamic>> createDefaultPieces(int initialPos) {
    return List.generate(
      4,
      (i) => LudoPiece(id: i + 1, pos: initialPos, inHome: false).toMap(),
    );
  }
}
