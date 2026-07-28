import 'package:flutter/material.dart';

import '../components/cyber_background.dart';
import '../components/game/game_header.dart';
import '../components/game/quick_chat_bar.dart';
import '../components/game/room_code_bar.dart';
import '../components/game_board.dart';
import '../components/game_controls.dart';
import '../controllers/ludo_controller.dart';
import '../theme/app_colors.dart';

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
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  GameHeader(controller: controller),
                  if (controller.isMyPlayerAiControlled) ...[
                    _AiControlBanner(controller: controller),
                    const SizedBox(height: 8),
                  ],
                  RoomCodeBar(controller: controller),
                  const SizedBox(height: 10),
                  QuickChatBar(onSendMessage: controller.sendQuickChat),
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

class _AiControlBanner extends StatelessWidget {
  final LudoController controller;

  const _AiControlBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final pending = controller.isMyReconnectPending;
    final myId = controller.user?.uid ?? '';
    final forfeited = controller.game?.forfeitedPlayers.contains(myId) == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.yellowBase.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.yellowBright.withOpacity(0.46)),
      ),
      child: Row(
        children: [
          const Icon(Icons.smart_toy, color: AppColors.yellowBright),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  forfeited
                      ? 'AI is playing this match permanently'
                      : pending
                      ? 'Control will return after this AI action'
                      : 'AI is currently playing for you',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (!forfeited)
                  Text(
                    pending
                        ? 'The current roll or move will finish first.'
                        : 'Take control back whenever no AI action is in progress.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.48),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          if (!forfeited)
            TextButton(
              onPressed: pending ? null : controller.requestTakeBackControl,
              child: Text(pending ? 'WAITING' : 'TAKE BACK'),
            ),
        ],
      ),
    );
  }
}