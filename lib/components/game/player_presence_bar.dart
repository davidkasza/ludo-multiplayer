import 'package:flutter/material.dart';

import '../../controllers/ludo_controller.dart';
import '../../models/ludo_models.dart';
import '../../theme/app_colors.dart';

class PlayerPresenceBar extends StatelessWidget {
  final LudoController controller;

  const PlayerPresenceBar({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final game = controller.game;
    if (game == null || game.players.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (int index = 0; index < game.players.length; index++) ...[
              _PresenceChip(
                controller: controller,
                playerId: game.players[index],
              ),
              if (index != game.players.length - 1)
                const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _PresenceChip extends StatelessWidget {
  final LudoController controller;
  final String playerId;

  const _PresenceChip({
    required this.controller,
    required this.playerId,
  });

  @override
  Widget build(BuildContext context) {
    final state = controller.resolvedPresenceState(playerId);
    final colour = _stateColour(state);
    final icon = _stateIcon(state);
    final isMe = playerId == controller.user?.uid;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: colour.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colour.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: colour,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colour.withOpacity(0.35),
                  blurRadius: 5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(icon, size: 13, color: colour),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Text(
              '${controller.getPlayerDisplayTitle(playerId)}${isMe ? ' (You)' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            controller.presenceLabelForPlayer(playerId),
            style: TextStyle(
              color: colour,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Color _stateColour(String state) {
    switch (state) {
      case PlayerPresence.online:
        return AppColors.successGreen;
      case PlayerPresence.reconnecting:
        return Colors.orangeAccent;
      case PlayerPresence.ai:
        return AppColors.yellowBright;
      case PlayerPresence.forfeited:
        return Colors.redAccent;
      default:
        return Colors.white38;
    }
  }

  IconData _stateIcon(String state) {
    switch (state) {
      case PlayerPresence.online:
        return Icons.wifi_rounded;
      case PlayerPresence.reconnecting:
        return Icons.sync_rounded;
      case PlayerPresence.ai:
        return Icons.smart_toy_outlined;
      case PlayerPresence.forfeited:
        return Icons.flag_outlined;
      default:
        return Icons.wifi_off_rounded;
    }
  }
}