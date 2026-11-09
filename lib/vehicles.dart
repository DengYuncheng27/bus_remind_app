import 'package:latlong2/latlong.dart';

import 'coordinate_transform.dart';

typedef VehicleJson = Map<String, dynamic>;

// Older Chelaile API responses omitted the coordinate-system marker on stops.
// Only station coordinates need this compatibility path, never bus positions.
VehicleJson? mapStop(dynamic stop, dynamic provider) {
  if (stop is! Map) return null;
  return {
    ...Map<String, dynamic>.from(stop),
    if (stop['coordinateSystem'] == null && provider == 'chelaile')
      'coordinateSystem': 'bd09',
  };
}

double? finiteNumber(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  return number != null && number.isFinite ? number : null;
}

LatLng? coordinates(dynamic value) {
  if (value is! Map) return null;
  final lat = finiteNumber(value['lat']), lng = finiteNumber(value['lng']);
  if (lat == null ||
      lng == null ||
      lat.abs() > 85.05112878 ||
      lng.abs() > 180 ||
      (lat == 0 && lng == 0) ||
      (lat == -1 && lng == -1)) {
    return null;
  }
  final point = LatLng(lat, lng);
  return value['coordinateSystem'] == 'bd09' ? bd09ToWgs84(point) : point;
}

List<VehicleJson> upcomingBuses(VehicleJson? realtime) {
  final buses = (realtime?['buses'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .where((b) => (finiteNumber(b['stationsAway']) ?? -1) >= 0)
      .toList();
  buses.sort((a, b) {
    final stations = finiteNumber(a['stationsAway'])!
        .compareTo(finiteNumber(b['stationsAway'])!);
    if (stations != 0) return stations;
    // ETA is along the route; straight-line distance cannot reliably order buses.
    final eta = (finiteNumber(a['etaSeconds']) ?? double.infinity).compareTo(
      finiteNumber(b['etaSeconds']) ?? double.infinity,
    );
    return eta != 0 ? eta : '${a['id']}'.compareTo('${b['id']}');
  });
  return buses;
}

class BusDistance {
  final double meters;
  final bool straightLine;
  const BusDistance(this.meters, {this.straightLine = false});
  String get label => '${straightLine ? '直线约 ' : '距上车站 '}${meters.round()} 米';
}

BusDistance? busDistance(VehicleJson bus, dynamic target) {
  final reported = finiteNumber(bus['distanceMeters']);
  // Legacy APIs used the same field for distance to the NEXT stop. Only trust
  // a distance explicitly identified as belonging to the requested target.
  if (bus['distanceSource'] == 'target-stop' &&
      reported != null &&
      reported >= 0) {
    return BusDistance(reported);
  }
  final position = coordinates(bus), destination = coordinates(target);
  if (position == null || destination == null) return null;
  return BusDistance(
    const Distance(calculator: Haversine())
        .as(LengthUnit.Meter, position, destination),
    straightLine: true,
  );
}

String arrivalLabel(VehicleJson bus) {
  final stations = finiteNumber(bus['stationsAway']);
  return stations == null
      ? '站数待更新'
      : stations == 0
      ? '到站附近'
      : '${stations.toInt()} 站后到达';
}

String etaLabel(VehicleJson bus) {
  final seconds = finiteNumber(bus['etaSeconds']);
  return seconds == null || seconds < 0
      ? '时间待更新'
      : seconds < 60
      ? '预计 1 分钟内'
      : '约 ${(seconds / 60).ceil()} 分钟';
}

String busLocation(VehicleJson bus, List<VehicleJson> stops) {
  final order = finiteNumber(bus['order']);
  if (order != null && order > 0) {
    for (final stop in stops) {
      if (finiteNumber(stop['order']) == order) return '${stop['name']}附近';
    }
  }
  return coordinates(bus) == null ? '车辆位置待更新' : '具体位置见地图';
}
