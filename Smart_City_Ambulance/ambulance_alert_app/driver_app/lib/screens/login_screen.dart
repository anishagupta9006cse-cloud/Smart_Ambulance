import 'package:flutter/material.dart';
import '../api.dart';
import '../config.dart';
import '../profile.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final Profile? existing;
  const LoginScreen({super.key, this.existing});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amb;
  late final TextEditingController _code;
  late final TextEditingController _server;
  bool _busy = false;
  String? _msg;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _amb = TextEditingController(text: p?.ambulanceId ?? '');
    _code = TextEditingController(text: p?.accessCode ?? '');
    _server = TextEditingController(text: p?.serverUrl ?? AppConfig.defaultServer);
  }

  @override
  void dispose() {
    _name.dispose();
    _amb.dispose();
    _code.dispose();
    _server.dispose();
    super.dispose();
  }

  Profile _profile() => Profile(
        name: _name.text.trim(),
        ambulanceId: _amb.text.trim().toUpperCase(),
        accessCode: _code.text.trim(),
        serverUrl: _server.text.trim().isEmpty ? AppConfig.defaultServer : _server.text.trim(),
      );

  Future<void> _go({bool skipCheck = false}) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final p = _profile();
    Api.I.configure(p.serverUrl, p.accessCode);
    if (!skipCheck) {
      setState(() {
        _busy = true;
        _failed = false;
        _msg = 'Connecting to the server...\n(The first time can take 30-60 seconds)';
      });
      final ok = await Api.I.wakeServer();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _failed = true;
          _msg = 'Could not connect to the server. Check your internet and try again.';
        });
        return;
      }
    }
    try {
      await p.save();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(profile: p)));
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
                  const Icon(Icons.local_hospital, size: 72, color: Colors.red),
                  const SizedBox(height: 8),
                  const Text('AMBUROUTE',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const Text('Ambulance Driver',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black54)),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Driver name', prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _amb,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                        labelText: 'Ambulance number / ID (e.g. AMB-101)',
                        prefixIcon: Icon(Icons.airport_shuttle),
                        border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the ambulance ID' : null,
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Advanced (server / access code)'),
                    children: [
                      TextFormField(
                        controller: _server,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(labelText: 'Server URL', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _code,
                        decoration: const InputDecoration(
                            labelText: 'Access code (if enabled on the server)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_msg != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_msg!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _failed ? Colors.red : Colors.black87)),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : () => _go(),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Continue', style: TextStyle(fontSize: 17)),
                  ),
                  if (_failed)
                    TextButton(onPressed: () => _go(skipCheck: true), child: const Text('Continue without connecting')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
