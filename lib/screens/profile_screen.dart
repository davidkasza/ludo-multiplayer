import 'dart:ui';

import 'package:flutter/material.dart';

import '../components/cyber_background.dart';
import '../components/game_controls/rolling_dice_ui.dart';
import '../controllers/ludo_controller.dart';
import '../controllers/mixins/ludo_google_auth_mixin.dart';
import '../game/ludo_board_theme.dart';
import '../game/dice_skin.dart';
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
  bool _savingDiceSkin = false;
  bool _authActionRunning = false;

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

  Future<void> _selectDiceSkin(String skinId) async {
    if (_savingDiceSkin || skinId == widget.controller.preferredDiceSkinId) {
      return;
    }

    setState(() => _savingDiceSkin = true);
    final saved = await widget.controller.updatePreferredDiceSkin(skinId);
    if (!mounted) return;
    setState(() => _savingDiceSkin = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'Dice skin saved.' : 'Could not save the dice skin.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _connectGoogle() async {
    if (_authActionRunning) return;
    setState(() => _authActionRunning = true);

    final result = await widget.controller.connectGoogleAccount();
    if (!mounted) return;

    if (result == GoogleAccountResult.conflict) {
      setState(() => _authActionRunning = false);
      await _showExistingGoogleAccountDialog();
      return;
    }

    await _finishAuthAction(result);
  }

  Future<void> _showExistingGoogleAccountDialog() async {
    final merge = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.panelBackground,
          title: const Text(
            'Existing Ludora account',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: Text(
            "This Google account already has Ludora progress. Sign in to it and merge this guest profile's stored match history, XP and coins. The merge is recorded so it cannot be awarded twice.",
            style: TextStyle(
              color: Colors.white.withOpacity(0.66),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blueBase,
                foregroundColor: Colors.white,
              ),
              child: const Text('Merge & Sign In'),
            ),
          ],
        );
      },
    );

    if (merge != true || !mounted) return;

    setState(() => _authActionRunning = true);
    final result = await widget.controller.mergeAndSignInWithExistingGoogle();
    if (!mounted) return;
    await _finishAuthAction(result);
  }

  Future<void> _signOut() async {
    if (_authActionRunning) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.panelBackground,
          title: const Text(
            'Sign out?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Your Google profile stays safe. This installation will start a new guest profile until you sign in again.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.66),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _authActionRunning = true);
    final result = await widget.controller.signOutToNewGuest();
    if (!mounted) return;
    await _finishAuthAction(result);
  }

  Future<void> _finishAuthAction(GoogleAccountResult result) async {
    if (!mounted) return;

    final successful =
        result == GoogleAccountResult.linked ||
        result == GoogleAccountResult.signedIn ||
        result == GoogleAccountResult.signedOut;

    if (successful) {
      final refreshedName = widget.controller.profileName;
      _nameController.text = refreshedName;
      widget.onNameChanged(refreshedName);
      setState(() {
        _authActionRunning = false;
        _reloadHistory();
      });
    } else {
      setState(() => _authActionRunning = false);
    }

    if (result == GoogleAccountResult.cancelled) return;

    final message = widget.controller.googleAuthMessage.isNotEmpty
        ? widget.controller.googleAuthMessage
        : successful
        ? 'Account updated.'
        : 'Google account action failed.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
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
                              _DiceSkinPanel(
                                selectedSkinId:
                                    widget.controller.preferredDiceSkinId,
                                saving: _savingDiceSkin,
                                onSelected: _selectDiceSkin,
                              ),
                              const SizedBox(height: 10),
                              _AccountPanel(
                                controller: widget.controller,
                                busy:
                                    _authActionRunning ||
                                    widget.controller.googleAuthBusy,
                                onConnect: _connectGoogle,
                                onSignOut: _signOut,
                              ),
                              const SizedBox(height: 10),
                              _ProgressionPanel(controller: widget.controller),
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

class _DiceSkinPanel extends StatelessWidget {
  final String selectedSkinId;
  final bool saving;
  final ValueChanged<String> onSelected;

  const _DiceSkinPanel({
    required this.selectedSkinId,
    required this.saving,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedSelection = DiceSkinResolver.normalizeId(selectedSkinId);

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Dice appearance',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Every player sees this material when you roll.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final skin in DiceSkinResolver.availableSkins)
                    _DiceSkinTile(
                      width: cardWidth,
                      skin: skin,
                      selected: skin.id == normalizedSelection,
                      enabled: !saving,
                      onTap: () => onSelected(skin.id),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DiceSkinTile extends StatelessWidget {
  final double width;
  final DiceSkinDefinition skin;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _DiceSkinTile({
    required this.width,
    required this.skin,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: selected
            ? AppColors.blueBase.withOpacity(0.15)
            : Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? AppColors.blueBright.withOpacity(0.7)
                    : Colors.white.withOpacity(0.09),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                RollingDiceUI(
                  value: 5,
                  isRolling: false,
                  animationKey: null,
                  initialProgress: 1,
                  rollDuration: const Duration(milliseconds: 800),
                  size: 36,
                  skin: skin,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    skin.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.blueBright,
                    size: 17,
                  ),
              ],
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

  const _ProfileHeader({required this.onBack, required this.onRefresh});

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
                  style: TextStyle(color: Colors.white54, fontSize: 11),
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
                child: const Icon(Icons.person, color: Colors.white, size: 32),
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
                      borderSide: const BorderSide(color: AppColors.blueBright),
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
                'Guest progress can be lost after clearing app data or changing devices. Connect Google below to protect this UID and keep its history.',
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

class _AccountPanel extends StatelessWidget {
  final LudoController controller;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onSignOut;

  const _AccountPanel({
    required this.controller,
    required this.busy,
    required this.onConnect,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final linked = controller.isGoogleLinked;
    final email = controller.googleEmail;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Account protection',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: linked
                      ? AppColors.successGreen.withOpacity(0.12)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: linked
                        ? AppColors.successGreen.withOpacity(0.35)
                        : Colors.white.withOpacity(0.10),
                  ),
                ),
                child: Icon(
                  linked ? Icons.verified_user_rounded : Icons.shield_outlined,
                  color: linked ? AppColors.successGreen : Colors.white54,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      linked ? 'Google connected' : 'Guest-only profile',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      linked
                          ? (email.isEmpty
                                ? 'Progress is available after Google sign-in.'
                                : email)
                          : 'Linking keeps the same Firebase UID, match history and active profile.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: linked
                ? OutlinedButton.icon(
                    onPressed: busy ? null : onSignOut,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout_rounded),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withOpacity(0.14)),
                      minimumSize: const Size.fromHeight(46),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: busy ? null : onConnect,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login_rounded),
                    label: const Text(
                      'Continue with Google',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xff1f2937),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProgressionPanel extends StatelessWidget {
  final LudoController controller;

  const _ProgressionPanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    final progress = controller.levelProgress;
    final isMax = progress.isMaxLevel;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Progression',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.yellowBright.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.yellowBright.withOpacity(0.30),
                  ),
                ),
                child: Text(
                  '${controller.profileCoins} COINS',
                  style: const TextStyle(
                    color: AppColors.yellowBright,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.blueBase.withOpacity(0.16),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.blueBright.withOpacity(0.45),
                    width: 2,
                  ),
                ),
                child: Text(
                  '${progress.level}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level ${progress.level}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isMax
                          ? '${controller.profileXp} total XP • Maximum configured level'
                          : '${progress.earnedWithinLevel}/${progress.requiredWithinLevel} XP to next level • ${controller.profileXp} total',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: isMax ? 1 : progress.fraction,
                        minHeight: 8,
                        backgroundColor: Colors.white.withOpacity(0.06),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.blueBright,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            'Rewards are calculated from one central configuration (v${controller.progressionConfig.version}). Sandbox rewards are ${controller.progressionConfig.sandboxRewardsEnabled ? 'enabled' : 'disabled'}.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.34),
              fontSize: 9,
              height: 1.35,
            ),
          ),
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
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.blueBright),
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
              _HistoryRow(entry: history[index], userId: userId),
              if (index != history.length - 1) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final MatchHistoryEntry entry;
  final String userId;

  const _HistoryRow({required this.entry, required this.userId});

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
                  '${_boardName(entry.boardId)} \u2022 ${entry.playerCount} players \u2022 ${_formatDuration(entry.duration)}',
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
            style: const TextStyle(color: Colors.white38, fontSize: 9),
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
    return LudoBoardThemeResolver.displayNameFor(boardId);
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
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 10),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
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
