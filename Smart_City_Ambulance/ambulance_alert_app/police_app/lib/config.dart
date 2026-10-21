import 'package:latlong2/latlong.dart';

class AppConfig {
  /// Server URL. It can also be changed under "Advanced" on the login screen.
  static const String defaultServer = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'https://smart-ambulance-mk2n.onrender.com',
  );
  static const String tileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String packageName = 'com.amburoute.police';
  static const LatLng indiaCenter = LatLng(22.9734, 78.6569);
}
