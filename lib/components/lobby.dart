import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/ludo_models.dart';
import '../theme/app_colors.dart';
import 'cyber_background.dart';
import 'glass_panel.dart';

class Lobby extends StatefulWidget {
  final String playerName;
  final ValueChanged<String> onPlayerNameChanged;
  final VoidCallback onCreateGame;
  final VoidCallback onPlayComputer;
  final VoidCallback onQuickMatch;
  final ValueChanged<String> onJoinGame;
  final VoidCallback onOpenProfile;
  final LudoGame? resumableGame;
  final String resumableGameId;
  final bool resumableGameAiControlled;
  final VoidCallback onContinueGame;
  final String statusMessage;

  const Lobby({
    super.key,
    required this.playerName,
    required this.onPlayerNameChanged,
    required this.onCreateGame,
    required this.onPlayComputer,
    required this.onQuickMatch,
    required this.onJoinGame,
    required this.onOpenProfile,
    required this.resumableGame,
    required this.resumableGameId,
    required this.resumableGameAiControlled,
    required this.onContinueGame,
    required this.statusMessage,
  });

  @override
  State<Lobby> createState() => _LobbyState();
}

class _LobbyState extends State<Lobby> {
  final TextEditingController _roomController = TextEditingController();
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.playerName);
  }

  @override
  void didUpdateWidget(covariant Lobby oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.playerName != _nameController.text) {
      final previousSelection = _nameController.selection;
      _nameController.text = widget.playerName;
      _nameController.selection = previousSelection;
    }
  }

  @override
  void dispose() {
    _roomController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasResumableMatch = widget.resumableGame != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CyberBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 40,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 430),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: 'Player profile',
                          onPressed: widget.onOpenProfile,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.06),
                            foregroundColor: AppColors.blueBright,
                          ),
                          icon: const Icon(Icons.account_circle_outlined),
                        ),
                      ),
                      if (widget.resumableGame != null) ...[
                        _ResumeMatchCard(
                          game: widget.resumableGame!,
                          roomId: widget.resumableGameId,
                          aiControlled: widget.resumableGameAiControlled,
                          onContinue: widget.onContinueGame,
                        ),
                        const SizedBox(height: 18),
                      ],
                      const Text(
                        '🎲',
                        style: TextStyle(fontSize: 56, height: 1),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Ludora: Match & Play',
                        style: TextStyle(
                          fontSize: 28,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Arial',
                        ),
                      ),
                      const Text(
                        'Play online, with friends, or against the computer',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xff9ca3af),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 25),
                      if (widget.statusMessage.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 15),
                          decoration: BoxDecoration(
                            color: AppColors.redBase.withOpacity(0.16),
                            border: Border.all(
                              color: AppColors.redBase.withOpacity(0.35),
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.statusMessage,
                            style: const TextStyle(
                              color: Color(0xfffca5a5),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      GlassPanel(
                        title: '1. Enter your nickname:',
                        child: TextField(
                          controller: _nameController,
                          onChanged: widget.onPlayerNameChanged,
                          maxLength: 15,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter your nickname',
                            hintStyle: const TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.normal,
                            ),
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.2),
                            counterText: '',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: AppColors.blueBase,
                                width: 2,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: AppColors.blueBright,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      GlassPanel(
                        title: '2. Choose how to play:',
                        child: Column(
                          children: [
                            _LobbyButton(
                              label: 'Quick Match',
                              icon: Icons.bolt,
                              color: AppColors.successGreen,
                              onPressed: hasResumableMatch ? null : widget.onQuickMatch,
                            ),
                            const SizedBox(height: 10),
                            _LobbyButton(
                              label: 'Play vs Computer',
                              icon: Icons.smart_toy,
                              color: AppColors.yellowDark,
                              onPressed: hasResumableMatch ? null : widget.onPlayComputer,
                            ),
                            const SizedBox(height: 10),
                            _LobbyButton(
                              label: 'Create Custom Room',
                              icon: Icons.add_circle_outline,
                              color: AppColors.blueBase,
                              onPressed: hasResumableMatch ? null : widget.onCreateGame,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'OR',
                              style: TextStyle(
                                color: Color(0xff6b7280),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      GlassPanel(
                        title: '3. Join with a room code:',
                        child: Column(
                          children: [
                            TextField(
                              controller: _roomController,
                              enabled: !hasResumableMatch,
                              textAlign: TextAlign.center,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(
                                color: Colors.white,
                                letterSpacing: 1,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Enter Room Code',
                                hintStyle: const TextStyle(
                                  color: Colors.grey,
                                  letterSpacing: 0,
                                  fontWeight: FontWeight.normal,
                                ),
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.2),
                                contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.2),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: AppColors.blueBase,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _LobbyButton(
                              label: 'Join Battle',
                              icon: Icons.login,
                              color: AppColors.blueBase,
                              onPressed: hasResumableMatch
                                  ? null
                                  : () => widget.onJoinGame(
                                _roomController.text,
                              ),
                            ),
                          ],
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
    );
  }
}

class _ResumeMatchCard extends StatelessWidget {
  final LudoGame game;
  final String roomId;
  final bool aiControlled;
  final VoidCallback onContinue;

  const _ResumeMatchCard({
    required this.game,
    required this.roomId,
    required this.aiControlled,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final boardLabel = game.boardId == 'classic' ? 'Classic board' : 'Circular board';
    final stateLabel = game.status == 'waiting' ? 'Waiting room' : 'Match in progress';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.blueBase.withOpacity(0.11),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.blueBright.withOpacity(0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.play_circle_outline, color: AppColors.blueBright),
              SizedBox(width: 8),
              Text(
                'MATCH IN PROGRESS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$stateLabel • Room $roomId',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${game.players.length} players • $boardLabel${aiControlled ? ' • AI is playing for you' : ''}',
            style: TextStyle(
              color: aiControlled
                  ? AppColors.yellowBright
                  : Colors.white.withOpacity(0.48),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Continue or forfeit this match before starting another one.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.38),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onContinue,
            icon: const Icon(Icons.login_rounded, size: 19),
            label: const Text(
              'Continue Match',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blueBase,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LobbyButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _LobbyButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 4,
        shadowColor: color.withOpacity(0.35),
      ),
    );
  }
}