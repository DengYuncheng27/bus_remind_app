import 'repeat_schedule.dart';
import 'api.dart';

/// Isolated, explicitly labelled design preview. Never sends network requests.
class DemoApi extends Api {
  final homePreferences = <String, String>{};
  @override
  Future<String?> readHomeReminder(String account) async =>
      homePreferences[account];
  @override
  Future<void> saveHomeReminder(String account, String id) async {
    homePreferences[account] = id;
  }

  final Duration latency;
  DemoApi({this.latency = const Duration(milliseconds: 180)});
  @override
  bool get demo => true;
  final List<Json> reminders = [
    {
      'id': 1,
      'city_id': '027',
      'city_name': '北京',
      'line_id': '107-out',
      'route_end_stop': '白石桥东',
      'line_no': '107',
      'target_stop_id': 'stop-2',
      'target_stop_name': '宝钞胡同',
      'stations_before': 3,
      'active': 1,
      'window_start': '17:30',
      'window_end': '18:30',
      'schedule_mode': 'china_workday',
      'channel_ids': [1],
      'channels': [
        {'id': 1, 'type': 'mobilepush', 'active': true, 'ready': true},
      ],
    },
    {
      'id': 2,
      'city_id': '027',
      'city_name': '北京',
      'line_id': '107-back',
      'route_end_stop': '东直门枢纽站',
      'line_no': '107',
      'target_stop_id': 'stop-1',
      'target_stop_name': '北海北门',
      'stations_before': 3,
      'active': 0,
      'window_start': '08:00',
      'window_end': '09:00',
      'schedule_mode': 'china_workday',
      'channel_ids': [1],
      'channels': [
        {'id': 1, 'type': 'mobilepush', 'active': true, 'ready': true},
      ],
    },
  ];
  @override
  Future<void> restore() async {
    token = 'preview';
  }

  @override
  Future<void> saveToken(String value) async {
    token = value;
  }

  @override
  Future<void> logout() async {
    token = null;
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    if (latency != Duration.zero) await Future<void>.delayed(latency);
    if (path == '/api/me') return {'email': 'preview@example.com'};
    if (path == '/api/auth/registration') {
      return {
        'data': {'mode': 'public'},
      };
    }
    if (path.startsWith('/api/auth/')) {
      return {'token': 'preview'};
    }
    if (path == '/api/mobile-push') {
      return {
        'data': {'enabled': false, 'devices': []},
      };
    }
    if (path == '/api/channels') {
      return {
        'data': [
          {
            'id': 1,
            'type': 'mobilepush',
            'label': '手机通知（演示）',
            'ready': true,
            'active': true,
          },
        ],
      };
    }
    if (path == '/api/cities') {
      return {
        'data': [
          {'cityId': '027', 'cityName': '北京'},
        ],
      };
    }
    if (path == '/api/routes/search') {
      return {
        'data': [
          {
            'lineId': '107-out',
            'lineNo': query?['q'] ?? '107',
            'endStop': '白石桥东',
            'startStop': '东直门枢纽站',
          },
          {
            'lineId': '107-back',
            'lineNo': query?['q'] ?? '107',
            'endStop': '东直门枢纽站',
            'startStop': '白石桥东',
          },
        ],
      };
    }
    if (path.endsWith('/realtime')) {
      return {
        'data': {
          'realData': true,
          'fetchedAt': DateTime.now().toIso8601String(),
          'buses': [
            {
              'id': 'preview',
              'stationsAway': 3,
              'etaSeconds': 360,
              'distanceMeters': 1200,
            },
          ],
        },
      };
    }
    if (path.startsWith('/api/routes/')) {
      return {
        'data': {
          'endStop': path.contains('back') ? '东直门枢纽站' : '白石桥东',
          'stops': [
            {'id': 'stop-1', 'name': '北海北门', 'order': 1},
            {'id': 'stop-2', 'name': '宝钞胡同', 'order': 2},
            {'id': 'stop-3', 'name': '鼓楼', 'order': 3},
          ],
        },
      };
    }
    if (path == '/api/reminders' && method == 'GET') {
      return {
        'data': reminders.map((r) => Map<String, dynamic>.from(r)).toList(),
      };
    }
    if (path == '/api/reminders' && method == 'POST') {
      final id =
          reminders.fold<int>(0, (a, b) => a > b['id'] ? a : b['id']) + 1;
      reminders.add({
        'id': id,
        'city_id': body!['cityId'],
        'city_name': '北京',
        'line_id': body['lineId'],
        'line_no': '107',
        'target_stop_id': body['targetStopId'],
        'target_stop_name': {
          'stop-1': '北海北门',
          'stop-2': '宝钞胡同',
          'stop-3': '鼓楼',
        }[body['targetStopId']],
        'stations_before': body['stationsBefore'],
        'active': 1,
        'window_start': body['windowStart'],
        'window_end': body['windowEnd'],
        ...scheduleFields(body['schedule']),
        'channels': [
          {'id': 1, 'type': 'mobilepush', 'active': true, 'ready': true},
        ],
      });
      return {
        'data': {'id': id},
      };
    }
    if (path.endsWith('/pause-today')) {
      final id = int.parse(path.split('/')[3]);
      final now = DateTime.now().toUtc().add(const Duration(hours: 8));
      final until = DateTime.utc(
        now.year,
        now.month,
        now.day + 1,
      ).subtract(const Duration(hours: 8)).toIso8601String();
      reminders.firstWhere((r) => r['id'] == id)['paused_until'] = until;
      return {
        'data': {'pausedUntil': until},
      };
    }
    if (path.startsWith('/api/reminders/')) {
      final id = int.parse(path.split('/').last);
      if (method == 'DELETE') {
        reminders.removeWhere((r) => r['id'] == id);
        return null;
      }
      final reminder = reminders.firstWhere((r) => r['id'] == id);
      if (body?.containsKey('active') == true) {
        reminder['active'] = body!['active'] ? 1 : 0;
      }
      if (body?['active'] == true) reminder['paused_until'] = null;
      for (final entry in {
        'stationsBefore': 'stations_before',
        'windowStart': 'window_start',
        'windowEnd': 'window_end',
      }.entries) {
        if (body?.containsKey(entry.key) == true) {
          reminder[entry.value] = body![entry.key];
        }
      }
      if (body?['schedule'] != null) {
        reminder.addAll(scheduleFields(body!['schedule']));
      }
      return {'data': reminder};
    }
    throw ApiException('演示模式不执行此操作');
  }
}

Json scheduleFields(Json schedule) => {
  'schedule_mode': schedule['mode'],
  'schedule_interval_weeks': schedule['intervalWeeks'] ?? 1,
  'schedule_weekdays_mask': daysMask(
    List<int>.from(schedule['weekdays'] ?? [1, 2, 3, 4, 5, 6, 7]),
  ),
  'schedule_anchor_date': schedule['anchorDate'],
  'skip_statutory_holidays': schedule['skipStatutoryHolidays'] ?? false,
};
