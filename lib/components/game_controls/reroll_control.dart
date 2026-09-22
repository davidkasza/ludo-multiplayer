import 'package:flutter/material.dart';

import '../../controllers/ludo_controller.dart';
import '../../controllers/mixins/ludo_dice_mixin.dart';
import '../../models/ludo_models.dart';
import '../../theme/app_colors.dart';

class RerollControl extends StatelessWidget {
  final LudoController controller;

  const RerollControl({super.key, required this.controller});

  Future<void> _run(
    BuildContext context,
    Future<PowerUpActionFeedback> action,
  ) async {
    final feedback = await action;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(feedback.message),
          backgroundColor: feedback.succeeded
              ? const Color(0xff166534)
              : const Color(0xff991b1b),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.shouldShowRerollControl) return const SizedBox.shrink();

    final cost = controller.currentRerollCost;
    final waitingForDecision =
        controller.game?.turnPhase == LudoGame.waitingForRerollDecision;
    final unavailableLabel = controller.rerollUnavailableLabel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.blueBase.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.blueBright.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          if (waitingForDecision) ...[
            const Expanded(
              child: Text(
                'No legal move',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ] else
            const Spacer(),
          OutlinedButton.icon(
            onPressed: controller.canUseReroll
                ? () => _run(context, controller.useReroll())
                : null,
            icon: const Icon(Icons.refresh, size: 17),
            label: Text(
              controller.rerollActionPending
                  ? 'Processing...'
                  : unavailableLabel ?? 'Reroll — ${cost ?? 0} coins',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.yellowBright,
              side: BorderSide(color: AppColors.yellowBright.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (waitingForDecision) ...[
            const SizedBox(width: 6),
            TextButton(
              onPressed: controller.canPassNoValidMove
                  ? () => _run(context, controller.passNoValidMove())
                  : null,
              child: const Text('Continue'),
            ),
          ],
        ],
      ),
    );
  }
}
