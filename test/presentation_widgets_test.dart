import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/components/game_controls/rolling_dice_ui.dart';
import 'package:ludo_game/components/presentation/quick_chat_bubble.dart';
import 'package:ludo_game/components/presentation/victory_celebration.dart';
import 'package:ludo_game/game/dice_skin.dart';
import 'package:ludo_game/models/ludo_models.dart';

void main() {
  testWidgets('a freshly landed six adds restrained visual feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mediaHost(
        child: const RollingDiceUI(
          value: 6,
          isRolling: true,
          animationKey: 'roll-1',
          initialProgress: 0,
          rollDuration: Duration(milliseconds: 800),
          skin: DiceSkinResolver.classic,
        ),
      ),
    );
    expect(_customPainterNamed('_DiceSpecialPainter'), findsNothing);

    await tester.pumpWidget(
      _mediaHost(
        child: const RollingDiceUI(
          value: 6,
          isRolling: false,
          animationKey: 'roll-1',
          initialProgress: 1,
          rollDuration: Duration(milliseconds: 800),
          skin: DiceSkinResolver.classic,
        ),
      ),
    );
    await tester.pump();

    expect(_customPainterNamed('_DiceSpecialPainter'), findsOneWidget);
  });

  testWidgets('reduced motion suppresses the landed-six burst', (tester) async {
    await tester.pumpWidget(
      _mediaHost(
        disableAnimations: true,
        child: const RollingDiceUI(
          value: 6,
          isRolling: true,
          animationKey: 'roll-2',
          initialProgress: 0,
          rollDuration: Duration(milliseconds: 800),
          skin: DiceSkinResolver.classic,
        ),
      ),
    );
    await tester.pumpWidget(
      _mediaHost(
        disableAnimations: true,
        child: const RollingDiceUI(
          value: 6,
          isRolling: false,
          animationKey: 'roll-2',
          initialProgress: 1,
          rollDuration: Duration(milliseconds: 800),
          skin: DiceSkinResolver.classic,
        ),
      ),
    );

    expect(_customPainterNamed('_DiceSpecialPainter'), findsNothing);
  });

  testWidgets('enabling reduced motion stops an active dice-six burst', (
    tester,
  ) async {
    const dice = RollingDiceUI(
      value: 6,
      isRolling: false,
      animationKey: 'roll-toggle',
      initialProgress: 1,
      rollDuration: Duration(milliseconds: 800),
      skin: DiceSkinResolver.classic,
    );
    await tester.pumpWidget(
      _mediaHost(
        child: const RollingDiceUI(
          value: 6,
          isRolling: true,
          animationKey: 'roll-toggle',
          initialProgress: 0,
          rollDuration: Duration(milliseconds: 800),
          skin: DiceSkinResolver.classic,
        ),
      ),
    );
    await tester.pumpWidget(_mediaHost(child: dice));
    expect(_customPainterNamed('_DiceSpecialPainter'), findsOneWidget);

    await tester.pumpWidget(_mediaHost(disableAnimations: true, child: dice));
    expect(_customPainterNamed('_DiceSpecialPainter'), findsNothing);
  });

  testWidgets('recent quick chat appears and stale reconnect chat is skipped', (
    tester,
  ) async {
    const now = 10000;
    await tester.pumpWidget(
      _mediaHost(
        child: QuickChatBubble(
          roomId: 'room-1',
          chat: LudoChat(
            sender: 'blue',
            message: 'Good luck! 🍀',
            timestamp: now,
          ),
          nowMs: now,
          senderSeat: 0,
          senderName: 'Blue Player',
          color: Colors.blueAccent,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Blue Player'), findsOneWidget);
    expect(find.text('Good luck! 🍀'), findsOneWidget);

    await tester.pumpWidget(
      _mediaHost(
        child: QuickChatBubble(
          roomId: 'room-2',
          chat: LudoChat(
            sender: 'red',
            message: 'Old message',
            timestamp: 1000,
          ),
          nowMs: 20000,
          senderSeat: 1,
          senderName: 'Red Player',
          color: Colors.redAccent,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Old message'), findsNothing);
  });

  testWidgets(
    'reduced motion shows finished state without celebration ticker',
    (tester) async {
      await tester.pumpWidget(
        _mediaHost(
          disableAnimations: true,
          child: const VictoryCelebration(
            enabled: true,
            winnerColor: Colors.green,
            child: Text('Match complete'),
          ),
        ),
      );

      expect(find.text('Match complete'), findsOneWidget);
      expect(_customPainterNamed('_VictoryFireworksPainter'), findsNothing);
    },
  );

  testWidgets('a losing result does not create fireworks', (tester) async {
    await tester.pumpWidget(
      _mediaHost(
        child: const VictoryCelebration(
          enabled: false,
          winnerColor: Colors.red,
          child: Text('Match complete'),
        ),
      ),
    );

    expect(find.text('Match complete'), findsOneWidget);
    expect(_customPainterNamed('_VictoryFireworksPainter'), findsNothing);
  });

  testWidgets('enabling reduced motion stops an active victory ticker', (
    tester,
  ) async {
    const celebration = VictoryCelebration(
      enabled: true,
      winnerColor: Colors.green,
      child: Text('Match complete'),
    );
    await tester.pumpWidget(_mediaHost(child: celebration));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_customPainterNamed('_VictoryFireworksPainter'), findsOneWidget);

    await tester.pumpWidget(
      _mediaHost(disableAnimations: true, child: celebration),
    );
    expect(_customPainterNamed('_VictoryFireworksPainter'), findsNothing);
  });
}

Finder _customPainterNamed(String typeName) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter.runtimeType.toString() == typeName,
  );
}

Widget _mediaHost({required Widget child, bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}
