// Read-only visual QA. Serve output/transit-snapshot.json next to this build.
// No login, reminders, or generated bus data; the original fetchedAt is kept.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:xiabanwang/api.dart';
import 'package:xiabanwang/screens/vehicle_panel.dart';
import 'package:xiabanwang/screens/commute_tile.dart';
import 'package:xiabanwang/theme.dart';
import 'package:xiabanwang/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final response = await http.get(Uri.base.resolve('transit-snapshot.json'));
  final data = jsonDecode(utf8.decode(response.bodyBytes)) as Json;
  runApp(
    MaterialApp(
      theme: commuteTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: _Preview(data: data),
    ),
  );
}

class _Preview extends StatefulWidget {
  final Json data;
  const _Preview({required this.data});
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  bool detail = true;
  @override
  Widget build(BuildContext context) {
    final route = widget.data['route'] as Json,
        realtime = widget.data['realtime'] as Json;
    return Scaffold(
      appBar: AppBar(
        title: const Text('真实接口快照校验'),
        actions: [
          TextButton(
            onPressed: () => setState(() => detail = !detail),
            child: Text(detail ? '首页卡片' : '车辆详情'),
          ),
        ],
      ),
      body: pageWidth(
        ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '${realtime['targetStop']['name']}',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            Text('${route['lineNo']} 路 · 开往 ${route['endStop']}'),
            if (detail)
              VehiclePanel(realtime: realtime, route: route)
            else
              CommuteTile(
                reminder: {
                  'active': 1,
                  'line_no': route['lineNo'],
                  'route_end_stop': route['endStop'],
                  'target_stop_name': realtime['targetStop']['name'],
                  'schedule_mode': 'china_workday',
                  'window_start': '17:30',
                  'window_end': '18:30',
                  'channels': <Json>[],
                },
                realtime: realtime,
                onTap: () => setState(() => detail = true),
              ),
          ],
        ),
      ),
    );
  }
}
