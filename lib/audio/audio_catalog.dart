import '../game/ludo_board_theme.dart';

enum MusicContext { menu, classic, auroraCircuit, solarisTemple }

class AudioCreditEntry {
  final String assetPath;
  final String title;
  final String author;
  final String sourceUrl;
  final String licenseName;
  final String licenseUrl;
  final String intendedUse;
  final bool attributionRequired;

  const AudioCreditEntry({
    required this.assetPath,
    required this.title,
    required this.author,
    required this.sourceUrl,
    required this.licenseName,
    required this.licenseUrl,
    required this.intendedUse,
    required this.attributionRequired,
  });
}

/// Static presentation metadata for bundled audio.
///
/// Asset paths intentionally preserve the original filenames supplied with the
/// project. Audio selection is local-only and never enters game state.
abstract final class AudioCatalog {
  static const String menuMusicAsset =
      'assets/audio/music/Ove Melaa - Supa Powa Loop A - open theme.mp3';
  static const String classicMusicAsset =
      'assets/audio/music/OveMelaa - Trance Bit Bit Loop - classic.ogg';
  static const String auroraMusicAsset =
      'assets/audio/music/Ove Melaa - Tube Ambient Loop - aurora.ogg';
  static const String solarisMusicAsset =
      'assets/audio/music/Ove Melaa - DrumLoop 1 64BPM - solaris_temple.mp3';
  static const String diceSfxAsset = 'assets/audio/sfx/dice-17 - dice.wav';

  static const int diceSfxDurationMs = 1032;

  static const String musicSourceUrl =
      'https://opengameart.org/content/'
      'oves-essential-game-audio-pack-collection-160-files-updated';
  static const String musicLicenseUrl =
      'https://creativecommons.org/licenses/by/3.0/';
  static const String diceSourceUrl =
      'https://opengameart.org/content/2-dice-roll-29-throws';
  static const String diceLicenseUrl =
      'https://creativecommons.org/publicdomain/zero/1.0/';

  static const List<AudioCreditEntry> musicCredits = [
    AudioCreditEntry(
      assetPath: menuMusicAsset,
      title: 'Supa Powa Loop A',
      author: 'Ove Melaa',
      sourceUrl: musicSourceUrl,
      licenseName: 'CC BY 3.0',
      licenseUrl: musicLicenseUrl,
      intendedUse: 'Menu, lobby, profile, customization and waiting rooms',
      attributionRequired: true,
    ),
    AudioCreditEntry(
      assetPath: classicMusicAsset,
      title: 'Trance Bit Bit Loop',
      author: 'Ove Melaa',
      sourceUrl: musicSourceUrl,
      licenseName: 'CC BY 3.0',
      licenseUrl: musicLicenseUrl,
      intendedUse: 'Classic board match music',
      attributionRequired: true,
    ),
    AudioCreditEntry(
      assetPath: auroraMusicAsset,
      title: 'Tube Ambient Loop',
      author: 'Ove Melaa',
      sourceUrl: musicSourceUrl,
      licenseName: 'CC BY 3.0',
      licenseUrl: musicLicenseUrl,
      intendedUse: 'Aurora Circuit board match music',
      attributionRequired: true,
    ),
    AudioCreditEntry(
      assetPath: solarisMusicAsset,
      title: 'DrumLoop 1 64BPM',
      author: 'Ove Melaa',
      sourceUrl: musicSourceUrl,
      licenseName: 'CC BY 3.0',
      licenseUrl: musicLicenseUrl,
      intendedUse: 'Solaris Temple board match music',
      attributionRequired: true,
    ),
  ];

  static const AudioCreditEntry diceCredit = AudioCreditEntry(
    assetPath: diceSfxAsset,
    title: '2 dice roll (29 throws)',
    author: 'RPG',
    sourceUrl: diceSourceUrl,
    licenseName: 'CC0 1.0',
    licenseUrl: diceLicenseUrl,
    intendedUse: 'Dice-roll presentation sound effect',
    attributionRequired: false,
  );

  static MusicContext musicContextForBoardId(String? boardId) {
    switch (LudoBoardThemeResolver.resolve(boardId).skin) {
      case LudoBoardSkin.auroraCircuit:
        return MusicContext.auroraCircuit;
      case LudoBoardSkin.solarisTemple:
        return MusicContext.solarisTemple;
      case LudoBoardSkin.nusantara:
        return MusicContext.classic;
      case LudoBoardSkin.classic:
        return MusicContext.classic;
    }
  }

  static String musicAssetFor(MusicContext context) {
    switch (context) {
      case MusicContext.menu:
        return menuMusicAsset;
      case MusicContext.classic:
        return classicMusicAsset;
      case MusicContext.auroraCircuit:
        return auroraMusicAsset;
      case MusicContext.solarisTemple:
        return solarisMusicAsset;
    }
  }

  /// `AssetSource` paths are relative to Flutter's `assets/` bundle root.
  static String sourcePathFor(String flutterAssetPath) {
    const prefix = 'assets/';
    return flutterAssetPath.startsWith(prefix)
        ? flutterAssetPath.substring(prefix.length)
        : flutterAssetPath;
  }
}
