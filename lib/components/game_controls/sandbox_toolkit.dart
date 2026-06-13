import 'package:flutter/material.dart';

import '../../controllers/ludo_controller.dart';
import '../../theme/app_colors.dart';

class SandboxToolkit extends StatefulWidget {
  final LudoController controller;
  final int cheatDiceValue;
  final ValueChanged<int> onCheatDiceChanged;

  const SandboxToolkit({
    super.key,
    required this.controller,
    required this.cheatDiceValue,
    required this.onCheatDiceChanged,
  });

  @override
  State<SandboxToolkit> createState() => _SandboxToolkitState();
}

class _SandboxToolkitState extends State<SandboxToolkit> {
  bool showCheatPanel = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final myPieces = c.getMyPieces();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xfff57f17).withOpacity(0.04),
        border: Border.all(
          color: AppColors.yellowSafeBorder.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text(
              showCheatPanel
                  ? "▲ Close Sandbox Toolkit"
                  : "▼ Open Sandbox Toolkit",
              style: const TextStyle(
                color: Color(0xffffe082),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            onTap: () {
              setState(() {
                showCheatPanel = !showCheatPanel;
              });
            },
          ),
          if (showCheatPanel)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(
                  left: 10,
                  right: 10,
                  bottom: 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.isMyTurn && c.game?.hasRolled == false)
                      _CheatDiceDropdown(
                        cheatDiceValue: widget.cheatDiceValue,
                        onCheatDiceChanged: widget.onCheatDiceChanged,
                      ),
                    const SizedBox(height: 8),
                    if (myPieces.isNotEmpty)
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        childAspectRatio: 2.8,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        physics: const NeverScrollableScrollPhysics(),
                        children: myPieces.map((p) {
                          final currentVal = p.pos == -1
                              ? "-1"
                              : p.inHome
                              ? "H${p.pos}"
                              : "${p.pos}";

                          return _PieceTeleportDropdown(
                            pieceId: p.id,
                            currentValue: currentVal,
                            onChanged: (val) {
                              c.teleportPiece(
                                p.id,
                                val ?? "-1",
                              );
                            },
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CheatDiceDropdown extends StatelessWidget {
  final int cheatDiceValue;
  final ValueChanged<int> onCheatDiceChanged;

  const _CheatDiceDropdown({
    required this.cheatDiceValue,
    required this.onCheatDiceChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "🔮 Next roll:",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xffffe082),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.panelBackground,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: cheatDiceValue,
              dropdownColor: AppColors.panelBackground,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              items: [
                const DropdownMenuItem(
                  value: 0,
                  child: Text("Random"),
                ),
                ...List.generate(
                  6,
                      (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text("Fix: ${i + 1}"),
                  ),
                ),
              ],
              onChanged: (val) {
                onCheatDiceChanged(val ?? 0);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PieceTeleportDropdown extends StatelessWidget {
  final int pieceId;
  final String currentValue;
  final ValueChanged<String?> onChanged;

  const _PieceTeleportDropdown({
    required this.pieceId,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.panelBackground.withOpacity(0.6),
        border: Border.all(
          color: AppColors.yellowSafeBorder.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "#$pieceId:",
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentValue,
              dropdownColor: AppColors.panelBackground,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              items: [
                const DropdownMenuItem(
                  value: "-1",
                  child: Text("Base"),
                ),
                ...List.generate(
                  52,
                      (i) => DropdownMenuItem(
                    value: "$i",
                    child: Text("Tile $i"),
                  ),
                ),
                ...List.generate(
                  5,
                      (i) => DropdownMenuItem(
                    value: "H$i",
                    child: Text("Home Path $i"),
                  ),
                ),
                const DropdownMenuItem(
                  value: "H5",
                  child: Text("👑 GOAL"),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}