import '../repeat_schedule.dart';
import 'repeat_sheet.dart';
import 'extensions_screen.dart';

import 'package:flutter/material.dart';

import '../api.dart';
import '../palette.dart';
import '../ui.dart';

class ReminderEditor extends StatefulWidget {
  final Api api;
  final Json? reminder;
  final Future<void> Function()? onSetup;
  const ReminderEditor({
    super.key,
    required this.api,
    this.reminder,
    this.onSetup,
  });
  @override
  State<ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<ReminderEditor> {
  final search = TextEditingController();
  List<Json> cities = [], routes = [], stops = [], channels = [];
  Json? city, route, stop;
  int step = 0, before = 3;
  final selectedChannels = <int>{};
  bool deliveryChanged = false;
  bool loading = true, busy = false, searched = false;
  String? error;
  RepeatSchedule repeat = RepeatSchedule();
  TimeOfDay start = const TimeOfDay(hour: 17, minute: 30),
      end = const TimeOfDay(hour: 18, minute: 30);
  bool get editing => widget.reminder != null;
  @override
  void initState() {
    super.initState();
    final r = widget.reminder;
    if (r != null) {
      step = 2;
      selectedChannels.addAll(
        ((r['channel_ids'] as List?) ?? [r['channel_id']]).whereType<int>(),
      );
      before = r['stations_before'];
      repeat = RepeatSchedule.fromReminder(r);
      start = parseTime(r['window_start'], start);
      end = parseTime(r['window_end'], end);
    }
    init();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  static TimeOfDay parseTime(dynamic v, TimeOfDay fallback) {
    final parts = v?.toString().split(':');
    return parts == null
        ? fallback
        : TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String clockText(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  Future<void> init() async {
    setState(() {
      loading = true;
      error = null;
    });
    // Existing reminders keep their configured delivery channel; editing rules
    // must not depend on fetching unrelated notification settings.
    if (editing) {
      setState(() => loading = false);
      return;
    }
    try {
      if (!editing) {
        cities = objects(await widget.api.data('/api/cities'));
        if (cities.isNotEmpty) city = cities.first;
      }
      channels = objects(await widget.api.data('/api/channels'))
          .where((c) => isOn(c['active']) && c['ready'] == true)
          .toList();
      channels.sort(
        (a, b) => (a['type'] == 'mobilepush' ? 0 : 1).compareTo(
          b['type'] == 'mobilepush' ? 0 : 1,
        ),
      );
      if (channels.isNotEmpty && selectedChannels.isEmpty) {
        selectedChannels.add(channels.first['id'] as int);
      }
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> findRoutes() async {
    if (city == null || search.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
      routes = [];
    });
    try {
      routes = objects(
        await widget.api.data(
          '/api/routes/search',
          query: {'cityId': city!['cityId'], 'q': search.text.trim()},
        ),
      );
      searched = true;
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> selectRoute(Json selected) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final detail = await widget.api.data(
        '/api/routes/${Uri.encodeComponent(selected['lineId'])}',
        query: {'cityId': city!['cityId']},
      );
      stops = objects(detail['stops']);
      route = selected;
      stop = null;
      step = 1;
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> save() async {
    if (busy) return;
    if (!editing && selectedChannels.isEmpty) return;
    if (start == end) {
      setState(() => error = '开始和结束时间不能相同');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = <String, dynamic>{
        'stationsBefore': before,
        'windowStart': clockText(start),
        'windowEnd': clockText(end),
        'schedule': repeat.toJson(),
        if (!editing || deliveryChanged)
          'channelIds': selectedChannels.toList(),
        if (!editing) ...{
          'cityId': city!['cityId'],
          'lineId': route!['lineId'],
          'targetStopId': stop!['id'],
          'maxNotificationsPerBus': 1,
          'repeatIntervalMinutes': 2,
        },
      };
      await widget.api.data(
        editing ? '/api/reminders/${widget.reminder!['id']}' : '/api/reminders',
        method: editing ? 'PATCH' : 'POST',
        body: body,
      );
      if (mounted) {
        notice(context, '提醒已保存');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(editing ? '编辑提醒' : '添加通勤'),
      leading: IconButton(
        tooltip: '返回',
        onPressed: busy
            ? null
            : () {
                if (!editing && step > 0) {
                  setState(() {
                    step--;
                    error = null;
                  });
                } else {
                  Navigator.pop(context);
                }
              },
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    bottomNavigationBar: step == 2 && !loading
        ? SafeArea(
            child: pageWidth(
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: FilledButton(
                  onPressed: busy || (!editing && selectedChannels.isEmpty)
                      ? null
                      : save,
                  child: Text(busy ? '保存中…' : '保存提醒'),
                ),
              ),
            ),
          )
        : null,
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : pageWidth(
            ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (!editing) ...[
                  Text(
                    '0${step + 1} / 03',
                    style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                Text(
                  ['你坐哪辆车？', '在哪一站上车？', '什么时候提醒你'][step],
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 24),
                if (error != null)
                  ErrorNotice(
                    error!,
                    editing || step == 2
                        ? save
                        : step == 0
                        ? init
                        : () => selectRoute(route!),
                  ),
                if (step == 0) ...[
                  DropdownButtonFormField<String>(
                    initialValue: city?['cityId'],
                    decoration: const InputDecoration(labelText: '城市'),
                    items: cities
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c['cityId'],
                            child: Text(c['cityName']),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            city = cities.firstWhere((c) => c['cityId'] == v);
                            routes = [];
                            searched = false;
                          }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      if (!busy) findRoutes();
                    },
                    decoration: InputDecoration(
                      labelText: '搜索线路，例如 107',
                      suffixIcon: IconButton(
                        tooltip: '搜索',
                        onPressed: busy ? null : findRoutes,
                        icon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (searched && routes.isEmpty) const Text('没有找到线路，试试其他线路号。'),
                  for (final r in routes)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      title: Text(
                        '${r['lineNo']} 路',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                        ),
                      ),
                      subtitle: Text(
                        '开往 ${r['endStop']}\n${r['startStop']} 出发',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy ? null : () => selectRoute(r),
                    ),
                ],
                if (step == 1) ...[
                  Text(
                    '${route!['lineNo']} 路 · 开往 ${route!['endStop']}',
                    style: const TextStyle(color: green, fontSize: 17),
                  ),
                  const SizedBox(height: 20),
                  if (stops.isEmpty) const Text('这条线路暂无站点数据，请返回选择其他线路。'),
                  for (final s in stops)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 5),
                      leading: const Icon(
                        Icons.radio_button_unchecked,
                        size: 18,
                      ),
                      title: Text(s['name']),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() {
                        stop = s;
                        step = 2;

                        error = null;
                      }),
                    ),
                ],
                if (step == 2) ...[
                  Text(
                    editing
                        ? '${widget.reminder!['line_no']} 路 · ${widget.reminder!['target_stop_name']}'
                        : '${route!['lineNo']} 路 · 开往 ${route!['endStop']}\n${stop!['name']} 上车',
                    style: const TextStyle(fontSize: 18),
                  ),
                  if (editing)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        pausedToday(widget.reminder!)
                            ? '今天暂停 · 保存规则后仍保持暂停'
                            : isOn(widget.reminder!['active'])
                            ? '已开启 · 按下面的规则提醒'
                            : '已暂停 · 保存后可在提醒页开启',
                        style: const TextStyle(
                          color: Color(0xFF66756C),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 32),
                  const Text('距离上车站还有'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: '少一站',
                        onPressed: !busy && before > 1
                            ? () => setState(() => before--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '$before 站',
                            style: const TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: '多一站',
                        onPressed: !busy && before < 10
                            ? () => setState(() => before++)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const Divider(),
                  ListTile(
                    key: const ValueKey('repeat-settings'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('重复'),
                    subtitle: Text(repeat.summary),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: busy
                        ? null
                        : () async {
                            final next = await editRepeat(context, repeat);
                            if (next != null && mounted) {
                              setState(() => repeat = next);
                            }
                          },
                  ),
                  const SizedBox(height: 24),
                  const Text('提醒时段 · 北京时间'),
                  if (editing && widget.reminder!['window_start'] == null)
                    const Text(
                      '这条提醒尚未设置时段，请确认开始和结束时间。',
                      style: TextStyle(fontSize: 13),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: start,
                              builder: (c, w) => MediaQuery(
                                data: MediaQuery.of(c)
                                    .copyWith(alwaysUse24HourFormat: true),
                                child: w!,
                              ),
                            );
                            if (t != null && mounted) setState(() => start = t);
                          },
                          child: Text(clockText(start)),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('至'),
                      ),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: end,
                              builder: (c, w) => MediaQuery(
                                data: MediaQuery.of(c)
                                    .copyWith(alwaysUse24HourFormat: true),
                                child: w!,
                              ),
                            );
                            if (t != null && mounted) setState(() => end = t);
                          },
                          child: Text(clockText(end)),
                        ),
                      ),
                    ],
                  ),
                  if (end.hour * 60 + end.minute <
                      start.hour * 60 + start.minute)
                    const Text('结束时间为次日', style: TextStyle(color: green)),
                  const Divider(),
                  ListTile(
                    key: const ValueKey('delivery-settings'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('接收渠道'),
                    subtitle: Text(
                      selectedChannels.isEmpty
                          ? '先连接通知或添加高级扩展'
                          : '已选择 ${selectedChannels.length} 个渠道',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: busy
                        ? null
                        : () async {
                            final selected = await selectDelivery(
                              context,
                              widget.api,
                              selectedChannels,
                            );
                            if (selected != null && mounted) {
                              setState(() {
                                selectedChannels.clear();
                                selectedChannels.addAll(selected);
                                deliveryChanged = true;
                              });
                            }
                          },
                  ),
                  if (!editing && selectedChannels.isEmpty)
                    TextButton(
                      onPressed: () async {
                        await widget.onSetup?.call();
                        if (mounted) init();
                      },
                      child: const Text('前往通知设置'),
                    ),
                  const SizedBox(height: 24),
                ],
                if (busy && step < 2)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
  );
}
