import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/audio/audio_preferences.dart';

void main() {
  group('audio volume parsing', () {
    test('uses moderate music and stronger SFX defaults', () {
      final settings = AudioVolumeSettings.fromStored();

      expect(settings.musicVolume, AudioVolumeSettings.defaultMusicVolume);
      expect(settings.sfxVolume, AudioVolumeSettings.defaultSfxVolume);
      expect(settings.sfxVolume, greaterThan(settings.musicVolume));
    });

    test('accepts numeric/string values and clamps to 0-1', () {
      expect(AudioVolumeSettings.fromStored(music: -4, sfx: 8).musicVolume, 0);
      expect(AudioVolumeSettings.fromStored(music: -4, sfx: 8).sfxVolume, 1);
      expect(AudioVolumeSettings.fromStored(music: '0.25').musicVolume, 0.25);
    });

    test('malformed and non-finite values fall back safely', () {
      expect(
        AudioVolumeSettings.fromStored(music: 'bad').musicVolume,
        AudioVolumeSettings.defaultMusicVolume,
      );
      expect(
        AudioVolumeSettings.fromStored(sfx: double.nan).sfxVolume,
        AudioVolumeSettings.defaultSfxVolume,
      );
      expect(
        AudioVolumeSettings.fromStored(music: double.infinity).musicVolume,
        AudioVolumeSettings.defaultMusicVolume,
      );
    });
  });
}
