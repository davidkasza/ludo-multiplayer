import 'package:flutter/material.dart';

class DiceSkinDefinition {
  final String id;
  final String displayName;
  final Color faceStart;
  final Color faceEnd;
  final Color border;
  final Color pip;
  final Color pipShadow;
  final Color pipHighlight;

  const DiceSkinDefinition({
    required this.id,
    required this.displayName,
    required this.faceStart,
    required this.faceEnd,
    required this.border,
    required this.pip,
    required this.pipShadow,
    required this.pipHighlight,
  });
}

/// Stable cosmetic IDs and paint metadata for persisted dice preferences.
///
/// Dice skins never participate in RNG or game-rule decisions. Unknown data
/// deliberately resolves to Classic White for legacy room compatibility.
abstract final class DiceSkinResolver {
  static const String classicId = 'classic';
  static const String obsidianId = 'obsidian';
  static const String oceanId = 'ocean';
  static const String rubyId = 'ruby';
  static const String emeraldId = 'emerald';
  static const String goldId = 'gold';

  static const DiceSkinDefinition classic = DiceSkinDefinition(
    id: classicId,
    displayName: 'Classic White',
    faceStart: Colors.white,
    faceEnd: Color(0xffe5e7eb),
    border: Colors.white,
    pip: Color(0xff111827),
    pipShadow: Color(0x33000000),
    pipHighlight: Color(0x2effffff),
  );

  static const DiceSkinDefinition obsidian = DiceSkinDefinition(
    id: obsidianId,
    displayName: 'Obsidian Black',
    faceStart: Color(0xff374151),
    faceEnd: Color(0xff090d14),
    border: Color(0xff6b7280),
    pip: Color(0xfff9fafb),
    pipShadow: Color(0x66000000),
    pipHighlight: Color(0x66ffffff),
  );

  static const DiceSkinDefinition ocean = DiceSkinDefinition(
    id: oceanId,
    displayName: 'Ocean Blue',
    faceStart: Color(0xff38bdf8),
    faceEnd: Color(0xff075985),
    border: Color(0xffbae6fd),
    pip: Color(0xfff8fafc),
    pipShadow: Color(0x660c4a6e),
    pipHighlight: Color(0x70ffffff),
  );

  static const DiceSkinDefinition ruby = DiceSkinDefinition(
    id: rubyId,
    displayName: 'Ruby Red',
    faceStart: Color(0xfffb7185),
    faceEnd: Color(0xff9f1239),
    border: Color(0xffffcdd5),
    pip: Color(0xfffffbeb),
    pipShadow: Color(0x667f1d1d),
    pipHighlight: Color(0x70ffffff),
  );

  static const DiceSkinDefinition emerald = DiceSkinDefinition(
    id: emeraldId,
    displayName: 'Emerald Green',
    faceStart: Color(0xff4ade80),
    faceEnd: Color(0xff166534),
    border: Color(0xffbbf7d0),
    pip: Color(0xfffffbeb),
    pipShadow: Color(0x6614532d),
    pipHighlight: Color(0x70ffffff),
  );

  static const DiceSkinDefinition gold = DiceSkinDefinition(
    id: goldId,
    displayName: 'Gold',
    faceStart: Color(0xffffe082),
    faceEnd: Color(0xffc48a13),
    border: Color(0xfffff3c4),
    pip: Color(0xff3f2a08),
    pipShadow: Color(0x55713f12),
    pipHighlight: Color(0x70ffffff),
  );

  static const List<DiceSkinDefinition> availableSkins = [
    classic,
    obsidian,
    ocean,
    ruby,
    emerald,
    gold,
  ];

  static DiceSkinDefinition resolve(String? skinId) {
    switch (skinId?.trim().toLowerCase()) {
      case obsidianId:
        return obsidian;
      case oceanId:
        return ocean;
      case rubyId:
        return ruby;
      case emeraldId:
        return emerald;
      case goldId:
        return gold;
      case classicId:
      default:
        return classic;
    }
  }

  static String normalizeId(String? skinId) => resolve(skinId).id;

  static DiceSkinDefinition forPlayer(
    Map<String, String>? playerDiceSkins,
    String playerId,
  ) {
    if (playerId.startsWith('bot_')) return classic;
    return resolve(playerDiceSkins?[playerId]);
  }

  /// Normalizes room metadata and supplies deterministic Classic dice for
  /// legacy participants and bots without creating separate bot profiles.
  static Map<String, String> normalizePlayerMap(
    Object? raw,
    Iterable<String> playerIds,
  ) {
    final source = raw is Map ? Map<Object?, Object?>.from(raw) : const {};
    return {
      for (final playerId in playerIds)
        playerId: playerId.startsWith('bot_')
            ? classicId
            : normalizeId(
                source[playerId] is String ? source[playerId] as String : null,
              ),
    };
  }

  static Map<String, String> withPlayer(
    Object? raw, {
    required Iterable<String> playerIds,
    required String playerId,
    required String skinId,
  }) {
    final result = normalizePlayerMap(raw, playerIds);
    result[playerId] = playerId.startsWith('bot_')
        ? classicId
        : normalizeId(skinId);
    return result;
  }
}
