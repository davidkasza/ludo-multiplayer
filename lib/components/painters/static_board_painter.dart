import 'package:flutter/material.dart';

import '../../game/classic_board.dart';
import '../../game/ludo_board_mapper.dart';
import '../../theme/app_colors.dart';

class StaticBoardPainter extends CustomPainter {
  const StaticBoardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const double baseRes = LudoBoardMapper.baseResolution;
    const double cellSize = LudoBoardMapper.cellSize;

    canvas.save();
    canvas.scale(size.width / baseRes);

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 600, 600),
      Paint()..color = AppColors.background,
    );

    final double basePxSize = cellSize * 6;
    final Paint paint = Paint()..style = PaintingStyle.fill;

    // BLUE BASE
    paint.color = AppColors.blueBase;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, basePxSize, basePxSize),
      paint,
    );

    paint.color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          basePxSize * 0.15,
          basePxSize * 0.15,
          basePxSize * 0.70,
          basePxSize * 0.70,
        ),
        const Radius.circular(12),
      ),
      paint,
    );

    // RED BASE
    paint.color = AppColors.redBase;
    final double redBaseX = cellSize * 9;

    canvas.drawRect(
      Rect.fromLTWH(redBaseX, redBaseX, basePxSize, basePxSize),
      paint,
    );

    paint.color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          redBaseX + basePxSize * 0.15,
          redBaseX + basePxSize * 0.15,
          basePxSize * 0.70,
          basePxSize * 0.70,
        ),
        const Radius.circular(12),
      ),
      paint,
    );

    void drawBaseNest(BoardPoint bp, Color color) {
      final double cx = bp.x * cellSize + cellSize / 2;
      final double cy = bp.y * cellSize + cellSize / 2;

      canvas.drawCircle(
        Offset(cx, cy),
        cellSize * 0.38,
        Paint()..color = Colors.white,
      );

      canvas.drawCircle(
        Offset(cx, cy),
        cellSize * 0.38,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    for (final bp in ClassicBoard.player1BaseGrid) {
      drawBaseNest(bp, AppColors.blueBase);
    }

    for (final bp in ClassicBoard.player2BaseGrid) {
      drawBaseNest(bp, AppColors.redBase);
    }

    void drawHomeTile(BoardPoint bp, Color color) {
      canvas.drawRect(
        Rect.fromLTWH(
          bp.x * cellSize,
          bp.y * cellSize,
          cellSize,
          cellSize,
        ),
        Paint()..color = color,
      );

      canvas.drawRect(
        Rect.fromLTWH(
          bp.x * cellSize,
          bp.y * cellSize,
          cellSize,
          cellSize,
        ),
        Paint()
          ..color = Colors.white.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    for (int i = 0; i < 5; i++) {
      drawHomeTile(ClassicBoard.p1HomeGrid[i], AppColors.blueBase);
    }

    for (int i = 0; i < 5; i++) {
      drawHomeTile(ClassicBoard.p2HomeGrid[i], AppColors.redBase);
    }

    const Set<int> safeTiles = {
      3,
      8,
      16,
      21,
      29,
      34,
      42,
      47,
    };

    for (int i = 0; i < ClassicBoard.gridPath.length; i++) {
      final bp = ClassicBoard.gridPath[i];

      final double tx = bp.x * cellSize;
      final double ty = bp.y * cellSize;

      Color bg = Colors.white;
      Color border = Colors.black.withOpacity(0.15);

      if (i == 0) {
        bg = const Color(0xff29b6f6);
        border = AppColors.blueBase;
      } else if (i == 26) {
        bg = AppColors.redBright;
        border = AppColors.redBase;
      } else if (safeTiles.contains(i)) {
        bg = AppColors.yellowSafe;
        border = AppColors.yellowSafeBorder;
      }

      canvas.drawRect(
        Rect.fromLTWH(tx, ty, cellSize, cellSize),
        Paint()..color = bg,
      );

      canvas.drawRect(
        Rect.fromLTWH(tx, ty, cellSize, cellSize),
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      if (safeTiles.contains(i)) {
        final textPainter = TextPainter(
          text: const TextSpan(
            text: "⭐",
            style: TextStyle(fontSize: 14),
          ),
          textDirection: TextDirection.ltr,
        );

        textPainter
          ..layout()
          ..paint(
            canvas,
            Offset(
              tx + cellSize / 2 - 7,
              ty + cellSize / 2 - 9,
            ),
          );
      }
    }

    final double midStart = cellSize * 6;
    final double midEnd = cellSize * 9;
    const double centerPt = baseRes / 2;

    final Path blueTriangle = Path()
      ..moveTo(midStart, midStart)
      ..lineTo(centerPt, centerPt)
      ..lineTo(midEnd, midStart)
      ..close();

    canvas.drawPath(
      blueTriangle,
      Paint()..color = AppColors.blueBase,
    );

    canvas.drawPath(
      blueTriangle,
      Paint()
        ..color = Colors.white.withOpacity(0.2)
        ..style = PaintingStyle.stroke,
    );

    final Path redTriangle = Path()
      ..moveTo(midStart, midEnd)
      ..lineTo(centerPt, centerPt)
      ..lineTo(midEnd, midEnd)
      ..close();

    canvas.drawPath(
      redTriangle,
      Paint()..color = AppColors.redBase,
    );

    canvas.drawPath(
      redTriangle,
      Paint()
        ..color = Colors.white.withOpacity(0.2)
        ..style = PaintingStyle.stroke,
    );

    final blueCrownPainter = TextPainter(
      text: const TextSpan(
        text: "👑",
        style: TextStyle(fontSize: 18),
      ),
      textDirection: TextDirection.ltr,
    );

    blueCrownPainter
      ..layout()
      ..paint(
        canvas,
        Offset(
          centerPt - 9,
          midStart + cellSize * 0.5 - 9,
        ),
      );

    final redCrownPainter = TextPainter(
      text: const TextSpan(
        text: "👑",
        style: TextStyle(fontSize: 18),
      ),
      textDirection: TextDirection.ltr,
    );

    redCrownPainter
      ..layout()
      ..paint(
        canvas,
        Offset(
          centerPt - 9,
          midEnd - cellSize * 0.5 - 9,
        ),
      );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StaticBoardPainter oldDelegate) => false;
}