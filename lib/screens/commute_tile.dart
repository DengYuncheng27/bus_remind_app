import 'package:flutter/material.dart';

import '../api.dart';
import '../palette.dart';
import '../vehicles.dart';

class CommuteTile extends StatelessWidget {
  final Json reminder;
  final Json? realtime;
  final String? error;
  final VoidCallback onTap;
  const CommuteTile({
    super.key,
    required this.reminder,
    this.realtime,
    this.error,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final active = isOn(reminder['active']);
    final bus = realtime == null ? null : nearestBus(realtime!);
    final stale = realtime != null && isStale(realtime!);
    final buses = upcomingBuses(realtime);
    final live = error == null && realtime?['realData'] == true && !stale;
    final target = mapStop(realtime?['targetStop'], realtime?['provider']);
    final ready = objects(reminder['channels'] ?? [])
        .any((c) => isOn(c['active']) && c['ready'] == true);
    final status = !active
        ? '已暂停'
        : pausedToday(reminder)
        ? '今天已暂停'
        : !ready
        ? '通知待连接'
        : '提醒已开启';
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Material(
        color: active ? ink : const Color(0xFFEAEDE5),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DefaultTextStyle(
              style: TextStyle(color: active ? Colors.white : ink),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${reminder['line_no']} 路',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        active
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_paused_outlined,
                        size: 17,
                        color: active ? const Color(0xFFCCEEA4) : ink,
                      ),
                      const SizedBox(width: 6),
                      Text(status, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${reminder['target_stop_name']} 上车',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    reminder['route_end_stop'] != null
                        ? '开往 ${reminder['route_end_stop']}'
                        : '点开查看线路方向',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 22),
                  if (live && bus != null) ...[
                    const Text('最近一辆', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 10),
                  ],
                  if (error != null)
                    const Text('车辆查询失败 · 点开重试', style: TextStyle(fontSize: 18))
                  else if (realtime == null)
                    const Text('正在查询车辆…', style: TextStyle(fontSize: 18))
                  else if (stale || realtime!['realData'] != true)
                    const Text(
                      '位置待更新',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else if (bus == null)
                    const Text(
                      '暂未查到车辆',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${bus['stationsAway']}',
                          style: const TextStyle(
                            fontSize: 64,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            bus['stationsAway'] == 0 ? '到站附近' : '站后到达',
                            style: const TextStyle(fontSize: 19),
                          ),
                        ),
                        if (bus['etaSeconds'] is num)
                          Text(
                            etaLabel(bus),
                            style: const TextStyle(fontSize: 15),
                          ),
                      ],
                    ),
                  if (live && bus != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      busDistance(bus, target)?.label ?? '距上车站：暂未提供',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    for (var i = 1; i < buses.length.clamp(0, 3); i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          children: [
                            Text(
                              '后续第 $i 辆 · ${buses[i]['stationsAway']} 站',
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              busDistance(buses[i], target)?.label ??
                                  etaLabel(buses[i]),
                              style: TextStyle(
                                fontSize: 13,
                                color: active ? const Color(0xFFC3CEC7) : ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      '查看${buses.length > 1 ? ' ${buses.length} 辆车与' : '车辆'}地图 →',
                      style: TextStyle(
                        fontSize: 12,
                        color: active ? const Color(0xFFCCEEA4) : green,
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  Container(
                    height: 1,
                    color: active ? Colors.white24 : const Color(0xFFCFD6CC),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${scheduleLabel(reminder)} · ${timeWindow(reminder)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: active
                                ? const Color(0xFFC3CEC7)
                                : const Color(0xFF526258),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: Color(0xFF9CBC80),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
