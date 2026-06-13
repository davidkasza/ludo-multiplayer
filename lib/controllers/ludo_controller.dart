import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ludo_models.dart';
import 'mixins/ludo_auth_mixin.dart';
import 'mixins/ludo_room_mixin.dart';
import 'mixins/ludo_dice_mixin.dart';
import 'mixins/ludo_movement_mixin.dart';
import 'mixins/ludo_chat_mixin.dart';
import 'mixins/ludo_sandbox_mixin.dart';

class LudoController extends ChangeNotifier
    with
        LudoAuthMixin,
        LudoRoomMixin,
        LudoDiceMixin,
        LudoMovementMixin,
        LudoChatMixin,
        LudoSandboxMixin {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final Random random = Random();

  User? user;
  String gameId = "";
  LudoGame? game;
  String statusMessage = "";

  bool isDiceRolling = false;

  final ValueNotifier<double> hopFrameNotifier = ValueNotifier<double>(0.0);

  LocalMovingPiece? localMovingPiece;
  Timer? hopTimer;
  StreamSubscription<DocumentSnapshot>? gameSubscription;

  ActiveMove? visualActiveMove;
  String? _visualActiveMoveKey;
  int _visualActiveMoveStartedLocallyAt = 0;
  Timer? _visualActiveMoveClearTimer;

  final List<int> globalSafePlaces = const [
    0,
    3,
    8,
    16,
    21,
    26,
    29,
    34,
    42,
    47,
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
    hopFrameNotifier.dispose();
    super.dispose();
  }

  int getPlayerIndex(String uid) {
    if (game == null) return 0;
    return game!.players.indexOf(uid);
  }

  int get myPlayerIndex {
    return user != null ? getPlayerIndex(user!.uid) : 0;
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
    if (game == null || user == null || game!.players.isEmpty) return false;
    return game!.players.first == user!.uid;
  }

  String getPlayerDisplayTitle(String uid) {
    if (game?.playerNames.containsKey(uid) == true) {
      return game!.playerNames[uid]!;
    }

    return getPlayerIndex(uid) == 0 ? "BLUE (P1)" : "RED (P2)";
  }

  List<LudoPiece> getMyPieces() {
    if (game == null || user == null) return [];
    return game!.pieces[user!.uid] ?? [];
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