import 'package:geolocator/geolocator.dart';

class LocationHelper {
  /// null = sab theek. Warna error message (Hinglish).
  static Future<String?> ensureReady() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return 'Phone GPS / Location is turned off. Please turn it on.';
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied) {
        return 'Location permission was denied. Please allow it.';
      }
      if (p == LocationPermission.deniedForever) {
        return 'Location permission is blocked. Open Phone Settings > Apps > AmbuRoute > Permissions > Location and allow it.';
      }
      return null;
    } catch (e) {
      return 'Location check error: $e';
    }
  }
}
