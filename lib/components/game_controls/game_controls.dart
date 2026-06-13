import 'package:flutter/material.dart';

import '../../controllers/ludo_controller.dart';
import 'sandbox_toolkit.dart';
import 'turn_status_card.dart';

class GameControls extends StatefulWidget {
  final LudoController controller;
  final int cheatDiceValue;
  final ValueChanged<int> onCheatDiceChanged;

  const GameControls({
    super.key,
    required this.controller,
    required this.cheatDiceValue,
    required this.onCheatDiceChanged,
  });

  @override
  State<GameControls> createState() => _GameControlsState();
}

class _GameControlsState extends State<GameControls>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _pulseRunning = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    widget.controller.addListener(_syncPulseAnimation);
    _syncPulseAnimation();
  }

  @override
  void didUpdateWidget(covariant GameControls oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncPulseAnimation);
      widget.controller.addListener(_syncPulseAnimation);
      _syncPulseAnimation();
    }
  }

  void _syncPulseAnimation() {
    final shouldRun = widget.controller.canRoll;

    if (shouldRun && !_pulseRunning) {
      _pulseController.repeat(reverse: true);
      _pulseRunning = true;
    } else if (!shouldRun && _pulseRunning) {
      _pulseController.stop();
      _pulseController.value = 0.0;
      _pulseRunning = false;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncPulseAnimation);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TurnStatusCard(
              controller: c,
              pulseAnimation: _pulseController,
              cheatDiceValue: widget.cheatDiceValue,
            ),
            if (c.game?.isTestModeActive == true) ...[
              const SizedBox(height: 6),
              SandboxToolkit(
                controller: c,
                cheatDiceValue: widget.cheatDiceValue,
                onCheatDiceChanged: widget.onCheatDiceChanged,
              ),
            ],
          ],
        );
      },
    );
  }
}