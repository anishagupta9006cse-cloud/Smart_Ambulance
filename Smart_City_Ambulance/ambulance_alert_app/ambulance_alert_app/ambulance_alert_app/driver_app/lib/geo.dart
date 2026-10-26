import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

double haversine(LatLng a, LatLng b) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180.0;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(s)));
}

String fmtDist(double m) {
  if (m < 1000) return '${m.round()} m';
  return '${(m / 1000).toStringAsFixed(1)} km';
}

String fmtDur(num sec) {
  final s = sec.round();
  if (s < 60) return '$s sec';
  final m = (s / 60).round();
  if (m < 60) return '$m min';
  return '${m ~/ 60} hr ${m % 60} min';
}

/// Route polyline + cumulative distance (used for simulation and the progress line).
class RouteTrack {
  final List<LatLng> points;
  final List<double> cum = [];

  RouteTrack(this.points) {
    cum.add(0);
    for (var i = 1; i < points.length; i++) {
      cum.add(cum[i - 1] + haversine(points[i - 1], points[i]));
    }
  }

  double get total => cum.isEmpty ? 0 : cum.last;

  LatLng pointAt(double chain) {
    if (points.isEmpty) return const LatLng(0, 0);
    if (chain <= 0) return points.first;
    if (chain >= total) return points.last;
    var lo = 0;
    var hi = cum.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] <= chain) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final seg = cum[hi] - cum[lo];
    final t = seg <= 0 ? 0.0 : (chain - cum[lo]) / seg;
    return LatLng(
      points[lo].latitude + (points[hi].latitude - points[lo].latitude) * t,
      points[lo].longitude + (points[hi].longitude - points[lo].longitude) * t,
    );
  }

  List<LatLng> upTo(double chain) {
    final out = <LatLng>[];
    for (var i = 0; i < points.length && cum[i] <= chain; i++) {
      out.add(points[i]);
    }
    if (out.isEmpty) return out;
    out.add(pointAt(chain));
    return out;
  }
}
