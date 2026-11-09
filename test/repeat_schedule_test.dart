import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiabanwang/api.dart';
import 'package:xiabanwang/demo.dart';
import 'package:xiabanwang/repeat_schedule.dart';
import 'package:xiabanwang/screens/reminder_editor.dart';
import 'package:xiabanwang/screens/repeat_sheet.dart';

Widget shell(Widget child) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: child,
);

void main() {
  test('China date and stored alternating masks round trip without losing phase or holidays', () {
    expect(
      dateText(chinaToday(DateTime.parse('2026-11-03T17:00:00Z'))),
      '2026-11-04',
    );
    final data = {
      'schedule_mode': 'custom',
      'schedule_interval_weeks': 2,
      'schedule_weekdays_mask': 63,
      'schedule_alternate_weekdays_mask': 31,
      'schedule_anchor_date': '2026-11-02',
      'skip_statutory_holidays': 1,
    };
    final value = RepeatSchedule.fromReminder(data);
    expect(value.toJson(), {
      'mode': 'custom',
      'intervalWeeks': 2,
      'weekdays': [1, 2, 3, 4, 5, 6],
      'alternateWeekdays': [1, 2, 3, 4, 5],
      'anchorDate': '2026-11-02',
      'skipStatutoryHolidays': true,
    });
    expect(value.summary, contains('第2周'));
    expect(
      RepeatSchedule.fromReminder({'schedule_mode': 'china_workday'}).toJson(),
      {'mode': 'china_workday'},
    );
  });

  testWidgets(
    'custom dialog validates interval and days; cancel leaves original untouched',
    (tester) async {
      final original = RepeatSchedule(anchor: DateTime.utc(2026, 11, 2));
      RepeatSchedule? result;
      await tester.pumpWidget(
        shell(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await editRepeat(context, original);
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('repeat-interval')),
        '0',
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1–52 之间的周数'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('repeat-interval')),
        '2',
      );
      for (var i = 1; i <= 5; i++) {
        await tester.tap(find.byKey(ValueKey('weekday-$i')));
      }
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('至少选择一个星期'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(original.weekdays, [1, 2, 3, 4, 5]);
      expect(original.intervalWeeks, 1);
    },
  );

  testWidgets(
    'alternating preset submits both weeks and holiday checkbox at small screen size',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      RepeatSchedule? result;
      await tester.pumpWidget(
        shell(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await editRepeat(
                    context,
                    RepeatSchedule(anchor: DateTime.utc(2026, 11, 2)),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('alternate-weeks')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('skip-holidays')));
      await tester.tap(find.byKey(const ValueKey('skip-holidays')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('确定'));
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result?.weekdays, [1, 2, 3, 4, 5, 6]);
      expect(result?.alternateWeekdays, [1, 2, 3, 4, 5]);
      expect(result?.skipHolidays, true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing saves the complete custom rule and always supplies a time window',
    (tester) async {
      final api = DemoApi(latency: Duration.zero);
      api.reminders[0].addAll({
        'schedule_mode': 'custom',
        'schedule_interval_weeks': 2,
        'schedule_weekdays_mask': 32,
        'schedule_anchor_date': '2026-11-07',
        'skip_statutory_holidays': 1,
        'window_start': null,
        'window_end': null,
      });
      await tester.pumpWidget(
        shell(ReminderEditor(api: api, reminder: api.reminders[0])),
      );
      await tester.pumpAndSettle();
      expect(find.text('全天'), findsNothing);
      await tester.ensureVisible(find.text('保存提醒'));
      await tester.tap(find.text('保存提醒'));
      await tester.pumpAndSettle();
      final saved = api.reminders[0];
      expect(saved['schedule_interval_weeks'], 2);
      expect(saved['schedule_weekdays_mask'], 32);
      expect(saved['schedule_anchor_date'], '2026-11-07');
      expect(saved['skip_statutory_holidays'], true);
      expect(saved['window_start'], '17:30');
      expect(saved['window_end'], '18:30');
    },
  );

  testWidgets(
    'older server rejects alternating weeks before submitting a lossy update',
    (tester) async {
      final api = OldServerApi();
      api.reminders[0].addAll({
        'schedule_mode': 'custom',
        'schedule_interval_weeks': 2,
        'schedule_weekdays_mask': 63,
        'schedule_alternate_weekdays_mask': 31,
        'schedule_anchor_date': '2026-11-02',
      });
      await tester.pumpWidget(
        shell(ReminderEditor(api: api, reminder: api.reminders[0])),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存提醒'));
      await tester.tap(find.text('保存提醒'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('大小周功能尚未开通，请联系管理员'));
      expect(find.text('大小周功能尚未开通，请联系管理员'), findsOneWidget);
      expect(api.saved, false);
    },
  );
}

class OldServerApi extends DemoApi {
  bool saved = false;
  OldServerApi() : super(latency: Duration.zero);
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    if (path == '/api/reminders/capabilities') {
      throw ApiException('Not found', 404);
    }
    if (method == 'PATCH' || method == 'POST') saved = true;
    return super.request(path, method: method, body: body, query: query);
  }
}
