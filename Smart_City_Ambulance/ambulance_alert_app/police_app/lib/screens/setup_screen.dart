import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../api.dart';
import '../config.dart';
import '../models.dart';
import '../location_helper.dart';
import '../profile.dart';
import 'dashboard_screen.dart';
import 'place_picker_screen.dart';

class SetupScreen extends StatefulWidget {
  final PostProfile? existing;
  const SetupScreen({super.key, this.existing});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _officer;
  late final TextEditingController _post;
  late final TextEditingController _code;
  late final TextEditingController _server;
  int _radius = 500;
  LatLng? _loc;
  String _locLabel = '';
  bool _busy = false;
  bool _gpsBusy = false;
  bool _failed = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _officer = TextEditingController(text: p?.officer ?? '');
    _post = TextEditingController(text: p?.postName ?? '');
    _code = TextEditingController(text: p?.accessCode ?? '');
    _server =
        TextEditingController(text: p?.serverUrl ?? AppConfig.defaultServer);
    if (p != null) {
      _radius = p.radius;
      _loc = LatLng(p.lat, p.lng);
      _locLabel = 'Previously saved location';
    }
  }

  @override
  void dispose() {
    _officer.dispose();
    _post.dispose();
    _code.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _useGps() async {
    setState(() {
      _gpsBusy = true;
      _msg = null;
    });
    try {
      final err = await LocationHelper.ensureReady();
      if (err != null) {
        setState(() {
          _msg = err;
          _failed = true;
        });
        return;
      }
      Position? pos;
      try {
        pos = await Geolocator.getPositionStream(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        ).first.timeout(const Duration(seconds: 25));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      final got = pos;
      if (got == null) {
        setState(() {
          _msg =
              'Could not get a GPS fix. Try outdoors or choose on the map.';
          _failed = true;
        });
        return;
      }
      setState(() {
        _loc = LatLng(got.latitude, got.longitude);
        _locLabel = 'Location taken from GPS';
        _failed = false;
        _msg = null;
      });
    } finally {
      if (mounted) setState(() => _gpsBusy = false);
    }
  }

  Future<void> _useMap() async {
    final r = await Navigator.of(context).push<PlaceResult>(
      MaterialPageRoute(
        builder: (_) => PlacePickerScreen(title: 'Choose your traffic area'),
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      _loc = r.point;
      _locLabel = r.name;
    });
  }

  Future<void> _start() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_loc == null) {
      setState(() {
        _failed = true;
        _msg = 'Please set your location first (GPS or map).';
      });
      return;
    }
    final url = _server.text.trim().isEmpty
        ? AppConfig.defaultServer
        : _server.text.trim();
    Api.I.configure(url, _code.text.trim());
    setState(() {
      _busy = true;
      _failed = false;
      _msg =
          'Connecting to the server...\n(The first time can take 30-60 seconds)';
    });
    final ok = await Api.I.wakeServer();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _failed = true;
        _msg =
            'Could not connect to the server. Check your internet and try again.';
      });
      return;
    }
    try {
      final draft = PostProfile(
        id: widget.existing?.id ?? '',
        officer: _officer.text.trim(),
        postName: _post.text.trim(),
        area: _locLabel,
        radius: _radius,
        lat: _loc!.latitude,
        lng: _loc!.longitude,
        accessCode: _code.text.trim(),
        serverUrl: url,
      );
      final id = await Api.I.registerPost(draft);
      final saved = draft.withId(id);
      try {
        await saved.save();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DashboardScreen(profile: saved)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
        _msg = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.local_police,
                      size: 72, color: Color(0xFF1565C0)),
                  const SizedBox(height: 8),
                  const Text('AMBUROUTE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2)),
                  const Text('Traffic Police',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.black54)),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _officer,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Officer name',
                        prefixIcon: Icon(Icons.badge),
                        border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Enter a name'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _post,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Post / junction name',
                        prefixIcon: Icon(Icons.traffic),
                        border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Enter the post name'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  const Text('Your traffic area (location)',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _gpsBusy ? null : _useGps,
                        icon: _gpsBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.my_location),
                        label: const Text('Use GPS'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _useMap,
                        icon: const Icon(Icons.map),
                        label: const Text('Choose on map'),
                      ),
                    ),
                  ]),
                  if (_loc != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '✓ $_locLabel\n(${_loc!.latitude.toStringAsFixed(5)}, ${_loc!.longitude.toStringAsFixed(5)})',
                        style:
                            const TextStyle(color: Colors.green, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 18),
                  const Text('Alert area (radius)',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [300, 500, 800, 1200]
                        .map((r) => ChoiceChip(
                              label: Text('$r m'),
                              selected: _radius == r,
                              onSelected: (_) => setState(() => _radius = r),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Just set your location. When an ambulance route passes through your area, the app detects it automatically and alerts you.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Advanced (server / access code)'),
                    children: [
                      TextFormField(
                        controller: _server,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                            labelText: 'Server URL',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _code,
                        decoration: const InputDecoration(
                            labelText: 'Access code (if enabled on the server)',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  if (_msg != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(_msg!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: _failed ? Colors.red : Colors.black87)),
                    ),
                  const SizedBox(height: 6),
                  FilledButton(
                    onPressed: _busy ? null : _start,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('START DUTY',
                            style: TextStyle(fontSize: 17)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
