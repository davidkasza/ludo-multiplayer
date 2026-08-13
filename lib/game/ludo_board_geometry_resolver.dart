import 'classic_grid_geometry.dart';
import 'ludo_board_geometry.dart';
import 'ludo_board_theme.dart';

/// Resolves persisted board identifiers to supported local geometry.
///
/// Missing, legacy, or unknown identifiers intentionally fall back to the
/// Classic theme's geometry.
abstract final class LudoBoardGeometryResolver {
  static const LudoBoardGeometry classic = ClassicGridGeometry();

  static LudoBoardGeometry resolve(String? boardId) {
    return LudoBoardThemeResolver.resolve(boardId).geometry;
  }
}
