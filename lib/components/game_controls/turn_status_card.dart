import 'package:flutter/material.dart';

import '../../controllers/ludo_controller.dart';
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

    final currentTurnUid = c.game?.currentTurn ?? "";
    final currentTurnIndex = c.getPlayerIndex(currentTurnUid);

    final avatarBgColor =
    currentTurnIndex == 0 ? AppColors.blueBase : AppColors.redBase;

    final avatarIconColor =
    currentTurnIndex == 0 ? AppColors.blueDark : AppColors.redDark;

    final myBaseColor =
    c.myPlayerIndex == 0 ? AppColors.blueBase : AppColors.redBase;

    final myBrightColor =
    c.myPlayerIndex == 0 ? AppColors.blueBright : AppColors.redBright;

    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: c.isMyTurn
                ? myBaseColor.withOpacity(0.08)
                : Colors.white.withOpacity(0.03),
            border: Border.all(
              color: c.isMyTurn
                  ? myBrightColor.withOpacity(0.5)
                  : Colors.white.withOpacity(0.1),
              width: c.isMyTurn ? 2.0 : 1.0,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: c.canRoll
                ? [
              BoxShadow(
                color: myBaseColor.withOpacity(
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
                  backgroundColor: avatarBgColor,
                  child: Icon(
                    Icons.person,
                    color: avatarIconColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.game?.status == 'waiting'
                            ? "Waiting..."
                            : c.isMyTurn
                            ? "YOUR TURN!"
                            : c.getPlayerDisplayTitle(
                          c.game?.currentTurn ?? "",
                        ),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        c.isMyTurn
                            ? c.game?.hasRolled == true
                            ? "Select a piece to move!"
                            : "Tap to roll!"
                            : "Waiting for opponent...",
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
              value: c.game?.diceValue ?? 0,
              isRolling: c.isDiceRolling,
              size: 42.0,
            ),
          ),
        ],
      ),
    );
  }
}