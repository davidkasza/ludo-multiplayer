import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'audio_catalog.dart';
import 'audio_playback_backend.dart';
import 'audio_preferences.dart';

typedef AudioDelay = Future<void> Function(Duration duration);

/// Owns the app's only background-music player and presentation SFX player.
///
/// The controller consumes local presentation state only. It never reads from
/// or writes to Firebase and authoritative gameplay never waits for audio.
class AppAudioController extends ChangeNotifier with WidgetsBindingObserver {
  static const Duration fadeOutDuration = Duration(milliseconds: 180);
  static const Duration fadeInDuration = Duration(milliseconds: 280);
  static const int _fadeSteps = 5;
  static const int _rememberedDiceActions = 64;

  final AudioPlaybackBackend _backend;
  final AudioPreferencesStore _preferences;
  final AudioDelay _delay;
  final Set<String> _playedDiceActionKeys = <String>{};
  final Queue<String> _playedDiceActionOrder = Queue<String>();

  double _musicVolume = AudioVolumeSettings.defaultMusicVolume;
  double _sfxVolume = AudioVolumeSettings.defaultSfxVolume;
  double _appliedMusicVolume = 0;
  MusicContext _desiredContext = MusicContext.menu;
  MusicContext? _activeContext;
  bool _initialized = false;
  bool _musicStarted = false;
  bool _transitioning = false;
  bool _lifecycleSuspended = false;
  bool _waitingForUserGesture = false;
  bool _disposed = false;

  AppAudioController({
    AudioPlaybackBackend? backend,
    AudioPreferencesStore? preferences,
    AudioDelay? delay,
  }) : _backend = backend ?? AudioplayersPlaybackBackend(),
       _preferences = preferences ?? SharedPreferencesAudioStore(),
       _delay = delay ?? Future<void>.delayed;

  double get musicVolume => _musicVolume;
  double get sfxVolume => _sfxVolume;
  MusicContext? get activeContext => _activeContext;
  MusicContext get desiredContext => _desiredContext;
  bool get isMutedMusic => _musicVolume == 0;
  bool get isMutedSfx => _sfxVolume == 0;

  Future<void> initialize({
    MusicContext initialContext = MusicContext.menu,
  }) async {
    if (_initialized || _disposed) return;

    _desiredContext = initialContext;
    try {
      final settings = await _preferences.load();
      _musicVolume = settings.musicVolume;
      _sfxVolume = settings.sfxVolume;
    } catch (error) {
      debugPrint('Could not load local audio preferences: $error');
    }

    if (_disposed) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
    await _runPendingTransition();
  }

  Future<void> setMusicContext(MusicContext context) async {
    if (_disposed) return;
    _desiredContext = context;
    if (!_initialized || _lifecycleSuspended || _waitingForUserGesture) return;
    await _runPendingTransition();
  }

  Future<void> handleUserInteraction() async {
    if (!_initialized || _disposed || _lifecycleSuspended) return;
    if (_waitingForUserGesture) _waitingForUserGesture = false;
    await _runPendingTransition();
  }

  Future<void> setMusicVolume(double value, {bool persist = true}) async {
    final normalized = AudioVolumeSettings.normalize(
      value,
      fallback: AudioVolumeSettings.defaultMusicVolume,
    );
    final changed = normalized != _musicVolume;
    _musicVolume = normalized;
    if (changed && !_disposed) notifyListeners();

    if (_musicStarted && !_lifecycleSuspended && !_disposed) {
      try {
        await _backend.setMusicVolume(normalized);
        _appliedMusicVolume = normalized;
      } catch (error) {
        debugPrint('Could not update music volume: $error');
      }
    }
    if (persist) await _saveMusicVolume(normalized);
  }

  Future<void> setSfxVolume(double value, {bool persist = true}) async {
    final normalized = AudioVolumeSettings.normalize(
      value,
      fallback: AudioVolumeSettings.defaultSfxVolume,
    );
    final changed = normalized != _sfxVolume;
    _sfxVolume = normalized;
    if (changed && !_disposed) notifyListeners();
    if (persist) await _saveSfxVolume(normalized);
  }

  /// Plays a dice sound only while the matching visual roll is in flight.
  ///
  /// Reconnected presentations seek into the sound by the already elapsed
  /// visual time. Result-hold or completed presentations are remembered but do
  /// not replay an already elapsed effect.
  Future<bool> playDiceRoll({
    required String actionKey,
    required int elapsedMs,
    required int rollDurationMs,
  }) async {
    final normalizedKey = actionKey.trim();
    if (normalizedKey.isEmpty ||
        _playedDiceActionKeys.contains(normalizedKey)) {
      return false;
    }
    if (!_initialized || _disposed) return false;
    _rememberDiceAction(normalizedKey);

    final safeRollDuration = rollDurationMs > 0 ? rollDurationMs : 800;
    final safeElapsed = elapsedMs.clamp(0, safeRollDuration).toInt();
    if (_lifecycleSuspended ||
        safeElapsed >= safeRollDuration ||
        _sfxVolume == 0) {
      return false;
    }

    final seekMs = safeElapsed.clamp(0, AudioCatalog.diceSfxDurationMs - 1);
    try {
      await _backend.playSfx(
        AudioCatalog.diceSfxAsset,
        volume: _sfxVolume,
        position: Duration(milliseconds: seekMs),
      );
      return true;
    } catch (error) {
      debugPrint('Could not play dice sound: $error');
      return false;
    }
  }

  void _rememberDiceAction(String key) {
    _playedDiceActionKeys.add(key);
    _playedDiceActionOrder.addLast(key);
    while (_playedDiceActionOrder.length > _rememberedDiceActions) {
      _playedDiceActionKeys.remove(_playedDiceActionOrder.removeFirst());
    }
  }

  Future<void> _runPendingTransition() async {
    if (_transitioning ||
        !_initialized ||
        _disposed ||
        _lifecycleSuspended ||
        _waitingForUserGesture) {
      return;
    }

    _transitioning = true;
    try {
      while (!_disposed &&
          !_lifecycleSuspended &&
          !_waitingForUserGesture &&
          (!_musicStarted || _activeContext != _desiredContext)) {
        if (_musicStarted) {
          await _fadeMusic(
            from: _appliedMusicVolume,
            to: 0,
            duration: fadeOutDuration,
          );
          await _backend.stopMusic();
          _musicStarted = false;
          _activeContext = null;
          _appliedMusicVolume = 0;
        }

        if (_disposed || _lifecycleSuspended) break;
        final target = _desiredContext;
        try {
          await _backend.playMusic(
            AudioCatalog.musicAssetFor(target),
            volume: 0,
          );
          _musicStarted = true;
          _activeContext = target;
          _appliedMusicVolume = 0;
          await _fadeMusic(from: 0, to: _musicVolume, duration: fadeInDuration);
          if (!_disposed && !_lifecycleSuspended) {
            await _backend.setMusicVolume(_musicVolume);
            _appliedMusicVolume = _musicVolume;
          }
        } catch (error) {
          _musicStarted = false;
          _activeContext = null;
          _appliedMusicVolume = 0;
          _waitingForUserGesture = true;
          debugPrint('Music playback is waiting for user interaction: $error');
        }
      }
    } finally {
      _transitioning = false;
    }

    if (!_disposed &&
        !_lifecycleSuspended &&
        !_waitingForUserGesture &&
        (!_musicStarted || _activeContext != _desiredContext)) {
      await _runPendingTransition();
    }
  }

  Future<void> _fadeMusic({
    required double from,
    required double to,
    required Duration duration,
  }) async {
    if (from == to) {
      await _backend.setMusicVolume(to);
      _appliedMusicVolume = to;
      return;
    }

    final stepDuration = Duration(
      microseconds: duration.inMicroseconds ~/ _fadeSteps,
    );
    for (var step = 1; step <= _fadeSteps; step++) {
      if (_disposed || _lifecycleSuspended) return;
      final progress = step / _fadeSteps;
      final volume = from + ((to - from) * progress);
      await _backend.setMusicVolume(volume);
      _appliedMusicVolume = volume;
      if (step != _fadeSteps) await _delay(stepDuration);
    }
  }

  Future<void> _saveMusicVolume(double value) async {
    try {
      await _preferences.saveMusicVolume(value);
    } catch (error) {
      debugPrint('Could not save local music volume: $error');
    }
  }

  Future<void> _saveSfxVolume(double value) async {
    try {
      await _preferences.saveSfxVolume(value);
    } catch (error) {
      debugPrint('Could not save local SFX volume: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeAfterLifecyclePause());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_suspendForLifecycle());
    }
  }

  Future<void> _suspendForLifecycle() async {
    if (_lifecycleSuspended || _disposed) return;
    _lifecycleSuspended = true;
    try {
      if (_musicStarted) await _backend.pauseMusic();
      await _backend.stopSfx();
    } catch (error) {
      debugPrint('Could not pause audio for app lifecycle: $error');
    }
  }

  Future<void> _resumeAfterLifecyclePause() async {
    if (!_lifecycleSuspended || _disposed) return;
    _lifecycleSuspended = false;
    if (_musicStarted && _activeContext == _desiredContext) {
      try {
        await _backend.resumeMusic();
        await _backend.setMusicVolume(_musicVolume);
        _appliedMusicVolume = _musicVolume;
        return;
      } catch (error) {
        _musicStarted = false;
        _activeContext = null;
        debugPrint('Could not resume music: $error');
      }
    }
    await _runPendingTransition();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_initialized) WidgetsBinding.instance.removeObserver(this);
    unawaited(_backend.dispose());
    super.dispose();
  }
}
