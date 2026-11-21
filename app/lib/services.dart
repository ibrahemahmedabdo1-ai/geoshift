import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockChannel {
  static const _c = MethodChannel('geoshift/mock');

  static Future<bool> isReady() async {
    try {
      return await _c.invokeMethod<bool>('isReady') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> openDeveloperSettings() =>
      _c.invokeMethod('openDeveloperSettings');

  static Future<void> update(LatLng p,
          {double speed = 0, double bearing = 0}) =>
      _c.invokeMethod('update', {
        'lat': p.latitude,
        'lng': p.longitude,
        'speed': speed,
        'bearing': bearing,
      });

  static Future<void> stop() => _c.invokeMethod('stop');
}

class Place {
  const Place(this.name, this.point);
  final String name;
  final LatLng point;

  Map<String, dynamic> toJson() =>
      {'n': name, 'lat': point.latitude, 'lng': point.longitude};

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        j['n'] as String,
        LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
      );
}

class SearchService {
  static final _coords =
      RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*[,\s]\s*(-?\d+(?:\.\d+)?)\s*$');

  static Future<List<Place>> search(String q) async {
    final m = _coords.firstMatch(q);
    if (m != null) {
      final lat = double.parse(m[1]!);
      final lng = double.parse(m[2]!);
      if (lat.abs() <= 90 && lng.abs() <= 180) {
        return [Place('$lat, $lng', LatLng(lat, lng))];
      }
    }
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'json',
      'limit': '6',
      'accept-language': 'ar',
    });
    final r = await http
        .get(uri, headers: {'User-Agent': 'GeoShift/1.0'})
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return [];
    return (jsonDecode(r.body) as List)
        .map((e) => Place(
              e['display_name'] as String,
              LatLng(double.parse(e['lat'] as String),
                  double.parse(e['lon'] as String)),
            ))
        .toList();
  }
}

class Store {
  static Future<List<Place>> favorites() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('favs');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Place.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveFavorites(List<Place> f) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('favs', jsonEncode(f.map((e) => e.toJson()).toList()));
  }

  static Future<LatLng?> lastPoint() async {
    final p = await SharedPreferences.getInstance();
    final lat = p.getDouble('lat');
    final lng = p.getDouble('lng');
    return (lat == null || lng == null) ? null : LatLng(lat, lng);
  }

  static Future<void> saveLast(LatLng l) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('lat', l.latitude);
    await p.setDouble('lng', l.longitude);
  }
}
