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
  final String category; // hospital | police | transport | market | ... | other
  final bool local; // true = saved in our own places database
  final int? distance; // metres from the user (if known)
  PlaceResult(this.name, this.point,
      {this.category = 'other', this.local = false, this.distance});
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
        return 'Police saw your alert';
      case 'clear_lane':
        return 'Police are clearing the lane';
      case 'escalate':
        return 'Police asked for help';
      default:
        return action;
    }
  }
}

/// A police post whose phone is online (shown on the driver map, even when it is not on the route).
class PolicePost {
  final String id;
  final String name;
  final String area;
  final LatLng point;
  final double radius;
  PolicePost(this.id, this.name, this.area, this.point, this.radius);

  factory PolicePost.fromJson(Map<String, dynamic> j) => PolicePost(
        _s(j['id']),
        _s(j['name'], 'Police Post'),
        _s(j['area']),
        LatLng(_d(j['lat']), _d(j['lng'])),
        _d(j['radius'], 500),
      );
}

/// State of one IoT device (display + buzzer).
class IotDevice {
  final String id;
  final bool online;
  final int? lastSeenSec;
  final bool auto;
  final bool displayOn;
  final String displayText;
  final bool buzzerOn;
  final String buzzerPattern;
  final int buzzerRemaining;
  IotDevice({
    required this.id,
    required this.online,
    required this.lastSeenSec,
    required this.auto,
    required this.displayOn,
    required this.displayText,
    required this.buzzerOn,
    required this.buzzerPattern,
    required this.buzzerRemaining,
  });

  factory IotDevice.fromJson(Map<String, dynamic> j) {
    final d = _m(j['display']);
    final b = _m(j['buzzer']);
    return IotDevice(
      id: _s(j['id']),
      online: j['online'] == true,
      lastSeenSec: j['lastSeenSec'] is num ? (j['lastSeenSec'] as num).round() : null,
      auto: j['auto'] != false,
      displayOn: d['on'] == true,
      displayText: _s(d['text']),
      buzzerOn: b['on'] == true,
      buzzerPattern: _s(b['pattern'], 'off'),
      buzzerRemaining: _d(b['remainingSec']).round(),
    );
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
  final bool critical;

  TripState({
    required this.status,
    required this.chain,
    required this.total,
    required this.remaining,
    required this.etaSec,
    required this.nextJunction,
    required this.posts,
    required this.actions,
    this.critical = false,
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
      critical: _s(j['priority']) == 'critical',
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
