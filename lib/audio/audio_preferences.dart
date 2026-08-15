import 'package:shared_preferences/shared_preferences.dart';

class AudioVolumeSettings {
  static const double defaultMusicVolume = 0.38;
  static const double defaultSfxVolume = 0.82;

  final double musicVolume;
  final double sfxVolume;

  const AudioVolumeSettings({
    required this.musicVolume,
    required this.sfxVolume,
  });

  factory AudioVolumeSettings.fromStored({Object? music, Object? sfx}) {
    return AudioVolumeSettings(
      musicVolume: normalize(music, fallback: defaultMusicVolume),
      sfxVolume: normalize(sfx, fallback: defaultSfxVolume),
    );
  }

  static double normalize(Object? value, {required double fallback}) {
    final parsed = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text),
      _ => null,
    };
    if (parsed == null || !parsed.isFinite) return fallback;
    return parsed.clamp(0.0, 1.0).toDouble();
  }
}

abstract interface class AudioPreferencesStore {
  Future<AudioVolumeSettings> load();

  Future<void> saveMusicVolume(double value);

  Future<void> saveSfxVolume(double value);
}

class SharedPreferencesAudioStore implements AudioPreferencesStore {
  static const String musicVolumeKey = 'ludora.audio.musicVolume';
  static const String sfxVolumeKey = 'ludora.audio.sfxVolume';

  final SharedPreferencesAsync _preferences;

  SharedPreferencesAudioStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  @override
  Future<AudioVolumeSettings> load() async {
    final values = await Future.wait<Object?>([
      _preferences.getDouble(musicVolumeKey),
      _preferences.getDouble(sfxVolumeKey),
    ]);
    return AudioVolumeSettings.fromStored(music: values[0], sfx: values[1]);
  }

  @override
  Future<void> saveMusicVolume(double value) {
    return _preferences.setDouble(
      musicVolumeKey,
      AudioVolumeSettings.normalize(
        value,
        fallback: AudioVolumeSettings.defaultMusicVolume,
      ),
    );
  }

  @override
  Future<void> saveSfxVolume(double value) {
    return _preferences.setDouble(
      sfxVolumeKey,
      AudioVolumeSettings.normalize(
        value,
        fallback: AudioVolumeSettings.defaultSfxVolume,
      ),
    );
  }
}
