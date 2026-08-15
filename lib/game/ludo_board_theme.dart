import 'classic_grid_geometry.dart';
import 'ludo_board_geometry.dart';

enum LudoBoardSkin { classic, auroraCircuit, solarisTemple }

class LudoBoardThemeDefinition {
  final String id;
  final String displayName;
  final LudoBoardSkin skin;
  final LudoBoardGeometry geometry;

  const LudoBoardThemeDefinition({
    required this.id,
    required this.displayName,
    required this.skin,
    required this.geometry,
  });
}

/// Registry for supported persisted board IDs.
///
/// Board IDs select presentation only. They never change the serialized Ludo
/// topology or movement rules.
abstract final class LudoBoardThemeResolver {
  static const String classicId = 'classic';
  static const String auroraCircuitId = 'auroraCircuit';
  static const String solarisTempleId = 'solarisTemple';

  static const LudoBoardThemeDefinition classic = LudoBoardThemeDefinition(
    id: classicId,
    displayName: 'Classic',
    skin: LudoBoardSkin.classic,
    geometry: ClassicGridGeometry(),
  );

  static const LudoBoardThemeDefinition auroraCircuit =
      LudoBoardThemeDefinition(
        id: auroraCircuitId,
        displayName: 'Aurora Circuit',
        skin: LudoBoardSkin.auroraCircuit,
        geometry: ClassicGridGeometry(),
      );

  static const LudoBoardThemeDefinition solarisTemple =
      LudoBoardThemeDefinition(
        id: solarisTempleId,
        displayName: 'Solaris Temple',
        skin: LudoBoardSkin.solarisTemple,
        geometry: ClassicGridGeometry(),
      );

  static const List<LudoBoardThemeDefinition> availableThemes = [
    classic,
    auroraCircuit,
    solarisTemple,
  ];

  static LudoBoardThemeDefinition resolve(String? boardId) {
    switch (boardId?.trim().toLowerCase()) {
      case 'auroracircuit':
        return auroraCircuit;
      case 'solaristemple':
        return solarisTemple;
      case 'classic':
      default:
        return classic;
    }
  }

  static String normalizeId(String? boardId) => resolve(boardId).id;

  static String displayNameFor(String? boardId) => resolve(boardId).displayName;

  static Map<String, String> get selectionLabels => {
    for (final theme in availableThemes) theme.id: theme.displayName,
  };
}
