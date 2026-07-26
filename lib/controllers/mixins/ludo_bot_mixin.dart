import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/ludo_models.dart';

mixin LudoBotMixin on ChangeNotifier {
  Random get random;
  LudoGame? get game;
  bool get isHost;

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
  String? _scheduledBotStateKey;
  bool _botBusy = false;

  void cancelBotTurn() {
    _botTurnTimer?.cancel();
    _botTurnTimer = null;
    _scheduledBotStateKey = null;
    _botBusy = false;
  }

  void syncBotTurn() {
    final currentGame = game;

    if (!isHost ||
        currentGame == null ||
        currentGame.status != 'playing' ||
        !isBotPlayer(currentGame.currentTurn) ||
        currentGame.activeMove != null) {
      _botTurnTimer?.cancel();
      _botTurnTimer = null;
      _scheduledBotStateKey = null;
      return;
    }

    final stateKey = [
      currentGame.currentTurn,
      currentGame.hasRolled,
      currentGame.diceValue,
      currentGame.activeMove?.startedAt ?? 0,
    ].join('|');

    if (_botBusy ||
        _botTurnTimer != null ||
        _scheduledBotStateKey == stateKey) {
      return;
    }

    _scheduledBotStateKey = stateKey;
    _botTurnTimer = Timer(const Duration(milliseconds: 850), () async {
      _botTurnTimer = null;

      final latestGame = game;
      if (latestGame == null ||
          latestGame.status != 'playing' ||
          !isHost ||
          !isBotPlayer(latestGame.currentTurn)) {
        _scheduledBotStateKey = null;
        return;
      }

      final latestStateKey = [
        latestGame.currentTurn,
        latestGame.hasRolled,
        latestGame.diceValue,
        latestGame.activeMove?.startedAt ?? 0,
      ].join('|');

      if (latestStateKey != stateKey || latestGame.activeMove != null) {
        _scheduledBotStateKey = null;
        syncBotTurn();
        return;
      }

      _botBusy = true;

      try {
        final botId = latestGame.currentTurn;

        if (!latestGame.hasRolled) {
          await rollDiceForPlayer(
            botId,
            animateLocally: false,
          );
        } else {
          final piece = _chooseBotPiece(
            botId: botId,
            diceValue: latestGame.diceValue,
          );

          if (piece != null) {
            await movePieceForPlayer(botId, piece.id);
          }
        }
      } catch (error) {
        statusMessage = 'Computer turn failed. Retrying...';
        _scheduledBotStateKey = null;
        notifyListeners();

        _botTurnTimer = Timer(
          const Duration(seconds: 1),
          syncBotTurn,
        );
      } finally {
        _botBusy = false;
        Future<void>.delayed(
          const Duration(milliseconds: 120),
          syncBotTurn,
        );
      }
    });
  }

  LudoPiece? _chooseBotPiece({
    required String botId,
    required int diceValue,
  }) {
    final pieces = getPiecesForPlayer(botId)
        .where(
          (piece) => isValidMove(
        piece: piece,
        diceValue: diceValue,
      ),
    )
        .toList();

    if (pieces.isEmpty) return null;

    final scores = <int, int>{
      for (final piece in pieces)
        piece.id: _scoreMove(
          botId: botId,
          piece: piece,
          diceValue: diceValue,
        ),
    };

    pieces.sort(
          (a, b) => scores[b.id]!.compareTo(scores[a.id]!),
    );

    return pieces.first;
  }

  int _scoreMove({
    required String botId,
    required LudoPiece piece,
    required int diceValue,
  }) {
    final destination = _simulateDestination(piece, diceValue);
    int score = 0;

    if (destination.inHome && destination.pos == 5) {
      score += 10000;
    } else if (destination.inHome) {
      score += 3000 + destination.pos * 100;
    }

    if (piece.pos == -1) {
      score += 1800;
    }

    if (_wouldCapture(
      botId: botId,
      destination: destination,
    )) {
      score += 5000;
    }

    if (!destination.inHome) {
      final botIndex = getPlayerIndex(botId);
      final globalPos = getGlobalPathIndexForIndex(
        botIndex,
        destination.pos,
      );

      if (globalSafePlaces.contains(globalPos)) {
        score += 450;
      }

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
  }) {
    final currentGame = game;
    if (currentGame == null || destination.inHome) return false;

    final botIndex = getPlayerIndex(botId);
    final globalPos = getGlobalPathIndexForIndex(
      botIndex,
      destination.pos,
    );

    if (globalSafePlaces.contains(globalPos)) return false;

    for (final opponentId in currentGame.players) {
      if (opponentId == botId) continue;

      final opponentIndex = getPlayerIndex(opponentId);
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