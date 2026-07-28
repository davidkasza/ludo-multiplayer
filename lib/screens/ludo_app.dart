import 'dart:async';

import 'package:flutter/material.dart';

import '../components/end_game.dart';
import '../components/lobby.dart';
import '../components/waiting_room.dart';
import '../controllers/ludo_controller.dart';
import '../models/ludo_models.dart';
import 'game_screen.dart';
import 'profile_screen.dart';

class LudoApp extends StatefulWidget {
  const LudoApp({super.key});

  @override
  State<LudoApp> createState() => _LudoAppState();
}

class _LudoAppState extends State<LudoApp> with WidgetsBindingObserver {
  final LudoController _controller = LudoController();

  String playerName = '';
  String selectedBoard = 'classic';
  bool isTestMode = false;
  int cheatDiceValue = 0;
  int lastChatTimestamp = 0;
  String lastSystemEventId = '';
  bool showProfile = false;
  bool _profileNameApplied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_gameListener);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.reconnectCurrentGame());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_controller.markPresenceOffline());
    }
  }

  void _gameListener() {
    if (!_profileNameApplied && _controller.profileLoaded) {
      _profileNameApplied = true;

      if (playerName.isEmpty && _controller.profileName.isNotEmpty && mounted) {
        setState(() => playerName = _controller.profileName);
      }
    }

    if (!mounted) return;

    _showSystemEventIfNeeded();
    _showChatIfNeeded();
  }

  void _showSystemEventIfNeeded() {
    final event = _controller.game?.systemEvent;
    if (event == null || event.id.isEmpty || event.id == lastSystemEventId) {
      return;
    }

    lastSystemEventId = event.id;
    final myId = _controller.user?.uid ?? '';
    final isRecent = DateTime.now().millisecondsSinceEpoch - event.createdAtMs <
        const Duration(seconds: 12).inMilliseconds;

    if (!isRecent || event.playerId == myId) return;

    final playerName = _controller.getPlayerDisplayTitle(event.playerId);
    final String message;
    final IconData icon;

    switch (event.type) {
      case GameSystemEvent.aiTakeover:
        message = '$playerName did not respond. AI has taken over.';
        icon = Icons.smart_toy;
        break;
      case GameSystemEvent.playerReconnected:
        message = '$playerName has reconnected and taken back control.';
        icon = Icons.wifi_rounded;
        break;
      case GameSystemEvent.playerForfeited:
        message = '$playerName forfeited. AI will finish the match.';
        icon = Icons.flag_rounded;
        break;
      default:
        return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showChatIfNeeded() {
    final chat = _controller.game?.activeChat;
    if (chat == null ||
        chat.message.isEmpty ||
        chat.timestamp == lastChatTimestamp) {
      return;
    }

    lastChatTimestamp = chat.timestamp;
    final senderName = _controller.getPlayerDisplayTitle(chat.sender);
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalMargin =
    screenWidth > 500 ? (screenWidth - 500) / 2 : 20.0;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'ðŸ’¬ $senderName: ${chat.message}',
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

  Future<void> _persistPlayerName() async {
    final normalized = playerName.trim();
    if (normalized.isEmpty) return;
    await _controller.updateProfileName(normalized);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
          return EndGame(
            controller: _controller,
            onQuit: () {
              showProfile = false;
              _controller.quitToMenu();
            },
          );
        }

        if (game != null && game.status == 'waiting') {
          return WaitingRoom(
            controller: _controller,
            onQuit: _controller.leaveGame,
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

        if (showProfile) {
          return ProfileScreen(
            controller: _controller,
            initialPlayerName: playerName,
            onNameChanged: (value) {
              setState(() => playerName = value);
            },
            onBack: () {
              setState(() => showProfile = false);
            },
          );
        }

        final resumableGame = _controller.resumableGame;
        final currentUserId = _controller.user?.uid ?? '';

        return Lobby(
          playerName: playerName,
          onPlayerNameChanged: (value) {
            setState(() => playerName = value);
          },
          onOpenProfile: () {
            setState(() => showProfile = true);
          },
          resumableGame: resumableGame,
          resumableGameId: _controller.activeGameId,
          resumableGameAiControlled: resumableGame != null &&
              resumableGame.aiControlledPlayers.contains(currentUserId),
          onContinueGame: () {
            unawaited(_controller.continueActiveGame());
          },
          onCreateGame: () async {
            await _persistPlayerName();
            await _controller.createGame(
              playerName,
              selectedBoard,
              isTestMode,
            );
          },
          onPlayComputer: () async {
            await _persistPlayerName();
            await _controller.createSoloGame(
              playerName,
              selectedBoard,
              isTestMode,
            );
          },
          onQuickMatch: () async {
            await _persistPlayerName();
            await _controller.randomJoinGame(
              playerName,
              selectedBoard,
              isTestMode,
            );
          },
          onJoinGame: (code) async {
            await _persistPlayerName();
            await _controller.joinGame(playerName, code);
          },
          statusMessage: _controller.statusMessage,
        );
      },
    );
  }
}