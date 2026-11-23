import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../map_tiles.dart';
import '../palette.dart';
import '../vehicles.dart';
import 'bus_marker_layer.dart';

class VehiclePanel extends StatefulWidget {
  final Json realtime;
  final Json? route;
  final bool loadMapTiles;
  final bool compact;
  const VehiclePanel({
    super.key,
    required this.realtime,
    this.route,
    this.loadMapTiles = true,
    this.compact = false,
  });

  @override
  State<VehiclePanel> createState() => _VehiclePanelState();
}

class _VehiclePanelState extends State<VehiclePanel> {
  String? selectedId;
  bool showAll = false;
  int focusRevision = 0;

  @override
  Widget build(BuildContext context) {
    final data = widget.realtime;
    final buses = upcomingBuses(data);
    final stops = objects(widget.route?['stops'] ?? [])
        .map((s) => mapStop(s, widget.route?['provider'] ?? data['provider'])!)
        .toList();
    final target = mapStop(data['targetStop'], data['provider']);
    final stale = isStale(data);
    final available = data['realData'] == true;
    final selectedIndex = buses.indexWhere((b) => '${b['id']}' == selectedId);
    final selected = selectedIndex < 0 ? 0 : selectedIndex;
    final other = objects(data['buses'] ?? [])
        .where((b) => (finiteNumber(b['stationsAway']) ?? -1) < 0)
        .toList();
    final time = DateTime.tryParse('${data['fetchedAt']}')?.toLocal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: widget.compact ? 8 : 22),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: stale || !available
                    ? const Color(0xFFFFEACB)
                    : const Color(0xFFE6EDDC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                !available
                    ? '暂无实时定位'
                    : stale
                    ? '上次位置 · 待更新'
                    : '${buses.length} 辆正在驶来',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              time == null
                  ? '更新时间未知'
                  : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} 查询',
              style: const TextStyle(fontSize: 12, color: Color(0xFF66756C)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (available) ...[
          BusMap(
            key: ValueKey('${data['lineId']}:${target?['id'] ?? ''}'),
            buses: buses,
            stops: stops,
            target: target,
            selected: selected,
            focusRevision: focusRevision,
            loadTiles: widget.loadMapTiles,
            height: widget.compact ? 240 : 280,
            stale: stale,
            fetchedAt: time,
            onSelect: (index) => setState(() {
              selectedId = '${buses[index]['id']}';
              focusRevision++;
              if (index >= 3) showAll = true;
            }),
          ),
          SizedBox(height: widget.compact ? 12 : 22),
          if (!widget.compact)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '驶向上车站',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '同线路 · 同方向',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          const SizedBox(height: 8),
          if (buses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('暂未发现驶来的车辆，稍后再刷新看看。'),
            ),
          for (
            var index = 0;
            index < (showAll ? buses.length : buses.length.clamp(0, 3));
            index++
          )
            if (widget.compact)
              _CompactVehicleRow(
                bus: buses[index],
                nearest: index == 0,
                selected: selected == index,
                target: target,
                stops: stops,
                stale: stale,
                onTap: () => setState(() {
                  selectedId = '${buses[index]['id']}';
                  focusRevision++;
                }),
              )
            else
              _VehicleRow(
                bus: buses[index],
                selected: selected == index,
                target: target,
                stops: stops,
                stale: stale,
                onTap: () => setState(() {
                  selectedId = '${buses[index]['id']}';
                  focusRevision++;
                }),
              ),
          if (buses.length > 3)
            TextButton(
              onPressed: () => setState(() => showAll = !showAll),
              child: Text(showAll ? '收起后续车辆' : '再看后续 ${buses.length - 3} 辆车'),
            ),
          if (other.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '已驶过 / 位置待确认 · ${other.length} 辆',
                style: const TextStyle(fontSize: 13, color: Color(0xFF66756C)),
              ),
              children: [
                for (final bus in other)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.directions_bus_outlined,
                      color: Colors.grey,
                    ),
                    title: Text(busLocation(bus, stops)),
                    subtitle: Text(
                      '${(finiteNumber(bus['stationsAway']) ?? 0) < 0 ? '已驶过上车站' : '站数待更新'} · ${busDistance(bus, target)?.label ?? '距离待更新'}',
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          const Text(
            '小车根据最近定位模拟移动。距离以你的上车站为终点。直线距离根据定位估算，不代表行驶里程；车辆与预计到达时间以上游更新为准。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF66756C),
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('线路暂未提供实时车辆位置，请稍后刷新。'),
          ),
      ],
    );
  }
}

class _CompactVehicleRow extends StatelessWidget {
  final Json bus;
  final dynamic target;
  final List<Json> stops;
  final bool nearest;
  final bool selected, stale;
  final VoidCallback onTap;
  const _CompactVehicleRow({
    required this.bus,
    required this.target,
    required this.stops,
    required this.nearest,
    required this.selected,
    required this.stale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: nearest ? 14 : 12,
          ),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF0E2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? green : const Color(0xFFE3E9DC),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.directions_bus_rounded,
                  size: 17,
                  color: selected ? Colors.white : green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (nearest)
                      const Text(
                        '最近一辆',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF66756C),
                        ),
                      ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          arrivalLabel(bus),
                          style: TextStyle(
                            fontSize: nearest ? 25 : 16,
                            fontWeight: FontWeight.w800,
                            height: 1.4,
                          ),
                        ),
                        Text(
                          stale ? '上次位置' : etaLabel(bus),
                          style: const TextStyle(fontSize: 13, color: green),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      busDistance(bus, target)?.label ?? '距离暂未提供',
                      style: TextStyle(
                        fontSize: nearest ? 16 : 13,
                        fontWeight: nearest ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${busLocation(bus, stops)}${coordinates(bus) == null ? ' · 无定位' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF66756C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleRow extends StatelessWidget {
  final Json bus;
  final dynamic target;
  final List<Json> stops;
  final bool selected, stale;
  final VoidCallback onTap;
  const _VehicleRow({
    required this.bus,
    required this.target,
    required this.stops,
    required this.selected,
    required this.stale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Material(
      color: selected ? const Color(0xFFE9EFDF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? const Color(0xFFB6C9A2) : const Color(0xFFE6E9DF),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? green : const Color(0xFFE9EDE5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.directions_bus_rounded,
                  size: 19,
                  color: selected ? Colors.white : ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          arrivalLabel(bus),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          stale ? '上次位置' : etaLabel(bus),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF66756C),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      busDistance(bus, target)?.label ?? '距上车站：暂未提供',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${busLocation(bus, stops)}${coordinates(bus) == null ? ' · 无定位' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF66756C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class BusMap extends StatefulWidget {
  final List<Json> buses, stops;
  final Json? target;
  final int selected, focusRevision;
  final bool loadTiles, stale;
  final DateTime? fetchedAt;
  final double height;
  final ValueChanged<int> onSelect;
  const BusMap({
    super.key,
    required this.buses,
    required this.stops,
    required this.target,
    required this.selected,
    this.focusRevision = 0,
    required this.onSelect,
    this.loadTiles = true,
    this.stale = false,
    this.fetchedAt,
    this.height = 280,
  });
  @override
  State<BusMap> createState() => _BusMapState();
}

class _BusMapState extends State<BusMap> {
  final controller = MapController();
  bool ready = false, tileFailed = false;
  int tileAttempt = 0;
  List<({LatLng point, LatLng estimate})?> locations = [];

  void updateLocations() {
    final stops = {
      for (final stop in [...widget.stops, ?widget.target])
        ?finiteNumber(stop['order']): ?coordinates(stop),
    };
    locations = [
      for (final bus in widget.buses)
        if (coordinates(bus) case final point?)
          (
            point: point,
            estimate: widget.stale
                ? point
                : estimatedBusPoint(
                    bus,
                    point,
                    stops[finiteNumber(bus['order'])],
                  ),
          )
        else
          null,
    ];
  }

  @override
  void initState() {
    super.initState();
    updateLocations();
  }

  List<LatLng> get points => [
    ?coordinates(widget.target),
    for (final location in locations.nonNulls.take(3)) ...[
      location.point,
      location.estimate,
    ],
  ];

  CameraFit fit(List<LatLng> positions) => CameraFit.coordinates(
    coordinates: positions,
    padding: const EdgeInsets.fromLTRB(72, 78, 72, 54),
    maxZoom: 16,
  );

  @override
  void didUpdateWidget(covariant BusMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateLocations();
    // Do not reset the user's viewport on every data refresh.
    if (ready &&
        widget.focusRevision != oldWidget.focusRevision &&
        widget.selected < widget.buses.length) {
      final location = locations[widget.selected];
      if (location != null) {
        controller.fitCamera(
          fit([location.point, location.estimate, ?coordinates(widget.target)]),
        );
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Key busKey(int index, LatLng point) {
    final id = widget.buses[index]['id']?.toString() ?? '';
    // The provider falls back to station order when a vehicle has no ID.
    return id.isEmpty || id.startsWith('unknown-')
        ? ValueKey((id, point, index))
        : ValueKey(id);
  }

  String busLabel(Json bus) {
    final stations = finiteNumber(bus['stationsAway']);
    final stops = stations != null && stations > 0
        ? '还有 ${stations.toInt()} 站'
        : arrivalLabel(bus);
    return "${widget.stale ? '上次位置' : etaLabel(bus)} · $stops";
  }

  void tileError(int attempt) {
    if (tileFailed || attempt != tileAttempt) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !tileFailed && attempt == tileAttempt) {
        setState(() => tileFailed = true);
      }
    });
    // A network error can arrive while Flutter is idle (especially on Safari).
    // Post-frame callbacks alone do not request a frame, leaving errors hidden.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final positions = points;
    if (positions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFFE9EDE5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          children: [
            Icon(Icons.location_off_outlined, size: 30, color: green),
            SizedBox(height: 10),
            Text('暂未提供定位'),
            SizedBox(height: 5),
            Text(
              '有坐标后会在这里显示地图',
              style: TextStyle(fontSize: 12, color: Color(0xFF66756C)),
            ),
          ],
        ),
      );
    }
    final missing = locations.where((location) => location == null).length;
    final attempt = tileAttempt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: controller,
                  options: MapOptions(
                    initialCameraFit: fit(positions),
                    minZoom: 3,
                    maxZoom: 19,
                    backgroundColor: const Color(0xFFE8ECDF),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    onMapReady: () => ready = true,
                  ),
                  children: [
                    if (widget.loadTiles)
                      BusMapTiles(
                        key: ValueKey(tileAttempt),
                        onError: () => tileError(attempt),
                      ),
                    MarkerLayer(
                      markers: [
                        for (final stop in widget.stops)
                          if (coordinates(stop) case final point?)
                            Marker(
                              point: point,
                              width: 12,
                              height: 12,
                              child: Tooltip(
                                message: '${stop['name']}',
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: green, width: 2),
                                  ),
                                ),
                              ),
                            ),
                        if (coordinates(widget.target) case final point?)
                          Marker(
                            point: point,
                            width: 94,
                            height: 44,
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: ink,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                              child: const Text(
                                '上车站',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    // Keep the selected bus and its callout above nearby buses.
                    for (final i in [
                      for (var index = 0; index < widget.buses.length; index++)
                        if (index != widget.selected) index,
                      if (widget.selected < widget.buses.length)
                        widget.selected,
                    ])
                      if (locations[i] case final location?)
                        BusMarkerLayer(
                          key: busKey(i, location.point),
                          point: location.point,
                          estimatedPoint: location.estimate,
                          fetchedAt: widget.fetchedAt,
                          stale: widget.stale,
                          stopped:
                              finiteNumber(widget.buses[i]['speedKph']) == 0 ||
                              finiteNumber(widget.buses[i]['etaSeconds']) == 0,
                          selected: widget.selected == i,
                          label: busLabel(widget.buses[i]),
                          buttonKey: ValueKey('bus-marker-$i'),
                          onTap: () => widget.onSelect(i),
                        ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Material(
                        color: Colors.white,
                        child: InkWell(
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://www.openstreetmap.org/copyright',
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(5),
                            child: Text(
                              '© OpenStreetMap contributors',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (locations.any((location) => location != null))
                  Positioned(
                    bottom: 8,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        widget.stale ? '上次车辆位置' : '模拟位置 · 点车查看',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filledTonal(
                    tooltip: '查看上车站和附近车辆',
                    style: IconButton.styleFrom(backgroundColor: Colors.white),
                    onPressed: () {
                      if (ready) controller.fitCamera(fit(points));
                    },
                    icon: const Icon(Icons.center_focus_strong, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (tileFailed)
          Row(
            children: [
              const Expanded(
                child: Text('底图加载失败，车辆信息仍可查看', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => setState(() {
                  tileFailed = false;
                  tileAttempt++;
                }),
                child: const Text('重试地图'),
              ),
            ],
          ),
        if (missing > 0 || coordinates(widget.target) == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${missing > 0 ? '$missing 辆车暂无坐标，未标在地图上。' : ''}${coordinates(widget.target) == null ? '上车站暂无坐标。' : ''}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF66756C)),
            ),
          ),
      ],
    );
  }
}
