import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/RSU.dart';
import '../utils/distance_calculator.dart' as dc;

class ApiService {
  // 🌍 Replace this with your current ngrok public URL
  static const String baseUrl = "https://frothy-bebe-sirenically.ngrok-free.dev";

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

  // ---------------------------
  // Pedestrian CRUD & queries
  // ---------------------------

  /// Create a new pedestrian in remote DB. Returns created Pedestrian (with uid/timestamp if provided by server)
  Future<Pedestrian> createPedestrian(Pedestrian p) async {
    final url = Uri.parse('$baseUrl/pedestrians');
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: json.encode(p.toMap()),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to create pedestrian: ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data is Map<String, dynamic>) {
      return Pedestrian.fromMap(data);
    }
    throw FormatException('Unexpected create response format');
  }

  /// Read/get pedestrian by uid
  Future<Pedestrian> getPedestrian(String uid) async {
    final url = Uri.parse('$baseUrl/pedestrians/$uid');
    final response = await http.get(url);
    if (response.statusCode != 200) throw Exception('Not found: $uid');
    final data = json.decode(response.body);
    return Pedestrian.fromMap(Map<String, dynamic>.from(data));
  }

  /// Update pedestrian by uid
  Future<Pedestrian> updatePedestrianById(String uid, Map<String, dynamic> patch) async {
    final url = Uri.parse('$baseUrl/pedestrians/$uid');
    final response = await http.put(
      url,
      headers: {"Content-Type": "application/json"},
      body: json.encode(patch),
    );
    if (response.statusCode != 200) throw Exception('Failed to update: $uid');
    final data = json.decode(response.body);
    return Pedestrian.fromMap(Map<String, dynamic>.from(data));
  }

  /// Delete pedestrian by uid
  Future<bool> deletePedestrian(String uid) async {
    final url = Uri.parse('$baseUrl/pedestrians/$uid');
    final response = await http.delete(url);
    return response.statusCode == 200 || response.statusCode == 204;
  }

  /// Query pedestrians within great-circle `distanceMeters` of (lat, lon)
  /// Expects server endpoint: GET /pedestrians/nearby?lat={lat}&lon={lon}&r={meters}
  Future<List<Pedestrian>> queryByDistance(double lat, double lon, double rMeters) async {
    // Strategy:
    // 1) Try to call server-side nearby endpoint if available (fast). If it fails,
    // 2) fallback: fetch all pedestrians, prefilter by Haversine with a slightly
    //    expanded radius, then compute road distance via OSRM per candidate and
    //    return those within rMeters.

    // Attempt server-side endpoint first
    try {
      final url = Uri.parse('$baseUrl/pedestrians/nearby?lat=$lat&lon=$lon&r=$rMeters');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          return data.map((e) => Pedestrian.fromMap(Map<String, dynamic>.from(e))).toList();
        }
      }
    } catch (e) {
      debugPrint('Server-side nearby endpoint not available or failed: $e');
    }

    // Fallback strategy: client-side filtering + OSRM routing
    final all = await fetchPedestrians();
    final candidates = all.map((m) => Pedestrian.fromMap(m)).where((p) {
      // prefilter by Haversine with a small buffer to reduce OSRM calls
      return dc.withinDistance(lat, lon, p.lat, p.lon, rMeters * 1.5);
    }).toList();

    // Helper to call OSRM route and return distance in meters
    Future<double> _roadDistance(Pedestrian p) async {
      final osrmBase = 'https://router.project-osrm.org';
      try {
        final coords = '${lon.toString()},${lat.toString()};${p.lon.toString()},${p.lat.toString()}';
        final url = Uri.parse('$osrmBase/route/v1/driving/$coords?overview=false');
        final res = await http.get(url).timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) {
          debugPrint('OSRM non-200: ${res.statusCode}');
          return dc.distanceMeters(lat, lon, p.lat, p.lon); // fallback to geodesic
        }
        final j = json.decode(res.body);
        if (j['routes'] is List && j['routes'].isNotEmpty) {
          final route = j['routes'][0];
          final d = (route['distance'] is num) ? (route['distance'] as num).toDouble() : double.parse(route['distance'].toString());
          return d; // meters
        }
        return dc.distanceMeters(lat, lon, p.lat, p.lon);
      } catch (e) {
        debugPrint('OSRM error: $e');
        return dc.distanceMeters(lat, lon, p.lat, p.lon);
      }
    }

    // Limit concurrency to avoid aggressive OSRM calls; process in small batches
    final results = <Pedestrian>[];
    const batchSize = 8;
    for (var i = 0; i < candidates.length; i += batchSize) {
      final batch = candidates.skip(i).take(batchSize).toList();
      final distances = await Future.wait(batch.map(_roadDistance));
      for (var j = 0; j < batch.length; j++) {
        if (distances[j] <= rMeters) results.add(batch[j]);
      }
    }
    return results;
  }

  /// Query pedestrians within displacement radius `rMeters` using server-side projection
  /// Expects server endpoint: GET /pedestrians/displacement?lat={lat}&lon={lon}&r={meters}
  Future<List<Pedestrian>> queryByDisplacement(double lat, double lon, double rMeters) async {
    final url = Uri.parse('$baseUrl/pedestrians/displacement?lat=$lat&lon=$lon&r=$rMeters');
    final response = await http.get(url);
    if (response.statusCode != 200) throw Exception('Query failed: ${response.statusCode}');
    final data = json.decode(response.body);
    if (data is List) {
      return data.map((e) => Pedestrian.fromMap(Map<String, dynamic>.from(e))).toList();
    }
    throw FormatException('Unexpected queryByDisplacement format');
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
