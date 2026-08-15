import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/audio/app_audio_controller.dart';
import 'package:ludo_game/audio/audio_catalog.dart';
import 'package:ludo_game/audio/audio_playback_backend.dart';
import 'package:ludo_game/audio/audio_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAudioBackend backend;
  late _FakeAudioPreferences preferences;
  late AppAudioController controller;

  setUp(() {
    backend = _FakeAudioBackend();
    preferences = _FakeAudioPreferences();
    controller = AppAudioController(
      backend: backend,
      preferences: preferences,
      delay: (_) async {},
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('same menu context does not restart music during navigation', () async {
    await controller.initialize();
    await controller.setMusicContext(MusicContext.menu);
    await controller.setMusicContext(MusicContext.menu);

    expect(backend.playedMusic, [AudioCatalog.menuMusicAsset]);
    expect(backend.stopMusicCalls, 0);
    expect(controller.activeContext, MusicContext.menu);
  });

  test(
    'board context fades, switches once, and loops through backend',
    () async {
      await controller.initialize();
      await controller.setMusicContext(MusicContext.auroraCircuit);

      expect(backend.playedMusic, [
        AudioCatalog.menuMusicAsset,
        AudioCatalog.auroraMusicAsset,
      ]);
      expect(backend.stopMusicCalls, 1);
      expect(backend.musicVolumes, contains(0));
      expect(backend.musicVolumes.last, controller.musicVolume);
      expect(controller.activeContext, MusicContext.auroraCircuit);
    },
  );

  test(
    'volume zero mutes locally and persists without stopping music',
    () async {
      await controller.initialize();
      await controller.setMusicVolume(0);
      await controller.setSfxVolume(0);

      expect(controller.isMutedMusic, isTrue);
      expect(controller.isMutedSfx, isTrue);
      expect(backend.musicVolumes.last, 0);
      expect(backend.stopMusicCalls, 0);
      expect(preferences.savedMusic, [0]);
      expect(preferences.savedSfx, [0]);
    },
  );

  test('dice SFX uses visual elapsed time and action identity once', () async {
    await controller.initialize();

    expect(
      await controller.playDiceRoll(
        actionKey: 'room:roll-1',
        elapsedMs: 180,
        rollDurationMs: 800,
      ),
      isTrue,
    );
    expect(
      await controller.playDiceRoll(
        actionKey: 'room:roll-1',
        elapsedMs: 220,
        rollDurationMs: 800,
      ),
      isFalse,
    );

    expect(backend.playedSfx, [AudioCatalog.diceSfxAsset]);
    expect(backend.sfxPositions, [const Duration(milliseconds: 180)]);
  });

  test('dice action observed before initialization can be retried', () async {
    expect(
      await controller.playDiceRoll(
        actionKey: 'room:startup-roll',
        elapsedMs: 50,
        rollDurationMs: 800,
      ),
      isFalse,
    );

    await controller.initialize();
    expect(
      await controller.playDiceRoll(
        actionKey: 'room:startup-roll',
        elapsedMs: 80,
        rollDurationMs: 800,
      ),
      isTrue,
    );
  });

  test('reconnect skips SFX after visual roll has already landed', () async {
    await controller.initialize();

    expect(
      await controller.playDiceRoll(
        actionKey: 'room:elapsed-roll',
        elapsedMs: 800,
        rollDurationMs: 800,
      ),
      isFalse,
    );
    expect(backend.playedSfx, isEmpty);

    // Repeated snapshots cannot replay the already elapsed action.
    expect(
      await controller.playDiceRoll(
        actionKey: 'room:elapsed-roll',
        elapsedMs: 0,
        rollDurationMs: 800,
      ),
      isFalse,
    );
  });

  test('muted dice action remains deduplicated after unmuting', () async {
    await controller.initialize();
    await controller.setSfxVolume(0);

    expect(
      await controller.playDiceRoll(
        actionKey: 'room:muted-roll',
        elapsedMs: 0,
        rollDurationMs: 800,
      ),
      isFalse,
    );
    await controller.setSfxVolume(1);
    expect(
      await controller.playDiceRoll(
        actionKey: 'room:muted-roll',
        elapsedMs: 0,
        rollDurationMs: 800,
      ),
      isFalse,
    );
    expect(backend.playedSfx, isEmpty);
  });

  test('lifecycle pause and resume preserve the same music track', () async {
    await controller.initialize(initialContext: MusicContext.solarisTemple);

    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);

    expect(backend.pauseMusicCalls, 1);
    expect(backend.resumeMusicCalls, 1);
    expect(backend.playedMusic, [AudioCatalog.solarisMusicAsset]);
    expect(backend.stopSfxCalls, 1);
  });
}

class _FakeAudioPreferences implements AudioPreferencesStore {
  final List<double> savedMusic = [];
  final List<double> savedSfx = [];
  AudioVolumeSettings initial = const AudioVolumeSettings(
    musicVolume: AudioVolumeSettings.defaultMusicVolume,
    sfxVolume: AudioVolumeSettings.defaultSfxVolume,
  );

  @override
  Future<AudioVolumeSettings> load() async => initial;

  @override
  Future<void> saveMusicVolume(double value) async {
    savedMusic.add(value);
  }

  @override
  Future<void> saveSfxVolume(double value) async {
    savedSfx.add(value);
  }
}

class _FakeAudioBackend implements AudioPlaybackBackend {
  final List<String> playedMusic = [];
  final List<double> musicVolumes = [];
  final List<String> playedSfx = [];
  final List<Duration> sfxPositions = [];
  int pauseMusicCalls = 0;
  int resumeMusicCalls = 0;
  int stopMusicCalls = 0;
  int stopSfxCalls = 0;

  @override
  Future<void> playMusic(String assetPath, {required double volume}) async {
    playedMusic.add(assetPath);
    musicVolumes.add(volume);
  }

  @override
  Future<void> setMusicVolume(double volume) async {
    musicVolumes.add(volume);
  }

  @override
  Future<void> pauseMusic() async {
    pauseMusicCalls++;
  }

  @override
  Future<void> resumeMusic() async {
    resumeMusicCalls++;
  }

  @override
  Future<void> stopMusic() async {
    stopMusicCalls++;
  }

  @override
  Future<void> playSfx(
    String assetPath, {
    required double volume,
    required Duration position,
  }) async {
    playedSfx.add(assetPath);
    sfxPositions.add(position);
  }

  @override
  Future<void> stopSfx() async {
    stopSfxCalls++;
  }

  @override
  Future<void> dispose() async {}
}
