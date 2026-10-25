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

class PlaceResult {
  final String name;
  final LatLng point;
  final String category; // hospital | police | transport | market | ... | other
  final bool local; // true = saved in our own places database
  final int? distance; // metres from the user (if known)
  PlaceResult(this.name, this.point,
      {this.category = 'other', this.local = false, this.distance});
}

class AlertAction {
  final String action;
  final int at;
  final String officer;
  AlertAction(this.action, this.at, this.officer);

  String get label {
    switch (action) {
      case 'ack':
        return 'Alert seen';
      case 'clear_lane':
        return 'Clearing the lane';
      case 'escalate':
        return 'Asked for help';
      default:
        return action;
    }
  }
}

class AmbAlert {
  final String tripId;
  final String ambulanceId;
  final String driverName;
  final String status; // standby | approaching | imminent | passed | paused | test
  final bool test;
  final double distAhead;
  final double etaSec;
  final LatLng amb;
  final String destination;
  final List<LatLng> route;
  final bool acked;
  final List<AlertAction> actions;
  final int gpsAgeSec;

  AmbAlert({
    required this.tripId,
    required this.ambulanceId,
    required this.driverName,
    required this.status,
    required this.test,
    required this.distAhead,
    required this.etaSec,
    required this.amb,
    required this.destination,
    required this.route,
    required this.acked,
    required this.actions,
    required this.gpsAgeSec,
  });

  bool get hasAction => actions.isNotEmpty;
  bool did(String a) => actions.any((x) => x.action == a);

  factory AmbAlert.fromJson(Map<String, dynamic> j) {
    final amb = _m(j['amb']);
    final pts = <LatLng>[];
    for (final e in _l(j['route'])) {
      final l = _l(e);
      if (l.length >= 2) pts.add(LatLng(_d(l[0]), _d(l[1])));
    }
    return AmbAlert(
      tripId: _s(j['tripId']),
      ambulanceId: _s(j['ambulanceId'], 'AMB'),
      driverName: _s(j['driverName']),
      status: _s(j['status'], 'standby'),
      test: j['test'] == true,
      distAhead: _d(j['distAhead']),
      etaSec: _d(j['etaSec']),
      amb: LatLng(_d(amb['lat']), _d(amb['lng'])),
      destination: _s(j['destination']),
      route: pts,
      acked: j['acked'] == true,
      actions: _l(j['actions']).map((e) {
        final a = _m(e);
        return AlertAction(_s(a['action']), _d(a['at']).round(), _s(a['officer']));
      }).toList(),
      gpsAgeSec: _d(j['gpsAgeSec']).round(),
    );
  }
}
