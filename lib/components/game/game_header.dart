import 'package:flutter/material.dart';

import '../../controllers/ludo_controller.dart';

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
              ? "🎲 Sandbox Mode"
              : "🎲 Ludo Battle",
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        TextButton(
          onPressed: controller.quitToMenu,
          child: const Text(
            "Quit",
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}