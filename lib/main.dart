import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'controllers/ludo_controller.dart';
import 'components/lobby.dart';
import 'components/game_board.dart';
import 'components/game_controls.dart';
import 'components/end_game.dart';
import 'components/cyber_background.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ludo Multiplayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const LudoApp(),
    );
  }
}

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
    var chat = _controller.gameData?['activeChat'];
    if (chat != null && chat['message'] != '' && chat['timestamp'] != lastChatTimestamp) {
      lastChatTimestamp = chat['timestamp'];
      String senderName = _controller.getPlayerDisplayTitle(chat['sender']);

      double screenWidth = MediaQuery.of(context).size.width;

      double horizontalMargin = screenWidth > 500 ? (screenWidth - 500) / 2 : 20.0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "💬 $senderName: ${chat['message']}",
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xff1f2937),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height * 0.75,
              left: horizontalMargin,
              right: horizontalMargin
          ),
          duration: const Duration(milliseconds: 3500),
        ),
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_gameListener);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.gameData?['status'] == 'finished') {
      bool iWon = _controller.user != null ? _controller.gameData!['winnerUid'] == _controller.user!.uid : false;
      String winnerColor = _controller.getPlayerIndex(_controller.gameData!['winnerUid']) == 0 ? "BLUE" : "RED";
      return EndGame(
        iWon: iWon,
        winnerName: _controller.getPlayerDisplayTitle(_controller.gameData!['winnerUid']),
        winnerColor: winnerColor,
        onQuit: _controller.quitToMenu,
      );
    }

    if (_controller.gameData != null) {
      return Scaffold(
        backgroundColor: const Color(0xff111827),
        body: CyberBackground(
          child: SafeArea(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            _controller.gameData?['isTestModeActive'] == true ? "🎲 Sandbox Mode" : "🎲 Ludo Battle",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)
                        ),
                        TextButton(onPressed: _controller.quitToMenu, child: const Text("Quit", style: TextStyle(color: Colors.red))),
                      ],
                    ),

                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withOpacity(0.05))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_controller.getPlayerDisplayTitle(_controller.user?.uid ?? ''), style: TextStyle(color: _controller.myPlayerIndex == 0 ? const Color(0xff42a5f5) : const Color(0xffef5350), fontWeight: FontWeight.bold)),
                          GestureDetector(
                            onTap: () async {
                              if (_controller.gameId.isNotEmpty) {
                                await Clipboard.setData(ClipboardData(text: _controller.gameId));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('📋 Room code successfully copied!'),
                                      duration: Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            },
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "Room Code: ${_controller.gameId}",
                                      style: const TextStyle(fontFamily: 'monospace', color: Colors.white),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text("📋", style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (_controller.gameData?['status'] == 'waiting')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.amber.withOpacity(0.10), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.withOpacity(0.5))),
                        child: const Text("⏳ Waiting for the opponent...", textAlign: TextAlign.center, style: TextStyle(color: Color(0xffffe082), fontWeight: FontWeight.bold)),
                      ),

                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withOpacity(0.04))),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ["Sorry! 🙏", "Ouch! 💥", "Love it! ❤️", "Good luck! 🍀", "😂", "😎", "🔥"].map((msg) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 4.0),
                              child: ActionChip(
                                label: Text(msg),
                                backgroundColor: Colors.white.withOpacity(0.05),
                                onPressed: () => _controller.sendQuickChat(msg),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Expanded(child: Center(child: GameBoard(controller: _controller))),
                    const SizedBox(height: 10),

                    GameControls(
                        controller: _controller,
                        cheatDiceValue: cheatDiceValue,
                        onCheatDiceChanged: (val) => setState(() => cheatDiceValue = val)
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Lobby(
      playerName: playerName,
      onPlayerNameChanged: (val) => playerName = val,
      selectedBoard: selectedBoard,
      onBoardChanged: (val) => setState(() => selectedBoard = val),
      isTestMode: isTestMode,
      onTestModeChanged: (val) => setState(() => isTestMode = val),
      onCreateGame: () => _controller.createGame(playerName, selectedBoard, isTestMode),
      onJoinGame: (code) => _controller.joinGame(playerName, code),
      statusMessage: _controller.statusMessage,
    );
  }
}