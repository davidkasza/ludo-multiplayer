import 'package:flutter/material.dart';

import '../../controllers/ludo_controller.dart';
import '../../models/ludo_models.dart';
import '../../theme/app_colors.dart';
import 'rolling_dice_ui.dart';

class TurnStatusCard extends StatelessWidget {
  final LudoController controller;
  final Animation<double> pulseAnimation;
  final int cheatDiceValue;

  const TurnStatusCard({
    super.key,
    required this.controller,
    required this.pulseAnimation,
    required this.cheatDiceValue,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final game = c.game;
    final currentTurnId = game?.currentTurn ?? '';
    final currentStyle = c.colorStyleForPlayer(currentTurnId);
    final myStyle = c.colorStyleForPlayer(c.user?.uid ?? '');
    final currentIsAutomated = c.isPlayerAiControlled(currentTurnId);
    final myId = c.user?.uid ?? '';
    final myPlacement = game?.placementFor(myId) ?? 0;
    final iAmFinished = myPlacement > 0;
    final rollingPlayerId = c.diceRollingPlayerId ?? currentTurnId;
    final rollingPlayerName = c.getPlayerDisplayTitle(rollingPlayerId);

    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.isMyTurn
                ? myStyle.base.withOpacity(0.08)
                : Colors.white.withOpacity(0.03),
            border: Border.all(
              color: c.isMyTurn
                  ? myStyle.bright.withOpacity(0.5)
                  : Colors.white.withOpacity(0.1),
              width: c.isMyTurn ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: c.canRoll
                ? [
              BoxShadow(
                color: myStyle.base.withOpacity(
                  pulseAnimation.value * 0.3,
                ),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ]
                : null,
          ),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: currentStyle.base,
                  child: Icon(
                    currentIsAutomated ? Icons.smart_toy : Icons.person,
                    color: currentStyle.dark,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              game?.status == 'waiting'
                                  ? 'Waiting...'
                                  : iAmFinished
                                  ? 'YOU FINISHED #$myPlacement'
                                  : c.isMyTurn
                                  ? 'YOUR TURN!'
                                  : c.getPlayerDisplayTitle(currentTurnId),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (game?.status == 'playing' && !iAmFinished) ...[
                            const SizedBox(width: 7),
                            _CountdownBadge(
                              seconds: c.turnSecondsRemaining,
                              automated: currentIsAutomated,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(
                          controller: c,
                          game: game,
                          iAmFinished: iAmFinished,
                          currentIsAutomated: currentIsAutomated,
                          rollingPlayerName: rollingPlayerName,
                        ),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.5),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: c.canRoll ? () => c.rollDice(cheatDiceValue) : null,
            child: RollingDiceUI(
              value: game?.diceValue ?? 0,
              isRolling: c.isDiceRolling,
              size: 42,
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle({
    required LudoController controller,
    required LudoGame? game,
    required bool iAmFinished,
    required bool currentIsAutomated,
    required String rollingPlayerName,
  }) {
    if (controller.isDiceRolling) {
      return controller.isMyTurn
          ? 'Rolling the dice...'
          : '$rollingPlayerName is rolling...';
    }
    if (iAmFinished) return 'Waiting for the remaining players...';
    if (currentIsAutomated) {
      return 'AI is playing for ${controller.getPlayerDisplayTitle(game?.currentTurn ?? '')}';
    }
    if (controller.isMyTurn) {
      return game?.turnPhase == LudoGame.waitingForMove
          ? 'Select a piece within ${controller.turnSecondsRemaining}s'
          : 'Roll within ${controller.turnSecondsRemaining}s';
    }
    if (game?.turnPhase == LudoGame.waitingForMove) {
      return 'Waiting for a piece selection...';
    }
    return 'Waiting for the other player to roll...';
  }
}

class _CountdownBadge extends StatelessWidget {
  final int seconds;
  final bool automated;

  const _CountdownBadge({
    required this.seconds,
    required this.automated,
  });

  @override
  Widget build(BuildContext context) {
    final colour = automated
        ? AppColors.yellowBright
        : seconds <= 3
        ? Colors.redAccent
        : seconds <= 5
        ? Colors.orangeAccent
        : AppColors.blueBright;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colour.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colour.withOpacity(0.45)),
      ),
      child: Text(
        automated ? 'AI' : '${seconds}s',
        style: TextStyle(
          color: colour,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}