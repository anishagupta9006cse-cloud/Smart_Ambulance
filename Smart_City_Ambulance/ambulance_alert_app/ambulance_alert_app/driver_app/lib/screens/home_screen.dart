import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../api.dart';
import '../config.dart';
import '../geo.dart';
import '../location_helper.dart';
import '../models.dart';
import '../profile.dart';
import '../theme.dart';
import '../voice.dart';
import 'help_screen.dart';
import 'iot_panel.dart';
import 'login_screen.dart';
import 'place_picker_screen.dart';

class HomeScreen extends StatefulWidget {
  final Profile profile;
  const HomeScreen({super.key, required this.profile});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _map = MapController();
  bool _mapReady = false;
  bool _follow = true;
  bool _centeredOnce = false;

  // GPS
  LatLng? _me;
  double _speed = 0;
  double _acc = 0;
  LatLng? _current; // position used for the trip (real GPS or simulation)
  StreamSubscription<Position>? _gpsSub;

  // From / To
  bool _fromIsMe = true;
  LatLng? _fromPoint;
  String _fromLabel = 'My current location';
  LatLng? _toPoint;
  String _toLabel = '';

  // Route / trip
  RouteInfo? _route;
  RouteTrack? _track;
  String? _tripId;
  TripState? _state;

  // status
  bool _busy = false;
  bool _checkingServer = true;
  bool _serverOk = false;
  String? _banner;
  bool _netWarn = false;

  // simulation
  bool _useSim = false;
  bool _simRunning = false;
  double _simKmh = 50;
  double _simDist = 0;

  Timer? _sendTimer;
  Timer? _simTimer;
  bool _sending = false;
  int _fails = 0;
  bool _recovering = false;
  String? _spokenJunction;
  final Set<String> _seenActions = {};

  // extra features
  List<PolicePost> _allPosts = []; // every police post that is online (map)
  Timer? _postsTimer;
  bool _critical = false; // critical patient
  bool _prioBusy = false;
  String? _lastQuick;

  bool get _tripActive => _tripId != null;
  double get _simMps => _simKmh / 3.6;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    _simTimer?.cancel();
    _postsTimer?.cancel();
    _gpsSub?.cancel();
    Voice.I.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------- init
  Future<void> _init() async {
    Voice.I.init();
    _checkServer();
    _loadPosts();
    _postsTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadPosts());
    final err = await LocationHelper.ensureReady();
    if (!mounted) return;
    if (err != null) {
      setState(() => _banner = err);
      return;
    }
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) _onPos(last);
    } catch (_) {}
    _startGps(foreground: false);
  }

  Future<void> _checkServer() async {
    setState(() => _checkingServer = true);
    final ok = await Api.I.wakeServer(tries: 6);
    if (!mounted) return;
    setState(() {
      _serverOk = ok;
      _checkingServer = false;
    });
  }

  void _startGps({required bool foreground}) {
    _gpsSub?.cancel();
    final LocationSettings settings = defaultTargetPlatform ==
            TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 3,
            intervalDuration: const Duration(seconds: 2),
            foregroundNotificationConfig: foreground
                ? const ForegroundNotificationConfig(
                    notificationTitle: 'AmbuRoute Driver',
                    notificationText: 'Emergency trip: GPS tracking is active',
                    enableWakeLock: true,
                    setOngoing: true,
                  )
                : null,
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.best, distanceFilter: 3);
    try {
      _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
        _onPos,
        onError: (Object e) {
          if (mounted) setState(() => _banner = 'GPS problem: $e');
        },
      );
    } catch (e) {
      if (mounted) setState(() => _banner = 'Could not start GPS: $e');
    }
  }

  void _onPos(Position p) {
    if (!mounted) return;
    final ll = LatLng(p.latitude, p.longitude);
    setState(() {
      _me = ll;
      _speed = p.speed < 0 ? 0 : p.speed;
      _acc = p.accuracy;
      if (!_simRunning) _current = ll;
      if (_banner != null && _banner!.startsWith('GPS')) _banner = null;
    });
    if (!_centeredOnce) {
      _centeredOnce = true;
      _moveMap(ll, 15);
    } else if (_tripActive && _follow && !_simRunning) {
      _moveMap(ll, null);
    }
  }

  void _moveMap(LatLng p, double? zoom) {
    if (!_mapReady) return;
    try {
      _map.move(p, zoom ?? _map.camera.zoom);
    } catch (_) {}
  }

  void _fitRoute() {
    final r = _route;
    if (r == null || r.points.length < 2 || !_mapReady) return;
    try {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(r.points),
        padding: const EdgeInsets.fromLTRB(40, 170, 40, 300),
      ));
    } catch (_) {}
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------------------------------------------------------- extra features
  /// All online police posts (so the driver always sees where police are, not only on the route).
  Future<void> _loadPosts() async {
    if (!mounted) return;
    try {
      final list = await Api.I.onlinePosts();
      if (mounted) setState(() => _allPosts = list);
    } catch (_) {}
  }

  /// One tap: pick the nearest saved hospital and make the route.
  Future<void> _nearestHospital() async {
    final from = _me;
    if (from == null) {
      _snack('Your location is not found yet. Please wait a moment.');
      return;
    }
    setState(() => _busy = true);
    try {
      final list = await Api.I.nearby('hospital', near: from);
      if (list.isEmpty) {
        _snack('No saved hospital found. Tap the box above and search.');
        return;
      }
      final h = list.first;
      if (!mounted) return;
      setState(() {
        _toPoint = h.point;
        _toLabel = h.name;
        _route = null;
        _track = null;
      });
      await _previewRoute();
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Critical patient on / off. Before the trip it is only remembered and sent when the trip starts.
  Future<void> _setCritical(bool v) async {
    final id = _tripId;
    if (id == null) {
      setState(() => _critical = v);
      return;
    }
    if (_prioBusy) return;
    setState(() {
      _critical = v;
      _prioBusy = true;
    });
    try {
      await Api.I.setPriority(id, v);
      _snack(v
          ? 'Marked CRITICAL. Police and IoT displays will show it.'
          : 'Back to normal priority.');
    } catch (e) {
      if (mounted) setState(() => _critical = !v);
      _snack('Could not change priority: $e');
    } finally {
      if (mounted) setState(() => _prioBusy = false);
    }
  }

  Future<void> _sendQuick(String text) async {
    final id = _tripId;
    if (id == null) return;
    try {
      await Api.I.sendMessage(id, text);
      if (mounted) setState(() => _lastQuick = text.isEmpty ? null : text);
      _snack(text.isEmpty ? 'Message removed.' : 'Message sent to the police.');
    } catch (e) {
      _snack('Message not sent: $e');
    }
  }

  Future<void> _openQuickMessage() async {
    if (_tripId == null) return;
    final ctrl = TextEditingController();
    const presets = <List<Object>>[
      ['Patient is critical', BtnColors.red],
      ['Need fast clearance', BtnColors.orange],
      ['Heavy traffic ahead', BtnColors.brown],
      ['Keep the lane open', BtnColors.teal],
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Message to police',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Police on your route see it on their alert card and hear it.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            for (final pr in presets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton(
                  style: solidButton(pr[1] as Color),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sendQuick(pr[0] as String);
                  },
                  child: Text((pr[0] as String).toUpperCase()),
                ),
              ),
            TextField(
              controller: ctrl,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Your own message',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            FilledButton.icon(
              style: solidButton(BtnColors.blue),
              onPressed: () {
                final t = ctrl.text.trim();
                if (t.isEmpty) return;
                Navigator.pop(ctx);
                _sendQuick(t);
              },
              icon: const Icon(Icons.send),
              label: const Text('SEND'),
            ),
            if (_lastQuick != null)
              TextButton(
                style: textColor(BtnColors.charcoal),
                onPressed: () {
                  Navigator.pop(ctx);
                  _sendQuick('');
                },
                child: const Text('Remove my last message'),
              ),
          ]),
        ),
      ),
    );
    ctrl.dispose();
  }

  String get _ambDeviceId {
    final id = widget.profile.ambulanceId
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^A-Z0-9_-]'), '');
    return id.length >= 2 ? id : 'AMB';
  }

  void _openIot() {
    IotPanel.show(
      context,
      IotPanel(
        title: 'IoT control: display and buzzer',
        prefsKey: 'iotDeviceId',
        defaultDeviceId: _ambDeviceId,
        by: widget.profile.name,
        presets: const [
          IotPreset('AMBULANCE ON DUTY', 'AMBULANCE\nON DUTY', BtnColors.red),
          IotPreset('CLEAR THE ROAD', 'CLEAR THE ROAD\nEMERGENCY', BtnColors.orange),
          IotPreset('KEEP LEFT', 'KEEP LEFT\nMAKE WAY', BtnColors.brown),
          IotPreset('THANK YOU', 'THANK YOU\nDRIVE SAFE', BtnColors.green),
        ],
        // Only while a trip is running: also command the police devices on the route.
        routeCommand: _tripActive
            ? (cmd) async {
                final id = _tripId;
                if (id == null) throw ApiException('Start a trip first.');
                final n = await Api.I.tripIot(id, cmd);
                if (n == 0) {
                  throw ApiException('No police post is on your route right now.');
                }
              }
            : null,
      ),
    );
  }

  // ---------------------------------------------------------------- places / route
  Future<void> _pickPlace({required bool isFrom}) async {
    if (_tripActive) return;
    final r = await Navigator.of(context).push<PlaceResult>(MaterialPageRoute(
      builder: (_) => PlacePickerScreen(
        title: isFrom ? 'Choose your start point' : 'Choose where to go',
        hint: isFrom ? 'Type a place name' : 'Type a hospital or place name',
        initial: _me ?? _fromPoint ?? _toPoint,
        chips: isFrom
            ? const [
                PlaceChip('Chowks & Markets', 'market', BtnColors.brown),
                PlaceChip('Hospitals', 'hospital', BtnColors.teal),
                PlaceChip('Railway & Bus', 'transport', BtnColors.indigo),
              ]
            : const [
                PlaceChip('Hospitals', 'hospital', BtnColors.teal),
                PlaceChip('Railway & Bus', 'transport', BtnColors.indigo),
                PlaceChip('Famous places', 'landmark', BtnColors.orange),
              ],
      ),
    ));
    if (r == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromIsMe = false;
        _fromPoint = r.point;
        _fromLabel = r.name;
      } else {
        _toPoint = r.point;
        _toLabel = r.name;
      }
      _route = null;
      _track = null;
    });
    await _previewRoute();
  }

  void _useMyLocationAsFrom() {
    setState(() {
      _fromIsMe = true;
      _fromLabel = 'My current location';
      _route = null;
      _track = null;
    });
    _previewRoute();
  }

  LatLng? get _startPoint => _fromIsMe ? _me : _fromPoint;

  Future<void> _previewRoute() async {
    final from = _startPoint;
    final to = _toPoint;
    if (to == null) return;
    if (from == null) {
      _snack(
          'Start location not found. Turn on GPS or choose a start point yourself.');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await Api.I.route(from, to);
      if (!mounted) return;
      setState(() {
        _route = r;
        _track = RouteTrack(r.points);
        _banner = r.fallback
            ? 'Road map data is not available now. Showing a straight line only (good for practice, not for real driving).'
            : null;
      });
      _fitRoute();
    } catch (e) {
      if (mounted) setState(() => _banner = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- trip
  Future<void> _startTrip() async {
    final r = _route;
    final to = _toPoint;
    if (r == null || to == null || r.points.isEmpty) return;
    if (!_useSim && _me == null) {
      _snack(
          'Your location is not found yet. Please wait, or turn on Practice mode.');
      return;
    }
    final from = _useSim ? r.points.first : (_me ?? r.points.first);
    setState(() => _busy = true);
    try {
      final res = await Api.I.startTrip(
        driverName: widget.profile.name,
        ambulanceId: widget.profile.ambulanceId,
        from: from,
        to: to,
        destinationName: _toLabel,
      );
      if (!mounted) return;
      setState(() {
        _tripId = res.tripId;
        _route = res.route;
        _track = RouteTrack(res.route.points);
        _state = res.state;
        _fails = 0;
        _netWarn = false;
        _banner = null;
        _follow = true;
        _spokenJunction = null;
        _seenActions.clear();
        _current = from;
      });
      _startGps(foreground: true);
      _sendTimer?.cancel();
      _sendTimer =
          Timer.periodic(const Duration(seconds: 2), (_) => _sendNow());
      if (_useSim) _startSim();
      _fitRoute();
      Voice.I.speak('Emergency trip started. Drive safely.');
      if (_critical) {
        Api.I.setPriority(res.tripId, true).catchError((_) {});
      }
      _sendNow();
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startSim() {
    _simDist = 0;
    _simRunning = true;
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final track = _track;
      if (track == null || !mounted) return;
      _simDist = (_simDist + _simMps * 0.5).clamp(0.0, track.total).toDouble();
      final p = track.pointAt(_simDist);
      setState(() {
        _current = p;
        _speed = _simMps;
      });
      if (_follow) _moveMap(p, null);
    });
  }

  Future<void> _sendNow() async {
    final id = _tripId;
    final pos = _current;
    if (id == null || pos == null || _sending) return;
    _sending = true;
    try {
      final st = await Api.I.sendLocation(
        id,
        pos,
        speed: _simRunning ? _simMps : _speed,
        accuracy: _simRunning ? 5 : _acc,
      );
      _fails = 0;
      if (!mounted || _tripId != id) return;
      setState(() {
        _state = st;
        if (_netWarn) {
          _banner = null;
          _netWarn = false;
        }
      });
      _handleVoice(st);
      if (st.status == 'completed') {
        _onCompleted();
      } else if (st.status == 'stopped') {
        await _endLocal();
        _snack('This trip has already ended.');
      }
    } on ApiException catch (e) {
      if (e.code == 'TRIP_NOT_FOUND') {
        await _recoverTrip();
      } else {
        _netFail(e.message);
      }
    } catch (_) {
      _netFail('Network / server problem. Retrying...');
    } finally {
      _sending = false;
    }
  }

  void _netFail(String msg) {
    _fails++;
    if (_fails >= 3 && mounted) {
      setState(() {
        _banner = 'Network problem: $msg';
        _netWarn = true;
      });
    }
  }

  /// If the server restarts, the trip is started again automatically.
  Future<void> _recoverTrip() async {
    if (_recovering) return;
    final to = _toPoint;
    final pos = _current;
    if (to == null || pos == null) return;
    _recovering = true;
    try {
      final res = await Api.I.startTrip(
        driverName: widget.profile.name,
        ambulanceId: widget.profile.ambulanceId,
        from: pos,
        to: to,
        destinationName: _toLabel,
      );
      if (!mounted) return;
      setState(() {
        _tripId = res.tripId;
        _route = res.route;
        _track = RouteTrack(res.route.points);
        _state = res.state;
        if (_simRunning) _simDist = 0;
      });
      if (_critical) {
        Api.I.setPriority(res.tripId, true).catchError((_) {});
      }
    } catch (e) {
      _netFail(e.toString());
    } finally {
      _recovering = false;
    }
  }

  void _handleVoice(TripState st) {
    final nj = st.nextJunction;
    if (nj != null && nj.distance <= 300 && _spokenJunction != nj.id) {
      _spokenJunction = nj.id;
      final d = (nj.distance / 50).round() * 50;
      Voice.I.speak('Next junction in $d meters.');
    }
    for (final a in st.actions) {
      final key = '${a.postName}|${a.action}|${a.at}';
      if (_seenActions.add(key) && a.action == 'ack') {
        Voice.I.speak('Police have seen your alert.');
      }
    }
  }

  void _onCompleted() {
    _endLocal();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('You have reached'),
        content: const Text(
            'The emergency trip is finished. Police alerts are stopped.'),
        actions: [
          FilledButton(
              style: solidButton(BtnColors.green),
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'))
        ],
      ),
    );
    Voice.I.speak('You have reached the destination.');
  }

  Future<void> _endLocal() async {
    _sendTimer?.cancel();
    _simTimer?.cancel();
    _simRunning = false;
    if (!mounted) return;
    setState(() {
      _tripId = null;
      _state = null;
      _critical = false;
      _lastQuick = null;
      _netWarn = false;
      _banner = null;
    });
    _startGps(foreground: false);
  }

  Future<void> _stopTrip() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Stop trip?'),
        content: const Text('Police will not get alerts about your ambulance any more.'),
        actions: [
          TextButton(
              style: textColor(BtnColors.teal),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No, keep going')),
          FilledButton(
              style: solidButton(BtnColors.charcoal),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, stop')),
        ],
      ),
    );
    if (ok != true) return;
    final id = _tripId;
    await _endLocal();
    if (id != null) {
      try {
        await Api.I.stopTrip(id);
      } catch (_) {}
    }
  }

  Future<void> _reroute() async {
    final id = _tripId;
    final p = _current;
    if (id == null || p == null) return;
    setState(() => _busy = true);
    try {
      final r = await Api.I.reroute(id, p);
      if (!mounted) return;
      setState(() {
        _route = r.route;
        _track = RouteTrack(r.route.points);
        _state = r.state;
        _simDist = 0;
      });
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testAlert() async {
    final id = _tripId;
    if (id == null) return;
    try {
      final n = await Api.I.testAlert(id);
      _snack(n == 0
          ? 'No police post is online right now. Ask the police to open their app.'
          : 'Test alert sent to $n police post(s).');
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _logout() async {
    if (_tripActive) {
      _snack('Please stop the trip first.');
      return;
    }
    await Profile.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => LoginScreen(existing: widget.profile)));
  }

  // ---------------------------------------------------------------- UI helpers
  Color _postColor(PostInfo p) {
    if (p.status == 'passed') return Colors.grey;
    if (p.acked) return Colors.green;
    switch (p.status) {
      case 'imminent':
        return Colors.red;
      case 'approaching':
        return Colors.orange;
      case 'paused':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }

  String _postText(PostInfo p) {
    if (p.status == 'passed') return 'Crossed';
    if (p.acked) return 'Police saw it ✓';
    switch (p.status) {
      case 'imminent':
        return 'Very close';
      case 'approaching':
        return 'Police alerted';
      case 'paused':
        return 'On hold';
      default:
        return 'Waiting';
    }
  }

  List<Marker> _markers() {
    final out = <Marker>[];
    final r = _route;
    final st = _state;
    if (r != null) {
      for (final j in r.junctions) {
        final passed = st != null && j.chain < st.chain;
        out.add(Marker(
          point: j.point,
          width: 18,
          height: 18,
          child: Container(
            decoration: BoxDecoration(
              color: passed ? Colors.grey : Colors.orange,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ));
      }
      if (r.points.length >= 2) {
        out.add(Marker(
          point: r.points.first,
          width: 34,
          height: 34,
          child: const Icon(Icons.trip_origin, color: Colors.green, size: 30),
        ));
        out.add(Marker(
          point: r.points.last,
          width: 44,
          height: 44,
          alignment: Alignment.topCenter,
          child: const Icon(Icons.location_on, color: Colors.red, size: 44),
        ));
      }
    }
    final routeIds = <String>{};
    if (st != null) {
      for (final p in st.posts) {
        routeIds.add(p.id);
        out.add(Marker(
          point: p.point,
          width: 38,
          height: 38,
          child: Container(
            decoration: BoxDecoration(
              color: _postColor(p),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child:
                const Icon(Icons.local_police, color: Colors.white, size: 20),
          ),
        ));
      }
    }
    // police posts that are online but not on my route
    for (final p in _allPosts) {
      if (routeIds.contains(p.id)) continue;
      out.add(Marker(
        point: p.point,
        width: 34,
        height: 34,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF546E7A),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(Icons.local_police, color: Colors.white, size: 18),
        ),
      ));
    }
    final cur = _current;
    if (cur != null) {
      out.add(Marker(
        point: cur,
        width: 46,
        height: 46,
        child: Container(
          decoration: BoxDecoration(
            color: _tripActive ? Colors.red : Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
          ),
          child: Icon(_tripActive ? Icons.local_hospital : Icons.navigation,
              color: Colors.white, size: 26),
        ),
      ));
    }
    return out;
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

  Widget _topArea() {
    final serverChip = _checkingServer
        ? _chip(Icons.sync, 'Connecting to server...', Colors.orange)
        : (_serverOk
            ? _chip(Icons.cloud_done, 'Server connected', Colors.green)
            : GestureDetector(
                onTap: _checkServer,
                child: _chip(Icons.cloud_off, 'No server. Tap to try again',
                    Colors.red)));
    final gpsChip = _me == null
        ? _chip(Icons.gps_not_fixed, 'Finding your location...', Colors.orange)
        : _chip(Icons.gps_fixed, 'Location accuracy: ${_acc.round()} m', Colors.green);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_tripActive)
          Card(
            margin: EdgeInsets.zero,
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Column(
                children: [
                  InkWell(
                    onTap: () => _pickPlace(isFrom: true),
                    child: Row(children: [
                      const Icon(Icons.trip_origin,
                          color: Colors.green, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(_fromLabel,
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (!_fromIsMe)
                        IconButton(
                            tooltip: 'My location',
                            icon: const Icon(Icons.my_location, size: 20),
                            onPressed: _useMyLocationAsFrom)
                      else
                        const SizedBox(height: 48),
                    ]),
                  ),
                  const Divider(height: 1),
                  InkWell(
                    onTap: () => _pickPlace(isFrom: false),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(children: [
                        const Icon(Icons.location_on,
                            color: Colors.red, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _toLabel.isEmpty
                                ? 'Where do you want to go? (hospital)'
                                : _toLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: _toLabel.isEmpty
                                    ? Colors.black45
                                    : Colors.black87,
                                fontWeight: _toLabel.isEmpty
                                    ? FontWeight.normal
                                    : FontWeight.w600),
                          ),
                        ),
                        const Icon(Icons.search, size: 20),
                        const SizedBox(width: 12),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            color: Colors.red,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                const Icon(Icons.emergency, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('EMERGENCY TRIP ON • ${widget.profile.ambulanceId}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                if (_simRunning)
                  const Text('PRACTICE',
                      style: TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            serverChip,
            gpsChip,
            _chip(
                Icons.local_police,
                _allPosts.isEmpty
                    ? 'No police online'
                    : 'Police online: ${_allPosts.length}',
                _allPosts.isEmpty ? Colors.grey : Colors.blue),
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
      ],
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      );

  Widget _bottomPanel() {
    final r = _route;
    final st = _state;

    Widget content;
    if (_tripActive && st != null) {
      final nj = st.nextJunction;
      final progress = st.total <= 0
          ? 0.0
          : (st.chain / st.total).clamp(0.0, 1.0).toDouble();
      content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (st.status == 'off_route')
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.wrong_location, color: Colors.red),
                  const SizedBox(width: 8),
                  const Expanded(
                      child: Text(
                          'You are off the route. Police alerts are on hold.')),
                  FilledButton(
                      style: solidButton(BtnColors.orange),
                      onPressed: _busy ? null : _reroute,
                      child: const Text('FIND NEW ROUTE')),
                ]),
              ),
            Row(children: [
              _stat('Distance left', fmtDist(st.remaining)),
              _stat('Time left', fmtDur(st.etaSec)),
              _stat('Speed', '${(_speed * 3.6).round()} km/h'),
            ]),
            const SizedBox(height: 10),
            LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.alt_route, color: Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    nj == null
                        ? 'No more junctions. You are near the end.'
                        : 'Next junction: ${fmtDist(nj.distance)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
            ),
            if (st.posts.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Police posts on your way',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              ...st.posts.take(4).map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Icon(Icons.circle, size: 10, color: _postColor(p)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(p.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(
                          p.status == 'passed'
                              ? ''
                              : '${fmtDist(p.distAhead < 0 ? 0 : p.distAhead)} • ',
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 12)),
                      Text(_postText(p),
                          style: TextStyle(
                              color: _postColor(p),
                              fontWeight: FontWeight.w600,
                              fontSize: 12)),
                    ]),
                  )),
            ],
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.warning_amber, color: Colors.red),
              title: const Text('Critical patient'),
              subtitle: const Text('Police and IoT displays will show CRITICAL'),
              value: _critical,
              onChanged: _prioBusy ? null : _setCritical,
            ),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: solidButton(BtnColors.indigo),
                  onPressed: _openIot,
                  icon: const Icon(Icons.developer_board),
                  label: const Text('IOT CONTROL'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: solidButton(BtnColors.teal),
                  onPressed: _openQuickMessage,
                  icon: const Icon(Icons.chat),
                  label: const Text('MESSAGE POLICE'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: solidButton(BtnColors.pink),
                  onPressed: _testAlert,
                  icon: const Icon(Icons.campaign),
                  label: const Text('TEST ALERT'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: solidButton(BtnColors.charcoal),
                  onPressed: _stopTrip,
                  icon: const Icon(Icons.stop_circle),
                  label: const Text('STOP TRIP'),
                ),
              ),
            ]),
          ]);
    } else if (r != null) {
      content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              _stat('Distance', fmtDist(r.distance)),
              _stat('Time', fmtDur(r.duration)),
              _stat('Junctions', '${r.junctions.length}'),
            ]),
            const SizedBox(height: 6),
            const Text(
              'Orange dots are junctions. They are chosen automatically. Police are alerted only when you are coming towards their area.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.warning_amber, color: Colors.red),
              title: const Text('Critical patient'),
              subtitle: const Text('Police and IoT displays will show CRITICAL'),
              value: _critical,
              onChanged: _setCritical,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Practice mode (test at home)'),
              subtitle: const Text(
                  'The ambulance moves on the map by itself. No real driving needed.'),
              value: _useSim,
              onChanged: (v) => setState(() => _useSim = v),
            ),
            if (_useSim)
              Row(children: [
                const Text('Speed: '),
                Expanded(
                  child: Slider(
                    value: _simKmh,
                    min: 20,
                    max: 200,
                    divisions: 9,
                    label: '${_simKmh.round()} km/h',
                    onChanged: (v) => setState(() => _simKmh = v),
                  ),
                ),
                Text('${_simKmh.round()} km/h'),
              ]),
            FilledButton.icon(
              style: solidButton(BtnColors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _busy ? null : _startTrip,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.emergency),
              label: const Text('START EMERGENCY TRIP',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ]);
    } else {
      content = Row(children: [
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _busy
                      ? 'Making your route...'
                      : 'Tap the box above and choose your hospital.',
                  style: const TextStyle(fontSize: 15),
                ),
                if (!_busy) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: solidButton(BtnColors.teal),
                    onPressed: _me == null ? null : _nearestHospital,
                    icon: const Icon(Icons.local_hospital),
                    label: const Text('NEAREST HOSPITAL'),
                  ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    style: solidButton(BtnColors.indigo),
                    onPressed: _openIot,
                    icon: const Icon(Icons.developer_board),
                    label: const Text('IOT CONTROL'),
                  ),
                ],
              ]),
        ),
      ]);
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 8,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: content,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _route;
    final st = _state;
    final polylines = <Polyline>[];
    if (r != null && r.points.length >= 2) {
      polylines.add(Polyline(
          points: r.points, strokeWidth: 7, color: const Color(0xFF1E88E5)));
      if (st != null && _track != null) {
        final done = _track!.upTo(st.chain);
        if (done.length >= 2) {
          polylines
              .add(Polyline(points: done, strokeWidth: 7, color: Colors.grey));
        }
      }
    }
    final circles = <CircleMarker>[];
    final routeIdsForCircles = <String>{...?st?.posts.map((p) => p.id)};
    for (final p in _allPosts) {
      if (routeIdsForCircles.contains(p.id)) continue;
      circles.add(CircleMarker(
        point: p.point,
        radius: p.radius,
        useRadiusInMeter: true,
        color: const Color(0xFF546E7A).withAlpha(22),
        borderColor: const Color(0xFF546E7A),
        borderStrokeWidth: 1,
      ));
    }
    if (st != null) {
      for (final p in st.posts) {
        circles.add(CircleMarker(
          point: p.point,
          radius: p.radius,
          useRadiusInMeter: true,
          color: _postColor(p).withAlpha(30),
          borderColor: _postColor(p),
          borderStrokeWidth: 1.5,
        ));
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _me ?? AppConfig.indiaCenter,
              initialZoom: _me == null ? 5 : 15,
              minZoom: 3,
              maxZoom: 19,
              onMapReady: () => _mapReady = true,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _follow && _tripActive) {
                  setState(() => _follow = false);
                }
              },
            ),
            children: [
              TileLayer(
                  urlTemplate: AppConfig.tileUrl,
                  userAgentPackageName: AppConfig.packageName),
              PolylineLayer(polylines: polylines),
              CircleLayer(circles: circles),
              MarkerLayer(markers: _markers()),
              const RichAttributionWidget(attributions: [
                TextSourceAttribution('OpenStreetMap contributors')
              ]),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _topArea()),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  icon: const CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Icon(Icons.more_vert, color: Colors.black87)),
                  onSelected: (v) {
                    if (v == 'logout') _logout();
                    if (v == 'server') _checkServer();
                    if (v == 'iot') _openIot();
                    if (v == 'help') {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const HelpScreen()));
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'iot', child: Text('IoT control (display, buzzer)')),
                    const PopupMenuItem(
                        value: 'help', child: Text('How to use')),
                    const PopupMenuItem(
                        value: 'server', child: Text('Check server')),
                    const PopupMenuItem(
                        value: 'logout',
                        child: Text('Change driver / ambulance')),
                  ],
                ),
              ]),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _bottomPanel()),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FloatingActionButton.small(
                heroTag: 'recenter',
                backgroundColor: Colors.white,
                onPressed: () {
                  setState(() => _follow = true);
                  final p = _current ?? _me;
                  if (p != null) _moveMap(p, 16);
                },
                child: Icon(Icons.my_location,
                    color: _follow ? Colors.blue : Colors.black54),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
