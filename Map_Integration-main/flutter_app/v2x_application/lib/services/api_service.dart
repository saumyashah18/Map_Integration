// lib/services/api_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/RSU.dart';

class ApiService {
  static const String baseUrl = "https://frothy-bebe-sirenically.ngrok-free.dev";
  
  // OSRM API for REAL road distance calculation
  static const String osrmRouteUrl = "https://router.project-osrm.org/route/v1/driving";

  // 🚶 Fetch pedestrian alerts from backend
  Future<List<Pedestrian>> fetchPedestrians() async {
    final url = Uri.parse('$baseUrl/get-pedestrians');
    try {
      final response = await http.get(url);

      final contentType = response.headers['content-type'] ?? '';
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final bodyTrim = response.body.trimLeft();
      if (contentType.toLowerCase().contains('html') || bodyTrim.startsWith('<')) {
        throw FormatException('Expected JSON but received HTML');
      }

      final data = json.decode(response.body);

      if (data is List) {
        return data.map<Pedestrian>((e) => Pedestrian.fromMap(Map<String, dynamic>.from(e as Map))).toList();
      } else if (data is Map) {
        return [Pedestrian.fromMap(Map<String, dynamic>.from(data as Map))];
      } else {
        throw FormatException('Unexpected JSON format');
      }
    } catch (e) {
      debugPrint(' API Exception (fetchPedestrians): $e');
      rethrow;
    }
  }

  //  Send vehicle location to backend
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
          "timestamp": DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        debugPrint(' Vehicle location updated: ($lat, $lon)');
      } else {
        debugPrint(' Failed to update location: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint(" Exception updating location: $e");
    }
  }

  // 👣 Send pedestrian alert to backend
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
          "timestamp": DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint(' Pedestrian alert sent: $pedestrianId');
      } else {
        debugPrint(' Failed to update pedestrian: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint(' Exception updating pedestrian: $e');
    }
  }

  // 🗺️ Calculate REAL road distance using OSRM (Open Source Routing Machine)
  // This uses actual OpenStreetMap data to calculate driving distance
  Future<RealDistanceResult> calculateRealRoadDistance(
    LatLng start,
    LatLng end,
  ) async {
    // OSRM format: longitude,latitude (not lat,lon!)
    final url = Uri.parse(
      '$osrmRouteUrl/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson',
    );

    try {
      debugPrint(' Calculating REAL distance from (${start.latitude},${start.longitude}) to (${end.latitude},${end.longitude})');
      
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final distanceMeters = (route['distance'] as num).toDouble();
          final durationSeconds = (route['duration'] as num).toDouble();

          debugPrint(' REAL distance: ${distanceMeters.toStringAsFixed(0)}m (${(distanceMeters/1000).toStringAsFixed(2)}km)');
          debugPrint(' ETA: ${(durationSeconds/60).toStringAsFixed(1)} minutes');

          return RealDistanceResult(
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            success: true,
          );
        } else {
          debugPrint(' OSRM returned: ${data['code']}');
          return RealDistanceResult(
            distanceMeters: 0,
            durationSeconds: 0,
            success: false,
            errorMessage: 'No route found: ${data['code']}',
          );
        }
      } else {
        debugPrint(' OSRM HTTP error: ${response.statusCode}');
        return RealDistanceResult(
          distanceMeters: 0,
          durationSeconds: 0,
          success: false,
          errorMessage: 'HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint(' Distance calculation error: $e');
      return RealDistanceResult(
        distanceMeters: 0,
        durationSeconds: 0,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  //  Check if pedestrian is nearby and calculate distance
  Future<ProximityCheckResult> checkPedestrianProximity(
    LatLng vehicleLocation,
    LatLng pedestrianLocation,
    double thresholdMeters,
  ) async {
    // Calculate REAL road distance
    final distanceResult = await calculateRealRoadDistance(
      vehicleLocation,
      pedestrianLocation,
    );

    if (!distanceResult.success) {
      return ProximityCheckResult(
        isNearby: false,
        distanceMeters: 0,
        durationSeconds: 0,
        error: distanceResult.errorMessage,
      );
    }

    final isNearby = distanceResult.distanceMeters <= thresholdMeters;

    debugPrint(
      isNearby
          ? ' NEARBY: ${distanceResult.distanceMeters.toStringAsFixed(0)}m (threshold: ${thresholdMeters.toStringAsFixed(0)}m)'
          : ' Safe: ${distanceResult.distanceMeters.toStringAsFixed(0)}m away',
    );

    return ProximityCheckResult(
      isNearby: isNearby,
      distanceMeters: distanceResult.distanceMeters,
      durationSeconds: distanceResult.durationSeconds,
    );
  }

  //  Snap coordinate to nearest road using OSRM
  Future<LatLng?> snapToRoad(LatLng coordinate) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/nearest/v1/driving/${coordinate.longitude},${coordinate.latitude}',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok' && data['waypoints'] != null && data['waypoints'].isNotEmpty) {
          final waypoint = data['waypoints'][0];
          final location = waypoint['location'];

          // location is [lon, lat]
          final snappedLoc = LatLng(
            (location[1] as num).toDouble(),
            (location[0] as num).toDouble(),
          );

          debugPrint(' Snapped to road: (${snappedLoc.latitude}, ${snappedLoc.longitude})');
          return snappedLoc;
        }
      }
    } catch (e) {
      debugPrint(' Road snapping error: $e');
    }

    return null;
  }
}

// Result classes
class RealDistanceResult {
  final double distanceMeters;
  final double durationSeconds;
  final bool success;
  final String? errorMessage;

  RealDistanceResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.success,
    this.errorMessage,
  });

  double get distanceKm => distanceMeters / 1000.0;
  double get durationMinutes => durationSeconds / 60.0;
}

class ProximityCheckResult {
  final bool isNearby;
  final double distanceMeters;
  final double durationSeconds;
  final String? error;

  ProximityCheckResult({
    required this.isNearby,
    required this.distanceMeters,
    required this.durationSeconds,
    this.error,
  });

  double get distanceKm => distanceMeters / 1000.0;
  double get durationMinutes => durationSeconds / 60.0;
}