import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_catalog.dart';

/// Android playback policy for the app's two independent audio layers.
///
/// Background music owns normal long-lived audio focus. Gameplay effects use
/// no focus request so Android mixes them into the existing game audio instead
/// of sending a focus-loss event to the music player.
abstract final class GameAudioContexts {
  static const AudioContextAndroid musicAndroid = AudioContextAndroid(
    contentType: AndroidContentType.music,
    usageType: AndroidUsageType.media,
    audioFocus: AndroidAudioFocus.gain,
  );

  static const AudioContextAndroid sfxAndroid = AudioContextAndroid(
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.game,
    audioFocus: AndroidAudioFocus.none,
  );
}

abstract interface class AudioPlaybackBackend {
  Future<void> playMusic(String assetPath, {required double volume});

  Future<void> setMusicVolume(double volume);

  Future<void> pauseMusic();

  Future<void> resumeMusic();

  Future<void> stopMusic();

  Future<void> playSfx(
    String assetPath, {
    required double volume,
    required Duration position,
  });

  Future<void> stopSfx();

  Future<void> dispose();
}

class AudioplayersPlaybackBackend implements AudioPlaybackBackend {
  final AudioPlayer _musicPlayer = AudioPlayer();
  final AudioPlayer _sfxPlayer = AudioPlayer();
  bool _androidContextsConfigured = false;

  Future<void> _ensureAndroidAudioContexts() async {
    if (_androidContextsConfigured ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await _musicPlayer.setAudioContext(
      AudioContext(android: GameAudioContexts.musicAndroid),
    );
    await _sfxPlayer.setAudioContext(
      AudioContext(android: GameAudioContexts.sfxAndroid),
    );
    _androidContextsConfigured = true;
  }

  @override
  Future<void> playMusic(String assetPath, {required double volume}) async {
    await _ensureAndroidAudioContexts();
    await _musicPlayer.setReleaseMode(ReleaseMode.loop);
    await _musicPlayer.play(
      AssetSource(AudioCatalog.sourcePathFor(assetPath)),
      volume: volume,
    );
  }

  @override
  Future<void> setMusicVolume(double volume) {
    return _musicPlayer.setVolume(volume);
  }

  @override
  Future<void> pauseMusic() => _musicPlayer.pause();

  @override
  Future<void> resumeMusic() => _musicPlayer.resume();

  @override
  Future<void> stopMusic() => _musicPlayer.stop();

  @override
  Future<void> playSfx(
    String assetPath, {
    required double volume,
    required Duration position,
  }) async {
    await _ensureAndroidAudioContexts();
    await _sfxPlayer.stop();
    await _sfxPlayer.setReleaseMode(ReleaseMode.stop);
    await _sfxPlayer.play(
      AssetSource(AudioCatalog.sourcePathFor(assetPath)),
      volume: volume,
      position: position,
    );
  }

  @override
  Future<void> stopSfx() => _sfxPlayer.stop();

  @override
  Future<void> dispose() async {
    await _musicPlayer.dispose();
    await _sfxPlayer.dispose();
  }
}
