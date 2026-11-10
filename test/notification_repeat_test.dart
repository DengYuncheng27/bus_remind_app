import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiabanwang/api.dart';
import 'package:xiabanwang/demo.dart';
import 'package:xiabanwang/main.dart';

class RecordingApi extends DemoApi {
  RecordingApi() : super(latency: Duration.zero);
  Json? lastBody;
  bool failSave = false;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) {
    if (path.startsWith('/api/reminders') &&
        (method == 'POST' || method == 'PATCH')) {
      lastBody = body;
      if (failSave) throw ApiException('保存失败，请重试', 503);
    }
    return super.request(path, method: method, body: body, query: query);
  }
}

void main() {
  final interval = find.byKey(const ValueKey('notification-interval'));
  final limit = find.byKey(const ValueKey('notification-limit'));

  Future<void> edit(WidgetTester tester, RecordingApi api) async {
    await tester.pumpWidget(CommuteApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提醒设置'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(limit, 160);
  }

  Future<void> select(WidgetTester tester, Finder field, String option) async {
    await tester.scrollUntilVisible(field, 120);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'new reminder defaults to one and can select a total count directly',
    (tester) async {
      final api = RecordingApi();
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
      await tester.scrollUntilVisible(limit, 160);
      expect(find.text('1 次'), findsOneWidget);
      expect(find.text('再次提醒'), findsNothing);
      expect(interval, findsNothing);
      await select(tester, limit, '3 次');
      await tester.tap(find.text('保存提醒'));
      await tester.pumpAndSettle();
      expect(api.lastBody!['repeatIntervalMinutes'], 2);
      expect(api.lastBody!['maxNotificationsPerBus'], 3);
      expect(api.reminders.last['max_notifications_per_bus'], 3);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'existing limits are preserved and selecting one hides the interval',
    (tester) async {
      final api = RecordingApi();
      api.reminders.first.addAll({
        'repeat_interval_minutes': 60,
        'max_notifications_per_bus': 10,
      });
      await edit(tester, api);
      await tester.scrollUntilVisible(interval, 120);
      expect(find.text('每隔 60 分钟'), findsOneWidget);
      await tester.scrollUntilVisible(limit, 120);
      expect(find.text('10 次'), findsOneWidget);
      await tester.tap(find.text('保存提醒'));
      await tester.pumpAndSettle();
      expect(api.lastBody!['repeatIntervalMinutes'], 60);
      expect(api.lastBody!['maxNotificationsPerBus'], 10);
      await tester.tap(find.text('提醒设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(limit, 160);
      await select(tester, limit, '1 次');
      expect(interval, findsNothing);
      await tester.tap(find.text('保存提醒'));
      await tester.pumpAndSettle();
      expect(api.lastBody!['maxNotificationsPerBus'], 1);
      expect(api.lastBody!['repeatIntervalMinutes'], 60);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'changed repeat settings survive save failure and reload on a small display',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = RecordingApi();
      await edit(tester, api);
      await select(tester, limit, '4 次');
      await select(tester, interval, '每隔 5 分钟');
      api.failSave = true;
      await tester.tap(find.text('保存提醒'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(interval, 120);
      expect(find.text('每隔 5 分钟'), findsOneWidget);
      await tester.scrollUntilVisible(limit, 120);
      expect(find.text('4 次'), findsOneWidget);
      api.failSave = false;
      await tester.tap(find.text('保存提醒'));
      await tester.pumpAndSettle();
      expect(api.lastBody!['repeatIntervalMinutes'], 5);
      expect(api.lastBody!['maxNotificationsPerBus'], 4);
      await tester.tap(find.text('提醒设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(limit, 160);
      await tester.scrollUntilVisible(interval, 120);
      expect(find.text('每隔 5 分钟'), findsOneWidget);
      await tester.scrollUntilVisible(limit, 120);
      expect(find.text('4 次'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
