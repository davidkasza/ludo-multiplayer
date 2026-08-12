import 'classic_grid_geometry.dart';
import 'ludo_board_geometry.dart';

/// Resolves persisted board identifiers to supported local geometry.
///
/// Classic remains the only active geometry. Missing, legacy, or unknown
/// identifiers intentionally fall back to it.
abstract final class LudoBoardGeometryResolver {
  static const LudoBoardGeometry classic = ClassicGridGeometry();

  static LudoBoardGeometry resolve(String? boardId) {
    switch (boardId?.trim().toLowerCase()) {
      case 'classic':
      default:
        return classic;
    }
  }
}
