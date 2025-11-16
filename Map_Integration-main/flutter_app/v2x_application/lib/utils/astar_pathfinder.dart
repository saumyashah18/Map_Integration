// lib/utils/astar_pathfinder.dart
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Route data returned from OSRM
class RouteData {
  final List<LatLng> waypoints; // Polyline waypoints
  final double distanceMeters; // Total distance in meters
  final double durationSeconds; // Total duration in seconds

  RouteData({
    required this.waypoints,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

/// OSRM-based A* Pathfinder
/// Uses Open Source Routing Machine (OSRM) for real road network distance calculation
/// Measures actual road distance, not straight-line distance
class AStarPathfinder {
  // OSRM API endpoint
  static const String osrmEndpoint = "https://router.project-osrm.org/route/v1/driving";

  /// Calculate shortest road distance using OSRM A*
  /// Returns actual road distance in meters (not straight-line)
  static Future<double> calculateRoadDistance(
    LatLng start,
    LatLng goal,
  ) async {
    try {
      final route = await _fetchOSRMRoute(start, goal);
      return route.distanceMeters;
    } catch (e) {
      debugPrint('❌ OSRM distance calculation failed: $e');
      return double.infinity;
    }
  }

  /// Get full route with waypoints and distance
  static Future<RouteData> getRoute(
    LatLng start,
    LatLng goal,
  ) async {
    try {
      return await _fetchOSRMRoute(start, goal);
    } catch (e) {
      debugPrint('❌ OSRM route failed: $e');
      return RouteData(
        waypoints: [start, goal],
        distanceMeters: double.infinity,
        durationSeconds: double.infinity,
      );
    }
  }

  /// Fetch route from OSRM using A* algorithm
  /// OSRM internally uses Contraction Hierarchies (an A* variant) for routing
  static Future<RouteData> _fetchOSRMRoute(
    LatLng start,
    LatLng goal,
  ) async {
    try {
      final url = Uri.parse(
        '$osrmEndpoint/${start.longitude},${start.latitude};${goal.longitude},${goal.latitude}'
        '?steps=true&geometries=geojson&overview=full&annotations=distance,duration'
      );

      debugPrint('🌐 Fetching OSRM route from (${start.latitude},${start.longitude}) to (${goal.latitude},${goal.longitude})');

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];

          // Extract distance and duration
          final distanceMeters = (route['distance'] as num?)?.toDouble() ?? 0.0;
          final durationSeconds = (route['duration'] as num?)?.toDouble() ?? 0.0;

          // Decode polyline geometry to waypoints
          final geometry = route['geometry'];
          final waypoints = _decodePolyline(geometry['coordinates']);

          debugPrint(
              '✓ OSRM route: ${distanceMeters.toStringAsFixed(1)}m, ${durationSeconds.toStringAsFixed(1)}s, ${waypoints.length} waypoints');

          return RouteData(
            waypoints: waypoints,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
          );
        } else {
          throw Exception('OSRM code: ${data['code']} - ${data['message'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      debugPrint('❌ OSRM Error: $e');
      rethrow;
    }
  }

  /// Decode GeoJSON coordinates to LatLng list
  static List<LatLng> _decodePolyline(List<dynamic> coordinates) {
    return coordinates.map<LatLng>((coord) {
      // GeoJSON uses [lon, lat] format
      return LatLng(
        (coord[1] as num).toDouble(),
        (coord[0] as num).toDouble(),
      );
    }).toList();
  }

  /// Calculate straight-line distance for heuristic only (not used for final measurement)
  static double straightLineDistance(LatLng a, LatLng b) {
    const earthRadiusMeters = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final lat1Rad = a.latitude * math.pi / 180.0;
    final lat2Rad = b.latitude * math.pi / 180.0;

    final sinHalfDLat = math.sin(dLat / 2.0);
    final sinHalfDLon = math.sin(dLon / 2.0);

    final dist = sinHalfDLat * sinHalfDLat +
        math.cos(lat1Rad) * math.cos(lat2Rad) * sinHalfDLon * sinHalfDLon;
    final centralAngle = 2.0 * math.atan2(math.sqrt(dist), math.sqrt(1 - dist));
    return earthRadiusMeters * centralAngle;
  }
}
