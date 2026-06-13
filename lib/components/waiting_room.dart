import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/ludo_controller.dart';
import '../theme/app_colors.dart';
import 'cyber_background.dart';
import 'glass_panel.dart';

class WaitingRoom extends StatelessWidget {
  final LudoController controller;
  final String selectedBoard;
  final ValueChanged<String> onBoardChanged;
  final bool isTestMode;
  final ValueChanged<bool> onTestModeChanged;
  final VoidCallback onQuit;
  final VoidCallback onStartGame;

  const WaitingRoom({
    super.key,
    required this.controller,
    required this.selectedBoard,
    required this.onBoardChanged,
    required this.isTestMode,
    required this.onTestModeChanged,
    required this.onQuit,
    required this.onStartGame,
  });

  @override
  Widget build(BuildContext context) {
    final game = controller.game;
    final isHost = controller.isHost;
    final players = game?.players ?? [];
    final canStart = isHost && players.length >= 2;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CyberBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 28,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 460),
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
                          "🎲",
                          style: TextStyle(fontSize: 52, height: 1),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Waiting Room",
                          style: TextStyle(
                            fontSize: 28,
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isHost
                              ? "Invite your opponent and start the match."
                              : "Waiting for the host to start the match.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),

                        const SizedBox(height: 24),

                        _RoomCodeCard(controller: controller),

                        const SizedBox(height: 20),

                        GlassPanel(
                          title: "Players",
                          child: Column(
                            children: [
                              if (players.isEmpty)
                                Text(
                                  "No players yet.",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                              ...players.map((uid) {
                                final isPlayerHost = players.isNotEmpty &&
                                    uid == players.first;

                                final playerIndex = controller.getPlayerIndex(uid);

                                final color = playerIndex == 0
                                    ? AppColors.blueBright
                                    : AppColors.redBright;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.06),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: color.withOpacity(0.18),
                                        child: Icon(
                                          Icons.person,
                                          color: color,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          controller.getPlayerDisplayTitle(uid),
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (isPlayerHost)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withOpacity(0.12),
                                            borderRadius:
                                            BorderRadius.circular(999),
                                            border: Border.all(
                                              color:
                                              Colors.amber.withOpacity(0.4),
                                            ),
                                          ),
                                          child: const Text(
                                            "Host",
                                            style: TextStyle(
                                              color: Color(0xffffe082),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        GlassPanel(
                          title: "Game settings",
                          child: Column(
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.panelBackground,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                  ),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedBoard,
                                    dropdownColor: AppColors.panelBackground,
                                    icon: const Icon(
                                      Icons.arrow_drop_down,
                                      color: Colors.white,
                                    ),
                                    isExpanded: true,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: "classic",
                                        child: Text("Classic Map"),
                                      ),
                                      DropdownMenuItem(
                                        value: "test",
                                        child: Text("Circular Loop"),
                                      ),
                                    ],
                                    onChanged: isHost
                                        ? (val) {
                                      if (val != null) {
                                        onBoardChanged(val);
                                      }
                                    }
                                        : null,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 12),

                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.yellowSafeBorder
                                      .withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.yellowSafeBorder
                                        .withOpacity(0.35),
                                  ),
                                ),
                                child: CheckboxListTile(
                                  title: const Text(
                                    "🛠️ Sandbox Mode",
                                    style: TextStyle(
                                      color: Color(0xffffe082),
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    isHost
                                        ? "Useful for testing. Pieces start near the end."
                                        : "Only the host can change this.",
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.45),
                                      fontSize: 11,
                                    ),
                                  ),
                                  value: isTestMode,
                                  activeColor: AppColors.blueBase,
                                  onChanged: isHost
                                      ? (val) =>
                                      onTestModeChanged(val ?? false)
                                      : null,
                                  controlAffinity:
                                  ListTileControlAffinity.leading,
                                  checkboxShape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        if (controller.statusMessage.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.amber.withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              controller.statusMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xffffe082),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                        ElevatedButton(
                          onPressed: canStart ? onStartGame : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.successGreen,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                          child: Text(
                            isHost
                                ? canStart
                                ? "Start Game"
                                : "Waiting for opponent..."
                                : "Waiting for host...",
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        TextButton(
                          onPressed: onQuit,
                          child: const Text(
                            "Back to Main Menu",
                            style: TextStyle(color: Colors.redAccent),
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
}

class _RoomCodeCard extends StatelessWidget {
  final LudoController controller;

  const _RoomCodeCard({
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.blueBright.withOpacity(0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.blueBase.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            "Room Code",
            style: TextStyle(
              color: Colors.white.withOpacity(0.62),
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          SelectableText(
            controller.gameId,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),

          const SizedBox(height: 12),

          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: controller.gameId),
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("📋 Room code copied!"),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text("Copy Code"),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blueBase,
              foregroundColor: Colors.white,
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