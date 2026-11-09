import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiabanwang/api.dart';
import 'package:xiabanwang/demo.dart';
import 'package:xiabanwang/main.dart';

void main() {
  test('arrival selection excludes passed and unknown vehicles; stale data is detected', () {
    final data = <String, dynamic>{
      'buses': [
        {'stationsAway': -1},
        {'id': 'unknown'},
        {'id': 'next', 'stationsAway': 2},
        {'id': 'later', 'stationsAway': 5},
      ],
      'fetchedAt': '2026-11-03T09:00:00Z',
    };
    expect(nearestBus(data)?['id'], 'next');
    expect(isStale(data, now: DateTime.parse('2026-11-03T09:03:00Z')), isTrue);
    expect(isStale(data, now: DateTime.parse('2026-11-03T09:01:00Z')), isFalse);
  });

  testWidgets('reminder menu pauses today without losing the rule', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = DemoApi(latency: Duration.zero);
    await tester.pumpWidget(CommuteApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('常用线路'), findsOneWidget);
    expect(find.text('北海北门 上车'), findsNothing);
    expect(find.text('界面预览 · 演示数据，不发送通知'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('tab-reminders')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reminder-more-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('今天暂停，明天继续'));
    await tester.tap(find.text('今天暂停，明天继续'));
    await tester.pumpAndSettle();
    expect(pausedToday(api.reminders.first), isTrue);
    expect(api.reminders.first['active'], 1);
    expect(find.text('今天暂停 · 明天恢复'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'three-step creation saves chosen stop, threshold and workday schedule',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DemoApi(latency: Duration.zero);
      await tester.pumpWidget(CommuteApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-reminders')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加通勤提醒'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '107');
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('107 路').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('鼓楼'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('多一站'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存提醒'));
      await tester.tap(find.text('保存提醒'));
      await tester.pumpAndSettle();
      expect(api.reminders.last['target_stop_id'], 'stop-3');
      expect(api.reminders.last['stations_before'], 4);
      expect(api.reminders.last['schedule_mode'], 'custom');
      expect(api.reminders.last['schedule_weekdays_mask'], 31);
      expect(api.reminders.last['window_start'], '17:30');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('compact display remains readable with larger system text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(CommuteApp(api: DemoApi(latency: Duration.zero)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
