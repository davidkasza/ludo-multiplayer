import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/classic_board.dart';
import '../../game/ludo_board_geometry.dart';
import '../../game/ludo_palette.dart';
import '../../game/ludo_rules.dart';

/// Static warm-stone skin for the shared Classic Ludo geometry.
///
/// This painter owns presentation only. Every tile, socket, Home-lane step,
/// and goal marker is positioned through [geometry].
class SolarisTempleBoardPainter extends CustomPainter {
  static const Color _ivory = Color(0xfffff8e8);
  static const Color _warmStone = Color(0xffe9dcc2);
  static const Color _stoneShade = Color(0xffc8b590);
  static const Color _bronze = Color(0xff8c642b);
  static const Color _bronzeDark = Color(0xff4d351d);
  static const Color _gold = Color(0xffd8a72f);
  static const Color _goldLight = Color(0xffffdf7d);
  static const Color _engraving = Color(0xff9e8355);
  static const Color _dormant = Color(0xffb7aa92);

  final List<String> seatColorIds;
  final LudoBoardGeometry geometry;
  final Set<int> activeSeats;

  const SolarisTempleBoardPainter({
    required this.seatColorIds,
    required this.geometry,
    required this.activeSeats,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final extent = geometry.boardExtent;
    final cell = geometry.nominalCellExtent;

    canvas.save();
    canvas.scale(size.width / extent, size.height / extent);

    final styles = List<LudoColorStyle>.generate(
      4,
      (seat) => LudoPalette.style(
        seatColorIds.length > seat
            ? seatColorIds[seat]
            : LudoPalette.defaultForSeat(seat),
      ),
    );

    _drawStoneArena(canvas, extent, cell);
    _drawEngravedCircuit(canvas, cell);

    for (int seat = 0; seat < 4; seat++) {
      _drawCourtyard(
        canvas: canvas,
        seat: seat,
        style: styles[seat],
        active: activeSeats.contains(seat),
        cell: cell,
      );
    }

    _drawOuterTiles(canvas, styles, cell);

    for (int seat = 0; seat < 4; seat++) {
      _drawHomeLane(
        canvas: canvas,
        seat: seat,
        style: styles[seat],
        active: activeSeats.contains(seat),
        cell: cell,
      );
    }

    _drawSolarAltar(canvas, styles, cell);
    _drawCornerOrnaments(canvas, extent, cell);
    canvas.restore();
  }

  void _drawStoneArena(Canvas canvas, double extent, double cell) {
    final full = Rect.fromLTWH(0, 0, extent, extent);
    canvas.drawRect(full, Paint()..color = _bronzeDark);

    final frame = full.deflate(cell * 0.18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, Radius.circular(cell * 0.72)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffb48942), Color(0xff5c4022), Color(0xffc49a51)],
          stops: [0, 0.52, 1],
        ).createShader(frame),
    );

    final stone = full.deflate(cell * 0.32);
    canvas.drawRRect(
      RRect.fromRectAndRadius(stone, Radius.circular(cell * 0.60)),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.18, -0.22),
          radius: 1.15,
          colors: [_ivory, Color(0xfff1e6cf), _warmStone],
        ).createShader(stone),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        stone.deflate(cell * 0.08),
        Radius.circular(cell * 0.52),
      ),
      Paint()
        ..color = _gold.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.045,
    );
  }

  void _drawEngravedCircuit(Canvas canvas, double cell) {
    final shadow = Paint()
      ..color = _bronzeDark.withOpacity(0.18)
      ..strokeWidth = cell * 0.54
      ..strokeCap = StrokeCap.round;
    final inlay = Paint()
      ..color = _gold.withOpacity(0.62)
      ..strokeWidth = cell * 0.075
      ..strokeCap = StrokeCap.round;

    for (int index = 0; index < ClassicBoard.size; index++) {
      final current = geometry.outerTrackCenter(index);
      final next = geometry.outerTrackCenter((index + 1) % ClassicBoard.size);
      canvas.drawLine(
        current.translate(0, cell * 0.07),
        next.translate(0, cell * 0.07),
        shadow,
      );
      canvas.drawLine(current, next, inlay);
    }
  }

  void _drawCourtyard({
    required Canvas canvas,
    required int seat,
    required LudoColorStyle style,
    required bool active,
    required double cell,
  }) {
    final bounds = geometry.baseAreaBounds(seat).deflate(cell * 0.30);
    final accent = active ? style.base : _dormant;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.translate(0, cell * 0.10),
        Radius.circular(cell * 0.58),
      ),
      Paint()..color = _bronzeDark.withOpacity(0.22),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(cell * 0.58)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: active
              ? [Color.lerp(_ivory, style.bright, 0.12)!, _warmStone]
              : [const Color(0xffded4c0), const Color(0xffc9bda7)],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.deflate(cell * 0.06),
        Radius.circular(cell * 0.52),
      ),
      Paint()
        ..color = active
            ? Color.lerp(_gold, style.base, 0.30)!
            : _engraving.withOpacity(0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.075,
    );

    _drawCourtyardMedallion(canvas, bounds.center, accent, active, cell);

    for (int pieceId = 1; pieceId <= 4; pieceId++) {
      final center = geometry.baseSlotCenter(seat, pieceId);
      canvas.drawCircle(
        center.translate(0, cell * 0.07),
        cell * 0.30,
        Paint()..color = _bronzeDark.withOpacity(0.25),
      );
      canvas.drawCircle(
        center,
        cell * 0.30,
        Paint()
          ..shader = RadialGradient(
            colors: active
                ? [Color.lerp(_ivory, style.bright, 0.18)!, _stoneShade]
                : [const Color(0xffd1c6b3), const Color(0xffa99d88)],
          ).createShader(Rect.fromCircle(center: center, radius: cell * 0.30)),
      );
      canvas.drawCircle(
        center,
        cell * 0.29,
        Paint()
          ..color = accent.withOpacity(active ? 0.82 : 0.34)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.07,
      );
      canvas.drawCircle(
        center,
        cell * 0.20,
        Paint()..color = _bronzeDark.withOpacity(active ? 0.10 : 0.16),
      );
    }
  }

  void _drawCourtyardMedallion(
    Canvas canvas,
    Offset center,
    Color accent,
    bool active,
    double cell,
  ) {
    final paint = Paint()
      ..color = accent.withOpacity(active ? 0.30 : 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.035;
    canvas.drawCircle(center, cell * 0.48, paint);
    for (int ray = 0; ray < 8; ray++) {
      final angle = ray * pi / 4;
      canvas.drawLine(
        center + Offset(cos(angle), sin(angle)) * cell * 0.36,
        center + Offset(cos(angle), sin(angle)) * cell * 0.47,
        paint,
      );
    }
  }

  void _drawOuterTiles(
    Canvas canvas,
    List<LudoColorStyle> styles,
    double cell,
  ) {
    final startSeatByIndex = <int, int>{
      for (int seat = 0; seat < 4; seat++)
        ClassicBoard.startOffsetForSeat(seat): seat,
    };

    for (int index = 0; index < ClassicBoard.size; index++) {
      final bounds = geometry.outerTrackCellBounds(index).deflate(cell * 0.075);
      final tile = RRect.fromRectAndRadius(
        bounds,
        Radius.circular(cell * 0.16),
      );
      final startSeat = startSeatByIndex[index];
      final activeStart = startSeat != null && activeSeats.contains(startSeat);
      final isSafe = LudoRules.safeGlobalPositions.contains(index);

      canvas.drawRRect(
        tile.shift(Offset(0, cell * 0.075)),
        Paint()..color = _bronzeDark.withOpacity(0.26),
      );
      canvas.drawRRect(
        tile,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: startSeat == null
                ? [const Color(0xfffffbef), const Color(0xffd8c9ab)]
                : activeStart
                ? [
                    Color.lerp(_ivory, styles[startSeat].bright, 0.42)!,
                    Color.lerp(_warmStone, styles[startSeat].base, 0.40)!,
                  ]
                : [const Color(0xffd9cfbd), const Color(0xffb9ad98)],
          ).createShader(bounds),
      );
      canvas.drawRRect(
        tile,
        Paint()
          ..color = startSeat == null
              ? _bronze.withOpacity(0.56)
              : (activeStart ? styles[startSeat].dark : _engraving).withOpacity(
                  0.72,
                )
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.045,
      );

      if (startSeat != null) {
        _drawGateway(
          canvas,
          bounds.center,
          activeStart ? styles[startSeat].dark : _engraving,
          cell,
        );
      } else if (isSafe) {
        _drawSunDisc(canvas, bounds.center, _bronze, cell * 0.27);
      }
    }
  }

  void _drawGateway(Canvas canvas, Offset center, Color color, double cell) {
    final paint = Paint()
      ..color = color.withOpacity(0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.055
      ..strokeCap = StrokeCap.round;
    final arch = Rect.fromCenter(
      center: center.translate(0, cell * 0.03),
      width: cell * 0.35,
      height: cell * 0.40,
    );
    canvas.drawArc(arch, pi, pi, false, paint);
    canvas.drawLine(
      Offset(arch.left, center.dy),
      Offset(arch.left, center.dy + cell * 0.17),
      paint,
    );
    canvas.drawLine(
      Offset(arch.right, center.dy),
      Offset(arch.right, center.dy + cell * 0.17),
      paint,
    );
    canvas.drawCircle(center, cell * 0.055, Paint()..color = _goldLight);
  }

  void _drawSunDisc(Canvas canvas, Offset center, Color color, double radius) {
    final paint = Paint()
      ..color = color.withOpacity(0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.18
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius * 0.56, paint);
    canvas.drawCircle(center, radius * 0.20, Paint()..color = color);
    for (int ray = 0; ray < 8; ray++) {
      final angle = ray * pi / 4;
      canvas.drawLine(
        center + Offset(cos(angle), sin(angle)) * radius * 0.70,
        center + Offset(cos(angle), sin(angle)) * radius,
        paint,
      );
    }
  }

  void _drawHomeLane({
    required Canvas canvas,
    required int seat,
    required LudoColorStyle style,
    required bool active,
    required double cell,
  }) {
    final first = geometry.homeLaneCenter(seat, 0);
    final last = geometry.homeLaneCenter(seat, 4);
    final accent = active ? style.base : _dormant;

    canvas.drawLine(
      first,
      last,
      Paint()
        ..color = _bronze.withOpacity(active ? 0.48 : 0.24)
        ..strokeWidth = cell * 0.70
        ..strokeCap = StrokeCap.round,
    );

    for (int position = 0; position < 5; position++) {
      final bounds = geometry
          .homeLaneCellBounds(seat, position)
          .deflate(cell * 0.075);
      final progress = (position + 1) / 5;
      final tile = RRect.fromRectAndRadius(
        bounds,
        Radius.circular(cell * 0.15),
      );
      canvas.drawRRect(
        tile.shift(Offset(0, cell * 0.065)),
        Paint()..color = _bronzeDark.withOpacity(0.22),
      );
      canvas.drawRRect(
        tile,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: active
                ? [
                    Color.lerp(_ivory, style.bright, 0.22 + progress * 0.25)!,
                    Color.lerp(_warmStone, style.base, 0.26 + progress * 0.34)!,
                  ]
                : [const Color(0xffd5cab7), const Color(0xffb7aa95)],
          ).createShader(bounds),
      );
      canvas.drawRRect(
        tile,
        Paint()
          ..color = accent.withOpacity(active ? 0.74 : 0.34)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.05,
      );
      canvas.drawCircle(
        bounds.center,
        cell * (0.045 + progress * 0.022),
        Paint()..color = active ? _goldLight : _engraving.withOpacity(0.55),
      );
    }
  }

  void _drawSolarAltar(
    Canvas canvas,
    List<LudoColorStyle> styles,
    double cell,
  ) {
    final center = geometry.boardCenter;
    final radius = geometry.goalAreaBounds.shortestSide * 0.48;

    canvas.drawCircle(
      center.translate(0, cell * 0.10),
      radius * 1.08,
      Paint()..color = _bronzeDark.withOpacity(0.30),
    );
    canvas.drawCircle(
      center,
      radius * 1.08,
      Paint()
        ..shader = const RadialGradient(
          colors: [_goldLight, _gold, _bronzeDark],
          stops: [0, 0.72, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 1.08)),
    );
    canvas.drawCircle(center, radius * 0.88, Paint()..color = _ivory);

    for (int seat = 0; seat < 4; seat++) {
      final goal = geometry.goalCenter(seat);
      final active = activeSeats.contains(seat);
      final accent = active ? styles[seat].base : _dormant;
      final direction = (goal - center);
      final perpendicular = Offset(-direction.dy, direction.dx);
      final normalizedPerpendicular = perpendicular.distance == 0
          ? Offset.zero
          : perpendicular / perpendicular.distance;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          goal.dx + normalizedPerpendicular.dx * cell * 0.34,
          goal.dy + normalizedPerpendicular.dy * cell * 0.34,
        )
        ..lineTo(
          goal.dx - normalizedPerpendicular.dx * cell * 0.34,
          goal.dy - normalizedPerpendicular.dy * cell * 0.34,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = accent.withOpacity(active ? 0.66 : 0.22),
      );
      canvas.drawCircle(
        goal,
        cell * 0.28,
        Paint()..color = _ivory.withOpacity(active ? 0.92 : 0.70),
      );
      canvas.drawCircle(
        goal,
        cell * 0.27,
        Paint()
          ..color = accent.withOpacity(active ? 0.88 : 0.38)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.065,
      );
    }

    _drawSunDisc(canvas, center, _bronzeDark, cell * 0.30);
  }

  void _drawCornerOrnaments(Canvas canvas, double extent, double cell) {
    final paint = Paint()
      ..color = _engraving.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.035;
    final centers = [
      Offset(cell * 0.88, cell * 0.88),
      Offset(extent - cell * 0.88, cell * 0.88),
      Offset(extent - cell * 0.88, extent - cell * 0.88),
      Offset(cell * 0.88, extent - cell * 0.88),
    ];
    for (final center in centers) {
      canvas.drawCircle(center, cell * 0.34, paint);
      canvas.drawCircle(center, cell * 0.19, paint);
      canvas.drawLine(
        center.translate(-cell * 0.42, 0),
        center.translate(cell * 0.42, 0),
        paint,
      );
      canvas.drawLine(
        center.translate(0, -cell * 0.42),
        center.translate(0, cell * 0.42),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SolarisTempleBoardPainter oldDelegate) {
    return oldDelegate.geometry != geometry ||
        oldDelegate.activeSeats.length != activeSeats.length ||
        !oldDelegate.activeSeats.containsAll(activeSeats) ||
        oldDelegate.seatColorIds.length != seatColorIds.length ||
        !_sameColors(oldDelegate.seatColorIds, seatColorIds);
  }

  bool _sameColors(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (int index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}
