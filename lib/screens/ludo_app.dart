import 'package:flutter/material.dart';

import '../components/end_game.dart';
import '../components/lobby.dart';
import '../components/waiting_room.dart';
import '../controllers/ludo_controller.dart';
import 'game_screen.dart';

class LudoApp extends StatefulWidget {
  const LudoApp({super.key});

  @override
  State<LudoApp> createState() => _LudoAppState();
}

class _LudoAppState extends State<LudoApp> {
  final LudoController _controller = LudoController();

  String playerName = '';
  String selectedBoard = 'classic';
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
      final horizontalMargin =
      screenWidth > 500 ? (screenWidth - 500) / 2 : 20.0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '💬 $senderName: ${chat.message}',
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
          final winnerId = game!.winnerUid;
          final iWon = _controller.user != null &&
              winnerId == _controller.user!.uid;

          return EndGame(
            iWon: iWon,
            winnerName: _controller.getPlayerDisplayTitle(winnerId),
            onQuit: _controller.quitToMenu,
          );
        }

        if (game != null && game.status == 'waiting') {
          return WaitingRoom(
            controller: _controller,
            onQuit: () {
              _controller.leaveGame();
            },
            onStartGame: _controller.startGame,
          );
        }

        if (game != null && game.status == 'playing') {
          return GameScreen(
            controller: _controller,
            cheatDiceValue: cheatDiceValue,
            onCheatDiceChanged: (value) {
              setState(() => cheatDiceValue = value);
            },
          );
        }

        return Lobby(
          playerName: playerName,
          onPlayerNameChanged: (value) {
            setState(() => playerName = value);
          },
          onCreateGame: () {
            _controller.createGame(
              playerName,
              selectedBoard,
              isTestMode,
            );
          },
          onPlayComputer: () {
            _controller.createSoloGame(
              playerName,
              selectedBoard,
              isTestMode,
            );
          },
          onQuickMatch: () {
            _controller.randomJoinGame(
              playerName,
              selectedBoard,
              isTestMode,
            );
          },
          onJoinGame: (code) {
            _controller.joinGame(playerName, code);
          },
          statusMessage: _controller.statusMessage,
        );
      },
    );
  }
}