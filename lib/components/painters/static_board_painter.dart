import 'package:flutter/material.dart';

import '../../game/classic_board.dart';
import '../../game/ludo_board_geometry.dart';
import '../../game/ludo_palette.dart';
import '../../theme/app_colors.dart';

class StaticBoardPainter extends CustomPainter {
  final List<String> seatColorIds;
  final LudoBoardGeometry geometry;

  const StaticBoardPainter({
    required this.seatColorIds,
    required this.geometry,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseRes = geometry.boardExtent;
    final cellSize = geometry.nominalCellExtent;

    canvas.save();
    canvas.scale(size.width / baseRes);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, baseRes, baseRes),
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

    final basePxSize = cellSize * 6;
    final outlinedCells = <Rect>[];

    for (int seat = 0; seat < 4; seat++) {
      final baseBounds = geometry.baseAreaBounds(seat);
      final style = styles[seat];

      canvas.drawRect(baseBounds, Paint()..color = style.base);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            baseBounds.left + basePxSize * 0.15,
            baseBounds.top + basePxSize * 0.15,
            basePxSize * 0.70,
            basePxSize * 0.70,
          ),
          const Radius.circular(12),
        ),
        Paint()..color = Colors.white,
      );

      for (int pieceId = 1; pieceId <= 4; pieceId++) {
        _drawBaseNest(
          canvas: canvas,
          center: geometry.baseSlotCenter(seat, pieceId),
          color: style.base,
          cellSize: cellSize,
        );
      }

      for (int homeIndex = 0; homeIndex < 5; homeIndex++) {
        final homeBounds = geometry.homeLaneCellBounds(seat, homeIndex);
        _fillCell(canvas: canvas, bounds: homeBounds, color: style.base);
        outlinedCells.add(homeBounds);
      }
    }

    const starSafeTiles = {3, 8, 16, 21, 29, 34, 42, 47};

    final startSeatByPathIndex = <int, int>{
      for (int seat = 0; seat < 4; seat++)
        ClassicBoard.startOffsetForSeat(seat): seat,
    };

    for (int pathIndex = 0; pathIndex < ClassicBoard.size; pathIndex++) {
      final bounds = geometry.outerTrackCellBounds(pathIndex);
      Color background = Colors.white;

      final startSeat = startSeatByPathIndex[pathIndex];
      if (startSeat != null) {
        background = styles[startSeat].bright;
      } else if (starSafeTiles.contains(pathIndex)) {
        background = AppColors.yellowSafe;
      }

      _fillCell(canvas: canvas, bounds: bounds, color: background);
      outlinedCells.add(bounds);
    }

    _drawGoalTriangles(canvas: canvas, styles: styles);

    // Borders are drawn only after every cell has been filled. Previously the
    // next cell's fill covered part of the preceding cell's border, which made
    // lines disappear or look thicker on one side.
    final gridPaint = Paint()
      ..color = Colors.black.withOpacity(0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseRes / size.width
      ..isAntiAlias = false;

    for (final bounds in outlinedCells) {
      canvas.drawRect(bounds, gridPaint);
    }

    for (final pathIndex in starSafeTiles) {
      _drawStar(
        canvas: canvas,
        bounds: geometry.outerTrackCellBounds(pathIndex),
      );
    }

    _drawGoalCrowns(canvas);

    canvas.restore();
  }

  void _fillCell({
    required Canvas canvas,
    required Rect bounds,
    required Color color,
  }) {
    canvas.drawRect(bounds, Paint()..color = color);
  }

  void _drawBaseNest({
    required Canvas canvas,
    required Offset center,
    required Color color,
    required double cellSize,
  }) {
    canvas.drawCircle(center, cellSize * 0.38, Paint()..color = Colors.white);

    canvas.drawCircle(
      center,
      cellSize * 0.38,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _drawStar({required Canvas canvas, required Rect bounds}) {
    final textPainter = TextPainter(
      text: const TextSpan(text: '⭐', style: TextStyle(fontSize: 14)),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        bounds.center.dx - textPainter.width / 2,
        bounds.center.dy - textPainter.height / 2,
      ),
    );
  }

  void _drawGoalTriangles({
    required Canvas canvas,
    required List<LudoColorStyle> styles,
  }) {
    final goalBounds = geometry.goalAreaBounds;
    final start = goalBounds.left;
    final end = goalBounds.right;
    final center = geometry.boardCenter;

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
      canvas.drawPath(paths[seat], Paint()..color = styles[seat].base);
      canvas.drawPath(
        paths[seat],
        Paint()
          ..color = Colors.black.withOpacity(0.34)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  void _drawGoalCrowns(Canvas canvas) {
    for (int seat = 0; seat < 4; seat++) {
      final crownCenter = geometry.goalCenter(seat);
      final crownPainter = TextPainter(
        text: const TextSpan(text: '👑', style: TextStyle(fontSize: 17)),
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
    if (oldDelegate.geometry != geometry) return true;
    if (oldDelegate.seatColorIds.length != seatColorIds.length) return true;

    for (int i = 0; i < seatColorIds.length; i++) {
      if (oldDelegate.seatColorIds[i] != seatColorIds[i]) return true;
    }

    return false;
  }
}
