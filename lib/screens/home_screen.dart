import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../home_selection.dart';
import '../palette.dart';
import '../push.dart';
import '../ui.dart';
import 'detail_screen.dart';
import 'reminder_editor.dart';
import 'settings_screen.dart';
import 'vehicle_panel.dart';

class HomeScreen extends StatefulWidget {
  final Api api;
  final VoidCallback onLogout;
  const HomeScreen({super.key, required this.api, required this.onLogout});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final PhonePush push = PhonePush(widget.api);
  final routeCache = <String, Json>{};
  List<Json>? reminders;
  Json? profile, realtime, route;
  String? selectedId, account, error, vehicleError, pushIssue;
  String? favoriteId;
  bool autoSelectionPending = true, manualSelection = false;
  int tab = 0, requestRevision = 0;
  int? pendingPushReminder;
  bool loading = false, refreshing = false, foreground = true;
  Timer? clock;
  Future<void> preferenceWrite = Future.value();
  final changingReminders = <String>{};
  final reminderErrors = <String, String>{};

  Json? get selected {
    for (final reminder in reminders ?? <Json>[]) {
      if ('${reminder['id']}' == selectedId) return reminder;
    }
    return null;
  }

  String direction(Json reminder) {
    final destination =
        reminder['route_end_stop'] ??
        routeCache['${reminder['city_id']}:${reminder['line_id']}']?['endStop'];
    return destination == null || '$destination'.isEmpty
        ? '点开查看方向'
        : '开往 $destination';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    push.onOpen = (id) async {
      pendingPushReminder = id;
      await load();
      openPendingPush();
    };
    load();
    restorePush();
    clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (foreground &&
          tab == 0 &&
          ModalRoute.of(context)?.isCurrent == true &&
          !refreshing &&
          !loading &&
          selected != null) {
        load();
      } else {
        setState(() {});
      }
    });
  }

  void openPendingPush() {
    if (!mounted ||
        loading ||
        pendingPushReminder == null ||
        reminders == null) {
      return;
    }
    final matches = reminders!.where((r) => r['id'] == pendingPushReminder);
    pendingPushReminder = null;
    if (matches.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openDetail(matches.first);
      });
    }
  }

  Future<void> restorePush() async {
    try {
      await push.restore();
    } catch (e) {
      if (mounted) setState(() => pushIssue = e.toString());
    }
  }

  @override
  void dispose() {
    requestRevision++;
    clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    push.onOpen = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      autoSelectionPending = true;
      manualSelection = false;
    }
    foreground = state == AppLifecycleState.resumed;
    if (foreground && ModalRoute.of(context)?.isCurrent == true) load();
  }

  Future<void> load({bool reselect = false}) async {
    if (loading || changingReminders.isNotEmpty) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = objects(await widget.api.data('/api/reminders'));
      if (profile == null) {
        try {
          profile = Map<String, dynamic>.from(
            await widget.api.request('/api/me') as Map,
          );
          account = (profile?['id'] ?? profile?['email'])?.toString();
          if (account != null && favoriteId == null) {
            favoriteId = await widget.api.readHomeReminder(account!);
          }
        } catch (_) {
          /* Routes remain usable if profile/preferences are unavailable. */
        }
      }
      if (!mounted) return;
      setState(() {
        reminders = list;
        favoriteId = fixedHomeReminder(list, favoriteId);
        final previousId = selectedId;
        if (!list.any((r) => '${r['id']}' == selectedId) ||
            ((autoSelectionPending || reselect) && !manualSelection)) {
          selectedId = selectHomeReminder(
            list,
            currentId: selectedId,
            favoriteId: favoriteId,
          );
        }
        autoSelectionPending = false;
        if (previousId != selectedId) {
          realtime = null;
          route = null;
          vehicleError = null;
        }
      });
      if (selected != null) {
        await refreshVehicle();
      } else {
        requestRevision++;
        setState(() {
          realtime = null;
          route = null;
          refreshing = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() => loading = false);
        openPendingPush();
      }
    }
  }

  Future<void> refreshVehicle() async {
    final reminder = selected;
    if (reminder == null) return;
    final revision = ++requestRevision;
    final routeKey = '${reminder['city_id']}:${reminder['line_id']}';
    final stopId = reminder['target_stop_id'];
    setState(() {
      refreshing = true;
      vehicleError = null;
      route = routeCache[routeKey];
      if (realtime?['lineId'] != reminder['line_id'] ||
          realtime?['targetStop']?['id'] != stopId) {
        realtime = null;
      }
    });
    // A failed metadata request must not hide vehicle positions.
    await Future.wait([
      () async {
        try {
          final result =
              routeCache[routeKey] ??
              await widget.api.data(
                '/api/routes/${Uri.encodeComponent(reminder['line_id'])}',
                query: {'cityId': reminder['city_id']},
              ) as Json;
          routeCache[routeKey] = result;
          if (mounted && revision == requestRevision) {
            setState(() => route = result);
          }
        } catch (_) {
          /* Realtime still contains the boarding stop. */
        }
      }(),
      () async {
        try {
          final result = await widget.api.data(
            '/api/routes/${Uri.encodeComponent(reminder['line_id'])}/realtime',
            query: {'cityId': reminder['city_id'], 'targetStopId': stopId},
          ) as Json;
          if (mounted && revision == requestRevision) {
            setState(() => realtime = result);
          }
        } catch (e) {
          if (mounted && revision == requestRevision) {
            setState(() => vehicleError = e.toString());
          }
        }
      }(),
    ]);
    if (mounted && revision == requestRevision) {
      setState(() => refreshing = false);
    }
  }

  Future<void> choose(Json reminder, {bool saveFavorite = false}) async {
    setState(() {
      selectedId = '${reminder['id']}';
      manualSelection = true;
      autoSelectionPending = false;
      if (saveFavorite) favoriteId = selectedId;
      realtime = null;
      route = null;
      tab = 0;
    });
    final id = selectedId!;
    unawaited(refreshVehicle());
    if (saveFavorite && account != null) {
      final owner = account!;
      preferenceWrite = preferenceWrite.then((_) async {
        try {
          await widget.api.saveHomeReminder(owner, id);
        } catch (_) {
          if (mounted) notice(context, '已切换线路，但未能保存首页常用');
        }
      });
      await preferenceWrite;
    }
  }

  Future<void> switchRoute() async {
    final choice = await showModalBottomSheet<Json>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Text('切换线路', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                '切换本次查看的线路；固定常用可在提醒中设置。',
                style: TextStyle(color: Color(0xFF66756C)),
              ),
              const SizedBox(height: 16),
              for (final r in reminders ?? <Json>[])
                ListTile(
                  key: ValueKey('choose-route-${r['id']}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('${r['line_no']} 路 · ${r['target_stop_name']}'),
                  subtitle: Text(direction(r)),
                  trailing: '${r['id']}' == selectedId
                      ? const Icon(Icons.check_circle, color: green)
                      : const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, r),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice != null && mounted) await choose(choice);
  }

  Future<void> openDetail(Json reminder) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(api: widget.api, reminder: reminder),
      ),
    );
    if (mounted) await load();
  }

  Future<void> editReminder(Json reminder) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReminderEditor(api: widget.api, reminder: reminder),
      ),
    );
    if (mounted) await load();
  }

  Future<void> changeReminder(Json reminder, String action) async {
    final id = '${reminder['id']}';
    if (loading || changingReminders.isNotEmpty) return;
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('删除这条通勤提醒？'),
          content: Text(
            '${reminder['line_no']} 路 · ${reminder['target_stop_name']}\n删除后将不再发送这条提醒。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('保留'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      changingReminders.add(id);
      reminderErrors.remove(id);
    });
    try {
      if (action == 'delete') {
        await widget.api.request('/api/reminders/$id', method: 'DELETE');
        if (!mounted) return;
        setState(() {
          reminders!.removeWhere((r) => '${r['id']}' == id);
          changingReminders.remove(id);
        });
        await load();
      } else if (action == 'pause') {
        final result = await widget.api.data(
          '/api/reminders/$id/pause-today',
          method: 'POST',
        );
        if (!mounted) return;
        setState(() => reminder['paused_until'] = result['pausedUntil']);
      } else {
        final active = pausedToday(reminder) || !isOn(reminder['active']);
        await widget.api.data(
          '/api/reminders/$id',
          method: 'PATCH',
          body: {'active': active},
        );
        if (!mounted) return;
        setState(() {
          reminder['active'] = active;
          reminder['paused_until'] = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => reminderErrors[id] =
              e is ApiException && e.status == 404 && action == 'pause'
              ? '服务端尚未支持今天暂停，原有提醒保持不变。'
              : '未能${action == 'delete' ? '删除' : '更新'}，原有提醒保持不变。$e',
        );
      }
    } finally {
      if (mounted) setState(() => changingReminders.remove(id));
    }
  }

  Future<void> settings() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          api: widget.api,
          push: push,
          onLogout: widget.onLogout,
        ),
      ),
    );
    if (mounted) {
      setState(() => pushIssue = null);
      await load();
    }
  }

  Future<void> addReminder() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReminderEditor(api: widget.api, onSetup: settings),
      ),
    );
    if (mounted) await load();
  }

  void selectTab(int value) {
    final enteringHome = tab != 0 && value == 0;
    setState(() => tab = value);
    if (enteringHome && !manualSelection) {
      load(reselect: true);
      return;
    }
    if (value == 0 && !refreshing && realtime != null && isStale(realtime!)) {
      refreshVehicle();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          const AppBrandIcon(size: 30),
          const SizedBox(width: 8),
          Text(
            ['下班王', '通勤提醒', '我的'][tab],
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ],
      ),
      actions: [
        if (tab < 2)
          IconButton(
            tooltip: tab == 0 ? '刷新车辆' : '刷新提醒',
            onPressed: loading || refreshing ? null : () => load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        const SizedBox(width: 8),
      ],
    ),
    body: IndexedStack(
      index: tab,
      children: [
        ridePage(),
        remindersPage(),
        SettingsScreen(
          api: widget.api,
          push: push,
          onLogout: widget.onLogout,
          embedded: true,
          profile: profile,
        ),
      ],
    ),
    floatingActionButton: tab == 1 && reminders?.isNotEmpty == true
        ? FloatingActionButton.extended(
            onPressed: addReminder,
            backgroundColor: green,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('添加通勤提醒'),
          )
        : null,
    bottomNavigationBar: DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E9DF))),
      ),
      child: pageWidth(
        NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: selectTab,
          backgroundColor: Colors.white,
          elevation: 0,
          height: 72,
          indicatorColor: const Color(0xFFE1ECCD),
          destinations: const [
            NavigationDestination(
              key: ValueKey('tab-ride'),
              icon: Icon(Icons.directions_bus_outlined),
              selectedIcon: Icon(Icons.directions_bus),
              label: '乘车',
            ),
            NavigationDestination(
              key: ValueKey('tab-reminders'),
              icon: Icon(Icons.notifications_none_rounded),
              selectedIcon: Icon(Icons.notifications_rounded),
              label: '提醒',
            ),
            NavigationDestination(
              key: ValueKey('tab-profile'),
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: '我的',
            ),
          ],
        ),
      ),
    ),
  );

  Widget emptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 60),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFFE7EEDC),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.directions_bus_outlined,
            size: 48,
            color: green,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          '先选一条常坐的线路',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        const Text(
          '地图、车辆位置和到站距离，\n打开就能看到。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF66756C), height: 1.7),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: addReminder,
          icon: const Icon(Icons.add),
          label: const Text('添加通勤提醒'),
        ),
      ],
    ),
  );

  Widget ridePage() {
    final reminder = selected;
    return pageWidth(
      RefreshIndicator(
        onRefresh: load,
        child: ListView(
          key: const PageStorageKey('ride-page'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            if (widget.api.demo)
              const Text(
                '界面预览 · 演示数据，不发送通知',
                style: TextStyle(color: green, fontSize: 12),
              ),
            if (error != null) ErrorNotice(error!, load),
            if (reminders == null && error == null)
              const Padding(
                padding: EdgeInsets.all(64),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (reminders?.isEmpty == true) emptyState(),
            if (reminder != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCurrentReminder(reminder)
                              ? '当前提醒 · ${reminder['window_start'] == null ? '全天' : timeWindow(reminder)}'
                              : selectedId == favoriteId
                              ? '常用线路'
                              : '本次查看',
                          style: const TextStyle(
                            color: Color(0xFF66756C),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${reminder['line_no']} 路',
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: switchRoute,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('切换线路'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                direction(reminder),
                style: const TextStyle(color: Color(0xFF66756C)),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.trip_origin, size: 17, color: green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${reminder['target_stop_name']} 上车',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => editReminder(reminder),
                    child: Text(
                      pausedToday(reminder)
                          ? '今天暂停'
                          : isOn(reminder['active'])
                          ? '提醒设置'
                          : '提醒已暂停',
                    ),
                  ),
                ],
              ),
              if (vehicleError != null)
                ErrorNotice(vehicleError!, refreshVehicle),
              if (realtime != null)
                VehiclePanel(
                  key: ValueKey(
                    'home-vehicle-$selectedId-${reminder['line_id']}-${reminder['target_stop_id']}',
                  ),
                  realtime: realtime!,
                  route: route,
                  compact: true,
                )
              else if (refreshing)
                const Padding(
                  padding: EdgeInsets.all(56),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (pushIssue != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: Text(pushIssue!, style: const TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => selectTab(2),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget remindersPage() => pageWidth(
    RefreshIndicator(
      onRefresh: load,
      child: ListView(
        key: const PageStorageKey('reminders-page'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 96),
        children: [
          Text('按你的节奏出发', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            '点提醒改时间和重复，开关随时启停。',
            style: TextStyle(color: Color(0xFF66756C)),
          ),
          if (error != null) ErrorNotice(error!, load),
          if (reminders == null && error == null)
            const Padding(
              padding: EdgeInsets.all(64),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (reminders?.isEmpty == true) emptyState(),
          const SizedBox(height: 20),
          for (final r in reminders ?? <Json>[]) reminderRow(r),
        ],
      ),
    ),
  );

  Widget reminderRow(Json r) {
    final id = '${r['id']}';
    final busy = loading || changingReminders.isNotEmpty;
    final enabled = isOn(r['active']) && !pausedToday(r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                key: ValueKey('edit-reminder-$id'),
                onTap: busy ? null : () => editReminder(r),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        timeWindow(r),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${r['line_no']} 路 · ${r['target_stop_name']}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        scheduleLabel(r),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF66756C),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        pausedToday(r)
                            ? '今天暂停 · 明天恢复'
                            : '${enabled ? '已开启' : '已暂停'} · 提前 ${r['stations_before']} 站',
                        style: TextStyle(
                          fontSize: 12,
                          color: enabled ? green : const Color(0xFF66756C),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                Semantics(
                  label: '${r['line_no']} 路 ${r['target_stop_name']} 提醒',
                  child: Switch(
                    key: ValueKey('reminder-switch-$id'),
                    value: enabled,
                    onChanged: busy ? null : (_) => changeReminder(r, 'toggle'),
                  ),
                ),
                if (changingReminders.contains(id))
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: busy ? null : () => editReminder(r),
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('编辑规则'),
            ),
            const Spacer(),
            if (id == favoriteId)
              const Text('首页常用', style: TextStyle(color: green, fontSize: 12)),
            PopupMenuButton<String>(
              key: ValueKey('reminder-more-$id'),
              tooltip: '更多操作',
              enabled: !busy,
              onSelected: (action) {
                if (action == 'ride') {
                  openDetail(r);
                } else if (action == 'home') {
                  choose(r, saveFavorite: true);
                } else {
                  changeReminder(r, action);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'ride', child: Text('查看车辆')),
                const PopupMenuItem(value: 'home', child: Text('设为首页常用')),
                if (enabled)
                  const PopupMenuItem(value: 'pause', child: Text('今天暂停，明天继续')),
                const PopupMenuItem(value: 'delete', child: Text('删除提醒')),
              ],
            ),
          ],
        ),
        if (reminderErrors[id] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              reminderErrors[id]!,
              style: const TextStyle(color: Color(0xFFAE3F32), fontSize: 13),
            ),
          ),
        const Divider(height: 24),
      ],
    );
  }
}
