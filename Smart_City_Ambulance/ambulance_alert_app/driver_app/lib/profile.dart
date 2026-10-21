import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class Profile {
  final String name;
  final String ambulanceId;
  final String accessCode;
  final String serverUrl;

  const Profile({
    required this.name,
    required this.ambulanceId,
    required this.accessCode,
    required this.serverUrl,
  });

  static Future<Profile?> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final n = sp.getString('name') ?? '';
      if (n.isEmpty) return null;
      return Profile(
        name: n,
        ambulanceId: sp.getString('ambulanceId') ?? '',
        accessCode: sp.getString('accessCode') ?? '',
        serverUrl: sp.getString('serverUrl') ?? AppConfig.defaultServer,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('name', name);
    await sp.setString('ambulanceId', ambulanceId);
    await sp.setString('accessCode', accessCode);
    await sp.setString('serverUrl', serverUrl);
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('name');
  }
}
