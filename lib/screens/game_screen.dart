import 'package:flutter/material.dart';

import '../controllers/ludo_controller.dart';
import '../components/cyber_background.dart';
import '../components/game_board.dart';
import '../components/game_controls.dart';
import '../components/game/game_header.dart';
import '../components/game/room_code_bar.dart';
import '../components/game/quick_chat_bar.dart';

class GameScreen extends StatelessWidget {
  final LudoController controller;
  final int cheatDiceValue;
  final ValueChanged<int> onCheatDiceChanged;

  const GameScreen({
    super.key,
    required this.controller,
    required this.cheatDiceValue,
    required this.onCheatDiceChanged,
  });

  @override
  Widget build(BuildContext context) {
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
                  GameHeader(
                    controller: controller,
                  ),

                  RoomCodeBar(
                    controller: controller,
                  ),

                  const SizedBox(height: 10),

                  QuickChatBar(
                    onSendMessage: controller.sendQuickChat,
                  ),

                  const SizedBox(height: 10),

                  Expanded(
                    child: Center(
                      child: GameBoard(controller: controller),
                    ),
                  ),

                  const SizedBox(height: 10),

                  GameControls(
                    controller: controller,
                    cheatDiceValue: cheatDiceValue,
                    onCheatDiceChanged: onCheatDiceChanged,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}