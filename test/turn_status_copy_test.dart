import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('turn card omits redundant action narration', () {
    final source = File(
      'lib/components/game_controls/turn_status_card.dart',
    ).readAsStringSync();

    for (final redundantCopy in const [
      'Rolling the dice',
      'is rolling',
      'You rolled',
      'is moving',
      'Moving your piece',
      'Waiting for a piece selection',
      'Waiting for the other player to roll',
      'AI is playing for',
    ]) {
      expect(source, isNot(contains(redundantCopy)));
    }
  });

  test('exceptional connection and AI takeover messages remain visible', () {
    final gameScreen = File('lib/screens/game_screen.dart').readAsStringSync();
    final presence = File(
      'lib/controllers/mixins/ludo_presence_mixin.dart',
    ).readAsStringSync();
    final roomController = File(
      'lib/controllers/mixins/ludo_room_mixin.dart',
    ).readAsStringSync();

    expect(gameScreen, contains('AI is currently playing for you'));
    expect(gameScreen, contains('Control will return after this AI action'));
    expect(presence, contains('Reconnecting'));
    expect(presence, contains('Forfeited'));
    expect(roomController, contains('Connection lost. Reconnecting'));
  });
}
