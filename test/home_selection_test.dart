import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiabanwang/demo.dart';
import 'package:xiabanwang/home_selection.dart';
import 'package:xiabanwang/main.dart';

void main() {
  test(
    'overlaps keep current, then favorite, then stable ID regardless of order',
    () {
      final reminders = [
        {'id': 3, 'active': 1, 'schedule_active': true},
        {'id': 2, 'active': 1, 'schedule_active': true},
        {'id': 1, 'active': 1, 'schedule_active': false},
      ];
      expect(
        selectHomeReminder(reminders, currentId: '3', favoriteId: '2'),
        '3',
      );
      expect(
        selectHomeReminder(reminders, currentId: '1', favoriteId: '3'),
        '3',
      );
      expect(selectHomeReminder(reminders, favoriteId: '1'), '2');
      expect(
        selectHomeReminder(reminders.reversed.toList(), favoriteId: '1'),
        '2',
      );
      expect(selectHomeReminder([]), isNull);
    },
  );

  test(
    'disabled, paused and old-server reminders cannot override the favorite',
    () {
      final reminders = [
        {'id': 1, 'active': 1},
        {'id': 2, 'active': 0, 'schedule_active': true},
        {
          'id': 3,
          'active': 1,
          'schedule_active': true,
          'paused_until': '2999-01-01T00:00:00Z',
        },
      ];
      expect(
        selectHomeReminder(reminders, currentId: '3', favoriteId: '2'),
        '2',
      );
      expect(selectHomeReminder(reminders, favoriteId: 'deleted'), '1');
    },
  );

  testWidgets(
    'automatic display does not overwrite favorite or switch during polling; reentry restores favorite',
    (tester) async {
      final api = DemoApi(latency: Duration.zero);
      api.homePreferences['preview@example.com'] = '1';
      api.reminders[1].addAll({'active': 1, 'schedule_active': true});
      await tester.pumpWidget(CommuteApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('北海北门 上车'), findsOneWidget);
      expect(find.text('当前提醒 · 08:00–09:00'), findsOneWidget);
      expect(api.homePreferences['preview@example.com'], '1');

      api.reminders[1]['schedule_active'] = false;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text('北海北门 上车'), findsOneWidget);
      expect(find.text('当前提醒 · 08:00–09:00'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tab-reminders')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-ride')));
      await tester.pumpAndSettle();
      expect(find.text('宝钞胡同 上车'), findsOneWidget);
      expect(api.homePreferences['preview@example.com'], '1');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'manual selection lasts through refresh and tabs, but a new visit follows the schedule',
    (tester) async {
      final api = DemoApi(latency: Duration.zero);
      api.homePreferences['preview@example.com'] = '1';
      api.reminders[1].addAll({'active': 1, 'schedule_active': true});
      await tester.pumpWidget(CommuteApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('切换线路'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('choose-route-1')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-ride')));
      await tester.pumpAndSettle();
      expect(find.text('宝钞胡同 上车'), findsOneWidget);
      expect(api.homePreferences['preview@example.com'], '1');

      // Losing focus to a dialog must not count as opening the app again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('宝钞胡同 上车'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('北海北门 上车'), findsOneWidget);
      expect(api.homePreferences['preview@example.com'], '1');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
