import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'profile.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const DriverApp());
  }, (e, s) => debugPrint('Unhandled error: $e'));
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AmbuRoute Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD32F2F)),
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
    final p = await Profile.load();
    if (!mounted) return;
    if (p == null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    } else {
      Api.I.configure(p.serverUrl, p.accessCode);
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(profile: p)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Icon(Icons.local_hospital, size: 80, color: Colors.red)),
    );
  }
}
