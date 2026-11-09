import 'package:flutter/material.dart';
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

  testWidgets('preserves exact minutes and accepts 24-hour boundary times', (
    tester,
  ) async {
    TimeOfDay? result;
    await open(tester, (value) => result = value);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result, const TimeOfDay(hour: 19, minute: 7));
    for (final time in [
      const TimeOfDay(hour: 0, minute: 0),
      const TimeOfDay(hour: 23, minute: 59),
    ]) {
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(hour, '${time.hour}');
      await tester.enterText(minute, '${time.minute}');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result, time);
    }
  });

  testWidgets('invalid or empty values cannot confirm; cancel discards edits', (
    tester,
  ) async {
    var completed = false;
    TimeOfDay? result;
    await open(tester, (value) {
      completed = true;
      result = value;
    });
    await tester.enterText(hour, '24');
    await tester.enterText(minute, '60');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(completed, isFalse);
    expect(find.text('请输入 00–23'), findsOneWidget);
    expect(find.text('请输入 00–59'), findsOneWidget);
    await tester.enterText(hour, '');
    await tester.enterText(minute, '');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(completed, isFalse);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
  });

  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets('quick minutes work with large text and keyboard at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      TimeOfDay? result;
      await open(tester, (value) => result = value);
      await tester.enterText(hour, '8');
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      final quick = find.widgetWithText(ChoiceChip, '45');
      await tester.ensureVisible(quick);
      await tester.tap(quick);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('确定'));
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result, const TimeOfDay(hour: 8, minute: 45));
      expect(tester.takeException(), isNull);
    });
  }
}
