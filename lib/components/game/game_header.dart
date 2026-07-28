import 'package:flutter/material.dart';

import '../../controllers/ludo_controller.dart';
import '../../theme/app_colors.dart';

class GameHeader extends StatelessWidget {
  final LudoController controller;

  const GameHeader({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          controller.game?.isTestModeActive == true
              ? '🎲 Sandbox Mode'
              : '🎲 Ludo Battle',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        TextButton(
          onPressed: () => _showLeaveDialog(context),
          child: const Text(
            'Quit',
            style: TextStyle(color: Colors.red),
          ),
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