import 'dart:math';
import 'package:flutter/material.dart';
import '../../game/classic_board.dart';
import '../../game/ludo_board_mapper.dart';
import '../../models/ludo_models.dart';
import '../../theme/app_colors.dart';

class StaticBoardPainter extends CustomPainter {
  const StaticBoardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    double baseRes = LudoBoardMapper.baseResolution;
    double cellSize = LudoBoardMapper.cellSize;

    canvas.save();
    canvas.scale(size.width / baseRes);

    canvas.drawRect(const Rect.fromLTWH(0, 0, 600, 600), Paint()..color = AppColors.background);

    double basePxSize = cellSize * 6;
    Paint paint = Paint()..style = PaintingStyle.fill;

    // BLUE BASE
    paint.color = AppColors.blueBase;
    canvas.drawRect(Rect.fromLTWH(0, 0, basePxSize, basePxSize), paint);
    paint.color = Colors.white;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(basePxSize * 0.15, basePxSize * 0.15, basePxSize * 0.70, basePxSize * 0.70), const Radius.circular(12)), paint);

    // RED BASE
    paint.color = AppColors.redBase;
    double redBaseX = cellSize * 9;
    canvas.drawRect(Rect.fromLTWH(redBaseX, redBaseX, basePxSize, basePxSize), paint);
    paint.color = Colors.white;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(redBaseX + basePxSize * 0.15, redBaseX + basePxSize * 0.15, basePxSize * 0.70, basePxSize * 0.70), const Radius.circular(12)), paint);

    void drawBaseNest(BoardPoint bp, Color color) {
      double cx = bp.x * cellSize + cellSize / 2;
      double cy = bp.y * cellSize + cellSize / 2;
      canvas.drawCircle(Offset(cx, cy), cellSize * 0.38, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(cx, cy), cellSize * 0.38, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3);
    }
    for (var bp in ClassicBoard.player1BaseGrid) { drawBaseNest(bp, AppColors.blueBase); }
    for (var bp in ClassicBoard.player2BaseGrid) { drawBaseNest(bp, AppColors.redBase); }

    void drawHomeTile(BoardPoint bp, Color color) {
      canvas.drawRect(Rect.fromLTWH(bp.x * cellSize, bp.y * cellSize, cellSize, cellSize), Paint()..color = color);
      canvas.drawRect(Rect.fromLTWH(bp.x * cellSize, bp.y * cellSize, cellSize, cellSize), Paint()..color = Colors.white.withOpacity(0.25)..style = PaintingStyle.stroke..strokeWidth = 1);
    }
    for (int i = 0; i < 5; i++) { drawHomeTile(ClassicBoard.p1HomeGrid[i], AppColors.blueBase); }
    for (int i = 0; i < 5; i++) { drawHomeTile(ClassicBoard.p2HomeGrid[i], AppColors.redBase); }

    const Set<int> safeTiles = {3, 8, 16, 21, 29, 34, 42, 47};

    for (int i = 0; i < ClassicBoard.gridPath.length; i++) {
      var bp = ClassicBoard.gridPath[i];
      double tx = bp.x * cellSize;
      double ty = bp.y * cellSize;

      Color bg = Colors.white;
      Color border = Colors.black.withOpacity(0.15);

      if (i == 0) { bg = const Color(0xff29b6f6); border = AppColors.blueBase; }
      else if (i == 26) { bg = AppColors.redBright; border = AppColors.redBase; }
      else if (safeTiles.contains(i)) { bg = AppColors.yellowSafe; border = AppColors.yellowSafeBorder; }

      canvas.drawRect(Rect.fromLTWH(tx, ty, cellSize, cellSize), Paint()..color = bg);
      canvas.drawRect(Rect.fromLTWH(tx, ty, cellSize, cellSize), Paint()..color = border..style = PaintingStyle.stroke..strokeWidth = 1);

      if (safeTiles.contains(i)) {
        TextPainter(text: const TextSpan(text: "⭐", style: TextStyle(fontSize: 14)), textDirection: TextDirection.ltr)
          ..layout()..paint(canvas, Offset(tx + cellSize / 2 - 7, ty + cellSize / 2 - 9));
      }
    }

    double midStart = cellSize * 6;
    double midEnd = cellSize * 9;
    double centerPt = baseRes / 2;

    Path blueTriangle = Path()..moveTo(midStart, midStart)..lineTo(centerPt, centerPt)..lineTo(midEnd, midStart)..close();
    canvas.drawPath(blueTriangle, Paint()..color = AppColors.blueBase);
    canvas.drawPath(blueTriangle, Paint()..color = Colors.white.withOpacity(0.2)..style = PaintingStyle.stroke);

    Path redTriangle = Path()..moveTo(midStart, midEnd)..lineTo(centerPt, centerPt)..lineTo(midEnd, midEnd)..close();
    canvas.drawPath(redTriangle, Paint()..color = AppColors.redBase);
    canvas.drawPath(redTriangle, Paint()..color = Colors.white.withOpacity(0.2)..style = PaintingStyle.stroke);

    TextPainter(text: const TextSpan(text: "👑", style: TextStyle(fontSize: 18)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(centerPt - 9, midStart + cellSize * 0.5 - 9));
    TextPainter(text: const TextSpan(text: "👑", style: TextStyle(fontSize: 18)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(centerPt - 9, midEnd - cellSize * 0.5 - 9));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StaticBoardPainter oldDelegate) => false;
}

// Animated Ludo tokens
class DynamicPiecesPainter extends CustomPainter {
  final Map<String, dynamic>? gameData;
  final String? currentUserId;
  final int myPlayerIndex;
  final bool isMyTurn;
  final LocalMovingPiece? localMovingPiece;
  final double hopFrame;

  DynamicPiecesPainter({
    required this.gameData,
    required this.currentUserId,
    required this.myPlayerIndex,
    required this.isMyTurn,
    required this.localMovingPiece,
    required this.hopFrame,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (gameData == null || gameData!['pieces'] == null) return;

    double baseRes = LudoBoardMapper.baseResolution;
    double cellSize = LudoBoardMapper.cellSize;

    canvas.save();
    canvas.scale(size.width / baseRes);

    (gameData!['pieces'] as Map).forEach((playerId, piecesList) {
      int pIndex = (gameData!['players'] as List).indexOf(playerId);
      if (pIndex == -1) pIndex = 0;
      bool isP1 = pIndex == 0;
      bool isCurrentPlayer = playerId == currentUserId;

      Color colorBright = isP1 ? AppColors.blueBright : AppColors.redBright;
      Color colorDark = isP1 ? AppColors.blueDark : AppColors.redDark;

      for (var pMap in piecesList) {
        LudoPiece piece = LudoPiece.fromMap(pMap);
        Offset? coords = LudoBoardMapper.getPieceCanvasCoords(
          piece: piece,
          isPlayerOne: isP1,
          isCurrentPlayer: isCurrentPlayer,
          isMyTurn: isMyTurn,
          localMovingPiece: localMovingPiece,
        );
        if (coords == null) continue;

        double cx = ((coords.dx - 20) / 50).roundToDouble() * cellSize + cellSize / 2;
        double cy = ((coords.dy - 20) / 50).roundToDouble() * cellSize + cellSize / 2;

        if (piece.inHome && piece.pos == 5) {
          cx = baseRes / 2;
          cy = isP1 ? (cellSize * 6 + cellSize * 0.5) : (cellSize * 9 - cellSize * 0.5);
        }

        if (isCurrentPlayer && localMovingPiece != null && localMovingPiece!.id == piece.id) {
          cy -= sin(hopFrame).abs() * (cellSize * 0.45);
        }

        bool isAtGoal = piece.inHome && piece.pos == 5;
        canvas.save();
        if (isAtGoal) {
          canvas.saveLayer(Rect.fromLTWH(cx - cellSize, cy - cellSize, cellSize * 2, cellSize * 2), Paint()..color = Colors.white.withOpacity(0.5));
        }

        Paint bodyPaint = Paint()..shader = RadialGradient(colors: [colorBright, colorDark], center: const Alignment(-0.3, -0.3)).createShader(Rect.fromCircle(center: Offset(cx, cy + cellSize * 0.15), radius: cellSize * 0.36));
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy + cellSize * 0.15), width: cellSize * 0.72, height: cellSize * 0.48), bodyPaint);
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy + cellSize * 0.15), width: cellSize * 0.72, height: cellSize * 0.48), Paint()..color = Colors.white.withOpacity(0.7)..style = PaintingStyle.stroke..strokeWidth = 1);

        Paint headPaint = Paint()..shader = RadialGradient(colors: [colorBright, colorDark], center: const Alignment(-0.3, -0.3)).createShader(Rect.fromCircle(center: Offset(cx, cy - cellSize * 0.18), radius: cellSize * 0.21));
        canvas.drawCircle(Offset(cx, cy - cellSize * 0.18), cellSize * 0.21, headPaint);
        canvas.drawCircle(Offset(cx, cy - cellSize * 0.18), cellSize * 0.21, Paint()..color = Colors.white.withOpacity(0.7)..style = PaintingStyle.stroke..strokeWidth = 1);

        if (isAtGoal) canvas.restore();
        canvas.restore();
      }
    });

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DynamicPiecesPainter oldDelegate) {
    return oldDelegate.gameData != gameData || oldDelegate.hopFrame != hopFrame || oldDelegate.localMovingPiece != localMovingPiece;
  }
}