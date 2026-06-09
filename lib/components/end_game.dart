import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'cyber_background.dart';

class EndGame extends StatelessWidget {
  final bool iWon;
  final String winnerName;
  final String winnerColor;
  final VoidCallback onQuit;

  const EndGame({
    super.key,
    required this.iWon,
    required this.winnerName,
    required this.winnerColor,
    required this.onQuit
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CyberBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(40.0),
                  decoration: BoxDecoration(
                    color: iWon
                        ? AppColors.successGreen.withOpacity(0.06)
                        : Colors.orange.withOpacity(0.06),
                    border: Border.all(
                        color: iWon
                            ? AppColors.successGreen.withOpacity(0.4)
                            : Colors.orange.withOpacity(0.4),
                        width: 2
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(iWon ? "🏆" : "👑", style: const TextStyle(fontSize: 64, height: 1)),
                      const SizedBox(height: 20),
                      Text(
                        iWon ? "Congratulations, You Won!" : "Game Over!",
                        style: TextStyle(
                            color: iWon ? const Color(0xff81c784) : const Color(0xffffb74d),
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Arial'
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "The match was won by:\n$winnerName ($winnerColor)!",
                        style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.9), height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: onQuit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: iWon ? AppColors.successGreen : const Color(0xffe65100),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 4,
                          shadowColor: (iWon ? AppColors.successGreen : Colors.orange).withOpacity(0.3),
                        ),
                        child: const Text(
                            "Back to Main Menu",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                        ),
                      )
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