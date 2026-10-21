import 'package:latlong2/latlong.dart';

double _d(dynamic v, [double def = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? def;
  return def;
}

String _s(dynamic v, [String def = '']) => v == null ? def : v.toString();

Map<String, dynamic> _m(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> _l(dynamic v) => v is List ? v : <dynamic>[];

class Junction {
  final String id;
  final String name;
  final LatLng point;
  final double chain;
  Junction(this.id, this.name, this.point, this.chain);

  factory Junction.fromJson(Map<String, dynamic> j) => Junction(
        _s(j['id']),
        _s(j['name'], 'Junction'),
        LatLng(_d(j['lat']), _d(j['lng'])),
        _d(j['chain']),
      );
}

class RouteInfo {
  final List<LatLng> points;
  final List<Junction> junctions;
  final double distance;
  final double duration;
  final bool fallback;
  RouteInfo(this.points, this.junctions, this.distance, this.duration, this.fallback);

  factory RouteInfo.fromJson(Map<String, dynamic> j) {
    final pts = <LatLng>[];
    for (final e in _l(j['points'])) {
      final l = _l(e);
      if (l.length >= 2) pts.add(LatLng(_d(l[0]), _d(l[1])));
    }
    return RouteInfo(
      pts,
      _l(j['junctions']).map((e) => Junction.fromJson(_m(e))).toList(),
      _d(j['distance']),
      _d(j['duration']),
      j['fallback'] == true,
    );
  }
}

class PlaceResult {
  final String name;
  final LatLng point;
  PlaceResult(this.name, this.point);
}

class NextJunction {
  final String id;
  final String name;
  final LatLng point;
  final double distance;
  NextJunction(this.id, this.name, this.point, this.distance);
}

class PostInfo {
  final String id;
  final String name;
  final LatLng point;
  final double radius;
  final double distAhead;
  final String status;
  final bool acked;
  PostInfo(this.id, this.name, this.point, this.radius, this.distAhead, this.status, this.acked);
}

class PoliceAction {
  final String postName;
  final String action;
  final int at;
  PoliceAction(this.postName, this.action, this.at);

  String get label {
    switch (action) {
      case 'ack':
        return 'Alert acknowledged';
      case 'clear_lane':
        return 'Clearing the lane';
      case 'escalate':
        return 'Escalated';
      default:
        return action;
    }
  }
}

class TripState {
  final String status; // ok | off_route | completed | stopped
  final double chain;
  final double total;
  final double remaining;
  final double etaSec;
  final NextJunction? nextJunction;
  final List<PostInfo> posts;
  final List<PoliceAction> actions;

  TripState({
    required this.status,
    required this.chain,
    required this.total,
    required this.remaining,
    required this.etaSec,
    required this.nextJunction,
    required this.posts,
    required this.actions,
  });

  factory TripState.fromJson(Map<String, dynamic> j) {
    NextJunction? nj;
    if (j['nextJunction'] is Map) {
      final n = _m(j['nextJunction']);
      nj = NextJunction(_s(n['id']), _s(n['name'], 'Junction'),
          LatLng(_d(n['lat']), _d(n['lng'])), _d(n['distance']));
    }
    return TripState(
      status: _s(j['status'], 'ok'),
      chain: _d(j['chain']),
      total: _d(j['total']),
      remaining: _d(j['remaining']),
      etaSec: _d(j['etaSec']),
      nextJunction: nj,
      posts: _l(j['posts']).map((e) {
        final p = _m(e);
        return PostInfo(_s(p['id']), _s(p['name'], 'Police Post'),
            LatLng(_d(p['lat']), _d(p['lng'])), _d(p['radius'], 500),
            _d(p['distAhead']), _s(p['status'], 'standby'), p['acked'] == true);
      }).toList(),
      actions: _l(j['actions']).map((e) {
        final a = _m(e);
        return PoliceAction(_s(a['postName']), _s(a['action']), _d(a['at']).round());
      }).toList(),
    );
  }
}
