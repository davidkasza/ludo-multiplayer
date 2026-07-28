import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final Random random = Random();

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

  int turnSecondsRemaining = 0;
  Timer? _turnClockTimer;
  String? _turnClockKey;

  bool isDiceRolling = false;
  String? diceRollingPlayerId;

  Timer? _diceRollAnimationTimer;
  String? _lastSeenDiceRollKey;
  String? _animatingDiceRollKey;

  final ValueNotifier<double> hopFrameNotifier = ValueNotifier<double>(0.0);

  LocalMovingPiece? localMovingPiece;
  Timer? hopTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? gameSubscription;

  ActiveMove? visualActiveMove;
  String? _visualActiveMoveKey;
  int _visualActiveMoveStartedLocallyAt = 0;
  Timer? _visualActiveMoveClearTimer;

  final List<int> globalSafePlaces = const [
    3,
    8,
    11,
    16,
    21,
    24,
    29,
    34,
    37,
    42,
    47,
    50,
  ];

  LudoController() {
    unawaited(_initialize());
    startHopAnimation();
  }

  Future<void> _initialize() async {
    await initAuth();
    await initializeGoogleAuth();
    await loadProgressionConfig();

    if (user != null) {
      await loadMyProfile();
    } else {
      profileLoaded = true;
      notifyListeners();
    }
  }

  int get visualMoveElapsedMs {
    if (visualActiveMove == null) return 0;

    return DateTime.now().millisecondsSinceEpoch -
        _visualActiveMoveStartedLocallyAt;
  }

  void syncVisualActiveMove(ActiveMove? remoteMove) {
    final remoteKey = remoteMove == null
        ? null
        : '${remoteMove.playerId}_${remoteMove.pieceId}_${remoteMove.startedAt}';

    if (remoteMove != null) {
      _visualActiveMoveClearTimer?.cancel();
      _visualActiveMoveClearTimer = null;

      if (_visualActiveMoveKey != remoteKey) {
        visualActiveMove = remoteMove;
        _visualActiveMoveKey = remoteKey;
        _visualActiveMoveStartedLocallyAt =
            DateTime.now().millisecondsSinceEpoch;
      }

      return;
    }

    if (visualActiveMove == null) return;
    if (_visualActiveMoveClearTimer != null) return;

    final remainingMs = visualActiveMove!.totalDurationMs - visualMoveElapsedMs;

    if (remainingMs <= 0) {
      _clearVisualActiveMove();
      return;
    }

    _visualActiveMoveClearTimer = Timer(
      Duration(milliseconds: remainingMs + 120),
      _clearVisualActiveMove,
    );
  }

  void _clearVisualActiveMove() {
    _visualActiveMoveClearTimer?.cancel();
    _visualActiveMoveClearTimer = null;
    visualActiveMove = null;
    _visualActiveMoveKey = null;
    _visualActiveMoveStartedLocallyAt = 0;
    notifyListeners();
  }

  void syncDiceRollAnimation(ActiveDiceRoll? remoteRoll) {
    if (remoteRoll == null) {
      _lastSeenDiceRollKey = null;
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

    _diceRollAnimationTimer = Timer(
      Duration(milliseconds: remoteRoll.durationMs),
          () {
        if (_animatingDiceRollKey != key) return;

        _diceRollAnimationTimer = null;
        _animatingDiceRollKey = null;
        diceRollingPlayerId = null;
        isDiceRolling = false;
        notifyListeners();
      },
    );
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
    final deadline = currentGame?.turnDeadlineAt;
    final key = currentGame == null || deadline == null
        ? null
        : '${currentGame.turnVersion}_${deadline.toDate().millisecondsSinceEpoch}';

    if (key == null || currentGame?.status != 'playing') {
      _turnClockTimer?.cancel();
      _turnClockTimer = null;
      _turnClockKey = null;
      if (turnSecondsRemaining != 0) {
        turnSecondsRemaining = 0;
        notifyListeners();
      }
      return;
    }
    final currentDeadline = deadline;

    if (currentDeadline == null) {
      turnSecondsRemaining = 0;
      notifyListeners();
      return;
    }

    void updateRemaining() {
      final milliseconds = currentDeadline
          .toDate()
          .difference(DateTime.now())
          .inMilliseconds;

      turnSecondsRemaining =
      milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();

      notifyListeners();
    }

    updateRemaining();
    if (_turnClockKey == key && _turnClockTimer?.isActive == true) return;

    _turnClockTimer?.cancel();
    _turnClockKey = key;
    _turnClockTimer = Timer.periodic(
      const Duration(milliseconds: 250),
          (_) => updateRemaining(),
    );
  }

  void startHopAnimation() {
    hopTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (localMovingPiece != null || visualActiveMove != null) {
        hopFrameNotifier.value += 0.2;
      }
    });
  }

  @override
  void dispose() {
    hopTimer?.cancel();
    gameSubscription?.cancel();
    _visualActiveMoveClearTimer?.cancel();
    _diceRollAnimationTimer?.cancel();
    _turnClockTimer?.cancel();
    stopPresenceTracking();
    stopRoomHeartbeat();
    cancelBotTurn();
    hopFrameNotifier.dispose();
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
        game!.activeDiceRoll == null &&
        game!.activeMove == null &&
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

  String getNextPlayerId(String currentPlayerId) {
    final currentGame = game;
    final players = currentGame?.players ?? const <String>[];
    if (players.isEmpty) return currentPlayerId;

    final finishedPlayers = currentGame?.finishOrder.toSet() ?? <String>{};
    final currentIndex = players.indexOf(currentPlayerId);
    final startIndex = currentIndex < 0 ? -1 : currentIndex;

    for (int offset = 1; offset <= players.length; offset++) {
      final candidate = players[(startIndex + offset) % players.length];
      if (!finishedPlayers.contains(candidate)) return candidate;
    }

    return currentPlayerId;
  }

  int getStartOffsetForIndex(int playerIndex) {
    return ClassicBoard.startOffsetForSeat(playerIndex);
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
          (i) => LudoPiece(
        id: i + 1,
        pos: initialPos,
        inHome: false,
      ).toMap(),
    );
  }
}