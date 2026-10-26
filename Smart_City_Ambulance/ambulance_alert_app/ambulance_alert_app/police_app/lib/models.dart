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

class AlertMessage {
  final String text;
  final int at;
  AlertMessage(this.text, this.at);
}

/// Any ambulance that is driving right now (shown on the police map).
class LiveAmb {
  final String tripId;
  final String ambulanceId;
  final String driverName;
  final LatLng point;
  final int speedKmh;
  final bool critical;
  final String destination;
  final int gpsAgeSec;
  final double distToPost;
  final double etaSec;
  LiveAmb({
    required this.tripId,
    required this.ambulanceId,
    required this.driverName,
    required this.point,
    required this.speedKmh,
    required this.critical,
    required this.destination,
    required this.gpsAgeSec,
    required this.distToPost,
    required this.etaSec,
  });

  factory LiveAmb.fromJson(Map<String, dynamic> j) => LiveAmb(
        tripId: _s(j['tripId']),
        ambulanceId: _s(j['ambulanceId'], 'AMB'),
        driverName: _s(j['driverName']),
        point: LatLng(_d(j['lat']), _d(j['lng'])),
        speedKmh: _d(j['speedKmh']).round(),
        critical: _s(j['priority']) == 'critical',
        destination: _s(j['destination']),
        gpsAgeSec: _d(j['gpsAgeSec']).round(),
        distToPost: _d(j['distToPost']),
        etaSec: _d(j['etaSec']),
      );
}

class AlertsResult {
  final List<AmbAlert> alerts;
  final List<LiveAmb> ambulances;
  AlertsResult(this.alerts, this.ambulances);
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
  final bool critical;
  final AlertMessage? message;
  final int speedKmh;

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
    this.critical = false,
    this.message,
    this.speedKmh = 0,
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
      critical: _s(j['priority']) == 'critical',
      message: j['message'] is Map
          ? AlertMessage(_s(_m(j['message'])['text']), _d(_m(j['message'])['at']).round())
          : null,
      speedKmh: _d(j['speedKmh']).round(),
    );
  }
}
