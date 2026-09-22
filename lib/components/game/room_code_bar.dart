import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/ludo_controller.dart';

class RoomCodeBar extends StatelessWidget {
  final LudoController controller;

  const RoomCodeBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final myId = controller.user?.uid ?? '';
    final myStyle = controller.colorStyleForPlayer(myId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.025),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.035)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              controller.getPlayerDisplayTitle(myId),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: myStyle.bright,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Copy room code ${controller.gameId}',
            child: GestureDetector(
              onTap: () async {
                if (controller.gameId.isEmpty) return;

                await Clipboard.setData(ClipboardData(text: controller.gameId));

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('📋 Room code successfully copied!'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.white.withOpacity(0.07)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          controller.gameId,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Colors.white.withOpacity(0.66),
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        Icons.copy_rounded,
                        size: 13,
                        color: Colors.white.withOpacity(0.55),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
