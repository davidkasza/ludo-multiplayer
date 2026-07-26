import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../game/classic_board.dart';
import '../game/ludo_palette.dart';
import '../models/ludo_models.dart';
import 'mixins/ludo_auth_mixin.dart';
import 'mixins/ludo_bot_mixin.dart';
import 'mixins/ludo_chat_mixin.dart';
import 'mixins/ludo_dice_mixin.dart';
import 'mixins/ludo_movement_mixin.dart';
import 'mixins/ludo_room_mixin.dart';
import 'mixins/ludo_sandbox_mixin.dart';

class LudoController extends ChangeNotifier
    with
        LudoAuthMixin,
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

  bool isDiceRolling = false;

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
    initAuth();
    startHopAnimation();
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
    return game?.currentTurn == user?.uid;
  }

  bool get canRoll {
    return isMyTurn &&
        game != null &&
        !game!.hasRolled &&
        game!.status == 'playing' &&
        !isDiceRolling &&
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
    final players = game?.players ?? const <String>[];
    if (players.isEmpty) return currentPlayerId;

    final currentIndex = players.indexOf(currentPlayerId);
    if (currentIndex < 0) return players.first;

    return players[(currentIndex + 1) % players.length];
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