import 'dart:math';
import 'package:flutter/material.dart';
import '../controllers/ludo_controller.dart';
import '../theme/app_colors.dart';

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

class _GameControlsState extends State<GameControls> with SingleTickerProviderStateMixin {
  bool showCheatPanel = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          var c = widget.controller;

          String currentTurnUid = c.gameData?['currentTurn'] ?? "";
          int currentTurnIndex = c.getPlayerIndex(currentTurnUid);

          Color avatarBgColor = currentTurnIndex == 0 ? AppColors.blueBase : AppColors.redBase;
          Color avatarIconColor = currentTurnIndex == 0 ? AppColors.blueDark : AppColors.redDark;

          Color myBaseColor = c.myPlayerIndex == 0 ? AppColors.blueBase : AppColors.redBase;
          Color myBrightColor = c.myPlayerIndex == 0 ? AppColors.blueBright : AppColors.redBright;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.isMyTurn ? myBaseColor.withOpacity(0.08) : Colors.white.withOpacity(0.03),
                      border: Border.all(
                          color: c.isMyTurn ? myBrightColor.withOpacity(0.5) : Colors.white.withOpacity(0.1),
                          width: c.isMyTurn ? 2.0 : 1.0
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: c.canRoll ? [BoxShadow(color: myBaseColor.withOpacity(_pulseController.value * 0.3), blurRadius: 10, spreadRadius: 1)] : null,
                    ),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: avatarBgColor,
                          child: Icon(Icons.person, color: avatarIconColor, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.gameData?['status'] == 'waiting' ? "Waiting..." : c.isMyTurn ? "YOUR TURN!" : c.getPlayerDisplayTitle(c.gameData?['currentTurn'] ?? ""),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white),
                            ),
                            Text(
                              c.isMyTurn ? (c.gameData?['hasRolled'] == true ? "Select a piece to move!" : "Tap to roll!") : "Waiting for opponent...",
                              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.bold),
                            )
                          ],
                        )
                      ],
                    ),

                    GestureDetector(
                      onTap: c.canRoll ? () => c.rollDice(widget.cheatDiceValue) : null,
                      child: _RollingDiceUI(
                        value: c.gameData?['diceValue'] ?? 0,
                        isRolling: c.isDiceRolling,
                        size: 42.0,
                      ),
                    )
                  ],
                ),
              ),

              if (c.gameData?['isTestModeActive'] == true) ...[
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                      color: const Color(0xfff57f17).withOpacity(0.04),
                      border: Border.all(color: AppColors.yellowSafeBorder.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(10)
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text(showCheatPanel ? "▲ Close Sandbox Toolkit" : "▼ Open Sandbox Toolkit", style: const TextStyle(color: Color(0xffffe082), fontWeight: FontWeight.bold, fontSize: 12)),
                        onTap: () => setState(() => showCheatPanel = !showCheatPanel),
                      ),
                      if (showCheatPanel)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 160),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(left: 10, right: 10, bottom: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (c.isMyTurn && c.gameData?['hasRolled'] == false)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("🔮 Next roll:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xffffe082))),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        decoration: BoxDecoration(color: AppColors.panelBackground, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white.withOpacity(0.1))),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<int>(
                                            value: widget.cheatDiceValue,
                                            dropdownColor: AppColors.panelBackground,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                            items: [
                                              const DropdownMenuItem(value: 0, child: Text("Random")),
                                              ...List.generate(6, (i) => DropdownMenuItem(value: i + 1, child: Text("Fix: ${i + 1}")))
                                            ],
                                            onChanged: (val) => widget.onCheatDiceChanged(val ?? 0),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                const SizedBox(height: 8),
                                if (c.getMyPieces().isNotEmpty)
                                  GridView.count(
                                    crossAxisCount: 2,
                                    shrinkWrap: true,
                                    childAspectRatio: 2.8,
                                    mainAxisSpacing: 6,
                                    crossAxisSpacing: 6,
                                    physics: const NeverScrollableScrollPhysics(),
                                    children: c.getMyPieces().map((p) {
                                      String currentVal = p.pos == -1 ? "-1" : p.inHome ? "H${p.pos}" : "${p.pos}";
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        decoration: BoxDecoration(
                                            color: AppColors.panelBackground.withOpacity(0.6),
                                            border: Border.all(color: AppColors.yellowSafeBorder.withOpacity(0.2)),
                                            borderRadius: BorderRadius.circular(6)
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text("#${p.id}:", style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
                                            DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                value: currentVal,
                                                dropdownColor: AppColors.panelBackground,
                                                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                                items: [
                                                  const DropdownMenuItem(value: "-1", child: Text("Base")),
                                                  ...List.generate(52, (i) => DropdownMenuItem(value: "$i", child: Text("Tile $i"))),
                                                  ...List.generate(5, (i) => DropdownMenuItem(value: "H$i", child: Text("Home Path $i"))),
                                                  const DropdownMenuItem(value: "H5", child: Text("👑 GOAL")),
                                                ],
                                                onChanged: (val) => c.teleportPiece(p.id, val ?? "-1"),
                                              ),
                                            )
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  )
                              ],
                            ),
                          ),
                        )
                    ],
                  ),
                )
              ]
            ],
          );
        }
    );
  }
}

class _RollingDiceUI extends StatefulWidget {
  final int value;
  final bool isRolling;
  final double size;

  const _RollingDiceUI({required this.value, required this.isRolling, this.size = 38.0});

  @override
  State<_RollingDiceUI> createState() => _RollingDiceUIState();
}

class _RollingDiceUIState extends State<_RollingDiceUI> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final Random _random = Random();
  int _randomFace = 6;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))
      ..addListener(() {
        if (widget.isRolling) {
          if (_random.nextDouble() > 0.7) {
            setState(() { _randomFace = _random.nextInt(6) + 1; });
          }
        }
      });
  }

  @override
  void didUpdateWidget(_RollingDiceUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRolling && !oldWidget.isRolling) {
      _animController.repeat();
    } else if (!widget.isRolling && oldWidget.isRolling) {
      _animController.stop();
      _animController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int displayValue = widget.isRolling ? _randomFace : (widget.value == 0 ? 6 : widget.value);

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        double animValue = widget.isRolling ? _animController.value : 0.0;
        double angleX = widget.isRolling ? animValue * pi * 4 : 0.0;
        double angleY = widget.isRolling ? animValue * pi * 2 : 0.0;
        double angleZ = widget.isRolling ? animValue * pi * 2 : 0.0;
        double elevation = widget.isRolling ? sin(animValue * pi) : 0.0;
        double jumpY = -elevation * 35.0;

        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.003)
            ..translate(0.0, jumpY, 0.0)
            ..rotateX(angleX)
            ..rotateY(angleY)
            ..rotateZ(angleZ),
          alignment: Alignment.center,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(widget.size * 0.15),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 6.0 + (elevation * 8),
                    offset: Offset(0, 4.0 + (elevation * 12))
                )
              ],
            ),
            child: CustomPaint(painter: _DicePainter(displayValue)),
          ),
        );
      },
    );
  }
}

class _DicePainter extends CustomPainter {
  final int value;
  _DicePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black87..style = PaintingStyle.fill;
    double r = size.width * 0.11;
    double p1 = size.width * 0.25;
    double p2 = size.width * 0.5;
    double p3 = size.width * 0.75;

    void drawDot(double x, double y) => canvas.drawCircle(Offset(x, y), r, paint);

    if (value.isOdd) drawDot(p2, p2);
    if (value > 1) { drawDot(p1, p1); drawDot(p3, p3); }
    if (value > 3) { drawDot(p1, p3); drawDot(p3, p1); }
    if (value == 6) { drawDot(p1, p2); drawDot(p3, p2); }
  }

  @override
  bool shouldRepaint(covariant _DicePainter oldDelegate) => oldDelegate.value != value;
}