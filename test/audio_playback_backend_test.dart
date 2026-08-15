import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/audio/audio_playback_backend.dart';

void main() {
  group('Android game audio focus policy', () {
    test('background music keeps normal long-lived focus', () {
      expect(
        GameAudioContexts.musicAndroid.contentType,
        AndroidContentType.music,
      );
      expect(GameAudioContexts.musicAndroid.usageType, AndroidUsageType.media);
      expect(GameAudioContexts.musicAndroid.audioFocus, AndroidAudioFocus.gain);
    });

    test('gameplay SFX mixes without taking focus from music', () {
      expect(
        GameAudioContexts.sfxAndroid.contentType,
        AndroidContentType.sonification,
      );
      expect(GameAudioContexts.sfxAndroid.usageType, AndroidUsageType.game);
      expect(GameAudioContexts.sfxAndroid.audioFocus, AndroidAudioFocus.none);
    });
  });
}
