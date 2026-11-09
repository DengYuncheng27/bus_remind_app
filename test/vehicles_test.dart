import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiabanwang/screens/vehicle_panel.dart';
import 'package:xiabanwang/vehicles.dart';
import 'package:xiabanwang/theme.dart';

void main() {
  test('legacy Chelaile stations align with upstream WGS coordinates without double conversion', () {
    final legacy = {'lat': 39.947163444789716, 'lng': 116.40673676230277};
    final mapped = coordinates(mapStop(legacy, 'chelaile'))!;
    expect(mapped.latitude, closeTo(39.939416, .00003));
    expect(mapped.longitude, closeTo(116.394126, .00003));
    final modern = {
      'lat': 39.939416,
      'lng': 116.394126,
      'coordinateSystem': 'wgs84',
    };
    expect(coordinates(mapStop(modern, 'chelaile'))!.latitude, 39.939416);
    expect(coordinates(mapStop(legacy, 'other'))!.latitude, legacy['lat']);
  });
  test('target distance is verified; legacy next-stop distances cannot masquerade as it', () {
    final target = {'lat': 39.93, 'lng': 116.4};
    final bus = {'lat': 39.931, 'lng': 116.4, 'distanceMeters': 12};
    final estimated = busDistance(bus, target)!;
    expect(estimated.straightLine, isTrue);
    expect(estimated.meters, closeTo(111, 1));
    expect(estimated.label, '直线约 111 米');
    expect(busDistance({'distanceMeters': 12}, target), isNull);
    expect(
      busDistance({...bus, 'distanceSource': 'target-stop'}, target)!.label,
      '距上车站 12 米',
    );
    expect(
      busDistance({
        'distanceSource': 'target-stop',
        'distanceMeters': 0,
      }, target)!.meters,
      0,
    );
    expect(
      busDistance({
        'distanceSource': 'target-stop',
        'distanceMeters': -1,
      }, target),
      isNull,
    );
    for (final invalid in [
      null,
      {'lat': 0, 'lng': 0},
      {'lat': double.nan, 'lng': 116},
      {'lat': 999, 'lng': 0},
    ]) {
      expect(coordinates(invalid), isNull);
    }
  });

  test(
    'upcoming buses exclude passed and unknown, order by stops then ETA',
    () {
      expect(
        upcomingBuses({
          'buses': [
            {'id': 'unknown'},
            {'id': 'passed', 'stationsAway': -1},
            {'id': 'later', 'stationsAway': 4, 'etaSeconds': 400},
            {'id': 'second', 'stationsAway': 2, 'etaSeconds': 180},
            {'id': 'first', 'stationsAway': 2, 'etaSeconds': 120},
            {'id': 'arrived', 'stationsAway': 0},
          ],
        }).map((b) => b['id']),
        ['arrived', 'first', 'second', 'later'],
      );
    },
  );

  testWidgets(
    'multiple bus markers select rows; stale data is labelled and missing coordinates are explicit',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = <String, dynamic>{
        'realData': true,
        'fetchedAt': DateTime.now().toIso8601String(),
        'targetStop': {'id': 'target', 'lat': 39.93, 'lng': 116.4},
        'buses': [
          {
            'id': 'first',
            'order': 1,
            'stationsAway': 2,
            'etaSeconds': 120,
            'lat': 39.931,
            'lng': 116.4,
          },
          {
            'id': 'second',
            'order': 2,
            'stationsAway': 3,
            'etaSeconds': 300,
            'lat': 39.933,
            'lng': 116.402,
          },
          {'id': 'third', 'stationsAway': 4},
        ],
      };
      Widget app() => MaterialApp(
        theme: commuteTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: VehiclePanel(
                realtime: data,
                route: const {
                  'stops': [
                    {'order': 1, 'name': '鼓楼'},
                  ],
                },
                loadMapTiles: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('3 辆正在驶来'), findsOneWidget);
      expect(find.text('直线约 111 米'), findsOneWidget);
      expect(find.text('鼓楼附近'), findsOneWidget);
      expect(find.textContaining('1 辆车暂无坐标'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bus-marker-1')));
      await tester.pumpAndSettle();
      expect(tester.widget<BusMap>(find.byType(BusMap)).selected, 1);
      expect(tester.widget<BusMap>(find.byType(BusMap)).focusRevision, 1);
      expect(tester.takeException(), isNull);
      data['fetchedAt'] = DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('上次位置 · 待更新'), findsOneWidget);
      expect(find.text('约 5 分钟'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
