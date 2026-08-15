import 'package:flutter/material.dart';

import '../../controllers/ludo_controller.dart';
import '../../game/dice_skin.dart';
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
    final currentTurnId = c.visualTurnPlayerId;
    final currentStyle = c.colorStyleForPlayer(currentTurnId);
    final myStyle = c.colorStyleForPlayer(c.user?.uid ?? '');
    final currentIsAutomated = c.isPlayerAiControlled(currentTurnId);
    final myId = c.user?.uid ?? '';
    final myPlacement = game?.placementFor(myId) ?? 0;
    final iAmFinished = c.isPlayerVisuallyFinished(myId);
    final rollingPlayerId = c.diceRollingPlayerId ?? currentTurnId;
    final diceSkin = DiceSkinResolver.forPlayer(
      game?.playerDiceSkins,
      rollingPlayerId,
    );

    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.isVisualMyTurn
                ? myStyle.base.withOpacity(0.08)
                : Colors.white.withOpacity(0.03),
            border: Border.all(
              color: c.isVisualMyTurn
                  ? myStyle.bright.withOpacity(0.5)
                  : Colors.white.withOpacity(0.1),
              width: c.isVisualMyTurn ? 2 : 1,
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
                  child: ValueListenableBuilder<int>(
                    valueListenable: c.turnSecondsNotifier,
                    builder: (context, seconds, child) => Row(
                      children: [
                        Flexible(
                          child: Text(
                            game?.status == 'waiting'
                                ? 'Waiting...'
                                : iAmFinished
                                ? 'YOU FINISHED #$myPlacement'
                                : c.isVisualMyTurn
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
                        if (game?.status == 'playing' &&
                            !iAmFinished &&
                            !c.isDicePresentationActive &&
                            c.visualActiveMove == null) ...[
                          const SizedBox(width: 7),
                          _CountdownBadge(
                            seconds: seconds,
                            automated: currentIsAutomated,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: c.canRoll ? () => c.rollDice(cheatDiceValue) : null,
            child: RollingDiceUI(
              value: c.visualDiceValue ?? game?.diceValue ?? 0,
              isRolling: c.isDiceRolling,
              animationKey: c.diceAnimationKey,
              initialProgress: c.diceRollInitialProgress,
              rollDuration: Duration(milliseconds: c.diceRollDurationMs),
              size: 42,
              skin: diceSkin,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  final int seconds;
  final bool automated;

  const _CountdownBadge({required this.seconds, required this.automated});

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
