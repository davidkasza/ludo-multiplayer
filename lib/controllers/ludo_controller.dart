import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ludo_models.dart';

class LudoController extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Random _random = Random();

  User? user;
  String gameId = "";
  LudoGame? game;
  String statusMessage = "";

  bool isDiceRolling = false;

  final ValueNotifier<double> hopFrameNotifier = ValueNotifier<double>(0.0);

  LocalMovingPiece? localMovingPiece;
  Timer? _hopTimer;

  StreamSubscription<DocumentSnapshot>? _gameSubscription;

  final List<int> globalSafePlaces = const [0, 3, 8, 16, 21, 26, 29, 34, 42, 47];

  LudoController() {
    _initAuth();
    _startHopAnimation();
  }

  void _initAuth() async {
    try {
      final res = await _auth.signInAnonymously();
      user = res.user;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print("Auth error: $e");
    }
  }

  void _startHopAnimation() {
    _hopTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (localMovingPiece != null) {
        hopFrameNotifier.value += 0.2;
      }
    });
  }

  @override
  void dispose() {
    _hopTimer?.cancel();
    _gameSubscription?.cancel();
    hopFrameNotifier.dispose();
    super.dispose();
  }

  int getPlayerIndex(String uid) {
    if (game == null) return 0;
    return game!.players.indexOf(uid);
  }

  int get myPlayerIndex => user != null ? getPlayerIndex(user!.uid) : 0;
  bool get isMyTurn => game?.currentTurn == user?.uid;
  bool get canRoll => isMyTurn && game != null && !game!.hasRolled && game!.status == 'playing' && !isDiceRolling;

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

  void listenGame(String id) {
    _gameSubscription?.cancel();
    _gameSubscription = _db.collection('games').doc(id).snapshots().listen((snap) {
      if (snap.exists && snap.data() != null) {
        game = LudoGame.fromMap(snap.data()!);
        notifyListeners();
      }
    });
  }

  Future<void> createGame(String playerName, String selectedBoard, bool isTestMode) async {
    if (user == null || playerName.trim().isEmpty) return;
    statusMessage = "";
    notifyListeners();

    int initialPos = isTestMode ? 49 : -1;
    final defaultPieces = List.generate(
        4,
            (i) => LudoPiece(id: i + 1, pos: initialPos, inHome: false).toMap()
    );

    final docRef = await _db.collection('games').add({
      'players': [user!.uid],
      'playerNames': {user!.uid: playerName.trim()},
      'currentTurn': user!.uid,
      'diceValue': 0,
      'hasRolled': false,
      'status': 'waiting',
      'winnerUid': '',
      'boardId': selectedBoard,
      'isTestModeActive': isTestMode,
      'activeChat': LudoChat(sender: '', message: '', timestamp: 0).toMap(),
      'pieces': {user!.uid: defaultPieces}
    });

    gameId = docRef.id;
    listenGame(gameId);
  }

  Future<void> joinGame(String playerName, String inputId) async {
    if (user == null || playerName.trim().isEmpty) return;
    statusMessage = "";
    notifyListeners();

    final ref = _db.collection('games').doc(inputId);
    final snap = await ref.get();

    if (!snap.exists) {
      statusMessage = "❌ Game not found!";
      notifyListeners();
      return;
    }

    final data = snap.data()!;
    List players = data['players'];
    if (players.length >= 2) {
      statusMessage = "❌ This room is already full!";
      notifyListeners();
      return;
    }

    int initialPos = data['isTestModeActive'] == true ? 49 : -1;
    Map playerNames = Map.from(data['playerNames'])..addAll({user!.uid: playerName.trim()});
    Map pieces = Map.from(data['pieces'])..addAll({
      user!.uid: [
        {'id': 1, 'pos': initialPos, 'inHome': false},
        {'id': 2, 'pos': initialPos, 'inHome': false},
        {'id': 3, 'pos': initialPos, 'inHome': false},
        {'id': 4, 'pos': initialPos, 'inHome': false},
      ]
    });

    await ref.update({
      'players': FieldValue.arrayUnion([user!.uid]),
      'playerNames': playerNames,
      'pieces': pieces,
      'status': 'playing'
    });

    gameId = inputId;
    listenGame(inputId);
  }

  Future<void> rollDice(int cheatDiceValue) async {
    if (!canRoll) return;

    isDiceRolling = true;
    notifyListeners();

    int value = cheatDiceValue > 0 && game?.isTestModeActive == true
        ? cheatDiceValue
        : _random.nextInt(6) + 1;

    await Future.delayed(const Duration(milliseconds: 600));
    isDiceRolling = false;

    List<LudoPiece> myPieces = getMyPieces();
    bool hasValidMove = myPieces.any((p) {
      if (p.pos == 5 && p.inHome) return false;
      if (p.pos == -1) return value == 6;
      if (p.inHome) return (p.pos + value) <= 5;
      return true;
    });

    if (!hasValidMove) {
      if (value == 6) {
        statusMessage = "🎲 You rolled a 6, but you have no valid moves. Roll again!";
        notifyListeners();
        await _db.collection('games').doc(gameId).update({
          'diceValue': value,
          'hasRolled': false,
          'currentTurn': user!.uid
        });
      } else {
        String nextPlayer = game!.players.firstWhere((p) => p != user!.uid, orElse: () => user!.uid);
        statusMessage = "🎲 Rolled: $value. No available moves, turn skipped.";
        notifyListeners();
        await _db.collection('games').doc(gameId).update({
          'diceValue': value,
          'hasRolled': false,
          'currentTurn': nextPlayer
        });
      }
    } else {
      await _db.collection('games').doc(gameId).update({'diceValue': value, 'hasRolled': true});
    }
  }

  Future<void> movePiece(int pieceId) async {
    if (gameId.isEmpty || user == null || game == null || !isMyTurn || !game!.hasRolled || localMovingPiece != null) return;

    List<LudoPiece> pieces = getMyPieces();
    var targetPiece = pieces.firstWhere((p) => p.id == pieceId);
    int dice = game!.diceValue;

    if (targetPiece.pos == 5 && targetPiece.inHome) return;
    if (targetPiece.pos == -1 && dice != 6) {
      statusMessage = "⚠️ You can only leave the base by rolling a 6!";
      notifyListeners();
      return;
    }
    if (targetPiece.inHome && (targetPiece.pos + dice) > 5) {
      statusMessage = "⚠️ Roll too high! You must enter the goal precisely.";
      notifyListeners();
      return;
    }

    statusMessage = "";
    int remainingSteps = targetPiece.pos == -1 ? 1 : dice;
    int virtualPos = targetPiece.pos;
    bool virtualInHome = targetPiece.inHome;

    localMovingPiece = LocalMovingPiece(id: pieceId, currentVisualPos: virtualPos, inHome: virtualInHome, stepCount: remainingSteps);
    notifyListeners();

    Timer.periodic(const Duration(milliseconds: 250), (timer) async {
      remainingSteps--;
      if (virtualPos == -1) {
        virtualPos = 0;
        virtualInHome = false;
      } else if (virtualInHome) {
        virtualPos++;
      } else {
        virtualPos++;
        if (virtualPos > 51) {
          virtualPos = 0;
          virtualInHome = true;
        }
      }

      if (remainingSteps <= 0) {
        timer.cancel();
        localMovingPiece = null;
        notifyListeners();
        _finalizeFirebaseMove(pieceId, virtualPos, virtualInHome, targetPiece);
      } else {
        localMovingPiece = localMovingPiece!.copyWith(currentVisualPos: virtualPos, inHome: virtualInHome, stepCount: remainingSteps);
        notifyListeners();
      }
    });
  }

  Future<void> _finalizeFirebaseMove(int pieceId, int finalPos, bool finalInHome, LudoPiece targetPiece) async {
    List<LudoPiece> pieces = getMyPieces();
    int dice = game!.diceValue;

    List<Map<String, dynamic>> updatedPieces = pieces.map((p) {
      if (p.id != pieceId) return p.toMap();
      return p.copyWith(pos: finalPos, inHome: finalInHome).toMap();
    }).toList();

    bool didCapture = false;
    String opponentUid = game!.players.firstWhere((p) => p != user!.uid, orElse: () => '');
    List<LudoPiece>? opponentPieces = opponentUid.isNotEmpty ? game!.pieces[opponentUid] : null;
    List<Map<String, dynamic>>? updatedOpponentPieces;

    if (opponentPieces != null && !finalInHome) {
      int myGlobalPos = myPlayerIndex == 0 ? finalPos : (finalPos + 26) % 52;
      if (!globalSafePlaces.contains(myGlobalPos)) {
        int opponentPlayerIndex = getPlayerIndex(opponentUid);
        updatedOpponentPieces = opponentPieces.map((op) {
          if (op.pos == -1 || op.inHome) return op.toMap();
          int opGlobalPos = opponentPlayerIndex == 0 ? op.pos : (op.pos + 26) % 52;
          if (opGlobalPos == myGlobalPos) {
            didCapture = true;
            return op.copyWith(pos: -1, inHome: false).toMap();
          }
          return op.toMap();
        }).toList();
      }
    }

    bool isWinner = updatedPieces.every((p) => p['inHome'] == true && p['pos'] == 5);
    String nextPlayer = game!.players.firstWhere((p) => p != user!.uid, orElse: () => user!.uid);

    bool didReachGoal = finalInHome && finalPos == 5 && !(targetPiece.inHome && targetPiece.pos == 5);

    if (dice == 6 || didCapture || didReachGoal) {
      nextPlayer = user!.uid;
      if (dice == 6) statusMessage = "✨ You rolled a 6! You get an extra roll as a reward!";
      if (didCapture) statusMessage = "💥 You captured an opponent! Extra roll awarded!";
      if (didReachGoal) statusMessage = "🎉 You reached the goal! You get an extra roll as a reward!";
    }

    Map<String, dynamic> finalAllPieces = {};
    game!.pieces.forEach((uid, pieceList) {
      finalAllPieces[uid] = pieceList.map((p) => p.toMap()).toList();
    });

    finalAllPieces[user!.uid] = updatedPieces;

    if (opponentUid.isNotEmpty && updatedOpponentPieces != null) {
      finalAllPieces[opponentUid] = updatedOpponentPieces;
    }

    await _db.collection('games').doc(gameId).update({
      'pieces': finalAllPieces,
      'currentTurn': isWinner ? user!.uid : nextPlayer,
      'hasRolled': false,
      'status': isWinner ? 'finished' : 'playing',
      'winnerUid': isWinner ? user!.uid : ''
    });
  }

  Future<void> sendQuickChat(String msg) async {
    if (gameId.isEmpty) return;
    await _db.collection('games').doc(gameId).update({
      'activeChat': {'sender': user?.uid ?? '', 'message': msg, 'timestamp': DateTime.now().millisecondsSinceEpoch}
    });
  }

  Future<void> teleportPiece(int pieceId, String valueStr) async {
    if (gameId.isEmpty || user == null || game == null) return;

    List<LudoPiece> pieces = getMyPieces();
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

    List<Map<String, dynamic>> updatedPieces = pieces.map((p) {
      if (p.id != pieceId) return p.toMap();
      return p.copyWith(pos: newPos, inHome: newInHome).toMap();
    }).toList();

    await _db.collection('games').doc(gameId).update({'pieces.${user!.uid}': updatedPieces});
  }

  void quitToMenu() {
    gameId = "";
    game = null;
    statusMessage = "";
    notifyListeners();
  }
}