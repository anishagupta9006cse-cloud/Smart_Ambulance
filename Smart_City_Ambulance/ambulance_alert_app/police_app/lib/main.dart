import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'profile.dart';
import 'screens/dashboard_screen.dart';
import 'screens/setup_screen.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const PoliceApp());
  }, (e, s) => debugPrint('Unhandled error: $e'));
}

class PoliceApp extends StatelessWidget {
  const PoliceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AmbuRoute Police',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: const _Boot(),
    );
  }
}

class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await PostProfile.load();
    if (!mounted) return;
    if (p == null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const SetupScreen()));
    } else {
      Api.I.configure(p.serverUrl, p.accessCode);
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => DashboardScreen(profile: p)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Icon(Icons.local_police, size: 80, color: Color(0xFF1565C0))),
    );
  }
}
