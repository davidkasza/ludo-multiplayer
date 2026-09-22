import 'package:flutter/material.dart';

import '../../game/ludo_board_theme.dart';
import '../../models/ludo_models.dart';
import '../../theme/app_colors.dart';
import '../painters/board_painters.dart';

/// Selects an existing board skin using a true miniature of its static
/// painter. The painters and their authored artwork remain unchanged.
class BoardStyleSelector extends StatelessWidget {
  final String selectedBoardId;
  final bool enabled;
  final List<String> seatColorIds;
  final int maxPlayers;
  final ValueChanged<String> onSelected;

  const BoardStyleSelector({
    super.key,
    required this.selectedBoardId,
    required this.enabled,
    required this.seatColorIds,
    required this.maxPlayers,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Board style',
          style: TextStyle(
            color: Colors.white.withOpacity(0.62),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: LudoBoardThemeResolver.availableThemes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final theme = LudoBoardThemeResolver.availableThemes[index];
              return _BoardStyleCard(
                theme: theme,
                selected: theme.id == selectedBoardId,
                enabled: enabled,
                seatColorIds: seatColorIds,
                activeSeats: LudoGame.seatLayoutForMaxPlayers(
                  maxPlayers,
                ).toSet(),
                onTap: () => onSelected(theme.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BoardStyleCard extends StatelessWidget {
  final LudoBoardThemeDefinition theme;
  final bool selected;
  final bool enabled;
  final List<String> seatColorIds;
  final Set<int> activeSeats;
  final VoidCallback onTap;

  const _BoardStyleCard({
    required this.theme,
    required this.selected,
    required this.enabled,
    required this.seatColorIds,
    required this.activeSeats,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.blueBright;
    return Semantics(
      selected: selected,
      button: true,
      label: '${theme.displayName} board style',
      child: Opacity(
        opacity: enabled ? 1 : 0.62,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            width: 108,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withOpacity(0.12)
                  : AppColors.background.withOpacity(0.75),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? accent.withOpacity(0.9)
                    : Colors.white.withOpacity(0.14),
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: accent.withOpacity(0.2), blurRadius: 9)]
                  : null,
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: const Size.square(76),
                          painter: _painter(),
                        ),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        right: 3,
                        top: 3,
                        child: Container(
                          width: 17,
                          height: 17,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Expanded(
                  child: Center(
                    child: Text(
                      theme.displayName,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  CustomPainter _painter() {
    switch (theme.skin) {
      case LudoBoardSkin.classic:
        return StaticBoardPainter(
          seatColorIds: seatColorIds,
          geometry: theme.geometry,
        );
      case LudoBoardSkin.auroraCircuit:
        return AuroraCircuitBoardPainter(
          seatColorIds: seatColorIds,
          geometry: theme.geometry,
          activeSeats: activeSeats,
        );
      case LudoBoardSkin.solarisTemple:
        return SolarisTempleBoardPainter(
          seatColorIds: seatColorIds,
          geometry: theme.geometry,
          activeSeats: activeSeats,
        );
      case LudoBoardSkin.nusantara:
        return NusantaraBoardPainter(
          seatColorIds: seatColorIds,
          geometry: theme.geometry,
          activeSeats: activeSeats,
        );
    }
  }
}
