import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class LudoColorStyle {
  final String id;
  final String label;
  final Color base;
  final Color bright;
  final Color dark;

  const LudoColorStyle({
    required this.id,
    required this.label,
    required this.base,
    required this.bright,
    required this.dark,
  });
}

class LudoPalette {
  const LudoPalette._();

  static const List<String> colorIds = [
    'blue',
    'green',
    'red',
    'yellow',
  ];

  static const Map<String, LudoColorStyle> _styles = {
    'blue': LudoColorStyle(
      id: 'blue',
      label: 'Blue',
      base: AppColors.blueBase,
      bright: AppColors.blueBright,
      dark: AppColors.blueDark,
    ),
    'green': LudoColorStyle(
      id: 'green',
      label: 'Green',
      base: AppColors.greenBase,
      bright: AppColors.greenBright,
      dark: AppColors.greenDark,
    ),
    'red': LudoColorStyle(
      id: 'red',
      label: 'Red',
      base: AppColors.redBase,
      bright: AppColors.redBright,
      dark: AppColors.redDark,
    ),
    'yellow': LudoColorStyle(
      id: 'yellow',
      label: 'Yellow',
      base: AppColors.yellowBase,
      bright: AppColors.yellowBright,
      dark: AppColors.yellowDark,
    ),
  };

  static LudoColorStyle style(String? id) {
    return _styles[normalize(id)]!;
  }

  static String normalize(String? id) {
    return colorIds.contains(id) ? id! : colorIds.first;
  }

  static String defaultForSeat(int seatIndex) {
    return colorIds[seatIndex.clamp(0, colorIds.length - 1).toInt()];
  }

  /// Builds a local-only colour assignment for the four physical seats.
  ///
  /// The viewer always receives their preferred colour. Other occupied seats
  /// are assigned a unique remaining colour. Therefore two players may both
  /// choose yellow and each one still sees themselves as yellow on their own
  /// device, while the opponent is remapped locally.
  static List<String> buildSeatColorIds({
    required List<String> players,
    required Map<String, String> preferredColors,
    required Map<String, int> playerSeats,
    required String? viewerId,
  }) {
    final result = List<String?>.filled(4, null);
    final used = <String>{};

    final viewerSeat = viewerId == null
        ? -1
        : (playerSeats[viewerId] ?? players.indexOf(viewerId));

    if (viewerSeat >= 0 && viewerSeat < 4) {
      final preferred = normalize(
        preferredColors[viewerId] ?? defaultForSeat(viewerSeat),
      );
      result[viewerSeat] = preferred;
      used.add(preferred);
    }

    for (final playerId in players) {
      final seat = playerSeats[playerId] ?? players.indexOf(playerId);
      if (seat < 0 || seat >= 4 || seat == viewerSeat) continue;

      final preferred = normalize(
        preferredColors[playerId] ?? defaultForSeat(seat),
      );

      final selected = used.contains(preferred)
          ? colorIds.firstWhere(
            (id) => !used.contains(id),
        orElse: () => defaultForSeat(seat),
      )
          : preferred;

      result[seat] = selected;
      used.add(selected);
    }

    for (int seat = 0; seat < 4; seat++) {
      if (result[seat] != null) continue;

      final fallback = colorIds.firstWhere(
            (id) => !used.contains(id),
        orElse: () => defaultForSeat(seat),
      );
      result[seat] = fallback;
      used.add(fallback);
    }

    return result.cast<String>();
  }
}