import 'package:flutter/material.dart';

import '../api.dart';
import '../palette.dart';
import '../ui.dart';

import 'dart:async';

import 'vehicle_panel.dart';
import 'reminder_editor.dart';

class DetailScreen extends StatefulWidget {
  final Api api;
  final Json reminder;
  const DetailScreen({super.key, required this.api, required this.reminder});
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late Json reminder = Map.of(widget.reminder);
  Json? realtime, route;
  String? error, routeError;
  bool busy = false, refreshing = false;
  Timer? clock;
  @override
  void initState() {
    super.initState();
    load();
    clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (refreshing) return;
    setState(() {
      refreshing = true;
      error = null;
    });
    try {
      routeError = null;
      route ??= await widget.api.data(
        '/api/routes/${Uri.encodeComponent(reminder['line_id'])}',
        query: {'cityId': reminder['city_id']},
      ) as Json;
    } catch (_) {
      routeError = '站点名称暂未加载，车辆定位仍可查看';
    }
    try {
      realtime = await widget.api.data(
        '/api/routes/${Uri.encodeComponent(reminder['line_id'])}/realtime',
        query: {
          'cityId': reminder['city_id'],
          'targetStopId': reminder['target_stop_id'],
        },
      ) as Json;
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => refreshing = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('这班车'),
      actions: [
        TextButton(
          onPressed: busy
              ? null
              : () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ReminderEditor(api: widget.api, reminder: reminder),
                    ),
                  );
                  if (!mounted) return;
                  try {
                    final list = objects(
                      await widget.api.data('/api/reminders'),
                    );
                    if (mounted) {
                      setState(
                        () => reminder = list.firstWhere(
                          (r) => r['id'] == reminder['id'],
                        ),
                      );
                      route = null;
                      realtime = null;
                      await load();
                    }
                  } catch (e) {
                    if (context.mounted) notice(context, e.toString());
                  }
                },
          child: const Text('提醒设置'),
        ),
      ],
    ),
    body: pageWidth(
      ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '${reminder['target_stop_name']}',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '${reminder['line_no']} 路 · ${route == null ? '方向查询中' : '开往 ${route!['endStop']}'}',
          ),
          if (realtime != null)
            VehiclePanel(realtime: realtime!, route: route)
          else if (refreshing)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (error != null) ErrorNotice(error!, load),
          if (routeError != null)
            Text(routeError!, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: refreshing ? null : load,
            icon: const Icon(Icons.refresh),
            label: Text(refreshing ? '更新中…' : '更新车辆位置'),
          ),
          const Divider(),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              '线路站点',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${objects(route?['stops'] ?? []).length} 站 · ${reminder['target_stop_name']} 上车',
            ),
            children: [
              for (final s in objects(route?['stops'] ?? []))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    s['id'] == reminder['target_stop_id']
                        ? Icons.location_on
                        : Icons.radio_button_unchecked,
                    color: s['id'] == reminder['target_stop_id']
                        ? green
                        : const Color(0xFF97A196),
                    size: 20,
                  ),
                  title: Text(s['name']),
                  trailing: s['id'] == reminder['target_stop_id']
                      ? const Text('上车站', style: TextStyle(color: green))
                      : null,
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
