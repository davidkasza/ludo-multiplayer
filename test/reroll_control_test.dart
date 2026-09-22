import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/components/game_controls/reroll_control.dart';
import 'package:ludo_game/components/painters/board_painters.dart';
import 'package:ludo_game/components/waiting_room/board_style_selector.dart';
import 'package:ludo_game/game/ludo_board_theme.dart';

Widget _host(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    builder: (context, appChild) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: appChild!,
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

CompactRerollAction _action({
  int price = 57,
  Future<String?> Function()? onPressed,
}) {
  final start = DateTime.fromMillisecondsSinceEpoch(1000);
  return CompactRerollAction(
    actionKey: 'roll_action_1',
    price: price,
    availableAt: start,
    deadlineAt: start.add(const Duration(seconds: 3)),
    serverNow: start,
    onPressed: onPressed ?? () async => null,
  );
}

void main() {
  testWidgets('Reroll visibility does not change the board layout', (
    tester,
  ) async {
    Widget layout({required bool showReroll}) {
      return SizedBox(
        width: 320,
        height: 420,
        child: Column(
          children: [
            const Expanded(
              child: ColoredBox(
                key: ValueKey('board-area'),
                color: Colors.black,
              ),
            ),
            TurnActionSlot(
              dice: const SizedBox.square(dimension: 42),
              reroll: showReroll ? _action() : null,
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(_host(layout(showReroll: false)));
    final boardWithoutReroll = tester.getRect(
      find.byKey(const ValueKey('board-area')),
    );
    final slotWithoutReroll = tester.getSize(
      find.byKey(const ValueKey('turn-action-slot')),
    );

    await tester.pumpWidget(_host(layout(showReroll: true)));
    final boardWithReroll = tester.getRect(
      find.byKey(const ValueKey('board-area')),
    );
    final slotWithReroll = tester.getSize(
      find.byKey(const ValueKey('turn-action-slot')),
    );

    expect(boardWithReroll, boardWithoutReroll);
    expect(slotWithReroll, slotWithoutReroll);
  });

  testWidgets('shows server price and expires after three seconds', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_action(price: 73)));
    expect(find.text('↻ 73'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);

    await tester.pump(const Duration(milliseconds: 2999));
    expect(find.byKey(const ValueKey('reroll-action')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2));
    expect(find.byKey(const ValueKey('reroll-action')), findsNothing);
  });

  testWidgets('successful Reroll dismisses quietly', (tester) async {
    await tester.pumpWidget(_host(_action()));
    await tester.tap(find.text('↻ 57'));
    await tester.pump();

    expect(find.byKey(const ValueKey('reroll-action')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('only an abnormal Reroll failure shows an error', (tester) async {
    await tester.pumpWidget(
      _host(_action(onPressed: () async => 'Could not use Reroll.')),
    );
    await tester.tap(find.text('↻ 57'));
    await tester.pump();

    expect(find.text('Could not use Reroll.'), findsOneWidget);
  });

  testWidgets('reduced motion keeps static action timing', (tester) async {
    await tester.pumpWidget(_host(_action(), reduceMotion: true));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('reroll-action')), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('reroll-action')), findsNothing);
  });

  testWidgets('board style selector uses all existing board painters', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 380,
          child: BoardStyleSelector(
            selectedBoardId: LudoBoardThemeResolver.classicId,
            enabled: true,
            seatColorIds: const ['blue', 'red', 'green', 'yellow'],
            maxPlayers: 2,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('Board style'), findsOneWidget);
    for (final painterType in [
      StaticBoardPainter,
      AuroraCircuitBoardPainter,
      SolarisTempleBoardPainter,
      NusantaraBoardPainter,
    ]) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter.runtimeType == painterType,
        ),
        findsOneWidget,
      );
    }
    await tester.drag(find.byType(ListView), const Offset(-280, 0));
    await tester.pump();
    await tester.tap(find.text('Nusantara'));
    expect(selected, LudoBoardThemeResolver.nusantaraId);
  });
}
