import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiabanwang/api.dart';
import 'package:xiabanwang/demo.dart';
import 'package:xiabanwang/main.dart';
import 'package:xiabanwang/screens/reminder_editor.dart';

void main() {
  testWidgets(
    'switch waits for server, rejects duplicate taps and retains original state on failure',
    (tester) async {
      final api = ReminderTestApi();
      await tester.pumpWidget(CommuteApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-reminders')));
      await tester.pumpAndSettle();
      final control = find.byKey(const ValueKey('reminder-switch-1'));
      expect(tester.widget<Switch>(control).value, true);
      api.pending = Completer<void>();
      await tester.tap(control);
      await tester.pump();
      expect(tester.widget<Switch>(control).value, true);
      expect(tester.widget<Switch>(control).onChanged, isNull);
      await tester.tap(control);
      expect(api.patches, 1);
      api.pending!.completeError(ApiException('服务暂时不可用', 503));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(control).value, true);
      expect(find.textContaining('原有提醒保持不变'), findsOneWidget);
      api.pending = null;
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(control).value, false);
      expect(api.reminders.first['active'], 0);
      expect(find.textContaining('原有提醒保持不变'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'editing opens rules directly without channel or vehicle dependency and preserves paused state',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = ReminderTestApi();
      api.reminders.first['active'] = 0;
      await tester.pumpWidget(CommuteApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-reminders')));
      await tester.pumpAndSettle();
      final queries = api.vehicleQueries;
      api.rejectChannels = true;
      await tester.tap(find.byKey(const ValueKey('edit-reminder-1')));
      await tester.pumpAndSettle();
      expect(find.byType(ReminderEditor), findsOneWidget);
      expect(api.vehicleQueries, queries);
      expect(find.text('保存提醒').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('多一站'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存提醒'));
      await tester.pumpAndSettle();
      expect(api.reminders.first['stations_before'], 4);
      expect(api.reminders.first['active'], 0);
      expect(api.lastBody!.containsKey('active'), false);
      expect(api.lastBody!.containsKey('channelId'), false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed save retains edits and can be retried', (tester) async {
    final api = ReminderTestApi();
    await tester.pumpWidget(CommuteApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提醒设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('多一站'));
    api.pending = Completer<void>();
    await tester.tap(find.text('保存提醒'));
    await tester.pump();
    api.pending!.completeError(ApiException('稍后再试', 503));
    await tester.pumpAndSettle();
    expect(find.text('4 站'), findsOneWidget);
    expect(find.byType(ReminderEditor), findsOneWidget);
    expect(api.reminders.first['stations_before'], 3);
    api.pending = null;
    await tester.tap(find.text('保存提醒'));
    await tester.pumpAndSettle();
    expect(api.reminders.first['stations_before'], 4);
    await tester.pumpWidget(const SizedBox());
  });
}

class ReminderTestApi extends DemoApi {
  Completer<void>? pending;
  int patches = 0, vehicleQueries = 0;
  bool rejectChannels = false;
  Json? lastBody;
  ReminderTestApi() : super(latency: Duration.zero);
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    if (path.endsWith('/realtime')) vehicleQueries++;
    if (path == '/api/channels' && rejectChannels) {
      throw ApiException('channels unavailable');
    }
    if (method == 'PATCH') {
      patches++;
      lastBody = body;
      if (pending != null) await pending!.future;
    }
    return super.request(path, method: method, body: body, query: query);
  }
}
