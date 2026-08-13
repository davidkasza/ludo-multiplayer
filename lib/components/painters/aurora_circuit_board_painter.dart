import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/classic_board.dart';
import '../../game/ludo_board_geometry.dart';
import '../../game/ludo_palette.dart';
import '../../game/ludo_rules.dart';

class AuroraCircuitBoardPainter extends CustomPainter {
  static const Color _arena = Color(0xff0b1018);
  static const Color _arenaRaised = Color(0xff131c29);
  static const Color _metalDark = Color(0xff202b3a);
  static const Color _metalLight = Color(0xff617086);
  static const Color _pad = Color(0xff263243);
  static const Color _padTop = Color(0xff354257);
  static const Color _dormant = Color(0xff151e2a);
  static const Color _frost = Color(0xffdce8f8);

  final List<String> seatColorIds;
  final LudoBoardGeometry geometry;
  final Set<int> activeSeats;

  const AuroraCircuitBoardPainter({
    required this.seatColorIds,
    required this.geometry,
    required this.activeSeats,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final boardExtent = geometry.boardExtent;
    final cell = geometry.nominalCellExtent;

    canvas.save();
    canvas.scale(size.width / boardExtent);

    _drawArena(canvas, boardExtent);

    final styles = List<LudoColorStyle>.generate(
      4,
      (seat) => LudoPalette.style(
        seatColorIds.length > seat
            ? seatColorIds[seat]
            : LudoPalette.defaultForSeat(seat),
      ),
    );

    _drawCircuitBed(canvas, cell);

    for (int seat = 0; seat < 4; seat++) {
      _drawDockingBay(
        canvas: canvas,
        seat: seat,
        style: styles[seat],
        active: activeSeats.contains(seat),
        cell: cell,
      );
    }

    _drawOuterTrack(canvas, styles, cell);

    for (int seat = 0; seat < 4; seat++) {
      _drawHomeRunway(
        canvas: canvas,
        seat: seat,
        style: styles[seat],
        active: activeSeats.contains(seat),
        cell: cell,
      );
    }

    _drawEnergyCore(canvas, styles, cell);
    _drawCornerHardware(canvas, boardExtent);

    canvas.restore();
  }

  void _drawArena(Canvas canvas, double extent) {
    final bounds = Rect.fromLTWH(0, 0, extent, extent);
    canvas.drawRect(bounds, Paint()..color = _arena);

    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds.deflate(9), const Radius.circular(27)),
      Paint()..color = _arenaRaised,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds.deflate(11), const Radius.circular(25)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff344154), Color(0xff111925), Color(0xff263245)],
          stops: [0, 0.52, 1],
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  void _drawCircuitBed(Canvas canvas, double cell) {
    final bounds = geometry.goalAreaBounds.inflate(cell * 0.56);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(cell * 0.72)),
      Paint()..color = const Color(0xff0d141f),
    );

    for (int index = 0; index < ClassicBoard.size; index++) {
      final current = geometry.outerTrackCenter(index);
      final next = geometry.outerTrackCenter((index + 1) % ClassicBoard.size);
      canvas.drawLine(
        current,
        next,
        Paint()
          ..color = const Color(0xff090d14)
          ..strokeWidth = cell * 0.73
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        current,
        next,
        Paint()
          ..color = _metalDark.withOpacity(0.72)
          ..strokeWidth = cell * 0.57
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawDockingBay({
    required Canvas canvas,
    required int seat,
    required LudoColorStyle style,
    required bool active,
    required double cell,
  }) {
    final bounds = geometry.baseAreaBounds(seat).deflate(cell * 0.28);
    final accent = active ? style.bright : _metalLight;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.translate(0, cell * 0.10),
        Radius.circular(cell * 0.62),
      ),
      Paint()..color = Colors.black.withOpacity(0.34),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(cell * 0.62)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: active
              ? [
                  Color.lerp(_arenaRaised, style.dark, 0.30)!,
                  const Color(0xff101722),
                ]
              : [_dormant, const Color(0xff0f151e)],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.deflate(cell * 0.05),
        Radius.circular(cell * 0.57),
      ),
      Paint()
        ..color = accent.withOpacity(active ? 0.62 : 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.055,
    );

    final innerBounds = bounds.deflate(cell * 0.70);
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerBounds, Radius.circular(cell * 0.35)),
      Paint()..color = Colors.black.withOpacity(active ? 0.25 : 0.34),
    );

    for (int pieceId = 1; pieceId <= 4; pieceId++) {
      final center = geometry.baseSlotCenter(seat, pieceId);
      canvas.drawCircle(
        center.translate(0, cell * 0.055),
        cell * 0.41,
        Paint()..color = Colors.black.withOpacity(0.55),
      );
      canvas.drawCircle(
        center,
        cell * 0.38,
        Paint()..color = active ? const Color(0xff192331) : _dormant,
      );
      canvas.drawCircle(
        center,
        cell * 0.38,
        Paint()
          ..color = accent.withOpacity(active ? 0.78 : 0.24)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.055,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: cell * 0.29),
        pi * 1.05,
        pi * 0.72,
        false,
        Paint()
          ..color = Colors.white.withOpacity(active ? 0.23 : 0.07)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.035
          ..strokeCap = StrokeCap.round,
      );
    }

    _drawDockMark(canvas, bounds, accent, active, cell);
  }

  void _drawDockMark(
    Canvas canvas,
    Rect bounds,
    Color accent,
    bool active,
    double cell,
  ) {
    final center = Offset(bounds.center.dx, bounds.top + cell * 0.35);
    canvas.drawLine(
      center.translate(-cell * 0.34, 0),
      center.translate(cell * 0.34, 0),
      Paint()
        ..color = accent.withOpacity(active ? 0.62 : 0.16)
        ..strokeWidth = cell * 0.055
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      center,
      cell * 0.07,
      Paint()..color = accent.withOpacity(active ? 0.92 : 0.25),
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
      final center = geometry.outerTrackCenter(index);
      final bounds = Rect.fromCenter(
        center: center,
        width: cell * 0.82,
        height: cell * 0.82,
      );
      final startSeat = startSeatByIndex[index];
      final isStart = startSeat != null;
      final isSafe = LudoRules.safeGlobalPositions.contains(index);
      final style = startSeat == null ? null : styles[startSeat];
      final activeStart = startSeat == null || activeSeats.contains(startSeat);
      final accent = style?.bright ?? _frost;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          bounds.translate(0, cell * 0.07),
          Radius.circular(cell * 0.17),
        ),
        Paint()..color = Colors.black.withOpacity(0.50),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, Radius.circular(cell * 0.17)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isStart && activeStart
                ? [Color.lerp(_padTop, style!.bright, 0.42)!, style.dark]
                : [_padTop, _pad],
          ).createShader(bounds),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, Radius.circular(cell * 0.17)),
        Paint()
          ..color = isStart
              ? accent.withOpacity(activeStart ? 0.92 : 0.28)
              : _metalLight.withOpacity(0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * (isStart ? 0.065 : 0.032),
      );
      canvas.drawLine(
        bounds.topLeft.translate(cell * 0.16, cell * 0.08),
        bounds.topRight.translate(-cell * 0.16, cell * 0.08),
        Paint()
          ..color = Colors.white.withOpacity(isStart ? 0.24 : 0.10)
          ..strokeWidth = cell * 0.025
          ..strokeCap = StrokeCap.round,
      );

      if (isSafe) {
        _drawSafeStation(
          canvas: canvas,
          center: center,
          color: isStart ? accent : const Color(0xff8ee8ff),
          cell: cell,
          isLaunchGate: isStart,
          active: activeStart,
        );
      }
    }
  }

  void _drawSafeStation({
    required Canvas canvas,
    required Offset center,
    required Color color,
    required double cell,
    required bool isLaunchGate,
    required bool active,
  }) {
    final opacity = active ? 1.0 : 0.34;
    canvas.drawCircle(
      center,
      cell * (isLaunchGate ? 0.29 : 0.25),
      Paint()
        ..color = color.withOpacity(0.16 * opacity)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      cell * (isLaunchGate ? 0.29 : 0.25),
      Paint()
        ..color = color.withOpacity(0.82 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.045,
    );
    canvas.drawCircle(
      center,
      cell * 0.17,
      Paint()
        ..color = _frost.withOpacity(0.70 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.028,
    );

    final shield = Path()
      ..moveTo(center.dx, center.dy - cell * 0.13)
      ..lineTo(center.dx + cell * 0.11, center.dy - cell * 0.07)
      ..lineTo(center.dx + cell * 0.075, center.dy + cell * 0.08)
      ..lineTo(center.dx, center.dy + cell * 0.14)
      ..lineTo(center.dx - cell * 0.075, center.dy + cell * 0.08)
      ..lineTo(center.dx - cell * 0.11, center.dy - cell * 0.07)
      ..close();
    canvas.drawPath(
      shield,
      Paint()
        ..color = color.withOpacity(0.88 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.037
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawHomeRunway({
    required Canvas canvas,
    required int seat,
    required LudoColorStyle style,
    required bool active,
    required double cell,
  }) {
    final centers = <Offset>[
      for (int position = 0; position < 5; position++)
        geometry.homeLaneCenter(seat, position),
    ];
    final accent = active ? style.bright : _metalLight;

    canvas.drawLine(
      centers.first,
      centers.last,
      Paint()
        ..color = Colors.black.withOpacity(0.64)
        ..strokeWidth = cell * 0.72
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      centers.first,
      centers.last,
      Paint()
        ..color = accent.withOpacity(active ? 0.15 : 0.055)
        ..strokeWidth = cell * 0.58
        ..strokeCap = StrokeCap.round,
    );

    for (int position = 0; position < centers.length; position++) {
      final progress = position / 4;
      final center = centers[position];
      final bounds = Rect.fromCenter(
        center: center,
        width: cell * 0.82,
        height: cell * 0.82,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          bounds.translate(0, cell * 0.06),
          Radius.circular(cell * 0.17),
        ),
        Paint()..color = Colors.black.withOpacity(0.48),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, Radius.circular(cell * 0.17)),
        Paint()
          ..color = active
              ? Color.lerp(_pad, style.dark, 0.22 + progress * 0.28)!
              : _dormant,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, Radius.circular(cell * 0.17)),
        Paint()
          ..color = accent.withOpacity(active ? 0.42 + progress * 0.36 : 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.048,
      );
      canvas.drawCircle(
        center,
        cell * 0.075,
        Paint()
          ..color = accent.withOpacity(active ? 0.58 + progress * 0.30 : 0.18),
      );
    }
  }

  void _drawEnergyCore(
    Canvas canvas,
    List<LudoColorStyle> styles,
    double cell,
  ) {
    final center = geometry.boardCenter;
    final bounds = geometry.goalAreaBounds.deflate(cell * 0.10);

    canvas.drawCircle(
      center.translate(0, cell * 0.10),
      cell * 1.45,
      Paint()..color = Colors.black.withOpacity(0.54),
    );
    canvas.drawCircle(
      center,
      cell * 1.43,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xff344157), Color(0xff121925)],
        ).createShader(bounds),
    );

    final points = <Offset>[
      bounds.topLeft,
      bounds.bottomLeft,
      bounds.bottomRight,
      bounds.topRight,
    ];
    for (int seat = 0; seat < 4; seat++) {
      final active = activeSeats.contains(seat);
      final facet = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(points[seat].dx, points[seat].dy)
        ..lineTo(points[(seat + 1) % 4].dx, points[(seat + 1) % 4].dy)
        ..close();
      final color = active ? styles[seat].bright : _metalLight;
      canvas.drawPath(
        facet,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(_metalDark, color, active ? 0.32 : 0.06)!,
              Color.lerp(_arena, color, active ? 0.11 : 0.025)!,
            ],
          ).createShader(bounds),
      );
      canvas.drawPath(
        facet,
        Paint()
          ..color = color.withOpacity(active ? 0.66 : 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.045,
      );
    }

    canvas.drawCircle(
      center,
      cell * 0.30,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xffeffbff), Color(0xff76dfff), Color(0xff284c6f)],
          stops: [0, 0.32, 1],
        ).createShader(Rect.fromCircle(center: center, radius: cell * 0.30)),
    );

    for (int seat = 0; seat < 4; seat++) {
      final goalCenter = geometry.goalCenter(seat);
      final active = activeSeats.contains(seat);
      final color = active ? styles[seat].bright : _metalLight;
      canvas.drawCircle(
        goalCenter,
        cell * 0.40,
        Paint()..color = Colors.black.withOpacity(0.22),
      );
      canvas.drawCircle(
        goalCenter,
        cell * 0.38,
        Paint()
          ..color = color.withOpacity(active ? 0.46 : 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.045,
      );
    }
  }

  void _drawCornerHardware(Canvas canvas, double extent) {
    const inset = 24.0;
    final centers = [
      const Offset(inset, inset),
      Offset(inset, extent - inset),
      Offset(extent - inset, extent - inset),
      Offset(extent - inset, inset),
    ];
    for (final center in centers) {
      canvas.drawCircle(center, 4.5, Paint()..color = const Color(0xff080c12));
      canvas.drawCircle(
        center,
        3.3,
        Paint()
          ..color = _metalLight.withOpacity(0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AuroraCircuitBoardPainter oldDelegate) {
    return oldDelegate.geometry != geometry ||
        !_sameList(oldDelegate.seatColorIds, seatColorIds) ||
        !_sameSet(oldDelegate.activeSeats, activeSeats);
  }

  bool _sameList(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (int index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  bool _sameSet(Set<int> first, Set<int> second) {
    return first.length == second.length && first.containsAll(second);
  }
}
