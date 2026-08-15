import 'package:audioplayers/audioplayers.dart';

import 'audio_catalog.dart';

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

  @override
  Future<void> playMusic(String assetPath, {required double volume}) async {
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
