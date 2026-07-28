import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/ludo_models.dart';

mixin LudoBotMixin on ChangeNotifier {
  FirebaseFirestore get db;
  User? get user;
  Random get random;
  String get gameId;
  LudoGame? get game;

  String get statusMessage;
  set statusMessage(String value);

  List<int> get globalSafePlaces;

  bool isBotPlayer(String playerId);
  int getPlayerIndex(String playerId);
  int getStartOffsetForIndex(int playerIndex);
  int getGlobalPathIndexForIndex(int playerIndex, int relativePos);
  List<LudoPiece> getPiecesForPlayer(String playerId);

  bool isValidMove({
    required LudoPiece piece,
    required int diceValue,
  });

  Future<void> rollDiceForPlayer(
      String playerId, {
        int forcedValue = 0,
        bool animateLocally = false,
      });

  Future<void> movePieceForPlayer(String playerId, int pieceId);

  Timer? _botTurnTimer;
  String? _scheduledAutomationStateKey;
  bool _automationBusy = false;

  void cancelBotTurn() {
    _botTurnTimer?.cancel();
    _botTurnTimer = null;
    _scheduledAutomationStateKey = null;
    _automationBusy = false;
  }

  void syncBotTurn() {
    final currentGame = game;

    if (currentGame == null ||
        gameId.isEmpty ||
        currentGame.status != 'playing' ||
        currentGame.currentTurn.isEmpty ||
        currentGame.finishOrder.contains(currentGame.currentTurn) ||
        currentGame.activeMove != null ||
        currentGame.activeDiceRoll != null) {
      _cancelScheduledAutomation();
      return;
    }

    final playerId = currentGame.currentTurn;
    final isAutomated = currentGame.isAiControlled(playerId);
    final deadline = currentGame.turnDeadlineAt?.toDate();

    if (!isAutomated && deadline == null) {
      _cancelScheduledAutomation();
      return;
    }

    final stateKey = _automationStateKey(currentGame);
    if (_automationBusy) return;

    if (_botTurnTimer != null && _scheduledAutomationStateKey != stateKey) {
      _botTurnTimer!.cancel();
      _botTurnTimer = null;
      _scheduledAutomationStateKey = null;
    }

    if (_botTurnTimer != null || _scheduledAutomationStateKey == stateKey) {
      return;
    }

    final Duration delay;
    if (isAutomated) {
      delay = const Duration(milliseconds: 850);
    } else {
      final remaining = deadline!.difference(DateTime.now());
      delay = remaining.isNegative
          ? const Duration(milliseconds: 120)
          : remaining + const Duration(milliseconds: 120);
    }

    _scheduledAutomationStateKey = stateKey;
    _botTurnTimer = Timer(delay, () async {
      _botTurnTimer = null;
      await _claimAndRunAutomation(stateKey);
    });
  }

  void _cancelScheduledAutomation() {
    _botTurnTimer?.cancel();
    _botTurnTimer = null;
    _scheduledAutomationStateKey = null;
  }

  String _automationStateKey(LudoGame currentGame) {
    return [
      gameId,
      currentGame.currentTurn,
      currentGame.turnPhase,
      currentGame.turnVersion,
      currentGame.hasRolled,
      currentGame.diceValue,
      currentGame.turnDeadlineAt?.toDate().millisecondsSinceEpoch ?? 0,
      currentGame.isAiControlled(currentGame.currentTurn),
      currentGame.activeMove?.startedAt ?? 0,
      currentGame.activeDiceRoll?.startedAt ?? 0,
    ].join('|');
  }

  Future<void> _claimAndRunAutomation(String expectedStateKey) async {
    if (_automationBusy || gameId.isEmpty || user == null) return;

    _automationBusy = true;
    try {
      final claim = await _claimAutomationLease(expectedStateKey);
      if (claim == null) return;

      if (claim.turnPhase == LudoGame.waitingForRoll && !claim.hasRolled) {
        await rollDiceForPlayer(claim.playerId);
      } else if (claim.turnPhase == LudoGame.waitingForMove &&
          claim.hasRolled) {
        final piece = _chooseBotPiece(
          botId: claim.playerId,
          diceValue: claim.diceValue,
          pieces: claim.pieces,
          currentGame: claim.game,
        );

        if (piece != null) {
          await movePieceForPlayer(claim.playerId, piece.id);
        } else {
          await _releaseAutomationLease(claim.turnVersion);
        }
      } else {
        await _releaseAutomationLease(claim.turnVersion);
      }
    } catch (error) {
      if (kDebugMode) {
        print('Automated turn error: $error');
      }
      statusMessage = 'Automated turn failed. Retrying...';
      notifyListeners();
    } finally {
      _automationBusy = false;
      _scheduledAutomationStateKey = null;
      Future<void>.delayed(
        const Duration(milliseconds: 180),
        syncBotTurn,
      );
    }
  }

  Future<_AutomationClaim?> _claimAutomationLease(
      String expectedStateKey,
      ) async {
    final currentUser = user;
    final currentGameId = gameId;
    if (currentUser == null || currentGameId.isEmpty) return null;

    final reference = db.collection('games').doc(currentGameId);

    return db.runTransaction<_AutomationClaim?>((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists || snapshot.data() == null) return null;

      final latest = LudoGame.fromMap(snapshot.data()!);
      if (_automationStateKey(latest) != expectedStateKey ||
          latest.status != 'playing' ||
          latest.currentTurn.isEmpty ||
          latest.finishOrder.contains(latest.currentTurn) ||
          latest.activeMove != null ||
          latest.activeDiceRoll != null) {
        return null;
      }

      final now = DateTime.now();
      final playerId = latest.currentTurn;
      final isBuiltInBot = isBotPlayer(playerId);
      final alreadyAiControlled = latest.aiControlledPlayers.contains(playerId);
      final deadlineExpired = latest.turnDeadlineAt != null &&
          !latest.turnDeadlineAt!.toDate().isAfter(now);

      if (!isBuiltInBot && !alreadyAiControlled && !deadlineExpired) {
        return null;
      }

      final existingLease = latest.automationLease;
      if (existingLease != null &&
          existingLease.turnVersion == latest.turnVersion &&
          !existingLease.isExpired &&
          existingLease.ownerUid != currentUser.uid) {
        return null;
      }

      final aiControlled = List<String>.from(latest.aiControlledPlayers);
      final newlyTakenOver = !isBuiltInBot && !aiControlled.contains(playerId);
      if (newlyTakenOver) aiControlled.add(playerId);

      final eventTime = DateTime.now().millisecondsSinceEpoch;
      final update = <String, dynamic>{
        'automationLease': AutomationLease(
          ownerUid: currentUser.uid,
          turnVersion: latest.turnVersion,
          expiresAt: Timestamp.fromDate(
            now.toUtc().add(const Duration(seconds: 8)),
          ),
        ).toMap(),
        'aiControlledPlayers': aiControlled,
        'lastActivityAt': FieldValue.serverTimestamp(),
      };

      if (newlyTakenOver) {
        update['systemEvent'] = GameSystemEvent(
          id: 'takeover_${playerId}_${latest.turnVersion}_$eventTime',
          type: GameSystemEvent.aiTakeover,
          playerId: playerId,
          createdAtMs: eventTime,
        ).toMap();
      }

      transaction.update(reference, update);

      return _AutomationClaim(
        playerId: playerId,
        turnPhase: latest.turnPhase,
        turnVersion: latest.turnVersion,
        hasRolled: latest.hasRolled,
        diceValue: latest.diceValue,
        pieces: latest.pieces[playerId] ?? const <LudoPiece>[],
        game: latest,
      );
    });
  }

  Future<void> _releaseAutomationLease(int expectedTurnVersion) async {
    final currentUser = user;
    if (currentUser == null || gameId.isEmpty) return;

    final reference = db.collection('games').doc(gameId);
    await db.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists || snapshot.data() == null) return;

      final latest = LudoGame.fromMap(snapshot.data()!);
      final lease = latest.automationLease;
      if (lease == null ||
          lease.ownerUid != currentUser.uid ||
          lease.turnVersion != expectedTurnVersion) {
        return;
      }

      transaction.update(reference, {
        'automationLease': null,
        'lastActivityAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<bool> requestTakeBackControl() async {
    final currentUser = user;
    if (currentUser == null || gameId.isEmpty) return false;

    final reference = db.collection('games').doc(gameId);
    bool deferred = false;

    final success = await db.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists || snapshot.data() == null) return false;

      final latest = LudoGame.fromMap(snapshot.data()!);
      final playerId = currentUser.uid;

      if (!latest.players.contains(playerId) ||
          latest.status != 'playing' ||
          latest.forfeitedPlayers.contains(playerId)) {
        return false;
      }

      if (!latest.aiControlledPlayers.contains(playerId)) return true;

      final actionInProgress = latest.currentTurn == playerId &&
          (latest.activeMove != null ||
              latest.activeDiceRoll != null ||
              (latest.automationLease != null &&
                  latest.automationLease!.turnVersion == latest.turnVersion &&
                  !latest.automationLease!.isExpired));

      final aiControlled = List<String>.from(latest.aiControlledPlayers);
      final pending = List<String>.from(latest.pendingReconnectPlayers);
      final eventTime = DateTime.now().millisecondsSinceEpoch;

      if (actionInProgress) {
        deferred = true;
        if (!pending.contains(playerId)) pending.add(playerId);
        transaction.update(reference, {
          'pendingReconnectPlayers': pending,
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
      } else {
        aiControlled.remove(playerId);
        pending.remove(playerId);
        final update = <String, dynamic>{
          'aiControlledPlayers': aiControlled,
          'pendingReconnectPlayers': pending,
          'automationLease': null,
          'systemEvent': GameSystemEvent(
            id: 'reconnected_${playerId}_${latest.turnVersion}_$eventTime',
            type: GameSystemEvent.playerReconnected,
            playerId: playerId,
            createdAtMs: eventTime,
          ).toMap(),
          'lastActivityAt': FieldValue.serverTimestamp(),
        };

        if (latest.currentTurn == playerId) {
          update['turnVersion'] = latest.turnVersion + 1;
          update['turnDeadlineAt'] = Timestamp.fromDate(
            DateTime.now().toUtc().add(
              latest.turnPhase == LudoGame.waitingForMove
                  ? const Duration(seconds: 30)
                  : const Duration(seconds: 10),
            ),
          );
        }

        transaction.update(reference, update);
      }

      return true;
    });

    if (success) {
      statusMessage = deferred
          ? 'Control will return after the current AI action.'
          : 'You are back in control.';
      notifyListeners();
    }

    return success;
  }

  Future<bool> markMyselfForfeit() async {
    final currentUser = user;
    if (currentUser == null || gameId.isEmpty) return false;

    final reference = db.collection('games').doc(gameId);

    return db.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists || snapshot.data() == null) return false;

      final latest = LudoGame.fromMap(snapshot.data()!);
      final playerId = currentUser.uid;
      if (!latest.players.contains(playerId) ||
          latest.status != 'playing' ||
          latest.finishOrder.contains(playerId)) {
        return false;
      }

      final aiControlled = List<String>.from(latest.aiControlledPlayers);
      final pending = List<String>.from(latest.pendingReconnectPlayers)
        ..remove(playerId);
      final forfeited = List<String>.from(latest.forfeitedPlayers);

      if (!aiControlled.contains(playerId)) aiControlled.add(playerId);
      if (!forfeited.contains(playerId)) forfeited.add(playerId);

      final eventTime = DateTime.now().millisecondsSinceEpoch;
      final update = <String, dynamic>{
        'aiControlledPlayers': aiControlled,
        'pendingReconnectPlayers': pending,
        'forfeitedPlayers': forfeited,
        'systemEvent': GameSystemEvent(
          id: 'forfeit_${playerId}_${latest.turnVersion}_$eventTime',
          type: GameSystemEvent.playerForfeited,
          playerId: playerId,
          createdAtMs: eventTime,
        ).toMap(),
        'lastActivityAt': FieldValue.serverTimestamp(),
      };

      if (latest.currentTurn == playerId &&
          latest.activeMove == null &&
          latest.activeDiceRoll == null) {
        update['turnDeadlineAt'] = Timestamp.now();
        update['turnVersion'] = latest.turnVersion + 1;
        update['automationLease'] = null;
      }

      transaction.update(reference, update);
      return true;
    });
  }

  LudoPiece? _chooseBotPiece({
    required String botId,
    required int diceValue,
    required List<LudoPiece> pieces,
    required LudoGame currentGame,
  }) {
    final validPieces = pieces
        .where(
          (piece) => isValidMove(
        piece: piece,
        diceValue: diceValue,
      ),
    )
        .toList();

    if (validPieces.isEmpty) return null;

    final scores = <int, int>{
      for (final piece in validPieces)
        piece.id: _scoreMove(
          botId: botId,
          piece: piece,
          diceValue: diceValue,
          currentGame: currentGame,
        ),
    };

    validPieces.sort(
          (a, b) => scores[b.id]!.compareTo(scores[a.id]!),
    );

    return validPieces.first;
  }

  int _scoreMove({
    required String botId,
    required LudoPiece piece,
    required int diceValue,
    required LudoGame currentGame,
  }) {
    final destination = _simulateDestination(piece, diceValue);
    int score = 0;

    if (destination.inHome && destination.pos == 5) {
      score += 10000;
    } else if (destination.inHome) {
      score += 3000 + destination.pos * 100;
    }

    if (piece.pos == -1) score += 1800;

    if (_wouldCapture(
      botId: botId,
      destination: destination,
      currentGame: currentGame,
    )) {
      score += 5000;
    }

    if (!destination.inHome) {
      final botIndex = currentGame.playerSeats[botId] ??
          currentGame.players.indexOf(botId).clamp(0, 3).toInt();
      final globalPos = getGlobalPathIndexForIndex(
        botIndex,
        destination.pos,
      );

      if (globalSafePlaces.contains(globalPos)) score += 450;
      score += destination.pos * 12;
    }

    score += random.nextInt(25);
    return score;
  }

  ActiveMoveStep _simulateDestination(LudoPiece piece, int diceValue) {
    int pos = piece.pos;
    bool inHome = piece.inHome;
    int remaining = piece.pos == -1 ? 1 : diceValue;

    while (remaining > 0) {
      remaining--;

      if (pos == -1) {
        pos = 0;
        inHome = false;
      } else if (inHome) {
        pos++;
      } else {
        pos++;
        if (pos > 51) {
          pos = 0;
          inHome = true;
        }
      }
    }

    return ActiveMoveStep(pos: pos, inHome: inHome);
  }

  bool _wouldCapture({
    required String botId,
    required ActiveMoveStep destination,
    required LudoGame currentGame,
  }) {
    if (destination.inHome) return false;

    final botIndex = currentGame.playerSeats[botId] ??
        currentGame.players.indexOf(botId).clamp(0, 3).toInt();
    final globalPos = getGlobalPathIndexForIndex(
      botIndex,
      destination.pos,
    );

    if (globalSafePlaces.contains(globalPos)) return false;

    for (final opponentId in currentGame.players) {
      if (opponentId == botId) continue;

      final opponentIndex = currentGame.playerSeats[opponentId] ??
          currentGame.players.indexOf(opponentId).clamp(0, 3).toInt();
      final opponentPieces = currentGame.pieces[opponentId] ?? const [];

      for (final opponentPiece in opponentPieces) {
        if (opponentPiece.pos == -1 || opponentPiece.inHome) continue;

        final opponentGlobalPos = getGlobalPathIndexForIndex(
          opponentIndex,
          opponentPiece.pos,
        );

        if (opponentGlobalPos == globalPos) return true;
      }
    }

    return false;
  }
}

class _AutomationClaim {
  final String playerId;
  final String turnPhase;
  final int turnVersion;
  final bool hasRolled;
  final int diceValue;
  final List<LudoPiece> pieces;
  final LudoGame game;

  const _AutomationClaim({
    required this.playerId,
    required this.turnPhase,
    required this.turnVersion,
    required this.hasRolled,
    required this.diceValue,
    required this.pieces,
    required this.game,
  });
}