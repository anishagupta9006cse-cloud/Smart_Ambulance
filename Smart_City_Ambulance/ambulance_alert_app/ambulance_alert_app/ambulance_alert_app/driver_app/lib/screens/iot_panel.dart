import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../models.dart';
import '../theme.dart';

/// One-tap messages for the IoT display.
class IotPreset {
  final String label;
  final String text; // shown on the display ("\n" = new line)
  final Color color;
  const IotPreset(this.label, this.text, this.color);
}

/// Control panel for an IoT device (ESP32 with a display and a buzzer).
/// The same file is used in the police app and in the driver app.
///
/// * [routeCommand] is only given by the driver app. It lets the driver also command the
///   police devices that are on his route (a switch appears at the top).
/// * [showAuto] is only true in the police app (auto mode of the post device).
class IotPanel extends StatefulWidget {
  final String title;
  final String prefsKey; // where the chosen device ID is saved on the phone
  final String defaultDeviceId;
  final String by; // officer / driver name, saved in the device log
  final List<IotPreset> presets;
  final bool showAuto;
  final Future<void> Function(Map<String, dynamic> cmd)? routeCommand;

  const IotPanel({
    super.key,
    required this.title,
    required this.prefsKey,
    required this.defaultDeviceId,
    required this.by,
    required this.presets,
    this.showAuto = false,
    this.routeCommand,
  });

  static Future<void> show(BuildContext context, IotPanel panel) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => panel,
    );
  }

  @override
  State<IotPanel> createState() => _IotPanelState();
}

class _IotPanelState extends State<IotPanel> {
  final TextEditingController _idCtrl = TextEditingController();
  final TextEditingController _textCtrl = TextEditingController();
  final Set<String> _busy = {}; // every button has its own busy flag (one slow button never blocks the others)
  Timer? _timer;
  IotDevice? _dev;
  String? _error;
  int _buzzSeconds = 20;
  bool _toRoute = false; // driver: command the police devices on the route instead of own device
  bool _loaded = false;

  String get _deviceId => _idCtrl.text.trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _idCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    String saved = '';
    try {
      final sp = await SharedPreferences.getInstance();
      saved = sp.getString(widget.prefsKey) ?? '';
    } catch (_) {}
    _idCtrl.text = saved.isNotEmpty ? saved : widget.defaultDeviceId;
    if (!mounted) return;
    setState(() => _loaded = true);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _saveId() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(widget.prefsKey, _deviceId);
    } catch (_) {}
  }

  bool get _idOk => RegExp(r'^[A-Za-z0-9_-]{2,40}$').hasMatch(_deviceId);

  Future<void> _refresh() async {
    if (_toRoute || !_idOk || !mounted) return;
    try {
      final d = await Api.I.iot(_deviceId);
      if (!mounted) return;
      setState(() {
        _dev = d;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  /// Runs one command. Only the pressed button shows a spinner.
  Future<void> _send(String key, Map<String, dynamic> cmd, String okMsg) async {
    if (_busy.contains(key)) return;
    if (!_toRoute && !_idOk) {
      _snack('Device ID is not valid. Use 2-40 letters, numbers, - or _.');
      return;
    }
    setState(() => _busy.add(key));
    try {
      if (_toRoute) {
        await widget.routeCommand!(cmd);
      } else {
        await _saveId();
        final d = await Api.I.iotCommand(_deviceId, cmd, by: widget.by);
        if (mounted) setState(() => _dev = d);
      }
      _snack(okMsg);
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  void _showText(String key, String text) => _send(
      key,
      {
        'display': {'text': text, 'seconds': 300}
      },
      'Message sent to the display.');

  void _buzz(String pattern, String label) => _send(
      'buzz_$pattern',
      {
        'buzzer': {'pattern': pattern, 'seconds': _buzzSeconds}
      },
      '$label started for $_buzzSeconds seconds.');

  Widget _btn(String key, IconData icon, String label, Color color, VoidCallback onTap) {
    final busy = _busy.contains(key);
    return FilledButton.icon(
      style: solidButton(color, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14)),
      onPressed: busy ? null : onTap,
      icon: busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _statusCard() {
    if (_toRoute) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
        child: const Text(
          'Commands go to every police post device that is on your route, ahead of you.',
          style: TextStyle(fontSize: 13),
        ),
      );
    }
    final d = _dev;
    final online = d?.online == true;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: online ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(online ? Icons.wifi : Icons.wifi_off, size: 18, color: online ? Colors.green : Colors.deepOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error != null
                  ? _error!
                  : d == null
                      ? 'Checking device...'
                      : online
                          ? 'Device is online'
                          : (d.lastSeenSec == null
                              ? 'Device has never connected yet'
                              : 'Device offline (last seen ${d.lastSeenSec} s ago)'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ]),
        if (d != null) ...[
          const SizedBox(height: 6),
          Text(
            'Display: ${d.displayOn ? d.displayText.replaceAll('\n', ' / ') : 'off'}',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          Text(
            'Buzzer: ${d.buzzerOn ? '${d.buzzerPattern} (${d.buzzerRemaining} s left)' : 'off'}',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ],
        if (!online && _error == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Commands are saved. The device will do them as soon as it connects to the internet.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: !_loaded
            ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.developer_board, color: BtnColors.indigo),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(widget.title,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 12),
                if (widget.routeCommand != null) ...[
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, icon: Icon(Icons.local_hospital), label: Text('My device')),
                      ButtonSegment(value: true, icon: Icon(Icons.local_police), label: Text('Police on route')),
                    ],
                    selected: {_toRoute},
                    onSelectionChanged: (v) {
                      setState(() => _toRoute = v.first);
                      if (!_toRoute) _refresh();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_toRoute) ...[
                  TextField(
                    controller: _idCtrl,
                    decoration: InputDecoration(
                      labelText: 'Device ID',
                      helperText: 'Same ID that is written in the IoT device code',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: _idOk ? null : 'Use 2-40 letters, numbers, - or _',
                    ),
                    onChanged: (_) {
                      setState(() => _dev = null);
                    },
                    onSubmitted: (_) {
                      _saveId();
                      _refresh();
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                _statusCard(),
                const SizedBox(height: 16),
                const Text('DISPLAY', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 0; i < widget.presets.length; i++)
                    _btn('preset$i', Icons.message, widget.presets[i].label, widget.presets[i].color,
                        () => _showText('preset$i', widget.presets[i].text)),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _textCtrl,
                  maxLength: 64,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Your own message for the display',
                    helperText: 'English letters and numbers work best on small displays',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                Row(children: [
                  Expanded(
                    child: _btn('custom', Icons.send, 'SHOW MESSAGE', BtnColors.blue, () {
                      final t = _textCtrl.text.trim();
                      if (t.isEmpty) {
                        _snack('Type a message first.');
                        return;
                      }
                      _showText('custom', t);
                    }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _btn('clear', Icons.clear_all, 'CLEAR DISPLAY', BtnColors.charcoal,
                        () => _send('clear', {'display': null}, 'Display cleared.')),
                  ),
                ]),
                const SizedBox(height: 16),
                const Text('BUZZER', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                const SizedBox(height: 8),
                Row(children: [
                  const Text('Ring for: '),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 10, label: Text('10 s')),
                        ButtonSegment(value: 20, label: Text('20 s')),
                        ButtonSegment(value: 60, label: Text('60 s')),
                      ],
                      selected: {_buzzSeconds},
                      onSelectionChanged: (v) => setState(() => _buzzSeconds = v.first),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _btn('buzz_beep', Icons.notifications_active, 'BEEP', BtnColors.orange, () => _buzz('beep', 'Beep')),
                  _btn('buzz_siren', Icons.campaign, 'SIREN', BtnColors.pink, () => _buzz('siren', 'Siren')),
                  _btn('buzz_continuous', Icons.volume_up, 'LONG TONE', BtnColors.purple,
                      () => _buzz('continuous', 'Long tone')),
                  _btn('buzz_off', Icons.volume_off, 'STOP BUZZER', BtnColors.red,
                      () => _send('buzz_off', {'buzzer': {'pattern': 'off'}}, 'Buzzer stopped.')),
                ]),
                if (widget.showAuto && !_toRoute) ...[
                  const Divider(height: 28),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto mode'),
                    subtitle: const Text(
                        'When an ambulance comes, the display and buzzer switch on by themselves, and switch off after it passes.'),
                    value: _dev?.auto ?? true,
                    onChanged: _busy.contains('auto')
                        ? null
                        : (v) => _send('auto', {'auto': v}, v ? 'Auto mode is ON.' : 'Auto mode is OFF.'),
                  ),
                ],
                const SizedBox(height: 6),
                const Text(
                  'The buzzer always stops by itself after at most 60 seconds, so it can never stay on by mistake.',
                  style: TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ]),
      ),
    );
  }
}
