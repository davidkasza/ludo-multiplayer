import 'dart:ui';

import 'package:flutter/material.dart';

import '../components/cyber_background.dart';
import '../controllers/ludo_controller.dart';
import '../models/profile_models.dart';
import '../theme/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  final LudoController controller;
  final String initialPlayerName;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onBack;

  const ProfileScreen({
    super.key,
    required this.controller,
    required this.initialPlayerName,
    required this.onNameChanged,
    required this.onBack,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  late Future<List<MatchHistoryEntry>> _historyFuture;
  bool _savingName = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.controller.profileName.isNotEmpty
          ? widget.controller.profileName
          : widget.initialPlayerName,
    );
    _reloadHistory();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _reloadHistory() {
    _historyFuture = widget.controller.loadMyMatchHistory();
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || name.length > 15 || _savingName) return;

    setState(() => _savingName = true);
    await widget.controller.updateProfileName(name);

    if (!mounted) return;
    widget.onNameChanged(name);
    setState(() => _savingName = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile name saved.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CyberBackground(
        child: SafeArea(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _ProfileHeader(
                    onBack: widget.onBack,
                    onRefresh: () {
                      setState(_reloadHistory);
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: FutureBuilder<List<MatchHistoryEntry>>(
                      future: _historyFuture,
                      builder: (context, snapshot) {
                        final history = snapshot.data ?? const [];
                        final userId = widget.controller.user?.uid ?? '';
                        final stats = PlayerMatchStats.fromHistory(
                          userId,
                          history,
                        );

                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            children: [
                              _ProfileIdentityCard(
                                nameController: _nameController,
                                isAnonymous:
                                widget.controller.user?.isAnonymous ?? true,
                                isSaving: _savingName,
                                onSave: _saveName,
                              ),
                              const SizedBox(height: 10),
                              _StatsPanel(stats: stats),
                              const SizedBox(height: 10),
                              _HistoryPanel(
                                controller: widget.controller,
                                userId: userId,
                                snapshot: snapshot,
                                history: history,
                                onRetry: () {
                                  setState(_reloadHistory);
                                },
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  const _ProfileHeader({
    required this.onBack,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Player Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Stats and match history',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh match history',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: AppColors.blueBright),
          ),
        ],
      ),
    );
  }
}

class _ProfileIdentityCard extends StatelessWidget {
  final TextEditingController nameController;
  final bool isAnonymous;
  final bool isSaving;
  final VoidCallback onSave;

  const _ProfileIdentityCard({
    required this.nameController,
    required this.isAnonymous,
    required this.isSaving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.blueBase.withOpacity(0.9),
                      AppColors.blueDark,
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.blueBright.withOpacity(0.7),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAnonymous ? 'Guest profile' : 'Signed-in profile',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isAnonymous
                          ? 'Saved on this installation through Firebase Anonymous Auth.'
                          : 'Your profile is connected to an account.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.46),
                        fontSize: 10,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nameController,
                  maxLength: 15,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSave(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Player name',
                    labelStyle: const TextStyle(color: Colors.white54),
                    counterText: '',
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.18),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.10),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: const BorderSide(
                        color: AppColors.blueBright,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: isSaving ? null : onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blueBase,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(Icons.save_outlined),
                ),
              ),
            ],
          ),
          if (isAnonymous) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withOpacity(0.26)),
              ),
              child: Text(
                'Guest progress can be lost after clearing app data or changing devices. Google sign-in can later be linked to this anonymous account without discarding its history.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  final PlayerMatchStats stats;

  const _StatsPanel({required this.stats});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Career stats',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.sports_esports,
                  label: 'Matches',
                  value: '${stats.gamesPlayed}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  icon: Icons.emoji_events,
                  label: 'Wins',
                  value: '${stats.wins}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  icon: Icons.workspace_premium,
                  label: 'Podiums',
                  value: '${stats.podiums}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  icon: Icons.percent,
                  label: 'Win rate',
                  value: '${(stats.winRate * 100).round()}%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
      decoration: BoxDecoration(
        color: AppColors.blueBase.withOpacity(0.08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.blueBright.withOpacity(0.16)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.blueBright, size: 18),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.40),
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  final LudoController controller;
  final String userId;
  final AsyncSnapshot<List<MatchHistoryEntry>> snapshot;
  final List<MatchHistoryEntry> history;
  final VoidCallback onRetry;

  const _HistoryPanel({
    required this.controller,
    required this.userId,
    required this.snapshot,
    required this.history,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Match history',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${history.length} stored',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.blueBright,
                ),
              ),
            )
          else if (snapshot.hasError)
            _HistoryMessage(
              icon: Icons.cloud_off,
              title: 'Could not load match history',
              subtitle:
              'Check Firestore rules and the matchResults collection.',
              actionLabel: 'Retry',
              onAction: onRetry,
            )
          else if (history.isEmpty)
              const _HistoryMessage(
                icon: Icons.history,
                title: 'No completed matches yet',
                subtitle: 'Finished games will appear here automatically.',
              )
            else
              for (int index = 0; index < history.length; index++) ...[
                _HistoryRow(
                  entry: history[index],
                  userId: userId,
                ),
                if (index != history.length - 1)
                  const SizedBox(height: 8),
              ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final MatchHistoryEntry entry;
  final String userId;

  const _HistoryRow({
    required this.entry,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final placement = entry.placementFor(userId);
    final winnerId = entry.ranking.isEmpty ? '' : entry.ranking.first;
    final opponents = entry.ranking
        .where((id) => id != userId)
        .map(entry.playerName)
        .join(', ');

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.15),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _placementColor(placement).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _placementColor(placement).withOpacity(0.34),
              ),
            ),
            child: Text(
              placement > 0 ? '#$placement' : '-',
              style: TextStyle(
                color: _placementColor(placement),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  placement == 1
                      ? 'Victory'
                      : '${entry.playerName(winnerId)} won',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  opponents.isEmpty ? 'Solo result' : 'vs $opponents',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.40),
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_boardName(entry.boardId)} • ${entry.playerCount} players • ${_formatDuration(entry.duration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.34),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDate(entry.finishedAt?.toDate()),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  static Color _placementColor(int placement) {
    switch (placement) {
      case 1:
        return AppColors.yellowBright;
      case 2:
        return const Color(0xffcfd8dc);
      case 3:
        return const Color(0xffffab91);
      default:
        return Colors.white54;
    }
  }

  static String _boardName(String boardId) {
    return boardId == 'classic' ? 'Classic' : 'Circular';
  }

  static String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  static String _formatDate(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.'
        '${local.day.toString().padLeft(2, '0')}.';
  }
}

class _HistoryMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _HistoryMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: Colors.white24, size: 34),
            const SizedBox(height: 9),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;

  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );
  }
}