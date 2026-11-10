import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiabanwang/screens/time_picker_dialog.dart';
import 'package:xiabanwang/theme.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    ValueChanged<TimeOfDay?> result,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: commuteTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result(
                await pickReminderTime(
                  context,
                  initialTime: const TimeOfDay(hour: 19, minute: 7),
                  title: '开始时间',
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  final hour = find.byKey(const ValueKey('time-hour'));
  final minute = find.byKey(const ValueKey('time-minute'));

  testWidgets(
    'preserves exact minutes and keyboard selects bounded 24-hour times',
    (tester) async {
      TimeOfDay? result;
      await open(tester, (value) => result = value);
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result, const TimeOfDay(hour: 19, minute: 7));
      for (final end in [false, true]) {
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        for (final wheel in [hour, minute]) {
          await tester.tapAt(tester.getCenter(wheel));
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(
            end ? LogicalKeyboardKey.end : LogicalKeyboardKey.home,
          );
          await tester.sendKeyEvent(
            end ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp,
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();
        expect(
          result,
          end
              ? const TimeOfDay(hour: 23, minute: 59)
              : const TimeOfDay(hour: 0, minute: 0),
        );
      }
    },
  );

  testWidgets('touch scroll changes selected hour and cancel discards it', (
    tester,
  ) async {
    var completed = false;
    TimeOfDay? result;
    await open(tester, (value) {
      completed = true;
      result = value;
    });
    await tester.drag(hour, const Offset(0, -96));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CupertinoPicker>(hour).scrollController!.selectedItem,
      greaterThan(19),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CupertinoPicker>(hour).scrollController!.selectedItem,
      19,
    );
  });

  testWidgets('desktop wheel, mouse drag and click select values', (
    tester,
  ) async {
    TimeOfDay? result;
    await open(tester, (value) => result = value);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(minute),
        scrollDelta: const Offset(0, 48),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<CupertinoPicker>(minute).scrollController!.selectedItem,
      8,
    );
    await tester.drag(
      hour,
      const Offset(0, -48),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<CupertinoPicker>(hour).scrollController!.selectedItem,
      greaterThan(19),
    );
    final nine = find.descendant(of: minute, matching: find.text('09'));
    await tester.tap(nine);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result!.minute, 9);
  });

  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets('quick minutes and confirm fit large text at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      TimeOfDay? result;
      await open(tester, (value) => result = value);
      final quick = find.widgetWithText(ChoiceChip, '45');
      await tester.ensureVisible(quick);
      await tester.tap(quick);
      // Confirm immediately: a shortcut must not return a stale animated value.
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result, const TimeOfDay(hour: 19, minute: 45));
      expect(tester.takeException(), isNull);
    });
  }
}
