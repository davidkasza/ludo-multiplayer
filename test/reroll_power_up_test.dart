import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/game/reroll_power_up.dart';
import 'package:ludo_game/models/ludo_models.dart';

const _testPricing = RerollPricing(
  costs: <int>[11, 17, 23],
  maxUsesPerMatch: 3,
);

Map<String, dynamic> _playingGame({
  String turnPhase = LudoGame.waitingForRerollDecision,
  Map<String, int> rerollsUsed = const <String, int>{},
  Map<String, dynamic>? rerollConfig,
}) {
  final pieces = List.generate(
    4,
    (index) => {'id': index + 1, 'pos': -1, 'inHome': false},
  );
  return {
    'players': ['a', 'b'],
    'playerNames': {'a': 'A', 'b': 'B'},
    'playerSeats': {'a': 0, 'b': 2},
    'pieces': {'a': pieces, 'b': pieces},
    'currentTurn': 'a',
    'diceValue': 1,
    'hasRolled': true,
    'status': 'playing',
    'turnPhase': turnPhase,
    'turnVersion': 4,
    'turnStartedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
    'turnDurationSeconds': 30,
    'rerollAvailableAt': Timestamp.fromMillisecondsSinceEpoch(1800),
    'rerollDeadlineAt': Timestamp.fromMillisecondsSinceEpoch(4800),
    'rerollConfig': rerollConfig ?? _testPricing.toMap(),
    'rerollsUsed': rerollsUsed,
    'activeDiceRoll': {
      'actionId': 'roll_action_1',
      'turnVersion': 4,
      'playerId': 'a',
      'startedAt': 1000,
      'durationMs': 800,
      'result': 1,
      'stateApplied': true,
    },
  };
}

void main() {
  group('Reroll pricing', () {
    test('uses the server-authored snapshot instead of Flutter defaults', () {
      final game = LudoGame.fromMap(
        _playingGame(
          rerollConfig: const <String, dynamic>{
            'costs': <int>[41, 57],
            'maxUsesPerMatch': 2,
          },
          rerollsUsed: const {'a': 1},
        ),
      );
      expect(game.rerollCostFor('a'), 57);
      expect(game.rerollPricing?.maxUsesPerMatch, 2);
    });

    test('a new match displays its first server-configured price', () {
      final game = LudoGame.fromMap(_playingGame());
      expect(game.rerollsUsedBy('a'), 0);
      expect(game.rerollCostFor('a'), 11);
    });

    test('missing or malformed pricing cannot invent a client price', () {
      final missing = _playingGame()..remove('rerollConfig');
      final malformed = _playingGame(
        rerollConfig: const <String, dynamic>{
          'costs': <int>[11, 17],
          'maxUsesPerMatch': 3,
        },
      );
      expect(LudoGame.fromMap(missing).rerollCostFor('a'), isNull);
      expect(LudoGame.fromMap(malformed).rerollCostFor('a'), isNull);
    });
  });

  group('Reroll presentation policy', () {
    test('allows an eligible local human action', () {
      expect(
        rerollAvailability(
          isActionContext: true,
          isHumanControlled: true,
          isDiceRolling: false,
          requestPending: false,
          isWindowOpen: true,
          pricing: _testPricing,
          uses: 1,
          coins: 60,
        ),
        RerollAvailability.available,
      );
    });

    test('reports coin, limit, AI, and rolling restrictions', () {
      expect(
        rerollAvailability(
          isActionContext: true,
          isHumanControlled: true,
          isDiceRolling: false,
          requestPending: false,
          isWindowOpen: true,
          pricing: _testPricing,
          uses: 0,
          coins: 10,
        ),
        RerollAvailability.insufficientCoins,
      );
      expect(
        rerollAvailability(
          isActionContext: true,
          isHumanControlled: true,
          isDiceRolling: false,
          requestPending: false,
          isWindowOpen: true,
          pricing: _testPricing,
          uses: 3,
          coins: 999,
        ),
        RerollAvailability.limitReached,
      );
      expect(
        rerollAvailability(
          isActionContext: true,
          isHumanControlled: false,
          isDiceRolling: false,
          requestPending: false,
          isWindowOpen: true,
          pricing: _testPricing,
          uses: 0,
          coins: 999,
        ),
        RerollAvailability.aiControlled,
      );
      expect(
        rerollAvailability(
          isActionContext: true,
          isHumanControlled: true,
          isDiceRolling: true,
          requestPending: false,
          isWindowOpen: true,
          pricing: _testPricing,
          uses: 0,
          coins: 999,
        ),
        RerollAvailability.rolling,
      );
    });

    test('requires the server-authored interaction window to be open', () {
      expect(
        rerollAvailability(
          isActionContext: true,
          isHumanControlled: true,
          isDiceRolling: false,
          requestPending: false,
          isWindowOpen: false,
          pricing: _testPricing,
          uses: 0,
          coins: 999,
        ),
        RerollAvailability.unavailableContext,
      );
      expect(
        isRerollWindowOpen(
          availableAt: DateTime.fromMillisecondsSinceEpoch(1800),
          deadlineAt: DateTime.fromMillisecondsSinceEpoch(4800),
          now: DateTime.fromMillisecondsSinceEpoch(4799),
        ),
        isTrue,
      );
      expect(
        isRerollWindowOpen(
          availableAt: DateTime.fromMillisecondsSinceEpoch(1800),
          deadlineAt: DateTime.fromMillisecondsSinceEpoch(4800),
          now: DateTime.fromMillisecondsSinceEpoch(4800),
        ),
        isFalse,
      );
    });

    test('hides local action for remote, AI, or committed-move contexts', () {
      expect(
        rerollAvailability(
          isActionContext: false,
          isHumanControlled: true,
          isDiceRolling: false,
          requestPending: false,
          isWindowOpen: true,
          pricing: _testPricing,
          uses: 0,
          coins: 999,
        ),
        RerollAvailability.unavailableContext,
      );
      expect(
        rerollAvailability(
          isActionContext: true,
          isHumanControlled: false,
          isDiceRolling: false,
          requestPending: false,
          isWindowOpen: true,
          pricing: _testPricing,
          uses: 0,
          coins: 999,
        ),
        RerollAvailability.aiControlled,
      );
      expect(
        rerollAvailability(
          isActionContext: true,
          isHumanControlled: true,
          isDiceRolling: false,
          requestPending: true,
          isWindowOpen: true,
          pricing: _testPricing,
          uses: 0,
          coins: 999,
        ),
        RerollAvailability.requestPending,
      );
    });
  });

  test('reconnect parsing preserves the no-move decision and usage', () {
    final game = LudoGame.fromMap(_playingGame(rerollsUsed: const {'a': 2}));
    expect(game.turnPhase, LudoGame.waitingForRerollDecision);
    expect(game.diceValue, 1);
    expect(game.hasRolled, isTrue);
    expect(game.rerollsUsedBy('a'), 2);
    expect(game.rerollCostFor('a'), 23);
    expect(game.effectiveTurnDeadline!.millisecondsSinceEpoch, 31000);

    final restored = LudoGame.fromMap(game.toMap());
    expect(restored.turnPhase, LudoGame.waitingForRerollDecision);
    expect(restored.rerollsUsedBy('a'), 2);
  });

  test('malformed usage is ignored without granting extra Rerolls', () {
    final map = _playingGame();
    map['rerollsUsed'] = {'a': 99, 'b': -1, 'outsider': 2};
    final game = LudoGame.fromMap(map);
    expect(game.rerollsUsed, isEmpty);
  });
}
