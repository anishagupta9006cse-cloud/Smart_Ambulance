import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'config.dart';
import 'models.dart';
import 'profile.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  final String? code;
  ApiException(this.message, {this.status, this.code});
  @override
  String toString() => message;
}

class Api {
  Api._();
  static final Api I = Api._();

  String baseUrl = AppConfig.defaultServer;
  String accessCode = '';

  void configure(String? url, String? code) {
    var u = (url ?? '').trim();
    if (u.isEmpty) u = AppConfig.defaultServer;
    if (!u.startsWith('http')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    baseUrl = u;
    accessCode = (code ?? '').trim();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessCode.isNotEmpty) 'x-access-code': accessCode,
      };

  Uri _u(String path, [Map<String, String>? q]) {
    final uri = Uri.parse('$baseUrl$path');
    return (q == null || q.isEmpty) ? uri : uri.replace(queryParameters: q);
  }

  /// The free Render server sleeps; the first request can take 30-60 seconds.
  Future<bool> wakeServer({int tries = 8}) async {
    for (var i = 0; i < tries; i++) {
      try {
        final r =
            await http.get(_u('/health')).timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) return true;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 25),
    int retries = 2,
  }) async {
    ApiException? last;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final uri = _u(path, query);
        final http.Response res = method == 'GET'
            ? await http.get(uri, headers: _headers).timeout(timeout)
            : await http
                .post(uri,
                    headers: _headers,
                    body: jsonEncode(body ?? <String, dynamic>{}))
                .timeout(timeout);
        dynamic data;
        try {
          data = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
        } catch (_) {
          data = <String, dynamic>{};
        }
        final map =
            data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        if (res.statusCode >= 200 && res.statusCode < 300) return map;
        final msg =
            map['error']?.toString() ?? 'Server error (${res.statusCode})';
        final err = ApiException(msg,
            status: res.statusCode, code: map['code']?.toString());
        if (res.statusCode >= 500 && attempt < retries) {
          last = err;
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        throw err;
      } on ApiException {
        rethrow;
      } catch (_) {
        last = ApiException(
            'Cannot reach the server. Check your internet connection.');
        if (attempt < retries)
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    throw last ?? ApiException('Unknown error');
  }

  // ignore: unused_element
  Map<String, double> _pt(LatLng p) => {'lat': p.latitude, 'lng': p.longitude};

  List<PlaceResult> _places(dynamic list) {
    final out = <PlaceResult>[];
    if (list is List) {
      for (final e in list) {
        if (e is Map) {
          final lat = e['lat'], lng = e['lng'];
          if (lat is num && lng is num) {
            final d = e['distance'];
            out.add(PlaceResult(
              e['name']?.toString() ?? 'Place',
              LatLng(lat.toDouble(), lng.toDouble()),
              category: e['category']?.toString() ?? 'other',
              local: e['local'] == true,
              distance: d is num ? d.round() : null,
            ));
          }
        }
      }
    }
    return out;
  }

  /// Search by name. Saved (local) places come first.
  Future<List<PlaceResult>> geocode(String q, {LatLng? near}) async {
    final res = await _send('GET', '/api/geocode',
        query: {
          'q': q,
          if (near != null) 'lat': near.latitude.toString(),
          if (near != null) 'lng': near.longitude.toString(),
        },
        timeout: const Duration(seconds: 30));
    return _places(res['results']);
  }

  /// Saved places of one type (example: hospital), nearest first.
  Future<List<PlaceResult>> nearby(String category, {LatLng? near}) async {
    final res = await _send('GET', '/api/places/nearby',
        query: {
          'category': category,
          if (near != null) 'lat': near.latitude.toString(),
          if (near != null) 'lng': near.longitude.toString(),
        },
        timeout: const Duration(seconds: 20),
        retries: 1);
    return _places(res['results']);
  }

  /// Save a new place in the server database so everybody can find it.
  Future<void> savePlace(String name, String category, LatLng p) async {
    await _send('POST', '/api/places',
        body: {
          'name': name,
          'category': category,
          'lat': p.latitude,
          'lng': p.longitude,
        },
        retries: 1);
  }

  /// Register (or re-register) the post. Returns the post ID.
  Future<String> registerPost(PostProfile p, {bool newPost = false}) async {
    final res = await _send('POST', '/api/posts/register',
        body: {
          if (!newPost && p.id.isNotEmpty) 'id': p.id,
          'name': p.postName,
          'area': p.area,
          'officer': p.officer,
          'lat': p.lat,
          'lng': p.lng,
          'radius': p.radius,
        },
        timeout: const Duration(seconds: 40));
    final post = res['post'];
    if (post is Map && post['id'] != null) return post['id'].toString();
    throw ApiException('The server did not return a post ID. Please try again.');
  }

  Future<List<AmbAlert>> alerts(String postId) async {
    final res = await _send('GET', '/api/posts/$postId/alerts',
        timeout: const Duration(seconds: 8), retries: 0);
    final out = <AmbAlert>[];
    final list = res['alerts'];
    if (list is List) {
      for (final e in list) {
        if (e is Map) out.add(AmbAlert.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  Future<void> action(
      String postId, String tripId, String action, String officer) async {
    await _send('POST', '/api/posts/$postId/action',
        body: {'tripId': tripId, 'action': action, 'officer': officer},
        retries: 1);
  }

  Future<void> offDuty(String postId) async {
    await _send('POST', '/api/posts/$postId/offduty',
        retries: 0, timeout: const Duration(seconds: 8));
  }
}
