// lib/services/optimized_distance_service.dart
// COMPLETE FILE - REPLACE ENTIRELY
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import '../utils/astar_pathfinder.dart';

class OptimizedDistanceService {
  static const String osrmTableUrl = "https://router.project-osrm.org/table/v1/driving";
  
  // IMPROVED: Longer cache expiry to reduce API calls
  final Map<String, CachedDistance> _distanceCache = {};
  static const int cacheExpirySeconds = 120; // 2 minutes cache
  
  // IMPROVED: Stricter rate limiting
  DateTime? _lastRequestTime;
  static const int minRequestIntervalMs = 1000; // 1 second between requests
  
  // IMPROVED: Exponential backoff for retries
  int _failureCount = 0;
  DateTime? _backoffUntil;
  
  // IMPROVED: Use A* (OSRM route) fallback when table API fails
  bool _useAStarFallback = false;
  
  /// Calculate distances from ONE vehicle to MULTIPLE pedestrians
  Future<Map<String, double>> calculateDistancesToMultiplePedestrians(
    LatLng vehicleLocation,
    List<PedestrianLocation> pedestrians,
  ) async {
    if (pedestrians.isEmpty) return {};
    
    // Check if in backoff period
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)) {
      final waitSeconds = _backoffUntil!.difference(DateTime.now()).inSeconds;
      debugPrint('⏸️ In backoff period, waiting ${waitSeconds}s...');
      return await _getCachedOrAStarDistances(vehicleLocation, pedestrians);
    }
    
    // Check cache first
    final cachedResults = <String, double>{};
    final uncachedPedestrians = <PedestrianLocation>[];
    
    for (final ped in pedestrians) {
      final cacheKey = _getCacheKey(vehicleLocation, ped.location);
      final cached = _distanceCache[cacheKey];
      
      if (cached != null && !cached.isExpired()) {
        cachedResults[ped.id] = cached.distanceMeters;
      } else {
        uncachedPedestrians.add(ped);
      }
    }
    
    // If all cached, return immediately
    if (uncachedPedestrians.isEmpty) {
      debugPrint('✅ All distances from cache (${cachedResults.length} pedestrians)');
      return cachedResults;
    }
    
    // If using fallback, use A* route distances for uncached
    if (_useAStarFallback) {
      debugPrint('🔄 Using A* fallback for ${uncachedPedestrians.length} pedestrians');
      final fallbackResults = await _calculateAStarDistances(vehicleLocation, uncachedPedestrians);
      return {...cachedResults, ...fallbackResults};
    }
    
    // Try API call with rate limiting
    await _enforceRateLimit();
    
    final results = <String, double>{...cachedResults};
    const batchSize = 10; // REDUCED from 50 to be safer
    
    for (int i = 0; i < uncachedPedestrians.length; i += batchSize) {
      final batch = uncachedPedestrians.skip(i).take(batchSize).toList();
      final batchResults = await _processBatch(vehicleLocation, batch);
      
      if (batchResults.isEmpty && batch.isNotEmpty) {
        // API failed, use A* fallback for this batch
        debugPrint('⚠️ API failed, using A* for ${batch.length} pedestrians');
        final fallbackResults = await _calculateAStarDistances(vehicleLocation, batch);
        results.addAll(fallbackResults);
      } else {
        results.addAll(batchResults);
      }
      
      // Add delay between batches
      if (i + batchSize < uncachedPedestrians.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    
    return results;
  }

  /// Calculate distances using A* (OSRM route) for multiple pedestrians.
  /// This forces per-pair routing (slower than table API) but gives road-aware distances.
  /// Uses batching/concurrency to avoid blasting the OSRM server and caches results.
  Future<Map<String, double>> calculateDistancesUsingAStar(
    LatLng vehicleLocation,
    List<PedestrianLocation> pedestrians, {
    int concurrency = 4,
  }) async {
    if (pedestrians.isEmpty) return {};

    final results = <String, double>{};
    final uncached = <PedestrianLocation>[];

    for (final ped in pedestrians) {
      final key = _getCacheKey(vehicleLocation, ped.location);
      final cached = _distanceCache[key];
      if (cached != null && !cached.isExpired()) {
        results[ped.id] = cached.distanceMeters;
      } else {
        uncached.add(ped);
      }
    }

    for (int i = 0; i < uncached.length; i += concurrency) {
      final batch = uncached.skip(i).take(concurrency).toList();

      final futures = batch.map((ped) async {
        final key = _getCacheKey(vehicleLocation, ped.location);
        try {
          final dist = await AStarPathfinder.calculateRoadDistance(vehicleLocation, ped.location);
          final distance = (dist.isFinite) ? dist : double.infinity;

          _distanceCache[key] = CachedDistance(
            distanceMeters: distance,
            durationSeconds: distance / 15.0,
            timestamp: DateTime.now(),
          );

          return MapEntry(ped.id, distance);
        } catch (e) {
          debugPrint('❌ A* routing failed for pair in batch: $e');
          final distance = double.infinity;
          _distanceCache[key] = CachedDistance(
            distanceMeters: distance,
            durationSeconds: double.infinity,
            timestamp: DateTime.now(),
          );
          return MapEntry(ped.id, distance);
        }
      }).toList();

      final batchResults = await Future.wait(futures);
      for (final kv in batchResults) {
        results[kv.key] = kv.value;
      }

      if (i + concurrency < uncached.length) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    return results;
  }
  
  /// Process a batch of pedestrians
  Future<Map<String, double>> _processBatch(
    LatLng vehicleLocation,
    List<PedestrianLocation> pedestrians,
  ) async {
    // Build coordinates string
    final coords = StringBuffer();
    coords.write('${vehicleLocation.longitude},${vehicleLocation.latitude}');
    
    for (final ped in pedestrians) {
      coords.write(';${ped.location.longitude},${ped.location.latitude}');
    }
    
    try {
      final url = Uri.parse('$osrmTableUrl/$coords?sources=0&annotations=distance,duration');
      
      debugPrint('🌐 OSRM Table API: 1 vehicle → ${pedestrians.length} pedestrians');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10), // INCREASED timeout to 10s
        onTimeout: () => throw TimeoutException('OSRM request timed out'),
      );
      
      if (response.statusCode == 429) {
        // Rate limited - activate backoff
        _failureCount++;
        final backoffSeconds = math.min(60, math.pow(2, _failureCount).toInt());
        _backoffUntil = DateTime.now().add(Duration(seconds: backoffSeconds));
        debugPrint('🚫 Rate limited! Backing off for ${backoffSeconds}s');
        throw Exception('HTTP 429 - Rate Limited');
      }
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok') {
          final distances = data['distances'][0] as List;
          final durations = data['durations'][0] as List;

          final results = <String, double>{};

          for (int i = 0; i < pedestrians.length; i++) {
            final ped = pedestrians[i];
            final distance = (distances[i + 1] as num).toDouble();
            final duration = (durations[i + 1] as num).toDouble();

            // Debug: compare OSRM table distance vs straight-line heuristic
            try {
              final straight = AStarPathfinder.straightLineDistance(vehicleLocation, ped.location);
              debugPrint('OSRM table distance to ${ped.id}: ${distance.toStringAsFixed(1)}m (straight-line ${straight.toStringAsFixed(1)}m)');
            } catch (e) {
              debugPrint('OSRM table distance to ${ped.id}: ${distance.toStringAsFixed(1)}m');
            }

            results[ped.id] = distance;

            // Cache result with longer expiry
            final cacheKey = _getCacheKey(vehicleLocation, ped.location);
            _distanceCache[cacheKey] = CachedDistance(
              distanceMeters: distance,
              durationSeconds: duration,
              timestamp: DateTime.now(),
            );
          }

          // Reset failure count on success
          _failureCount = 0;
          _useAStarFallback = false;

          return results;
        } else {
          throw Exception('OSRM returned: ${data['code']}');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } on TimeoutException catch (e) {
      debugPrint('❌ Distance calculation error: $e');
      _failureCount++;
      
      // After 3 timeouts, switch to A* fallback
      if (_failureCount >= 3) {
        debugPrint('⚠️ Too many failures, switching to A* fallback mode');
        _useAStarFallback = true;
      }
      
      return {};
    } catch (e) {
      debugPrint('❌ Distance calculation error: $e');
      _failureCount++;
      
      if (_failureCount >= 3) {
        _useAStarFallback = true;
      }
      
      return {};
    }
  }
  
  /// Calculate road distances using A* (OSRM route) for each pair.
  /// If A* fails for a pair, returns `double.infinity` (no haversine fallback).
  Future<Map<String, double>> _calculateAStarDistances(
    LatLng vehicleLocation,
    List<PedestrianLocation> pedestrians,
  ) async {
    final results = <String, double>{};

    for (final ped in pedestrians) {
      final cacheKey = _getCacheKey(vehicleLocation, ped.location);

      try {
        final dist = await AStarPathfinder.calculateRoadDistance(vehicleLocation, ped.location);
        final distance = (dist.isFinite) ? dist : double.infinity;

        results[ped.id] = distance;

        // Cache result (may be infinity if routing failed)
        _distanceCache[cacheKey] = CachedDistance(
          distanceMeters: distance,
          durationSeconds: distance.isFinite ? distance / 15.0 : double.infinity,
          timestamp: DateTime.now(),
        );
      } catch (e) {
        // On any error, mark as unreachable (infinite distance)
        debugPrint('❌ A* routing failed for pair: $e');
        final distance = double.infinity;
        results[ped.id] = distance;
        _distanceCache[cacheKey] = CachedDistance(
          distanceMeters: distance,
          durationSeconds: double.infinity,
          timestamp: DateTime.now(),
        );
      }
    }

    return results;
  }
  
  /// Get cached distances or compute using A* (async). Falls back to haversine per pair.
  Future<Map<String, double>> _getCachedOrAStarDistances(
    LatLng vehicleLocation,
    List<PedestrianLocation> pedestrians,
  ) async {
    final results = <String, double>{};

    final toCompute = <PedestrianLocation>[];

    for (final ped in pedestrians) {
      final cacheKey = _getCacheKey(vehicleLocation, ped.location);
      final cached = _distanceCache[cacheKey];

      if (cached != null && !cached.isExpired()) {
        results[ped.id] = cached.distanceMeters;
      } else {
        toCompute.add(ped);
      }
    }

    if (toCompute.isNotEmpty) {
      final computed = await _calculateAStarDistances(vehicleLocation, toCompute);
      results.addAll(computed);
    }

    return results;
  }
  
  // Haversine removed: distances now computed exclusively using A* (OSRM routes).
  
  /// Enforce rate limiting between requests
  Future<void> _enforceRateLimit() async {
    if (_lastRequestTime != null) {
      final timeSinceLastRequest = DateTime.now().difference(_lastRequestTime!).inMilliseconds;
      if (timeSinceLastRequest < minRequestIntervalMs) {
        await Future.delayed(Duration(milliseconds: minRequestIntervalMs - timeSinceLastRequest));
      }
    }
    _lastRequestTime = DateTime.now();
  }
  
  /// Generate cache key
  String _getCacheKey(LatLng from, LatLng to) {
    // Round to 3 decimal places for better cache hits
    return '${from.latitude.toStringAsFixed(3)},${from.longitude.toStringAsFixed(3)}'
           '->${to.latitude.toStringAsFixed(3)},${to.longitude.toStringAsFixed(3)}';
  }
  
  /// Clean expired cache entries
  void cleanCache() {
    final before = _distanceCache.length;
    _distanceCache.removeWhere((key, value) => value.isExpired());
    debugPrint('🧹 Cleaned cache: $before → ${_distanceCache.length} entries');
  }
  
  /// Clear all cache and reset state
  void clearCache() {
    _distanceCache.clear();
    _failureCount = 0;
    _backoffUntil = null;
    _useAStarFallback = false;
    debugPrint('🗑️ Cache cleared, state reset');
  }
  
  /// Get current state info
  String getStatusInfo() {
    final status = _useAStarFallback ? 'A* Fallback' : 'OSRM API';
    final cached = _distanceCache.length;
    final backoff = _backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)
        ? 'Yes (${_backoffUntil!.difference(DateTime.now()).inSeconds}s)'
        : 'No';
    
    return 'Mode: $status | Cache: $cached | Backoff: $backoff';
  }
}

// Helper classes
class PedestrianLocation {
  final String id;
  final LatLng location;
  
  PedestrianLocation({required this.id, required this.location});
}

class CachedDistance {
  final double distanceMeters;
  final double durationSeconds;
  final DateTime timestamp;
  
  CachedDistance({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.timestamp,
  });
  
  bool isExpired() {
    return DateTime.now().difference(timestamp).inSeconds > OptimizedDistanceService.cacheExpirySeconds;
  }
}