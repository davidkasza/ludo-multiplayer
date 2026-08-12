import 'package:flutter/material.dart';

import '../../game/classic_board.dart';
import '../../game/ludo_board_mapper.dart';
import '../../game/ludo_palette.dart';
import '../../theme/app_colors.dart';

class StaticBoardPainter extends CustomPainter {
  final List<String> seatColorIds;

  const StaticBoardPainter({
    required this.seatColorIds,
  });

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

    final styles = List.generate(
      4,
          (index) => LudoPalette.style(
        seatColorIds.length > index
            ? seatColorIds[index]
            : LudoPalette.defaultForSeat(index),
      ),
    );

    const baseOrigins = [
      BoardPoint(0, 0),
      BoardPoint(0, 9),
      BoardPoint(9, 9),
      BoardPoint(9, 0),
    ];

    final double basePxSize = cellSize * 6;
    final outlinedCells = <BoardPoint>[];

    for (int seat = 0; seat < 4; seat++) {
      final origin = baseOrigins[seat];
      final style = styles[seat];
      final left = origin.x * cellSize;
      final top = origin.y * cellSize;

      canvas.drawRect(
        Rect.fromLTWH(left, top, basePxSize, basePxSize),
        Paint()..color = style.base,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left + basePxSize * 0.15,
            top + basePxSize * 0.15,
            basePxSize * 0.70,
            basePxSize * 0.70,
          ),
          const Radius.circular(12),
        ),
        Paint()..color = Colors.white,
      );

      for (final basePoint in ClassicBoard.baseForSeat(seat)) {
        _drawBaseNest(
          canvas: canvas,
          point: basePoint,
          color: style.base,
          cellSize: cellSize,
        );
      }

      for (int homeIndex = 0; homeIndex < 5; homeIndex++) {
        final homePoint = ClassicBoard.homeForSeat(seat)[homeIndex];
        _fillCell(
          canvas: canvas,
          point: homePoint,
          color: style.base,
          cellSize: cellSize,
        );
        outlinedCells.add(homePoint);
      }
    }

    const starSafeTiles = {
      3,
      8,
      16,
      21,
      29,
      34,
      42,
      47,
    };

    final startSeatByPathIndex = <int, int>{
      for (int seat = 0; seat < 4; seat++)
        ClassicBoard.startOffsetForSeat(seat): seat,
    };

    for (int pathIndex = 0;
    pathIndex < ClassicBoard.gridPath.length;
    pathIndex++) {
      final point = ClassicBoard.gridPath[pathIndex];
      Color background = Colors.white;

      final startSeat = startSeatByPathIndex[pathIndex];
      if (startSeat != null) {
        background = styles[startSeat].bright;
      } else if (starSafeTiles.contains(pathIndex)) {
        background = AppColors.yellowSafe;
      }

      _fillCell(
        canvas: canvas,
        point: point,
        color: background,
        cellSize: cellSize,
      );
      outlinedCells.add(point);
    }

    _drawGoalTriangles(
      canvas: canvas,
      styles: styles,
      cellSize: cellSize,
      baseResolution: baseRes,
    );

    // Borders are drawn only after every cell has been filled. Previously the
    // next cell's fill covered part of the preceding cell's border, which made
    // lines disappear or look thicker on one side.
    final gridPaint = Paint()
      ..color = Colors.black.withOpacity(0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseRes / size.width
      ..isAntiAlias = false;

    for (final point in outlinedCells) {
      canvas.drawRect(
        Rect.fromLTWH(
          point.x * cellSize,
          point.y * cellSize,
          cellSize,
          cellSize,
        ),
        gridPaint,
      );
    }

    for (final pathIndex in starSafeTiles) {
      _drawStar(
        canvas: canvas,
        point: ClassicBoard.gridPath[pathIndex],
        cellSize: cellSize,
      );
    }

    /*const startArrows = ['→', '↑', '←', '↓'];
    for (int seat = 0; seat < 4; seat++) {
      _drawStartArrow(
        canvas: canvas,
        point: ClassicBoard.gridPath[
        ClassicBoard.startOffsetForSeat(seat)
        ],
        arrow: startArrows[seat],
        cellSize: cellSize,
      );
    }*/

    _drawGoalCrowns(
      canvas: canvas,
      cellSize: cellSize,
      baseResolution: baseRes,
    );

    canvas.restore();
  }

  void _fillCell({
    required Canvas canvas,
    required BoardPoint point,
    required Color color,
    required double cellSize,
  }) {
    canvas.drawRect(
      Rect.fromLTWH(
        point.x * cellSize,
        point.y * cellSize,
        cellSize,
        cellSize,
      ),
      Paint()..color = color,
    );
  }

  void _drawBaseNest({
    required Canvas canvas,
    required BoardPoint point,
    required Color color,
    required double cellSize,
  }) {
    final center = Offset(
      point.x * cellSize + cellSize / 2,
      point.y * cellSize + cellSize / 2,
    );

    canvas.drawCircle(
      center,
      cellSize * 0.38,
      Paint()..color = Colors.white,
    );

    canvas.drawCircle(
      center,
      cellSize * 0.38,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _drawStar({
    required Canvas canvas,
    required BoardPoint point,
    required double cellSize,
  }) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '⭐',
        style: TextStyle(fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final left = point.x * cellSize;
    final top = point.y * cellSize;

    textPainter.paint(
      canvas,
      Offset(
        left + cellSize / 2 - textPainter.width / 2,
        top + cellSize / 2 - textPainter.height / 2,
      ),
    );
  }

  void _drawGoalTriangles({
    required Canvas canvas,
    required List<LudoColorStyle> styles,
    required double cellSize,
    required double baseResolution,
  }) {
    final start = cellSize * 6;
    final end = cellSize * 9;
    final center = Offset(baseResolution / 2, baseResolution / 2);

    // Path order follows the physical seat order:
    // top-left -> left, bottom-left -> bottom,
    // bottom-right -> right, top-right -> top.
    final paths = <Path>[
      Path()
        ..moveTo(start, start)
        ..lineTo(center.dx, center.dy)
        ..lineTo(start, end)
        ..close(),
      Path()
        ..moveTo(start, end)
        ..lineTo(center.dx, center.dy)
        ..lineTo(end, end)
        ..close(),
      Path()
        ..moveTo(end, start)
        ..lineTo(center.dx, center.dy)
        ..lineTo(end, end)
        ..close(),
      Path()
        ..moveTo(start, start)
        ..lineTo(center.dx, center.dy)
        ..lineTo(end, start)
        ..close(),
    ];

    for (int seat = 0; seat < 4; seat++) {
      canvas.drawPath(
        paths[seat],
        Paint()..color = styles[seat].base,
      );
      canvas.drawPath(
        paths[seat],
        Paint()
          ..color = Colors.black.withOpacity(0.34)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  void _drawGoalCrowns({
    required Canvas canvas,
    required double cellSize,
    required double baseResolution,
  }) {
    final center = Offset(baseResolution / 2, baseResolution / 2);
    final crownCenters = [
      Offset(cellSize * 6.5, center.dy),
      Offset(center.dx, cellSize * 8.5),
      Offset(cellSize * 8.5, center.dy),
      Offset(center.dx, cellSize * 6.5),
    ];

    for (final crownCenter in crownCenters) {
      final crownPainter = TextPainter(
        text: const TextSpan(
          text: '👑',
          style: TextStyle(fontSize: 17),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      crownPainter.paint(
        canvas,
        Offset(
          crownCenter.dx - crownPainter.width / 2,
          crownCenter.dy - crownPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant StaticBoardPainter oldDelegate) {
    if (oldDelegate.seatColorIds.length != seatColorIds.length) return true;

    for (int i = 0; i < seatColorIds.length; i++) {
      if (oldDelegate.seatColorIds[i] != seatColorIds[i]) return true;
    }

    return false;
  }
}
