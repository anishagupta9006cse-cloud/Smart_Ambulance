import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class PostProfile {
  final String id; // server ne diya post id
  final String officer;
  final String postName;
  final String area;
  final int radius;
  final double lat;
  final double lng;
  final String accessCode;
  final String serverUrl;

  const PostProfile({
    required this.id,
    required this.officer,
    required this.postName,
    required this.area,
    required this.radius,
    required this.lat,
    required this.lng,
    required this.accessCode,
    required this.serverUrl,
  });

  PostProfile withId(String newId) => PostProfile(
        id: newId,
        officer: officer,
        postName: postName,
        area: area,
        radius: radius,
        lat: lat,
        lng: lng,
        accessCode: accessCode,
        serverUrl: serverUrl,
      );

  static Future<PostProfile?> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final id = sp.getString('postId') ?? '';
      final lat = sp.getDouble('lat');
      final lng = sp.getDouble('lng');
      if (id.isEmpty || lat == null || lng == null) return null;
      return PostProfile(
        id: id,
        officer: sp.getString('officer') ?? '',
        postName: sp.getString('postName') ?? 'Police Post',
        area: sp.getString('area') ?? '',
        radius: sp.getInt('radius') ?? 500,
        lat: lat,
        lng: lng,
        accessCode: sp.getString('accessCode') ?? '',
        serverUrl: sp.getString('serverUrl') ?? AppConfig.defaultServer,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('postId', id);
    await sp.setString('officer', officer);
    await sp.setString('postName', postName);
    await sp.setString('area', area);
    await sp.setInt('radius', radius);
    await sp.setDouble('lat', lat);
    await sp.setDouble('lng', lng);
    await sp.setString('accessCode', accessCode);
    await sp.setString('serverUrl', serverUrl);
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('postId');
  }
}
