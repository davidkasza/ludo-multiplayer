import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../game/ludo_rules.dart';
import '../../models/ludo_models.dart';

mixin LudoBotMixin on ChangeNotifier {
  FirebaseFirestore get db;
  User? get user;
  Random get random;
  String get gameId;
  LudoGame? get game;
  ActiveMove? get visualActiveMove;
  bool get isDiceRolling;
  DateTime get estimatedServerNow;

  String get statusMessage;
  set statusMessage(String value);

  int getGlobalPathIndexForIndex(int playerIndex, int relativePos);

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
    final currentUser = user;
    if (currentGame == null ||
        currentUser == null ||
        gameId.isEmpty ||
        currentGame.status != 'playing' ||
        currentGame.currentTurn.isEmpty ||
        currentGame.finishOrder.contains(currentGame.currentTurn) ||
        visualActiveMove != null ||
        isDiceRolling) {
      _cancelScheduledAutomation();
      return;
    }

    final humanControllers = currentGame.players
        .where((playerId) => !playerId.startsWith('bot_'))
        .toList();
    final controllerRank = humanControllers.indexOf(currentUser.uid);
    if (controllerRank < 0) {
      _cancelScheduledAutomation();
      return;
    }

    final playerId = currentGame.currentTurn;
    final automated = currentGame.isAiControlled(playerId);
    final deadline = currentGame.effectiveTurnDeadline;
    if (!automated && deadline == null) {
      _cancelScheduledAutomation();
      return;
    }

    final stateKey = _automationStateKey(currentGame);
    if (_automationBusy) return;
    if (_botTurnTimer != null && _scheduledAutomationStateKey != stateKey) {
      _cancelScheduledAutomation();
    }
    if (_botTurnTimer != null || _scheduledAutomationStateKey == stateKey) {
      return;
    }

    final Duration delay;
    // Every connected participant can recover an automated/expired turn, but
    // staggering them lets the first available client commit before later
    // clients spend a transaction read on the same state. If that client is
    // disconnected, the next participant still takes over shortly afterward.
    final recoveryStagger = Duration(milliseconds: controllerRank * 600);
    if (automated) {
      delay = const Duration(milliseconds: 650) + recoveryStagger;
    } else {
      final remaining = deadline!.difference(estimatedServerNow);
      final deadlineDelay = remaining.isNegative
          ? const Duration(milliseconds: 120)
          : remaining + const Duration(milliseconds: 120);
      delay = deadlineDelay + recoveryStagger;
    }

    _scheduledAutomationStateKey = stateKey;
    _botTurnTimer = Timer(delay, () async {
      _botTurnTimer = null;
      await _runAutomation(stateKey);
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
      currentGame.effectiveTurnDeadline?.millisecondsSinceEpoch ?? 0,
      currentGame.isAiControlled(currentGame.currentTurn),
    ].join('|');
  }

  Future<void> _runAutomation(String expectedStateKey) async {
    if (_automationBusy || gameId.isEmpty || user == null) return;
    final currentGame = game;
    if (currentGame == null ||
        _automationStateKey(currentGame) != expectedStateKey) {
      return;
    }

    final playerId = currentGame.currentTurn;
    final deadline = currentGame.effectiveTurnDeadline;
    if (!currentGame.isAiControlled(playerId) &&
        (deadline == null || deadline.isAfter(estimatedServerNow))) {
      return;
    }

    _automationBusy = true;
    try {
      if (currentGame.turnPhase == LudoGame.waitingForRoll &&
          !currentGame.hasRolled) {
        await rollDiceForPlayer(playerId);
      } else if (currentGame.turnPhase == LudoGame.waitingForMove &&
          currentGame.hasRolled) {
        final piece = _chooseBotPiece(
          playerId: playerId,
          diceValue: currentGame.diceValue,
          pieces: currentGame.pieces[playerId] ?? const <LudoPiece>[],
          currentGame: currentGame,
        );
        if (piece != null) await movePieceForPlayer(playerId, piece.id);
      }
    } catch (error, stackTrace) {
      debugPrint('Automated turn failed: $error\n$stackTrace');
      statusMessage = 'Automated turn failed. Retrying...';
      notifyListeners();
    } finally {
      _automationBusy = false;
      _scheduledAutomationStateKey = null;
      Future<void>.delayed(const Duration(milliseconds: 180), syncBotTurn);
    }
  }

  Future<bool> requestTakeBackControl() async {
    final currentUser = user;
    if (currentUser == null || gameId.isEmpty) return false;
    final reference = db.collection('games').doc(gameId);
    bool deferred = false;

    final success = await db.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return false;
      final latest = LudoGame.fromMap(data);
      final playerId = currentUser.uid;
      if (!latest.players.contains(playerId) ||
          latest.status != 'playing' ||
          latest.forfeitedPlayers.contains(playerId)) {
        return false;
      }
      if (!latest.aiControlledPlayers.contains(playerId)) return true;

      // New action descriptors have already been applied and are only visual.
      // Only legacy two-phase actions require deferred hand-back.
      final legacyActionInProgress =
          latest.currentTurn == playerId &&
          ((latest.activeMove != null && !latest.activeMove!.stateApplied) ||
              (latest.activeDiceRoll != null &&
                  !latest.activeDiceRoll!.stateApplied));
      final aiControlled = List<String>.from(latest.aiControlledPlayers);
      final pending = List<String>.from(latest.pendingReconnectPlayers);
      final nextVersion = latest.turnVersion + 1;
      if (legacyActionInProgress) {
        deferred = true;
        if (!pending.contains(playerId)) pending.add(playerId);
        transaction.update(reference, {
          'pendingReconnectPlayers': pending,
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
      } else {
        aiControlled.remove(playerId);
        pending.remove(playerId);
        final seconds = latest.turnPhase == LudoGame.waitingForMove ? 30 : 10;
        transaction.update(reference, {
          'aiControlledPlayers': aiControlled,
          'pendingReconnectPlayers': pending,
          'automationLease': null,
          'systemEvent': GameSystemEvent(
            id: 'reconnected_${playerId}_$nextVersion',
            type: GameSystemEvent.playerReconnected,
            playerId: playerId,
            createdAtMs: estimatedServerNow.millisecondsSinceEpoch,
          ).toMap(),
          if (latest.currentTurn == playerId) ...{
            'turnVersion': nextVersion,
            'turnStartedAt': FieldValue.serverTimestamp(),
            'turnDurationSeconds': seconds,
            'turnDeadlineAt': Timestamp.fromDate(
              estimatedServerNow.add(Duration(seconds: seconds)),
            ),
          },
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
      }
      return true;
    });

    if (success) {
      statusMessage = deferred
          ? 'Control will return after the interrupted legacy action recovers.'
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
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return false;
      final latest = LudoGame.fromMap(data);
      final playerId = currentUser.uid;
      if (!latest.players.contains(playerId) ||
          latest.status != 'playing' ||
          latest.finishOrder.contains(playerId)) {
        return false;
      }

      final ai = List<String>.from(latest.aiControlledPlayers);
      final pending = List<String>.from(latest.pendingReconnectPlayers)
        ..remove(playerId);
      final forfeited = List<String>.from(latest.forfeitedPlayers);
      if (!ai.contains(playerId)) ai.add(playerId);
      if (!forfeited.contains(playerId)) forfeited.add(playerId);
      final nextVersion = latest.turnVersion + 1;
      transaction.update(reference, {
        'aiControlledPlayers': ai,
        'pendingReconnectPlayers': pending,
        'forfeitedPlayers': forfeited,
        'systemEvent': GameSystemEvent(
          id: 'forfeit_${playerId}_$nextVersion',
          type: GameSystemEvent.playerForfeited,
          playerId: playerId,
          createdAtMs: estimatedServerNow.millisecondsSinceEpoch,
        ).toMap(),
        if (latest.currentTurn == playerId) ...{
          'turnVersion': nextVersion,
          'turnStartedAt': FieldValue.serverTimestamp(),
          'turnDurationSeconds': 0,
          'turnDeadlineAt': Timestamp.fromDate(estimatedServerNow),
          'automationLease': null,
        },
        'lastActivityAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  LudoPiece? _chooseBotPiece({
    required String playerId,
    required int diceValue,
    required List<LudoPiece> pieces,
    required LudoGame currentGame,
  }) {
    final valid = pieces
        .where((piece) => LudoRules.isValidMove(piece, diceValue))
        .toList();
    if (valid.isEmpty) return null;
    valid.sort((a, b) {
      final bScore = _scoreMove(playerId, b, diceValue, currentGame);
      final aScore = _scoreMove(playerId, a, diceValue, currentGame);
      return bScore.compareTo(aScore);
    });
    return valid.first;
  }

  int _scoreMove(
    String playerId,
    LudoPiece piece,
    int diceValue,
    LudoGame currentGame,
  ) {
    final destination = LudoRules.destination(piece, diceValue);
    var score = 0;
    if (destination.inHome && destination.pos == LudoRules.goalPosition) {
      score += 10000;
    } else if (destination.inHome) {
      score += 3000 + destination.pos * 100;
    }
    if (piece.pos == LudoRules.basePosition) score += 1800;
    if (_wouldCapture(playerId, destination, currentGame)) score += 5000;
    if (!destination.inHome) {
      final seat =
          currentGame.playerSeats[playerId] ??
          currentGame.players.indexOf(playerId).clamp(0, 3).toInt();
      final global = getGlobalPathIndexForIndex(seat, destination.pos);
      if (LudoRules.safeGlobalPositions.contains(global)) score += 450;
      score += destination.pos * 12;
    }
    return score + random.nextInt(25);
  }

  bool _wouldCapture(
    String playerId,
    ActiveMoveStep destination,
    LudoGame currentGame,
  ) {
    if (destination.inHome) return false;
    final seat =
        currentGame.playerSeats[playerId] ??
        currentGame.players.indexOf(playerId).clamp(0, 3).toInt();
    final global = getGlobalPathIndexForIndex(seat, destination.pos);
    if (LudoRules.safeGlobalPositions.contains(global)) return false;
    for (final opponentId in currentGame.players) {
      if (opponentId == playerId) continue;
      final opponentSeat =
          currentGame.playerSeats[opponentId] ??
          currentGame.players.indexOf(opponentId).clamp(0, 3).toInt();
      for (final opponent
          in currentGame.pieces[opponentId] ?? const <LudoPiece>[]) {
        if (opponent.pos == LudoRules.basePosition || opponent.inHome) continue;
        if (getGlobalPathIndexForIndex(opponentSeat, opponent.pos) == global) {
          return true;
        }
      }
    }
    return false;
  }
}
