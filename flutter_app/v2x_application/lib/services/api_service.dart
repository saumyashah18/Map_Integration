import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // 🌍 Replace this with your current ngrok public URL
  static const String baseUrl = "https://jeneva-chylocaulous-vocatively.ngrok-free.dev";

  // 🚶 Fetch all pedestrian coordinates
  // Returns a List of maps like: [{"id": "p1", "lat": 12.34, "lon": 56.78}, ...]
  Future<List<Map<String, dynamic>>> fetchPedestrians() async {
    final url = Uri.parse('$baseUrl/get-pedestrians');
    try {
      final response = await http.get(url);

      // Helpful debugging when the server returns HTML (common with ngrok auth pages or errors)
      final contentType = response.headers['content-type'] ?? '';
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      // If server returns HTML (starts with '<' or content-type contains html), surface a clear error
      final bodyTrim = response.body.trimLeft();
      if (contentType.toLowerCase().contains('html') || bodyTrim.startsWith('<')) {
        // include a short snippet to help debugging
        final snippet = response.body.length > 200 ? response.body.substring(0, 200) : response.body;
  throw FormatException('Expected JSON but received HTML/markup. Response snippet: $snippet');
      }

      final data = json.decode(response.body);
      if (data is List) {
        // Ensure each item is a Map
        return data.map<Map<String, dynamic>>((e) {
          if (e is Map) return Map<String, dynamic>.from(e);
          return <String, dynamic>{};
        }).toList();
      } else {
        throw FormatException('Unexpected JSON format: expected List but got ${data.runtimeType}');
      }
    } catch (e) {
      // Re-throw as FormatException for JSON errors to match earlier logs, but keep original
      // use debugPrint (better for Flutter) instead of print
      // ignore: avoid_print
      debugPrint('API Exception (fetchPedestrians): $e');
      rethrow;
    }
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
      print("Exception while updating location: $e");
    }
  }

  // 👣 Optionally: send pedestrian data for testing/demo
  Future<void> updatePedestrian(double lat, double lon) async {
    final url = Uri.parse('$baseUrl/update-pedestrian');
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "id": "pedestrian1",
          "lat": lat,
          "lon": lon,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Pedestrian updated successfully');
      } else {
        debugPrint('❌ Failed to update pedestrian: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Exception while updating pedestrian: $e');
    }
  }
}
