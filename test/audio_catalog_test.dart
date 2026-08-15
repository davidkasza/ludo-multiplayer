import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/audio/audio_catalog.dart';

void main() {
  group('board music mapping', () {
    test('maps every supported board to its match music', () {
      expect(
        AudioCatalog.musicContextForBoardId('classic'),
        MusicContext.classic,
      );
      expect(
        AudioCatalog.musicContextForBoardId('auroraCircuit'),
        MusicContext.auroraCircuit,
      );
      expect(
        AudioCatalog.musicContextForBoardId('solarisTemple'),
        MusicContext.solarisTemple,
      );
      expect(
        AudioCatalog.musicContextForBoardId('nusantara'),
        MusicContext.classic,
        reason: 'Nusantara safely reuses Classic music until it has a track',
      );

      expect(
        AudioCatalog.musicAssetFor(MusicContext.menu),
        AudioCatalog.menuMusicAsset,
      );
      expect(
        AudioCatalog.musicAssetFor(MusicContext.classic),
        AudioCatalog.classicMusicAsset,
      );
      expect(
        AudioCatalog.musicAssetFor(MusicContext.auroraCircuit),
        AudioCatalog.auroraMusicAsset,
      );
      expect(
        AudioCatalog.musicAssetFor(MusicContext.solarisTemple),
        AudioCatalog.solarisMusicAsset,
      );
    });

    test('unknown and malformed board IDs use Classic music', () {
      for (final boardId in <String?>[
        null,
        '',
        'unknown',
        'aurora-circuit',
        'solaris-temple',
      ]) {
        expect(
          AudioCatalog.musicContextForBoardId(boardId),
          MusicContext.classic,
        );
      }
    });
  });

  test('catalog preserves every exact Flutter asset filename', () {
    expect(
      AudioCatalog.menuMusicAsset,
      'assets/audio/music/'
      'Ove Melaa - Supa Powa Loop A - open theme.mp3',
    );
    expect(
      AudioCatalog.classicMusicAsset,
      'assets/audio/music/'
      'OveMelaa - Trance Bit Bit Loop - classic.ogg',
    );
    expect(
      AudioCatalog.auroraMusicAsset,
      'assets/audio/music/Ove Melaa - Tube Ambient Loop - aurora.ogg',
    );
    expect(
      AudioCatalog.solarisMusicAsset,
      'assets/audio/music/'
      'Ove Melaa - DrumLoop 1 64BPM - solaris_temple.mp3',
    );
    expect(AudioCatalog.diceSfxAsset, 'assets/audio/sfx/dice-17 - dice.wav');
    expect(
      AudioCatalog.sourcePathFor(AudioCatalog.diceSfxAsset),
      'audio/sfx/dice-17 - dice.wav',
    );
  });

  test('credits describe all bundled assets and license requirements', () {
    expect(AudioCatalog.musicCredits, hasLength(4));
    expect(
      AudioCatalog.musicCredits.map((credit) => credit.assetPath).toSet(),
      {
        AudioCatalog.menuMusicAsset,
        AudioCatalog.classicMusicAsset,
        AudioCatalog.auroraMusicAsset,
        AudioCatalog.solarisMusicAsset,
      },
    );
    expect(
      AudioCatalog.musicCredits.every(
        (credit) =>
            credit.author == 'Ove Melaa' &&
            credit.licenseName == 'CC BY 3.0' &&
            credit.attributionRequired,
      ),
      isTrue,
    );
    expect(AudioCatalog.diceCredit.author, 'RPG');
    expect(AudioCatalog.diceCredit.licenseName, 'CC0 1.0');
    expect(AudioCatalog.diceCredit.attributionRequired, isFalse);
  });
}
