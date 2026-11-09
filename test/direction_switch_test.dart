import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiabanwang/api.dart';
import 'package:xiabanwang/demo.dart';
import 'package:xiabanwang/main.dart';

void main() {
  testWidgets(
    'direction switches route and opposite stop IDs, returns, and never changes reminders',
    (tester) async {
      final api = DirectionApi();
      await tester.pumpWidget(CommuteApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('flip-direction')));
      await tester.pumpAndSettle();
      expect(find.text('开往 东直门枢纽站'), findsOneWidget);
      expect(find.text('宝钞胡同 上车'), findsOneWidget);
      expect(find.text('此方向未设提醒'), findsOneWidget);
      expect(api.lastLine, '107-back');
      expect(api.lastStop, 'opposite-stop');
      await tester.tap(find.byKey(const ValueKey('tab-reminders')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-ride')));
      await tester.pumpAndSettle();
      expect(find.text('开往 东直门枢纽站'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('flip-direction')));
      await tester.pumpAndSettle();
      expect(find.text('开往 白石桥东'), findsOneWidget);
      expect(api.lastLine, '107-out');
      expect(api.lastStop, 'stop-2');
      expect(api.writes, 0);
      expect(api.reminders.first['line_id'], '107-out');
      expect(api.reminders.first['active'], 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'no matching stop requires selection and cancellation keeps original view',
    (tester) async {
      final api = DirectionApi()..noMatch = true;
      await tester.pumpWidget(CommuteApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('flip-direction')));
      await tester.pumpAndSettle();
      expect(find.text('选择反方向上车站'), findsOneWidget);
      Navigator.of(tester.element(find.text('选择反方向上车站'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('开往 白石桥东'), findsOneWidget);
      expect(api.lastLine, '107-out');
      await tester.tap(find.byKey(const ValueKey('flip-direction')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('另一侧站点'));
      await tester.pumpAndSettle();
      expect(find.text('另一侧站点 上车'), findsOneWidget);
      expect(api.lastStop, 'opposite-stop');
      expect(api.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed lookup and absent opposite route retain current direction',
    (tester) async {
      final api = DirectionApi()..failSearch = true;
      await tester.pumpWidget(CommuteApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('flip-direction')));
      await tester.pumpAndSettle();
      expect(find.text('线路查询暂不可用'), findsOneWidget);
      expect(find.text('开往 白石桥东'), findsOneWidget);
      api.failSearch = false;
      api.noOpposite = true;
      await tester.tap(find.byKey(const ValueKey('flip-direction')));
      await tester.pumpAndSettle();
      expect(find.text('开往 白石桥东'), findsOneWidget);
      expect(api.lastLine, '107-out');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('switching favorite discards late opposite direction lookup', (
    tester,
  ) async {
    final api = DirectionApi()..searchGate = Completer<void>();
    await tester.pumpWidget(CommuteApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('flip-direction')));
    await tester.pump();
    await tester.tap(find.text('切换线路'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choose-route-2')));
    await tester.pumpAndSettle();
    api.searchGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('北海北门 上车'), findsOneWidget);
    expect(api.lastStop, 'stop-1');
    await tester.pumpWidget(const SizedBox());
  });
}

class DirectionApi extends DemoApi {
  String? lastLine, lastStop;
  int writes = 0;
  bool noMatch = false, failSearch = false, noOpposite = false;
  Completer<void>? searchGate;
  DirectionApi() : super(latency: Duration.zero);
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    if (method != 'GET') writes++;
    if (path == '/api/routes/search') {
      if (searchGate != null) await searchGate!.future;
      if (failSearch) throw ApiException('线路查询暂不可用');
      if (noOpposite) return {'data': []};
    }
    if (path == '/api/routes/107-back') {
      return {
        'data': {
          'lineId': '107-back',
          'startStop': '白石桥东',
          'endStop': '东直门枢纽站',
          'stops': [
            {
              'id': 'opposite-stop',
              'name': noMatch ? '另一侧站点' : '宝钞胡同',
              'order': 1,
            },
          ],
        },
      };
    }
    if (path.endsWith('/realtime')) {
      lastLine = path.split('/')[3];
      lastStop = query?['targetStopId'];
    }
    return super.request(path, method: method, body: body, query: query);
  }
}
