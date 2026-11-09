import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiabanwang/api.dart';
import 'package:xiabanwang/demo.dart';
import 'package:xiabanwang/main.dart';
import 'package:xiabanwang/screens/vehicle_panel.dart';

void main() {
  testWidgets('only the visible ride tab polls the selected route', (
    tester,
  ) async {
    final api = CountingTransitApi();
    await tester.pumpWidget(CommuteApp(api: api));
    await tester.pumpAndSettle();
    expect(api.queries, 1);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(api.queries, 2);
    await tester.tap(find.byKey(const ValueKey('tab-reminders')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(api.queries, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'home shows one route, tabs preserve selection, and the preference survives restart and deletion',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DemoApi(latency: Duration.zero);
      await tester.pumpWidget(CommuteApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('宝钞胡同 上车'), findsOneWidget);
      expect(find.text('北海北门 上车'), findsNothing);
      expect(find.byType(VehiclePanel), findsOneWidget);
      await tester.tap(find.text('切换线路'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('choose-route-2')));
      await tester.pumpAndSettle();
      expect(find.text('北海北门 上车'), findsOneWidget);
      expect(api.homePreferences['preview@example.com'], '2');
      await tester.tap(find.byKey(const ValueKey('tab-reminders')));
      await tester.pumpAndSettle();
      expect(find.text('107 路 · 宝钞胡同'), findsOneWidget);
      expect(find.text('107 路 · 北海北门'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-profile')));
      await tester.pumpAndSettle();
      expect(find.text('我的账号'), findsOneWidget);
      expect(find.text('preview@example.com'), findsOneWidget);
      expect(find.byKey(const ValueKey('tab-ride')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-ride')));
      await tester.pumpAndSettle();
      expect(find.text('北海北门 上车'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(CommuteApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('北海北门 上车'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.reminders.removeLast();
      await tester.pumpWidget(CommuteApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('宝钞胡同 上车'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'late response from previous route cannot replace the selected route',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DelayedTransitApi();
      await tester.pumpWidget(CommuteApp(api: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('切换线路'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.byKey(const ValueKey('choose-route-2')));
      await tester.tap(find.byKey(const ValueKey('choose-route-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      api.back.complete({
        'data': {
          'realData': true,
          'fetchedAt': DateTime.now().toIso8601String(),
          'buses': [
            {'id': 'back', 'stationsAway': 7, 'etaSeconds': 600},
          ],
        },
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('7 站后到达'), findsOneWidget);
      api.out.complete({
        'data': {
          'realData': true,
          'fetchedAt': DateTime.now().toIso8601String(),
          'buses': [
            {'id': 'out', 'stationsAway': 2, 'etaSeconds': 120},
          ],
        },
      });
      await tester.pumpAndSettle();
      expect(find.text('7 站后到达'), findsOneWidget);
      expect(find.text('2 站后到达'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('empty home offers creation while all three tabs remain usable', (
    tester,
  ) async {
    final api = DemoApi(latency: Duration.zero)..reminders.clear();
    await tester.pumpWidget(CommuteApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('先选一条常坐的线路'), findsOneWidget);
    expect(find.text('添加通勤提醒'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab-profile')));
    await tester.pumpAndSettle();
    expect(find.text('我的账号'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class CountingTransitApi extends DemoApi {
  int queries = 0;
  CountingTransitApi() : super(latency: Duration.zero);
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) {
    if (path.endsWith('/realtime')) queries++;
    return super.request(path, method: method, body: body, query: query);
  }
}

class DelayedTransitApi extends DemoApi {
  final out = Completer<dynamic>(), back = Completer<dynamic>();
  DelayedTransitApi() : super(latency: Duration.zero);
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) {
    if (path.endsWith('/realtime')) {
      return path.contains('107-out') ? out.future : back.future;
    }
    return super.request(path, method: method, body: body, query: query);
  }
}
