import 'dart:ui';

import 'package:flutter/material.dart';

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
  final String statusMessage;

  const Lobby({
    super.key,
    required this.playerName,
    required this.onPlayerNameChanged,
    required this.onCreateGame,
    required this.onPlayComputer,
    required this.onQuickMatch,
    required this.onJoinGame,
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
                            hintText: 'e.g., David',
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
                              onPressed: widget.onQuickMatch,
                            ),
                            const SizedBox(height: 10),
                            _LobbyButton(
                              label: 'Play vs Computer',
                              icon: Icons.smart_toy,
                              color: AppColors.yellowDark,
                              onPressed: widget.onPlayComputer,
                            ),
                            const SizedBox(height: 10),
                            _LobbyButton(
                              label: 'Create Custom Room',
                              icon: Icons.add_circle_outline,
                              color: AppColors.blueBase,
                              onPressed: widget.onCreateGame,
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
                              onPressed: () => widget.onJoinGame(
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

class _LobbyButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

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