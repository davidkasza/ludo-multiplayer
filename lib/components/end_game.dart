import 'dart:ui';

import 'package:flutter/material.dart';

import '../controllers/ludo_controller.dart';
import '../models/ludo_models.dart';
import '../theme/app_colors.dart';
import 'cyber_background.dart';

class EndGame extends StatelessWidget {
  final LudoController controller;
  final VoidCallback onQuit;

  const EndGame({
    super.key,
    required this.controller,
    required this.onQuit,
  });

  @override
  Widget build(BuildContext context) {
    final game = controller.game;
    if (game == null) return const SizedBox.shrink();

    final ranking = _resolvedRanking(game);
    final myId = controller.user?.uid ?? '';
    final myPlacement = ranking.indexOf(myId) + 1;
    final iWon = myPlacement == 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CyberBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 460),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.045),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: iWon
                            ? AppColors.yellowBright.withOpacity(0.55)
                            : Colors.white.withOpacity(0.10),
                        width: iWon ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.38),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.yellowBright.withOpacity(0.30),
                                AppColors.yellowBase.withOpacity(0.06),
                              ],
                            ),
                            border: Border.all(
                              color: AppColors.yellowBright.withOpacity(0.45),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '🏆',
                            style: TextStyle(fontSize: 46, height: 1),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'MATCH RESULTS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          myPlacement > 0
                              ? iWon
                              ? 'You claimed 1st place!'
                              : 'You finished ${_ordinal(myPlacement)}.'
                              : 'The match has finished.',
                          style: TextStyle(
                            color: iWon
                                ? AppColors.yellowBright
                                : Colors.white.withOpacity(0.62),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _MatchSummary(game: game),
                        const SizedBox(height: 18),
                        for (int index = 0; index < ranking.length; index++) ...[
                          _RankingRow(
                            controller: controller,
                            playerId: ranking[index],
                            placement: index + 1,
                            isMe: ranking[index] == myId,
                          ),
                          if (index != ranking.length - 1)
                            const SizedBox(height: 9),
                        ],
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: onQuit,
                            icon: const Icon(Icons.home_rounded),
                            label: const Text(
                              'Back to Main Menu',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.blueBase,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                              elevation: 4,
                              shadowColor: AppColors.blueBase.withOpacity(0.35),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Player colours are mapped locally on each device. The ranking is tied to player IDs, not colours.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.36),
                            fontSize: 10,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<String> _resolvedRanking(LudoGame game) {
    final ranking = <String>[];

    for (final playerId in game.finishOrder) {
      if (game.players.contains(playerId) && !ranking.contains(playerId)) {
        ranking.add(playerId);
      }
    }

    if (ranking.isEmpty && game.winnerUid.isNotEmpty) {
      ranking.add(game.winnerUid);
    }

    ranking.addAll(
      game.players.where((playerId) => !ranking.contains(playerId)),
    );

    return ranking;
  }

  static String _ordinal(int value) {
    final mod100 = value % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${value}th';

    switch (value % 10) {
      case 1:
        return '${value}st';
      case 2:
        return '${value}nd';
      case 3:
        return '${value}rd';
      default:
        return '${value}th';
    }
  }
}

class _MatchSummary extends StatelessWidget {
  final LudoGame game;

  const _MatchSummary({required this.game});

  @override
  Widget build(BuildContext context) {
    final duration = game.matchDuration;
    const boardName = 'Classic';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryItem(
              icon: Icons.timer_outlined,
              label: 'Match time',
              value: _formatDuration(duration),
            ),
          ),
          Container(
            width: 1,
            height: 34,
            color: Colors.white.withOpacity(0.08),
          ),
          Expanded(
            child: _SummaryItem(
              icon: Icons.grid_view_rounded,
              label: 'Board',
              value: boardName,
            ),
          ),
          Container(
            width: 1,
            height: 34,
            color: Colors.white.withOpacity(0.08),
          ),
          Expanded(
            child: _SummaryItem(
              icon: Icons.groups_rounded,
              label: 'Players',
              value: '${game.players.length}',
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.blueBright, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withOpacity(0.38),
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class _RankingRow extends StatelessWidget {
  final LudoController controller;
  final String playerId;
  final int placement;
  final bool isMe;

  const _RankingRow({
    required this.controller,
    required this.playerId,
    required this.placement,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final colour = controller.colorStyleForPlayer(playerId);
    final isBot = controller.isBotPlayer(playerId);

    return Container(
      constraints: const BoxConstraints(
        minHeight: 66,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isMe
            ? colour.base.withOpacity(0.16)
            : Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? colour.bright.withOpacity(0.65)
              : Colors.white.withOpacity(0.07),
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              _medal(placement),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _placementColour(placement),
                fontSize: placement <= 3 ? 25 : 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 19,
            backgroundColor: colour.base.withOpacity(0.25),
            child: Icon(
              isBot ? Icons.smart_toy : Icons.person,
              color: colour.bright,
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        controller.getPlayerDisplayTitle(playerId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colour.bright.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'YOU',
                          style: TextStyle(
                            color: colour.bright,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colour.bright,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isBot ? 'AI player' : 'Human player',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.42),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            EndGame._ordinal(placement).toUpperCase(),
            style: TextStyle(
              color: _placementColour(placement),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  String _medal(int value) {
    switch (value) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '$value';
    }
  }

  Color _placementColour(int value) {
    switch (value) {
      case 1:
        return AppColors.yellowBright;
      case 2:
        return const Color(0xffcfd8dc);
      case 3:
        return const Color(0xffffab91);
      default:
        return Colors.white54;
    }
  }
}
