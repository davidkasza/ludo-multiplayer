import 'package:flutter/material.dart';

import '../../controllers/ludo_controller.dart';
import '../../theme/app_colors.dart';

class GameHeader extends StatelessWidget {
  final LudoController controller;

  const GameHeader({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            controller.game?.isTestModeActive == true
                ? '🎲 Sandbox Mode'
                : '🎲 Ludo Battle',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.yellowBase.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.yellowBright.withOpacity(0.38)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.monetization_on,
                size: 15,
                color: AppColors.yellowBright,
              ),
              const SizedBox(width: 4),
              Text(
                '${controller.profileCoins}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: () => _showLeaveDialog(context),
          child: const Text('Quit', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  Future<void> _showLeaveDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.panelBackground,
          title: const Text(
            'Leave this match?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Continue later keeps your place. If your turn expires, AI will play for you until you return. Forfeit gives control to AI permanently.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.67),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            if (controller.game?.finishOrder.contains(
                  controller.user?.uid ?? '',
                ) !=
                true)
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await controller.forfeitAndLeave();
                },
                child: const Text(
                  'Forfeit Match',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                controller.leaveTemporarily();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blueBase,
                foregroundColor: Colors.white,
              ),
              child: const Text('Continue Later'),
            ),
          ],
        );
      },
    );
  }
}
