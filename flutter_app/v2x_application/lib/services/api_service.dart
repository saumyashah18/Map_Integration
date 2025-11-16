// lib/services/api_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/RSU.dart';
import '../utils/distance_calculator.dart' as dc;

class ApiService {
  static const String defaultBaseUrl = "https://jeneva-chylocaulous-vocatively.ngrok-free.dev";

  /// The base URL used for requests. It can be updated at runtime.
  String baseUrl;

  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? defaultBaseUrl {
    // Load any previously persisted baseUrl (fire-and-forget)
    _loadPersistedBaseUrl();
  }

  // Attempt to load persisted baseUrl (fire-and-forget)
  void _loadPersistedBaseUrl() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final saved = sp.getString('api_base_url');
      if (saved != null && saved.isNotEmpty && saved != baseUrl) {
        baseUrl = saved;
        debugPrint('Loaded persisted baseUrl: $baseUrl');
      }
    } catch (e) {
      debugPrint('Failed to load persisted baseUrl: $e');
    }
  }

  // (removed unused named constructor)

  // 🚶 Fetch all pedestrian alerts from Flask
  Future<List<Pedestrian>> fetchPedestrians() async {
    final url = Uri.parse('$baseUrl/get-pedestrians');
    try {
      final response = await http.get(url);

      final contentType = response.headers['content-type'] ?? '';
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final bodyTrim = response.body.trimLeft();
      if (contentType.toLowerCase().contains('html') ||
          bodyTrim.startsWith('<')) {
        final snippet = response.body.length > 200
            ? response.body.substring(0, 200)
            : response.body;

        // ❗ NO `const` here – we’re interpolating $snippet
        throw FormatException(
          'Expected JSON but received HTML/markup. Response snippet: $snippet',
        );
      }

      final data = json.decode(response.body);

      // support both: a list of alerts OR a single alert object
      if (data is List) {
        return data
            .map<Pedestrian>((e) => Pedestrian.fromMap(
                  Map<String, dynamic>.from(e),
                ))
            .toList();
      } else if (data is Map) {
        return [
          Pedestrian.fromMap(
            Map<String, dynamic>.from(data),
          ),
        ];
      } else {
        throw FormatException(
          'Unexpected JSON format: expected List or Map but got ${data.runtimeType}',
        );
      }
    } catch (e) {
      debugPrint('API Exception (fetchPedestrians): $e');
      rethrow;
    }
  }

  /// Update the baseUrl used by this ApiService instance.
  void updateBaseUrl(String url) {
    baseUrl = url;
    debugPrint('ApiService baseUrl updated to: $baseUrl');
    // persist
    SharedPreferences.getInstance().then((sp) => sp.setString('api_base_url', url));
  }

  // 🚗 Send current vehicle coordinates to Flask
  Future<void> updateLocation(double lat, double lon) async {
    final url = Uri.parse('$baseUrl/update-location');
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "id": "vehicle1",
          "lat": lat,
          "lon": lon,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Vehicle location updated successfully');
      } else {
        debugPrint('❌ Failed to update location: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("Exception while updating location: $e");
    }
  }

  // 👣 test/demo endpoint (sends a pedestrian alert)
  Future<void> updatePedestrian(
    double lat,
    double lon, {
    String pedestrianId = "pedestrian1",
    String rsuId = "RSU1",
    String obuId = "OBU1",
    int pedestriansCount = 1,
  }) async {
    final url = Uri.parse('$baseUrl/update-pedestrian');
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "id": pedestrianId,
          "lat": lat,
          "lon": lon,
          "pedestrians_count": pedestriansCount,
          "rsuid": rsuId,
          "obuid": obuId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Pedestrian alert sent successfully');
      } else {
        debugPrint('❌ Failed to update pedestrian: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Exception while updating pedestrian: $e');
    }
  }

  /// Optional: distance-based query on client side
  Future<List<Pedestrian>> queryByDistance(
      double lat, double lon, double rMeters) async {
    final all = await fetchPedestrians();
    final list = all.where((p) {
      return dc.withinDisplacement(lat, lon, p.lat, p.lon, rMeters);
    }).toList();
    return list;
  }
}
