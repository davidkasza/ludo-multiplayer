import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/game/dice_skin.dart';
import 'package:ludo_game/models/ludo_models.dart';
import 'package:ludo_game/models/profile_models.dart';

void main() {
  group('dice skin resolution', () {
    test('resolves every stable persisted ID', () {
      expect(DiceSkinResolver.availableSkins.map((skin) => skin.id), [
        'classic',
        'obsidian',
        'ocean',
        'ruby',
        'emerald',
        'gold',
      ]);

      for (final skin in DiceSkinResolver.availableSkins) {
        expect(DiceSkinResolver.resolve(skin.id), same(skin));
        expect(
          DiceSkinResolver.resolve(' ${skin.id.toUpperCase()} '),
          same(skin),
        );
      }
    });

    test('falls back to Classic White for malformed or unknown IDs', () {
      for (final id in <String?>[null, '', 'unknown', 'ocean-blue', '42']) {
        expect(DiceSkinResolver.resolve(id), same(DiceSkinResolver.classic));
        expect(DiceSkinResolver.normalizeId(id), DiceSkinResolver.classicId);
      }

      final profile = PlayerProfile.fromMap('uid', {
        'diceSkinId': <String>['not', 'a', 'string'],
      });
      expect(profile.preferredDiceSkinId, DiceSkinResolver.classicId);
    });

    test('keeps pips readable for every initial material', () {
      for (final skin in DiceSkinResolver.availableSkins) {
        final face = Color.lerp(skin.faceStart, skin.faceEnd, 0.5)!;
        expect(
          _contrastRatio(face, skin.pip),
          greaterThan(3),
          reason: '${skin.displayName} needs clear pip contrast',
        );
      }
    });
  });

  group('room dice skin metadata', () {
    test('create metadata uses preference and deterministic bot fallback', () {
      final metadata = DiceSkinResolver.normalizePlayerMap(
        const {'host': 'obsidian', 'bot_2': 'ruby'},
        const ['host', 'bot_2'],
      );

      expect(metadata, const {'host': 'obsidian', 'bot_2': 'classic'});
    });

    test('join metadata adds the joining player without changing the host', () {
      final metadata = DiceSkinResolver.withPlayer(
        const {'host': 'obsidian'},
        playerIds: const ['host', 'guest'],
        playerId: 'guest',
        skinId: 'ocean',
      );

      expect(metadata, const {'host': 'obsidian', 'guest': 'ocean'});
    });

    test('different players resolve their own snapshot cosmetics', () {
      final game = LudoGame.fromMap({
        'players': ['a', 'b'],
        'status': 'waiting',
        'playerDiceSkins': {'a': 'ruby', 'b': 'emerald'},
      });

      expect(game.diceSkinIdForPlayer('a'), DiceSkinResolver.rubyId);
      expect(game.diceSkinIdForPlayer('b'), DiceSkinResolver.emeraldId);
    });

    test('ActiveDiceRoll player ID selects the rolling player skin', () {
      final game = LudoGame.fromMap({
        'players': ['a', 'b'],
        'status': 'waiting',
        'playerDiceSkins': {'a': 'obsidian', 'b': 'ocean'},
        'activeDiceRoll': {
          'actionId': 'roll-1',
          'playerId': 'b',
          'startedAt': 1,
          'durationMs': 800,
          'result': 4,
          'stateApplied': true,
        },
      });

      final rollingPlayerId = game.activeDiceRoll!.playerId;
      expect(
        DiceSkinResolver.forPlayer(game.playerDiceSkins, rollingPlayerId),
        same(DiceSkinResolver.ocean),
      );
    });

    test('legacy rooms and reconnect serialization remain safe', () {
      final legacy = LudoGame.fromMap({
        'players': ['a', 'b', 'bot_2'],
        'status': 'waiting',
      });
      expect(legacy.playerDiceSkins, {
        'a': 'classic',
        'b': 'classic',
        'bot_2': 'classic',
      });

      final restored = LudoGame.fromMap({
        ...legacy.toMap(),
        'playerDiceSkins': {'a': 'gold', 'b': 'ruby', 'bot_2': 'emerald'},
      });
      expect(restored.diceSkinIdForPlayer('a'), 'gold');
      expect(restored.diceSkinIdForPlayer('b'), 'ruby');
      expect(restored.diceSkinIdForPlayer('bot_2'), 'classic');
    });

    test('roll descriptors do not duplicate skin metadata', () {
      const roll = ActiveDiceRoll(
        actionId: 'roll-1',
        playerId: 'a',
        startedAt: 1,
        durationMs: 800,
        result: 6,
        stateApplied: true,
      );

      expect(roll.toMap(), isNot(contains('diceSkinId')));
      expect(roll.toMap(), isNot(contains('skin')));
    });
  });
}

double _contrastRatio(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final darker = identical(lighter, first) ? second : first;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
