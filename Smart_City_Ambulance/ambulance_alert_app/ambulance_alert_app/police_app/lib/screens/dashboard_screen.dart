import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:wakelock_plus/wakelock_plus.dart';
import '../api.dart';
import '../config.dart';
import '../geo.dart';
import '../models.dart';
import '../profile.dart';
import '../theme.dart';
import '../voice.dart';
import 'help_screen.dart';
import 'iot_panel.dart';
import 'setup_screen.dart';

class DashboardScreen extends StatefulWidget {
  final PostProfile profile;
  const DashboardScreen({super.key, required this.profile});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final MapController _map = MapController();
  bool _mapReady = false;
  bool _autoFit = true;

  late PostProfile _p;
  List<AmbAlert> _alerts = [];
  List<LiveAmb> _live = [];
  Timer? _pollTimer;
  bool _polling = false;
  int _fails = 0;
  bool _online = false;
  bool _netBanner = false;
  String? _banner;
  io.Socket? _socket;

  // Every action button has its own "sending" flag, so one slow request never locks the other buttons.
  final Set<String> _inflight = {};

  final Map<String, String> _lastStatus = {};
  final Map<String, DateTime> _lastSpoke = {};
  final Map<String, int> _lastMsgAt = {};

  LatLng get _postPoint => LatLng(_p.lat, _p.lng);

  @override
  void initState() {
    super.initState();
    _p = widget.profile;
    try {
      WakelockPlus.enable();
    } catch (_) {}
    Voice.I.init();
    _boot();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    try {
      _socket?.dispose();
    } catch (_) {}
    try {
      WakelockPlus.disable();
    } catch (_) {}
    Voice.I.stop();
    super.dispose();
  }

  Future<void> _boot() async {
    await _register();
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    _connectSocket();
  }

  Future<void> _register() async {
    try {
      final id = await Api.I.registerPost(_p);
      if (id != _p.id) {
        _p = _p.withId(id);
        try {
          await _p.save();
        } catch (_) {}
      }
      _socket?.emit('join_post', _p.id);
    } catch (e) {
      if (mounted) setState(() => _banner = e.toString());
    }
  }

  void _connectSocket() {
    try {
      final s = io.io(
        Api.I.baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .enableReconnection()
            .build(),
      );
      s.onConnect((_) => s.emit('join_post', _p.id));
      s.on('refresh', (_) => _poll());
      _socket = s;
    } catch (_) {}
  }

  Future<void> _poll() async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final res = await Api.I.alerts(_p.id);
      _fails = 0;
      if (!mounted) return;
      setState(() {
        _alerts = res.alerts;
        _live = res.ambulances;
        _online = true;
        if (_netBanner) {
          _banner = null;
          _netBanner = false;
        }
      });
      _handleAlerts(res.alerts);
      _fitIfNeeded();
    } on ApiException catch (e) {
      if (e.code == 'POST_NOT_FOUND') {
        await _register();
      } else {
        _fail(e.message);
      }
    } catch (_) {
      _fail('Network connection issue');
    } finally {
      _polling = false;
    }
  }

  void _fail(String msg) {
    _fails++;
    if (_fails >= 2 && mounted) {
      setState(() {
        _online = false;
        _netBanner = true;
        _banner = 'Connection lost. Trying again...';
      });
    }
  }

  void _handleAlerts(List<AmbAlert> alerts) {
    final keys = <String>{};
    for (final a in alerts) {
      final key = a.test ? '${a.tripId}_test' : a.tripId;
      keys.add(key);
      final prev = _lastStatus[key];
      final changed = prev != a.status;
      final last = _lastSpoke[key];
      final repeatDue = a.status == 'imminent' &&
          !a.acked &&
          (last == null || DateTime.now().difference(last).inSeconds >= 15);
      if (a.status == 'approaching' ||
          a.status == 'imminent' ||
          a.status == 'test') {
        if (changed || repeatDue) _announce(a, key);
      } else if (a.status == 'passed' && changed) {
        Voice.I.speak('The ambulance has passed. The alert is off now.');
      }
      _lastStatus[key] = a.status;

      // new quick message from the driver
      final m = a.message;
      if (m != null && m.at != (_lastMsgAt[a.tripId] ?? 0)) {
        final first = !_lastMsgAt.containsKey(a.tripId);
        _lastMsgAt[a.tripId] = m.at;
        if (!first || a.status != 'passed') {
          Voice.I.speak('Message from the driver. ${m.text}');
          _buzz();
        }
      }
    }
    _lastStatus.removeWhere((k, _) => !keys.contains(k));
    _lastSpoke.removeWhere((k, _) => !keys.contains(k));
  }

  void _announce(AmbAlert a, String key) {
    _lastSpoke[key] = DateTime.now();
    _buzz();
    final d = (a.distAhead / 50).round() * 50;
    if (a.status == 'test') {
      Voice.I.speak('This is a test alert.');
    } else if (a.status == 'imminent') {
      Voice.I.speak(a.critical
          ? 'Attention! Critical patient. Ambulance is very close. Clear the road now.'
          : 'Attention! Ambulance is very close. Clear the road now.');
    } else {
      Voice.I.speak(a.critical
          ? 'Attention! Critical patient. An ambulance is coming, about $d meters away. Please clear the road.'
          : 'Attention! An ambulance is coming, about $d meters away. Please clear the road.');
    }
  }

  Future<void> _buzz() async {
    for (var i = 0; i < 3; i++) {
      try {
        await HapticFeedback.heavyImpact();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 350));
    }
  }

  AmbAlert? get _primary {
    for (final a in _alerts) {
      if (a.status != 'passed') return a;
    }
    return _alerts.isEmpty ? null : _alerts.first;
  }

  void _fitIfNeeded() {
    final a = _primary;
    if (a == null || !_mapReady || !_autoFit || a.test) return;
    final pts = <LatLng>[_postPoint, a.amb, ...a.route];
    if (pts.length < 2) return;
    try {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.fromLTRB(50, 170, 50, 360),
        maxZoom: 17,
      ));
    } catch (_) {}
  }

  void _fitAllAmbulances() {
    if (!_mapReady || _live.isEmpty) return;
    final pts = <LatLng>[_postPoint, ..._live.map((x) => x.point)];
    try {
      setState(() => _autoFit = false);
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.fromLTRB(50, 170, 50, 360),
        maxZoom: 17,
      ));
    } catch (_) {}
  }

  void _centerOnPost() {
    setState(() => _autoFit = true);
    if (!_mapReady) return;
    try {
      _map.move(_postPoint, 16);
    } catch (_) {}
    _fitIfNeeded();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  bool _isSending(AmbAlert a, String action) =>
      _inflight.contains('${a.tripId}|$action');

  /// Sends one police answer. Only the pressed button shows "SENDING...".
  /// If the network fails, the button comes back after a few seconds and a message is shown.
  Future<void> _act(AmbAlert a, String action) async {
    final key = '${a.tripId}|$action';
    if (_inflight.contains(key) || a.did(action)) return;
    setState(() => _inflight.add(key));
    try {
      await Api.I.action(_p.id, a.tripId, action, _p.officer);
      _snack(action == 'ack'
          ? 'Done. The driver can see that you got the alert.'
          : action == 'clear_lane'
              ? 'Done. The driver can see you are clearing the lane.'
              : 'Done. Your request for help is saved.');
      _poll();
    } catch (e) {
      _snack('Not sent: $e  Please press the button again.');
    } finally {
      if (mounted) setState(() => _inflight.remove(key));
    }
  }

  Future<void> _endDuty() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finish duty?'),
        content: const Text('This post will not get ambulance alerts any more.'),
        actions: [
          TextButton(
              style: textColor(BtnColors.teal),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No, stay on duty')),
          FilledButton(
              style: solidButton(BtnColors.brown),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, finish')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.offDuty(_p.id);
    } catch (_) {}
    await PostProfile.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SetupScreen(existing: _p)));
  }

  void _openIot() {
    IotPanel.show(
      context,
      IotPanel(
        title: 'IoT control: display and buzzer',
        prefsKey: 'iotDeviceId',
        defaultDeviceId: _p.id,
        by: _p.officer,
        showAuto: true,
        presets: const [
          IotPreset('AMBULANCE COMING', 'AMBULANCE COMING\nCLEAR THE ROAD', BtnColors.red),
          IotPreset('KEEP LEFT', 'KEEP LEFT\nMAKE WAY', BtnColors.orange),
          IotPreset('STOP VEHICLES', 'STOP\nAMBULANCE PASSING', BtnColors.brown),
          IotPreset('ROAD CLEAR', 'ROAD CLEAR\nDRIVE SAFE', BtnColors.green),
        ],
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'imminent':
        return Colors.red;
      case 'approaching':
        return Colors.orange.shade800;
      case 'paused':
        return Colors.purple;
      case 'test':
        return Colors.teal;
      case 'passed':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  String _statusTitle(AmbAlert a) {
    switch (a.status) {
      case 'imminent':
        return 'AMBULANCE VERY CLOSE!';
      case 'approaching':
        return 'AMBULANCE IS COMING';
      case 'paused':
        return 'ALERT ON HOLD (no GPS signal)';
      case 'test':
        return 'TEST ALERT';
      case 'passed':
        return 'AMBULANCE HAS PASSED';
      default:
        return 'AMBULANCE WILL COME THIS WAY LATER';
    }
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _topBar() {
    final pr = _primary;
    final hot =
        pr != null && (pr.status == 'imminent' || pr.status == 'approaching');
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Card(
        margin: EdgeInsets.zero,
        elevation: 4,
        color: hot ? _statusColor(pr.status) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(children: [
            Icon(Icons.local_police,
                color: hot ? Colors.white : const Color(0xFF1565C0)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_p.postName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: hot ? Colors.white : Colors.black87)),
                    Text('${_p.officer} • Alert distance ${_p.radius} m',
                        style: TextStyle(
                            fontSize: 12,
                            color: hot ? Colors.white70 : Colors.black54)),
                  ]),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  color: hot ? Colors.white : Colors.black87),
              onSelected: (v) {
                if (v == 'voice') {
                  Voice.I.speak('This is a voice alert test.');
                  _buzz();
                }
                if (v == 'iot') _openIot();
                if (v == 'duty') _endDuty();
                if (v == 'help') {
                  Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HelpScreen()));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'iot', child: Text('IoT control (display, buzzer)')),
                PopupMenuItem(value: 'help', child: Text('How to use')),
                PopupMenuItem(
                    value: 'voice', child: Text('Test sound and voice')),
                PopupMenuItem(value: 'duty', child: Text('Finish duty')),
              ],
            ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _online
              ? _chip(Icons.wifi_tethering, 'Watching for ambulances', Colors.green)
              : _chip(Icons.sync_problem, 'Connecting...', Colors.orange),
          GestureDetector(
            onTap: _fitAllAmbulances,
            child: _chip(
                Icons.local_hospital,
                _live.isEmpty
                    ? 'No ambulance on road'
                    : '${_live.length} ambulance${_live.length == 1 ? '' : 's'} on road',
                _live.isEmpty ? Colors.grey : Colors.red),
          ),
          FilledButton.icon(
            style: solidButton(BtnColors.indigo,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
            onPressed: _openIot,
            icon: const Icon(Icons.developer_board, size: 16),
            label: const Text('IOT CONTROL', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
      if (_banner != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                const Icon(Icons.warning_amber,
                    color: Colors.deepOrange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        Text(_banner!, style: const TextStyle(fontSize: 13))),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      );

  Widget _actionButton(
      AmbAlert a, String action, IconData icon, String label, Color color) {
    final done = a.did(action);
    final sending = _isSending(a, action);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilledButton(
          style: solidButton(color,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4)),
          onPressed: (sending || done) ? null : () => _act(a, action),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            sending
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : Icon(done ? Icons.check_circle : icon,
                    size: 22, color: Colors.white),
            const SizedBox(height: 4),
            Text(sending ? 'SENDING...' : label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ]),
        ),
      ),
    );
  }

  bool _canAct(AmbAlert a) =>
      a.status == 'approaching' ||
      a.status == 'imminent' ||
      a.status == 'paused' ||
      a.status == 'test';

  /// Scrollable information part of the alert card.
  Widget _alertInfo(AmbAlert a) {
    final color = _statusColor(a.status);
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.emergency, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_statusTitle(a),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15)),
              ),
              if (a.critical)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Text('CRITICAL',
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          if (a.status != 'passed')
            Row(children: [
              _stat('Distance', fmtDist(a.distAhead)),
              _stat('Time to reach you', fmtDur(a.etaSec)),
              _stat('Speed', '${a.speedKmh} km/h'),
            ]),
          const SizedBox(height: 8),
          Text(
            '${a.ambulanceId}${a.driverName.isEmpty ? '' : ' • ${a.driverName}'}${a.destination.isEmpty ? '' : '\nDestination: ${a.destination}'}',
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
          if (a.message != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.chat_bubble, size: 18, color: BtnColors.indigo),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Driver says: ${a.message!.text}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13))),
              ]),
            ),
          if (a.status == 'paused')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                  'The ambulance GPS signal is lost, or it left the route. Please follow your normal duty steps.',
                  style: TextStyle(fontSize: 12, color: Colors.purple)),
            ),
        ]);
  }

  /// Buttons stay pinned at the bottom of the card (never hidden by scrolling).
  Widget _alertActions(AmbAlert a) {
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            _actionButton(a, 'ack', Icons.visibility, 'I SAW IT', BtnColors.blue),
            _actionButton(a, 'clear_lane', Icons.alt_route, 'CLEARING\nTHE LANE',
                BtnColors.orange),
            _actionButton(a, 'escalate', Icons.priority_high, 'NEED HELP',
                BtnColors.red),
          ]),
          const SizedBox(height: 4),
          const Text(
            'These buttons only send a message to the driver. They do not change traffic lights.',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ]);
  }

  Widget _idlePanel() {
    final list = _live.take(3).toList();
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield, color: Colors.green, size: 34),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You are on duty',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    SizedBox(height: 2),
                    Text(
                        'No ambulance is coming towards your area right now.',
                        style: TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          if (list.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Ambulances on the road now',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 4),
            for (final x in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(Icons.local_hospital,
                      size: 18, color: x.critical ? Colors.red : Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          '${x.ambulanceId}${x.critical ? '  (CRITICAL)' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text('${fmtDist(x.distToPost)} away • ${x.speedKmh} km/h',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              ),
          ],
        ]);
  }

  Marker _postMarker() => Marker(
        point: _postPoint,
        width: 44,
        height: 44,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black38)],
          ),
          child: const Icon(Icons.local_police, color: Colors.white, size: 24),
        ),
      );

  Marker _ambMarker(LatLng p, String label, {required bool main, required bool critical}) {
    final color = critical ? Colors.red : (main ? Colors.deepOrange : Colors.orange.shade700);
    return Marker(
      point: p,
      width: 96,
      height: 70,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black26)]),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800, color: color)),
        ),
        const SizedBox(height: 2),
        Container(
          width: main ? 40 : 32,
          height: main ? 40 : 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black38)],
          ),
          child: Icon(Icons.local_hospital,
              color: Colors.white, size: main ? 22 : 18),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pr = _primary;

    // ---- bottom card content ----
    Widget info;
    Widget? actions;
    if (pr == null) {
      info = _idlePanel();
    } else {
      final others = _alerts.where((x) => x != pr).toList();
      info = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _alertInfo(pr),
          if (others.isNotEmpty) ...[
            const Divider(height: 22),
            Text(
              'More ambulances coming: ${others.length}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ],
      );
      if (_canAct(pr)) actions = _alertActions(pr);
    }

    // ---- map layers ----
    final polylines = <Polyline>[];
    if (pr != null && pr.route.length >= 2) {
      polylines.add(Polyline(
          points: pr.route,
          strokeWidth: 6,
          color: _statusColor(pr.status).withAlpha(200)));
    }
    final markers = <Marker>[_postMarker()];
    final drawn = <String>{};
    for (final x in _live) {
      drawn.add(x.tripId);
      final isMain = pr != null && pr.tripId == x.tripId;
      markers.add(_ambMarker(
          x.point, '${x.ambulanceId} • ${x.speedKmh} km/h',
          main: isMain, critical: x.critical));
    }
    if (pr != null && !drawn.contains(pr.tripId)) {
      markers.add(_ambMarker(pr.amb, pr.ambulanceId, main: true, critical: pr.critical));
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _postPoint,
              initialZoom: 15,
              onMapReady: () {
                _mapReady = true;
                _fitIfNeeded();
              },
              // only a finger movement turns auto-fit off (not the app's own camera moves)
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _autoFit) setState(() => _autoFit = false);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: AppConfig.tileUrl,
                userAgentPackageName: AppConfig.packageName,
              ),
              PolylineLayer(polylines: polylines),
              CircleLayer(circles: [
                CircleMarker(
                  point: _postPoint,
                  radius: _p.radius.toDouble(),
                  useRadiusInMeter: true,
                  color: const Color(0xFF1565C0).withAlpha(28),
                  borderColor: const Color(0xFF1565C0),
                  borderStrokeWidth: 1.5,
                ),
              ]),
              MarkerLayer(markers: markers),
              const RichAttributionWidget(attributions: [
                TextSourceAttribution('OpenStreetMap contributors')
              ]),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _topBar(),
                  const Spacer(),
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 8,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.55,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                    14, 14, 14, actions == null ? 14 : 8),
                                child: info,
                              ),
                            ),
                            if (actions != null)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 0, 14, 12),
                                child: actions,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_autoFit)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FloatingActionButton.small(
                  heroTag: 'recenter',
                  backgroundColor: BtnColors.cyan,
                  foregroundColor: Colors.white,
                  onPressed: _centerOnPost,
                  child: const Icon(Icons.my_location),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
