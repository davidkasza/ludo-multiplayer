import 'package:flutter/material.dart';

import '../controllers/ludo_controller.dart';
import '../components/lobby.dart';
import '../components/waiting_room.dart';
import '../components/end_game.dart';
import 'game_screen.dart';

class LudoApp extends StatefulWidget {
  const LudoApp({super.key});

  @override
  State<LudoApp> createState() => _LudoAppState();
}

class _LudoAppState extends State<LudoApp> {
  final LudoController _controller = LudoController();

  String playerName = "David";
  String selectedBoard = "classic";
  bool isTestMode = false;
  int cheatDiceValue = 0;
  int lastChatTimestamp = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_gameListener);
  }

  void _gameListener() {
    final chat = _controller.game?.activeChat;

    if (chat != null &&
        chat.message.isNotEmpty &&
        chat.timestamp != lastChatTimestamp) {
      lastChatTimestamp = chat.timestamp;

      final senderName = _controller.getPlayerDisplayTitle(chat.sender);
      final screenWidth = MediaQuery.of(context).size.width;
      final horizontalMargin = screenWidth > 500 ? (screenWidth - 500) / 2 : 20.0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "💬 $senderName: ${chat.message}",
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 14,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xff1f2937),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height * 0.75,
            left: horizontalMargin,
            right: horizontalMargin,
          ),
          duration: const Duration(milliseconds: 3500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_gameListener);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final game = _controller.game;

        if (game?.status == 'finished') {
          final iWon = _controller.user != null &&
              game!.winnerUid == _controller.user!.uid;

          final winnerColor =
          _controller.getPlayerIndex(game!.winnerUid) == 0 ? "BLUE" : "RED";

          return EndGame(
            iWon: iWon,
            winnerName: _controller.getPlayerDisplayTitle(game.winnerUid),
            winnerColor: winnerColor,
            onQuit: _controller.quitToMenu,
          );
        }

        if (game != null && game.status == 'waiting') {
          return WaitingRoom(
            controller: _controller,
            selectedBoard: game.boardId,
            onBoardChanged: (val) {
              setState(() => selectedBoard = val);
              _controller.updateWaitingRoomSettings(
                selectedBoard: val,
                isTestMode: game.isTestModeActive,
              );
            },
            isTestMode: game.isTestModeActive,
            onTestModeChanged: (val) {
              setState(() => isTestMode = val);
              _controller.updateWaitingRoomSettings(
                selectedBoard: game.boardId,
                isTestMode: val,
              );
            },
            onQuit: _controller.quitToMenu,
            onStartGame: _controller.startGame,
          );
        }

        if (game != null && game.status == 'playing') {
          return GameScreen(
            controller: _controller,
            cheatDiceValue: cheatDiceValue,
            onCheatDiceChanged: (val) {
              setState(() => cheatDiceValue = val);
            },
          );
        }

        return Lobby(
          playerName: playerName,
          onPlayerNameChanged: (val) => setState(() => playerName = val),
          selectedBoard: selectedBoard,
          onBoardChanged: (val) => setState(() => selectedBoard = val),
          isTestMode: isTestMode,
          onTestModeChanged: (val) => setState(() => isTestMode = val),
          onCreateGame: () =>
              _controller.createGame(playerName, selectedBoard, isTestMode),
          onJoinGame: (code) => _controller.joinGame(playerName, code),
          statusMessage: _controller.statusMessage,
        );
      },
    );
  }
}