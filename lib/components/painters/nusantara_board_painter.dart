import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/classic_board.dart';
import '../../game/ludo_board_geometry.dart';
import '../../game/ludo_palette.dart';
import '../../game/ludo_rules.dart';

/// Static emerald-and-antique-gold skin for the shared Ludo geometry.
///
/// Its ornament is built from original geometric rosettes, woven diamonds,
/// and split-gate forms. The painter never owns topology or piece positions;
/// every gameplay destination continues to come from [geometry].
class NusantaraBoardPainter extends CustomPainter {
  static const Color _forestBlack = Color(0xff061b15);
  static const Color _forest = Color(0xff0a2d23);
  static const Color _emerald = Color(0xff0d4938);
  static const Color _jade = Color(0xff1f7057);
  static const Color _teal = Color(0xff17624f);
  static const Color _paleJade = Color(0xffd9e6d3);
  static const Color _ivory = Color(0xfff1efda);
  static const Color _gold = Color(0xffb58a46);
  static const Color _goldLight = Color(0xffd8bc76);
  static const Color _bronze = Color(0xff6f5030);
  static const Color _dormant = Color(0xff435c51);

  final List<String> seatColorIds;
  final LudoBoardGeometry geometry;
  final Set<int> activeSeats;

  const NusantaraBoardPainter({
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

    _drawArena(canvas, extent, cell);
    _drawSurfaceOrnament(canvas, extent, cell);
    _drawTrackFoundation(canvas, cell);

    for (int seat = 0; seat < 4; seat++) {
      _drawCourtyard(
        canvas: canvas,
        seat: seat,
        style: styles[seat],
        active: activeSeats.contains(seat),
        cell: cell,
      );
    }

    _drawOuterTrack(canvas, styles, cell);

    for (int seat = 0; seat < 4; seat++) {
      _drawHomeLane(
        canvas: canvas,
        seat: seat,
        style: styles[seat],
        active: activeSeats.contains(seat),
        cell: cell,
      );
    }

    _drawGoalMedallion(canvas, styles, cell);
    _drawFrameEngraving(canvas, extent, cell);
    canvas.restore();
  }

  void _drawArena(Canvas canvas, double extent, double cell) {
    final full = Rect.fromLTWH(0, 0, extent, extent);
    canvas.drawRect(full, Paint()..color = _forestBlack);

    final frame = full.deflate(cell * 0.10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, Radius.circular(cell * 0.78)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_jade, _forestBlack, _bronze, _forest],
          stops: [0, 0.38, 0.70, 1],
        ).createShader(frame),
    );

    final goldBand = frame.deflate(cell * 0.10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(goldBand, Radius.circular(cell * 0.66)),
      Paint()
        ..color = _gold.withOpacity(0.82)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.075,
    );

    final surface = full.deflate(cell * 0.29);
    canvas.drawRRect(
      RRect.fromRectAndRadius(surface, Radius.circular(cell * 0.56)),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.24, -0.30),
          radius: 1.18,
          colors: [_teal, _emerald, _forest],
          stops: [0, 0.46, 1],
        ).createShader(surface),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        surface.deflate(cell * 0.06),
        Radius.circular(cell * 0.50),
      ),
      Paint()
        ..color = _goldLight.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.035,
    );
  }

  void _drawSurfaceOrnament(Canvas canvas, double extent, double cell) {
    final paint = Paint()
      ..color = _goldLight.withOpacity(0.075)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.028;
    final centers = [
      Offset(extent * 0.19, extent * 0.19),
      Offset(extent * 0.81, extent * 0.19),
      Offset(extent * 0.81, extent * 0.81),
      Offset(extent * 0.19, extent * 0.81),
    ];

    for (final center in centers) {
      for (int ring = 1; ring <= 3; ring++) {
        final radius = cell * (0.72 + ring * 0.34);
        final diamond = Path()
          ..moveTo(center.dx, center.dy - radius)
          ..lineTo(center.dx + radius, center.dy)
          ..lineTo(center.dx, center.dy + radius)
          ..lineTo(center.dx - radius, center.dy)
          ..close();
        canvas.drawPath(diamond, paint);
      }
      _drawWovenFlower(
        canvas,
        center,
        cell * 0.52,
        _goldLight.withOpacity(0.09),
      );
    }
  }

  void _drawTrackFoundation(Canvas canvas, double cell) {
    final shadow = Paint()
      ..color = _forestBlack.withOpacity(0.78)
      ..strokeWidth = cell * 0.82
      ..strokeCap = StrokeCap.round;
    final greenInlay = Paint()
      ..color = _jade.withOpacity(0.54)
      ..strokeWidth = cell * 0.66
      ..strokeCap = StrokeCap.round;
    final goldThread = Paint()
      ..color = _gold.withOpacity(0.48)
      ..strokeWidth = cell * 0.055
      ..strokeCap = StrokeCap.round;

    for (int index = 0; index < ClassicBoard.size; index++) {
      final current = geometry.outerTrackCenter(index);
      final next = geometry.outerTrackCenter((index + 1) % ClassicBoard.size);
      canvas.drawLine(
        current.translate(0, cell * 0.08),
        next.translate(0, cell * 0.08),
        shadow,
      );
      canvas.drawLine(current, next, greenInlay);
      canvas.drawLine(current, next, goldThread);
    }
  }

  void _drawCourtyard({
    required Canvas canvas,
    required int seat,
    required LudoColorStyle style,
    required bool active,
    required double cell,
  }) {
    final bounds = geometry.baseAreaBounds(seat).deflate(cell * 0.31);
    final accent = active ? style.base : _dormant;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.translate(0, cell * 0.12),
        Radius.circular(cell * 0.62),
      ),
      Paint()..color = _forestBlack.withOpacity(0.52),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(cell * 0.62)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: active
              ? [Color.lerp(_jade, style.dark, 0.16)!, _forest]
              : [const Color(0xff29473b), const Color(0xff173329)],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.deflate(cell * 0.07),
        Radius.circular(cell * 0.55),
      ),
      Paint()
        ..color = active
            ? Color.lerp(_gold, style.base, 0.22)!
            : _gold.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.07,
    );

    _drawCourtyardWeave(canvas, bounds, accent, active, cell);

    for (int pieceId = 1; pieceId <= 4; pieceId++) {
      _drawSocket(
        canvas: canvas,
        center: geometry.baseSlotCenter(seat, pieceId),
        accent: accent,
        active: active,
        cell: cell,
      );
    }
  }

  void _drawCourtyardWeave(
    Canvas canvas,
    Rect bounds,
    Color accent,
    bool active,
    double cell,
  ) {
    final center = bounds.center;
    final ornament = active ? Color.lerp(_goldLight, accent, 0.22)! : _gold;
    final paint = Paint()
      ..color = ornament.withOpacity(active ? 0.20 : 0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.035;
    canvas.drawCircle(center, cell * 0.60, paint);
    for (int turn = 0; turn < 4; turn++) {
      final angle = turn * pi / 2;
      final direction = Offset(cos(angle), sin(angle));
      final side = Offset(-direction.dy, direction.dx);
      final tip = center + direction * cell * 0.54;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(tip.dx + side.dx * cell * 0.19, tip.dy + side.dy * cell * 0.19)
        ..lineTo(tip.dx - side.dx * cell * 0.19, tip.dy - side.dy * cell * 0.19)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawSocket({
    required Canvas canvas,
    required Offset center,
    required Color accent,
    required bool active,
    required double cell,
  }) {
    canvas.drawCircle(
      center.translate(0, cell * 0.075),
      cell * 0.34,
      Paint()..color = _forestBlack.withOpacity(0.72),
    );
    canvas.drawCircle(
      center,
      cell * 0.34,
      Paint()
        ..shader = RadialGradient(
          colors: active
              ? [Color.lerp(_emerald, accent, 0.28)!, _forestBlack]
              : [const Color(0xff38584c), const Color(0xff152f26)],
        ).createShader(Rect.fromCircle(center: center, radius: cell * 0.34)),
    );
    canvas.drawCircle(
      center,
      cell * 0.31,
      Paint()
        ..color = accent.withOpacity(active ? 0.92 : 0.34)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.065,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: cell * 0.24),
      pi * 1.08,
      pi * 0.66,
      false,
      Paint()
        ..color = _goldLight.withOpacity(active ? 0.72 : 0.24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.035
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawOuterTrack(
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
        Radius.circular(cell * 0.15),
      );
      final startSeat = startSeatByIndex[index];
      final activeStart = startSeat != null && activeSeats.contains(startSeat);
      final isSafe = LudoRules.safeGlobalPositions.contains(index);

      canvas.drawRRect(
        tile.shift(Offset(0, cell * 0.075)),
        Paint()..color = _forestBlack.withOpacity(0.58),
      );
      canvas.drawRRect(
        tile,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: startSeat == null
                ? [_ivory, _paleJade]
                : activeStart
                ? [
                    Color.lerp(_ivory, styles[startSeat].bright, 0.30)!,
                    Color.lerp(_paleJade, styles[startSeat].base, 0.36)!,
                  ]
                : [const Color(0xffbac9ba), const Color(0xff8ea598)],
          ).createShader(bounds),
      );
      canvas.drawRRect(
        tile,
        Paint()
          ..color = startSeat == null
              ? _gold.withOpacity(0.72)
              : (activeStart ? styles[startSeat].dark : _dormant).withOpacity(
                  0.88,
                )
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * (startSeat == null ? 0.042 : 0.065),
      );
      canvas.drawLine(
        bounds.topLeft.translate(cell * 0.14, cell * 0.075),
        bounds.topRight.translate(-cell * 0.14, cell * 0.075),
        Paint()
          ..color = Colors.white.withOpacity(0.46)
          ..strokeWidth = cell * 0.025
          ..strokeCap = StrokeCap.round,
      );

      if (startSeat != null) {
        _drawSplitGateway(
          canvas,
          bounds.center,
          activeStart ? styles[startSeat].dark : _dormant,
          cell,
          active: activeStart,
        );
      } else if (isSafe) {
        _drawSafeRosette(canvas, bounds.center, cell, opacity: 1);
      }
    }
  }

  void _drawSplitGateway(
    Canvas canvas,
    Offset center,
    Color color,
    double cell, {
    required bool active,
  }) {
    final opacity = active ? 1.0 : 0.48;
    final paint = Paint()..color = color.withOpacity(0.90 * opacity);
    final left = Path()
      ..moveTo(center.dx - cell * 0.22, center.dy + cell * 0.18)
      ..lineTo(center.dx - cell * 0.17, center.dy - cell * 0.16)
      ..lineTo(center.dx - cell * 0.04, center.dy - cell * 0.04)
      ..lineTo(center.dx - cell * 0.075, center.dy + cell * 0.18)
      ..close();
    final right = Path()
      ..moveTo(center.dx + cell * 0.22, center.dy + cell * 0.18)
      ..lineTo(center.dx + cell * 0.17, center.dy - cell * 0.16)
      ..lineTo(center.dx + cell * 0.04, center.dy - cell * 0.04)
      ..lineTo(center.dx + cell * 0.075, center.dy + cell * 0.18)
      ..close();
    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint);
    canvas.drawCircle(
      center.translate(0, cell * 0.11),
      cell * 0.055,
      Paint()..color = _goldLight.withOpacity(0.95 * opacity),
    );
    canvas.drawCircle(
      center,
      cell * 0.27,
      Paint()
        ..color = _gold.withOpacity(0.64 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.032,
    );
  }

  void _drawSafeRosette(
    Canvas canvas,
    Offset center,
    double cell, {
    required double opacity,
  }) {
    final petalPaint = Paint()
      ..color = _gold.withOpacity(0.90 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.038
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(
      center,
      cell * 0.255,
      Paint()
        ..color = _bronze.withOpacity(0.70 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.035,
    );
    for (int petal = 0; petal < 8; petal++) {
      final angle = petal * pi / 4;
      final direction = Offset(cos(angle), sin(angle));
      final side = Offset(-direction.dy, direction.dx);
      final tip = center + direction * cell * 0.21;
      final path = Path()
        ..moveTo(
          center.dx + side.dx * cell * 0.055,
          center.dy + side.dy * cell * 0.055,
        )
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(
          center.dx - side.dx * cell * 0.055,
          center.dy - side.dy * cell * 0.055,
        );
      canvas.drawPath(path, petalPaint);
    }
    canvas.drawCircle(
      center,
      cell * 0.065,
      Paint()..color = _goldLight.withOpacity(opacity),
    );
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
      first.translate(0, cell * 0.07),
      last.translate(0, cell * 0.07),
      Paint()
        ..color = _forestBlack.withOpacity(0.72)
        ..strokeWidth = cell * 0.76
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      first,
      last,
      Paint()
        ..color = _gold.withOpacity(active ? 0.58 : 0.24)
        ..strokeWidth = cell * 0.64
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
        Paint()..color = _forestBlack.withOpacity(0.48),
      );
      canvas.drawRRect(
        tile,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: active
                ? [
                    Color.lerp(_ivory, style.bright, 0.14 + progress * 0.26)!,
                    Color.lerp(_paleJade, style.base, 0.22 + progress * 0.34)!,
                  ]
                : [const Color(0xffacbeb0), const Color(0xff789486)],
          ).createShader(bounds),
      );
      canvas.drawRRect(
        tile,
        Paint()
          ..color = accent.withOpacity(active ? 0.82 : 0.40)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.052,
      );

      final diamondRadius = cell * (0.045 + progress * 0.028);
      final center = bounds.center;
      final diamond = Path()
        ..moveTo(center.dx, center.dy - diamondRadius)
        ..lineTo(center.dx + diamondRadius, center.dy)
        ..lineTo(center.dx, center.dy + diamondRadius)
        ..lineTo(center.dx - diamondRadius, center.dy)
        ..close();
      canvas.drawPath(
        diamond,
        Paint()..color = active ? _goldLight : _forest.withOpacity(0.50),
      );
    }
  }

  void _drawGoalMedallion(
    Canvas canvas,
    List<LudoColorStyle> styles,
    double cell,
  ) {
    final center = geometry.boardCenter;
    final radius = geometry.goalAreaBounds.shortestSide * 0.49;

    canvas.drawCircle(
      center.translate(0, cell * 0.10),
      radius * 1.04,
      Paint()..color = _forestBlack.withOpacity(0.64),
    );
    canvas.drawCircle(
      center,
      radius * 1.04,
      Paint()
        ..shader = const RadialGradient(
          colors: [_goldLight, _gold, _bronze, _forestBlack],
          stops: [0, 0.62, 0.86, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 1.04)),
    );
    canvas.drawCircle(center, radius * 0.88, Paint()..color = _forest);

    for (int seat = 0; seat < 4; seat++) {
      final goal = geometry.goalCenter(seat);
      final direction = goal - center;
      final angle = atan2(direction.dy, direction.dx);
      final active = activeSeats.contains(seat);
      final accent = active ? styles[seat].base : _dormant;
      final left =
          center +
          Offset(cos(angle - pi / 4), sin(angle - pi / 4)) * radius * 0.82;
      final right =
          center +
          Offset(cos(angle + pi / 4), sin(angle + pi / 4)) * radius * 0.82;
      final facet = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(goal.dx, goal.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(
        facet,
        Paint()..color = accent.withOpacity(active ? 0.68 : 0.24),
      );
      canvas.drawPath(
        facet,
        Paint()
          ..color = _goldLight.withOpacity(active ? 0.50 : 0.20)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.035,
      );

      canvas.drawCircle(
        goal,
        cell * 0.29,
        Paint()..color = _ivory.withOpacity(active ? 0.94 : 0.68),
      );
      canvas.drawCircle(
        goal,
        cell * 0.285,
        Paint()
          ..color = accent.withOpacity(active ? 0.94 : 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.065,
      );
    }

    canvas.drawCircle(
      center,
      radius * 0.72,
      Paint()
        ..color = _gold.withOpacity(0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.045,
    );
    for (int ornament = 0; ornament < 12; ornament++) {
      final angle = ornament * pi / 6;
      final ornamentCenter =
          center + Offset(cos(angle), sin(angle)) * radius * 0.66;
      final diamond = Path()
        ..moveTo(ornamentCenter.dx, ornamentCenter.dy - cell * 0.075)
        ..lineTo(ornamentCenter.dx + cell * 0.055, ornamentCenter.dy)
        ..lineTo(ornamentCenter.dx, ornamentCenter.dy + cell * 0.075)
        ..lineTo(ornamentCenter.dx - cell * 0.055, ornamentCenter.dy)
        ..close();
      canvas.drawPath(diamond, Paint()..color = _goldLight.withOpacity(0.88));
    }

    _drawWovenFlower(canvas, center, cell * 0.27, _goldLight);
  }

  void _drawWovenFlower(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, radius * 0.10)
      ..strokeJoin = StrokeJoin.round;
    for (int petal = 0; petal < 8; petal++) {
      final angle = petal * pi / 4;
      final direction = Offset(cos(angle), sin(angle));
      final side = Offset(-direction.dy, direction.dx);
      final tip = center + direction * radius;
      final path = Path()
        ..moveTo(
          center.dx + side.dx * radius * 0.24,
          center.dy + side.dy * radius * 0.24,
        )
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(
          center.dx - side.dx * radius * 0.24,
          center.dy - side.dy * radius * 0.24,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.drawCircle(center, radius * 0.18, Paint()..color = color);
  }

  void _drawFrameEngraving(Canvas canvas, double extent, double cell) {
    final paint = Paint()
      ..color = _goldLight.withOpacity(0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.028;
    const count = 12;
    for (int index = 0; index < count; index++) {
      final axis = cell * 0.72 + index * ((extent - cell * 1.44) / (count - 1));
      for (final center in [
        Offset(axis, cell * 0.20),
        Offset(axis, extent - cell * 0.20),
        Offset(cell * 0.20, axis),
        Offset(extent - cell * 0.20, axis),
      ]) {
        final diamond = Path()
          ..moveTo(center.dx, center.dy - cell * 0.07)
          ..lineTo(center.dx + cell * 0.10, center.dy)
          ..lineTo(center.dx, center.dy + cell * 0.07)
          ..lineTo(center.dx - cell * 0.10, center.dy)
          ..close();
        canvas.drawPath(diamond, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant NusantaraBoardPainter oldDelegate) {
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
