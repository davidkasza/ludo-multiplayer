import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../audio/app_audio_controller.dart';
import '../../audio/audio_catalog.dart';
import '../../theme/app_colors.dart';

class AudioSettingsPanel extends StatelessWidget {
  final AppAudioController controller;

  const AudioSettingsPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Audio',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              _VolumeSlider(
                label: 'Music',
                icon: controller.isMutedMusic
                    ? Icons.music_off_rounded
                    : Icons.music_note_rounded,
                value: controller.musicVolume,
                onChanged: (value) {
                  unawaited(controller.setMusicVolume(value, persist: false));
                },
                onChangeEnd: controller.setMusicVolume,
              ),
              _VolumeSlider(
                label: 'SFX',
                icon: controller.isMutedSfx
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                value: controller.sfxVolume,
                onChanged: (value) {
                  unawaited(controller.setSfxVolume(value, persist: false));
                },
                onChangeEnd: controller.setSfxVolume,
              ),
              const Divider(color: Colors.white12, height: 18),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => showAudioCreditsDialog(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.blueBright,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Music & Sound Credits',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: Colors.white38),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _VolumeSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 19),
        const SizedBox(width: 9),
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 1,
            divisions: 20,
            activeColor: AppColors.blueBright,
            inactiveColor: Colors.white12,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
        ),
      ],
    );
  }
}

Future<void> showAudioCreditsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: const Text(
          'Music & Sound Credits',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Ove's Essential Game Audio Pack Collection",
                  style: TextStyle(
                    color: AppColors.blueBright,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                for (final credit in AudioCatalog.musicCredits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '"${credit.title}" written and produced by '
                      '${credit.author}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                const SizedBox(height: 5),
                const Text(
                  'Licensed under CC BY 3.0',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    _CreditLink(
                      label: 'Source',
                      url: AudioCatalog.musicSourceUrl,
                    ),
                    _CreditLink(
                      label: 'CC BY 3.0 license',
                      url: AudioCatalog.musicLicenseUrl,
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 26),
                const Text(
                  'Dice sound',
                  style: TextStyle(
                    color: AppColors.blueBright,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Dice sound from "${AudioCatalog.diceCredit.title}" by '
                  '${AudioCatalog.diceCredit.author}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 5),
                const Text(
                  'CC0 1.0 — attribution is optional; included for '
                  'transparency.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    _CreditLink(
                      label: 'Source',
                      url: AudioCatalog.diceSourceUrl,
                    ),
                    _CreditLink(
                      label: 'CC0 1.0',
                      url: AudioCatalog.diceLicenseUrl,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

class _CreditLink extends StatelessWidget {
  final String label;
  final String url;

  const _CreditLink({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _openUrl(context, url),
      icon: const Icon(Icons.open_in_new_rounded, size: 14),
      label: Text(label),
    );
  }

  static Future<void> _openUrl(BuildContext context, String value) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final opened = await launchUrl(Uri.parse(value));
      if (!opened) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('Could not open this link.')),
        );
      }
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not open this link.')),
      );
    }
  }
}
