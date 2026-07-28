import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/ludo_controller.dart';
import '../game/ludo_palette.dart';
import '../models/ludo_models.dart';
import '../theme/app_colors.dart';
import 'cyber_background.dart';

class WaitingRoom extends StatefulWidget {
  final LudoController controller;
  final VoidCallback onQuit;
  final VoidCallback onStartGame;

  const WaitingRoom({
    super.key,
    required this.controller,
    required this.onQuit,
    required this.onStartGame,
  });

  @override
  State<WaitingRoom> createState() => _WaitingRoomState();
}

class _WaitingRoomState extends State<WaitingRoom> {
  static const Duration _saveDebounce = Duration(milliseconds: 280);

  Timer? _settingsSaveTimer;
  String _draftRoomId = '';
  int _draftMaxPlayers = 2;
  Map<int, String> _draftSeatTypes = const {
    0: LudoGame.humanSeat,
    2: LudoGame.humanSeat,
  };

  int _draftRevision = 0;
  bool _saveQueued = false;
  bool _saveInFlight = false;
  bool _awaitingRemoteAck = false;

  LudoController get controller => widget.controller;

  bool get _isSyncing =>
      _saveQueued || _saveInFlight || _awaitingRemoteAck;

  @override
  void initState() {
    super.initState();
    _syncDraftFromRemote(force: true);
  }

  @override
  void didUpdateWidget(covariant WaitingRoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDraftFromRemote();
  }

  @override
  void dispose() {
    _settingsSaveTimer?.cancel();
    super.dispose();
  }

  Map<int, String> _normalizeSeatTypes({
    required int maxPlayers,
    required Map<int, String> source,
  }) {
    final layout = LudoGame.seatLayoutForMaxPlayers(maxPlayers);
    final result = <int, String>{};

    for (int index = 0; index < layout.length; index++) {
      final seat = layout[index];
      result[seat] = index == 0
          ? LudoGame.humanSeat
          : LudoGame.normalizeSeatType(source[seat]);
    }

    return result;
  }

  bool _remoteMatchesDraft(LudoGame game) {
    if (game.maxPlayers != _draftMaxPlayers) return false;

    final layout = LudoGame.seatLayoutForMaxPlayers(_draftMaxPlayers);
    for (final seat in layout) {
      if (game.seatTypeForSeat(seat) !=
          LudoGame.normalizeSeatType(_draftSeatTypes[seat])) {
        return false;
      }
    }

    return true;
  }

  void _syncDraftFromRemote({bool force = false}) {
    final game = controller.game;
    if (game == null) return;

    final roomChanged = _draftRoomId != controller.gameId;
    if (roomChanged) {
      _settingsSaveTimer?.cancel();
      _saveQueued = false;
      _saveInFlight = false;
      _awaitingRemoteAck = false;
      _draftRevision = 0;
    }

    if (_awaitingRemoteAck && _remoteMatchesDraft(game)) {
      _awaitingRemoteAck = false;
    }

    if (!force &&
        !roomChanged &&
        (_saveQueued || _saveInFlight || _awaitingRemoteAck)) {
      return;
    }

    _draftRoomId = controller.gameId;
    _draftMaxPlayers = game.maxPlayers;
    _draftSeatTypes = _normalizeSeatTypes(
      maxPlayers: game.maxPlayers,
      source: game.seatTypes,
    );
  }

  void _changePlayerCount(int value) {
    if (!controller.isHost || value == _draftMaxPlayers) return;

    setState(() {
      _draftMaxPlayers = value.clamp(2, 4).toInt();
      _draftSeatTypes = _normalizeSeatTypes(
        maxPlayers: _draftMaxPlayers,
        source: _draftSeatTypes,
      );
      _draftRevision++;
      _saveQueued = true;
      _awaitingRemoteAck = false;
    });

    _scheduleSettingsSave();
  }

  void _changeSeatType(int seat, String seatType) {
    if (!controller.isHost) return;

    final normalized = LudoGame.normalizeSeatType(seatType);
    if (_draftSeatTypes[seat] == normalized) return;

    setState(() {
      _draftSeatTypes = Map<int, String>.from(_draftSeatTypes)
        ..[seat] = normalized;
      _draftRevision++;
      _saveQueued = true;
      _awaitingRemoteAck = false;
    });

    _scheduleSettingsSave();
  }

  void _scheduleSettingsSave({
    Duration delay = _saveDebounce,
  }) {
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = Timer(
      delay,
          () => unawaited(_flushDraftSettings()),
    );
  }

  Future<void> _flushDraftSettings() async {
    if (!mounted || !_saveQueued) return;

    if (_saveInFlight) {
      _scheduleSettingsSave(delay: const Duration(milliseconds: 80));
      return;
    }

    final game = controller.game;
    if (game == null || game.status != 'waiting' || !controller.isHost) {
      return;
    }

    final revision = _draftRevision;
    final maxPlayers = _draftMaxPlayers;
    final seatTypes = Map<int, String>.from(_draftSeatTypes);

    setState(() {
      _saveQueued = false;
      _saveInFlight = true;
    });

    final saved = await controller.updateWaitingRoomSettings(
      selectedBoard: game.boardId,
      isTestMode: game.isTestModeActive,
      maxPlayers: maxPlayers,
      seatTypes: seatTypes,
      isPublic: game.isPublic,
    );

    if (!mounted) return;

    setState(() {
      _saveInFlight = false;

      if (!saved && revision == _draftRevision) {
        _awaitingRemoteAck = false;
        _saveQueued = false;
        _draftMaxPlayers = game.maxPlayers;
        _draftSeatTypes = _normalizeSeatTypes(
          maxPlayers: game.maxPlayers,
          source: game.seatTypes,
        );
      } else if (saved && revision == _draftRevision) {
        final currentGame = controller.game;
        _awaitingRemoteAck =
            currentGame == null || !_remoteMatchesDraft(currentGame);
      }
    });

    if (_saveQueued) {
      _scheduleSettingsSave(delay: const Duration(milliseconds: 80));
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = controller.game;
    if (game == null) return const SizedBox.shrink();

    final isHost = controller.isHost;
    final canStart = isHost && game.isReady;
    final visibleMaxPlayers = isHost ? _draftMaxPlayers : game.maxPlayers;
    final visibleSeatTypes = isHost
        ? _draftSeatTypes
        : _normalizeSeatTypes(
      maxPlayers: game.maxPlayers,
      source: game.seatTypes,
    );
    final seatLayout = LudoGame.seatLayoutForMaxPlayers(visibleMaxPlayers);
    final hasHumanOpponentSeat = seatLayout.skip(1).any(
          (seat) =>
      LudoGame.normalizeSeatType(visibleSeatTypes[seat]) ==
          LudoGame.humanSeat,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CyberBackground(
        child: SafeArea(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: [
                  _CompactHeader(
                    isHost: isHost,
                    onBack: widget.onQuit,
                    onSettings: () => _showGameSettings(
                      context: context,
                      game: game,
                      isHost: isHost,
                      hasHumanOpponentSeat: hasHumanOpponentSeat,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _RoomCodeStrip(controller: controller),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          _PlayerSlotsPanel(
                            controller: controller,
                            game: game,
                            isHost: isHost,
                            maxPlayers: visibleMaxPlayers,
                            seatTypes: visibleSeatTypes,
                            seatLayout: seatLayout,
                            isSyncing: isHost && _isSyncing,
                            onPlayerCountChanged: _changePlayerCount,
                            onSeatTypeChanged: _changeSeatType,
                          ),
                          const SizedBox(height: 10),
                          _ColourAndSettingsRow(
                            controller: controller,
                            game: game,
                            isHost: isHost,
                            onColourTap: () => _showColourPicker(
                              context: context,
                              game: game,
                            ),
                            onSettingsTap: () => _showGameSettings(
                              context: context,
                              game: game,
                              isHost: isHost,
                              hasHumanOpponentSeat: hasHumanOpponentSeat,
                            ),
                          ),
                          if (controller.statusMessage.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _StatusMessage(
                              message: controller.statusMessage,
                            ),
                          ],
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StartBar(
                    isHost: isHost,
                    canStart: canStart,
                    openHumanSeats: game.openHumanSeats,
                    onStart: widget.onStartGame,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateSettings({
    required LudoGame game,
    String? selectedBoard,
    bool? isTestMode,
    int? maxPlayers,
    Map<int, String>? seatTypes,
    bool? isPublic,
  }) {
    unawaited(controller.updateWaitingRoomSettings(
      selectedBoard: selectedBoard ?? game.boardId,
      isTestMode: isTestMode ?? game.isTestModeActive,
      maxPlayers: maxPlayers ?? _draftMaxPlayers,
      seatTypes: seatTypes ?? _draftSeatTypes,
      isPublic: isPublic ?? game.isPublic,
    ));
  }

  Future<void> _showColourPicker({
    required BuildContext context,
    required LudoGame game,
  }) async {
    final myId = controller.user?.uid ?? '';
    var selected = game.preferredColors[myId] ??
        LudoPalette.defaultForSeat(controller.myPlayerIndex < 0
            ? 0
            : controller.myPlayerIndex);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return _BottomSheetShell(
              title: 'Choose your colour',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: LudoPalette.colorIds.map((colorId) {
                      final style = LudoPalette.style(colorId);
                      final isSelected = selected == colorId;

                      return InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () {
                          setSheetState(() => selected = colorId);
                          controller.updateMyPreferredColor(colorId);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: style.base.withOpacity(
                              isSelected ? 0.30 : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isSelected
                                  ? style.bright
                                  : style.base.withOpacity(0.55),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: style.bright,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                style.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Colour is a local preference. Two players may choose the same colour and each will still see themselves in that colour on their own device.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.52),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blueBase,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showGameSettings({
    required BuildContext context,
    required LudoGame game,
    required bool isHost,
    required bool hasHumanOpponentSeat,
  }) async {
    var boardId = game.boardId;
    var sandbox = game.isTestModeActive;
    var isPublic = game.isPublic && hasHumanOpponentSeat;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return _BottomSheetShell(
              title: 'Game settings',
              child: Column(
                children: [
                  _SettingDropdown<String>(
                    label: 'Board',
                    value: boardId,
                    enabled: isHost,
                    items: const {
                      'classic': 'Classic Map',
                      'test': 'Circular Loop',
                    },
                    onChanged: (value) {
                      setSheetState(() => boardId = value);
                      _updateSettings(
                        game: game,
                        selectedBoard: value,
                        isTestMode: sandbox,
                        isPublic: isPublic,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _ToggleSetting(
                    title: 'Public room / Quick Match',
                    subtitle: hasHumanOpponentSeat
                        ? 'Allows Quick Match to fill open real-player slots.'
                        : 'Add at least one real-player opponent slot to publish the room.',
                    value: isPublic && hasHumanOpponentSeat,
                    enabled: isHost && hasHumanOpponentSeat,
                    onChanged: (value) {
                      setSheetState(() => isPublic = value);
                      _updateSettings(
                        game: game,
                        selectedBoard: boardId,
                        isTestMode: sandbox,
                        isPublic: value,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _ToggleSetting(
                    title: 'ðŸ› ï¸ Sandbox Mode',
                    subtitle: isHost
                        ? 'Pieces start near the end for quick testing.'
                        : 'Only the host can change this setting.',
                    value: sandbox,
                    enabled: isHost,
                    accentColor: AppColors.yellowSafeBorder,
                    onChanged: (value) {
                      setSheetState(() => sandbox = value);
                      _updateSettings(
                        game: game,
                        selectedBoard: boardId,
                        isTestMode: value,
                        isPublic: isPublic,
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blueBase,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _CompactHeader extends StatelessWidget {
  final bool isHost;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  const _CompactHeader({
    required this.isHost,
    required this.onBack,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to Main Menu',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
          ),
          const Text('ðŸŽ²', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting Room',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Configure seats, then start.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isHost ? 'Game settings' : 'View settings',
            onPressed: onSettings,
            icon: const Icon(Icons.tune, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _RoomCodeStrip extends StatelessWidget {
  final LudoController controller;

  const _RoomCodeStrip({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.blueBright.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.blueBase.withOpacity(0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.meeting_room_outlined,
              color: AppColors.blueBright,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          const Text(
            'Room',
            style: TextStyle(
              color: Colors.white60,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              controller.gameId,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 1,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy room code',
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: controller.gameId),
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('ðŸ“‹ Room code copied!'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy, color: AppColors.blueBright),
          ),
        ],
      ),
    );
  }
}

class _PlayerSlotsPanel extends StatelessWidget {
  final LudoController controller;
  final LudoGame game;
  final bool isHost;
  final int maxPlayers;
  final Map<int, String> seatTypes;
  final List<int> seatLayout;
  final bool isSyncing;
  final ValueChanged<int> onPlayerCountChanged;
  final void Function(int seat, String seatType) onSeatTypeChanged;

  const _PlayerSlotsPanel({
    required this.controller,
    required this.game,
    required this.isHost,
    required this.maxPlayers,
    required this.seatTypes,
    required this.seatLayout,
    required this.isSyncing,
    required this.onPlayerCountChanged,
    required this.onSeatTypeChanged,
  });

  String? _previewPlayerIdForSeat(int physicalSeat) {
    final playerId = game.playerIdForSeat(physicalSeat);
    if (playerId == null) return null;

    final seatType = LudoGame.normalizeSeatType(seatTypes[physicalSeat]);
    if (seatType == LudoGame.humanSeat &&
        controller.isBotPlayer(playerId)) {
      return null;
    }

    return playerId;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Player slots (${game.players.length}/$maxPlayers)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              if (isSyncing) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.blueBright,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              _PlayerCountSelector(
                value: maxPlayers,
                enabled: isHost,
                onChanged: onPlayerCountChanged,
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (int slotIndex = 0;
          slotIndex < seatLayout.length;
          slotIndex++) ...[
            _CompactPlayerSeat(
              controller: controller,
              game: game,
              slotIndex: slotIndex,
              physicalSeat: seatLayout[slotIndex],
              playerId: _previewPlayerIdForSeat(seatLayout[slotIndex]),
              seatType: slotIndex == 0
                  ? LudoGame.humanSeat
                  : LudoGame.normalizeSeatType(
                seatTypes[seatLayout[slotIndex]],
              ),
              canConfigure: isHost,
              onSeatTypeChanged: (seatType) {
                onSeatTypeChanged(seatLayout[slotIndex], seatType);
              },
            ),
            if (slotIndex != seatLayout.length - 1)
              const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _PlayerCountSelector extends StatelessWidget {
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _PlayerCountSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [2, 3, 4].map((count) {
          final selected = count == value;
          return InkWell(
            onTap: enabled ? () => onChanged(count) : null,
            borderRadius: BorderRadius.circular(7),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 30,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.blueBase
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: enabled || selected ? Colors.white : Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CompactPlayerSeat extends StatelessWidget {
  final LudoController controller;
  final LudoGame game;
  final int slotIndex;
  final int physicalSeat;
  final String? playerId;
  final String seatType;
  final bool canConfigure;
  final ValueChanged<String> onSeatTypeChanged;

  const _CompactPlayerSeat({
    required this.controller,
    required this.game,
    required this.slotIndex,
    required this.physicalSeat,
    required this.playerId,
    required this.seatType,
    required this.canConfigure,
    required this.onSeatTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final occupied = playerId != null;
    final resolvedPlayerId = playerId ?? '';
    final isHostSeat = slotIndex == 0;
    final isPlayerHost = occupied && resolvedPlayerId == game.hostUid;
    final isBot = occupied && controller.isBotPlayer(resolvedPlayerId);
    final occupiedByRealPlayer = occupied && !isBot;
    final canChangeType =
        canConfigure && !isHostSeat && !occupiedByRealPlayer;
    final colour = occupied
        ? controller.colorStyleForPlayer(resolvedPlayerId)
        : controller.colorStyleForSeat(physicalSeat);

    final playerName = occupied
        ? controller.getPlayerDisplayTitle(resolvedPlayerId)
        : seatType == LudoGame.computerSeat
        ? 'Creating AI player...'
        : 'Waiting for player';

    final presenceLabel = occupied
        ? controller.presenceLabelForPlayer(resolvedPlayerId)
        : '';
    final subtitle = isPlayerHost
        ? 'Host • $presenceLabel'
        : isBot
        ? 'AI opponent'
        : occupied
        ? presenceLabel
        : seatType == LudoGame.computerSeat
        ? 'AI slot'
        : 'Open real-player slot';

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: occupied
            ? colour.base.withOpacity(0.075)
            : Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: occupied
              ? colour.base.withOpacity(0.34)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: occupied
                ? colour.base.withOpacity(0.20)
                : Colors.white.withOpacity(0.06),
            child: Icon(
              isBot
                  ? Icons.smart_toy
                  : occupied
                  ? Icons.person
                  : Icons.hourglass_empty,
              color: occupied ? colour.bright : Colors.white38,
              size: 19,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  playerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: occupied ? Colors.white : Colors.white60,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (occupied) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colour.bright,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.42),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isHostSeat)
            const _SmallLockedLabel(text: 'Human')
          else
            SizedBox(
              width: 132,
              child: _SeatTypeToggle(
                value: seatType,
                enabled: canChangeType,
                onChanged: onSeatTypeChanged,
              ),
            ),
        ],
      ),
    );
  }
}

class _SeatTypeToggle extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _SeatTypeToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withOpacity(0.11)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SeatTypeOption(
              text: 'Human',
              icon: Icons.person,
              selected: value == LudoGame.humanSeat,
              enabled: enabled,
              onTap: () => onChanged(LudoGame.humanSeat),
            ),
          ),
          Expanded(
            child: _SeatTypeOption(
              text: 'AI',
              icon: Icons.smart_toy,
              selected: value == LudoGame.computerSeat,
              enabled: enabled,
              onTap: () => onChanged(LudoGame.computerSeat),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatTypeOption extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _SeatTypeOption({
    required this.text,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.blueBase.withOpacity(enabled ? 0.95 : 0.42)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: enabled || selected ? Colors.white : Colors.white30,
            ),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                color: enabled || selected ? Colors.white : Colors.white30,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallLockedLabel extends StatelessWidget {
  final String text;

  const _SmallLockedLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ColourAndSettingsRow extends StatelessWidget {
  final LudoController controller;
  final LudoGame game;
  final bool isHost;
  final VoidCallback onColourTap;
  final VoidCallback onSettingsTap;

  const _ColourAndSettingsRow({
    required this.controller,
    required this.game,
    required this.isHost,
    required this.onColourTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final myId = controller.user?.uid ?? '';
    final colourId = game.preferredColors[myId] ??
        LudoPalette.defaultForSeat(controller.myPlayerIndex < 0
            ? 0
            : controller.myPlayerIndex);
    final colour = LudoPalette.style(colourId);
    final boardLabel = game.boardId == 'classic' ? 'Classic' : 'Circular';
    final visibilityLabel = game.isPublic ? 'Public' : 'Private';
    final sandboxLabel = game.isTestModeActive ? 'Sandbox on' : 'Normal mode';

    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onColourTap,
            child: Container(
              height: 62,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colour.base.withOpacity(0.10),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: colour.base.withOpacity(0.36)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: colour.bright,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your colour',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          colour.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onSettingsTap,
            child: Container(
              height: 62,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.045),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Icon(
                    isHost ? Icons.tune : Icons.visibility_outlined,
                    color: AppColors.blueBright,
                    size: 21,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$boardLabel â€¢ $visibilityLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sandboxLabel,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusMessage extends StatelessWidget {
  final String message;

  const _StatusMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.35)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xffffe082),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _StartBar extends StatelessWidget {
  final bool isHost;
  final bool canStart;
  final int openHumanSeats;
  final VoidCallback onStart;

  const _StartBar({
    required this.isHost,
    required this.canStart,
    required this.openHumanSeats,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final label = isHost
        ? canStart
        ? 'Start Game'
        : 'Waiting for $openHumanSeats real player(s)...'
        : 'Waiting for host...';

    return Container(
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: ElevatedButton.icon(
        onPressed: canStart ? onStart : null,
        icon: Icon(canStart ? Icons.play_arrow_rounded : Icons.hourglass_top),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.successGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withOpacity(0.10),
          disabledForegroundColor: Colors.white38,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
    );
  }
}

class _BottomSheetShell extends StatelessWidget {
  final String title;
  final Widget child;

  const _BottomSheetShell({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              20,
              10,
              20,
              20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: AppColors.panelBackground.withOpacity(0.98),
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final bool enabled;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  const _SettingDropdown({
    required this.label,
    required this.value,
    required this.enabled,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.58),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              dropdownColor: AppColors.panelBackground,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              isExpanded: true,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              items: items.entries
                  .map(
                    (entry) => DropdownMenuItem<T>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
                  .toList(),
              onChanged: enabled
                  ? (newValue) {
                if (newValue != null) onChanged(newValue);
              }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleSetting extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final Color accentColor;

  const _ToggleSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.accentColor = AppColors.blueBase,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: accentColor.withOpacity(0.30)),
      ),
      child: SwitchListTile.adaptive(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 11,
          ),
        ),
        value: value,
        activeColor: accentColor,
        onChanged: enabled ? onChanged : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}