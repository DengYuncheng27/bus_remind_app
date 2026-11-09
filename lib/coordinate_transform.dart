// BD-09 -> GCJ-02 -> WGS-84 approximation, adapted from wandergis/coordtransform.
// Copyright (c) 2015 记忆的残骸. MIT license: ../THIRD_PARTY_NOTICES.md.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

LatLng bd09ToWgs84(LatLng point) {
  const xPi = math.pi * 3000 / 180;
  final x = point.longitude - .0065, y = point.latitude - .006;
  final z = math.sqrt(x * x + y * y) - .00002 * math.sin(y * xPi);
  final theta = math.atan2(y, x) - .000003 * math.cos(x * xPi);
  final lng = z * math.cos(theta), lat = z * math.sin(theta);
  if (lng <= 73.66 || lng >= 135.05 || lat <= 3.86 || lat >= 53.55) {
    return LatLng(lat, lng);
  }
  final a = lng - 105, b = lat - 35;
  final wave =
      (20 * math.sin(6 * a * math.pi) + 20 * math.sin(2 * a * math.pi)) * 2 / 3;
  var dlat =
      -100 +
      2 * a +
      3 * b +
      .2 * b * b +
      .1 * a * b +
      .2 * math.sqrt(a.abs()) +
      wave;
  dlat += (20 * math.sin(b * math.pi) + 40 * math.sin(b / 3 * math.pi)) * 2 / 3;
  dlat +=
      (160 * math.sin(b / 12 * math.pi) + 320 * math.sin(b * math.pi / 30)) *
      2 /
      3;
  var dlng =
      300 +
      a +
      2 * b +
      .1 * a * a +
      .1 * a * b +
      .1 * math.sqrt(a.abs()) +
      wave;
  dlng += (20 * math.sin(a * math.pi) + 40 * math.sin(a / 3 * math.pi)) * 2 / 3;
  dlng +=
      (150 * math.sin(a / 12 * math.pi) + 300 * math.sin(a / 30 * math.pi)) *
      2 /
      3;
  const axis = 6378245.0, eccentricity = .00669342162296594323;
  final rad = lat / 180 * math.pi;
  final magic = 1 - eccentricity * math.pow(math.sin(rad), 2);
  dlat =
      dlat *
      180 /
      (axis * (1 - eccentricity) / (magic * math.sqrt(magic)) * math.pi);
  dlng = dlng * 180 / (axis / math.sqrt(magic) * math.cos(rad) * math.pi);
  return LatLng(lat - dlat, lng - dlng);
}
