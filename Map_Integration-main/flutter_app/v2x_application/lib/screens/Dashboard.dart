// lib/screens/Dashboard.dart
// COMPLETE FILE - REPLACE ENTIRELY (LAYOUT FIXED)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_service.dart';
import '../services/optimized_distance_service.dart';
import '../models/RSU.dart' as rsu;
import '../models/StaticPedestrian.dart';
import '../utils/astar_pathfinder.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _currentLocation;
  late final MapController _mapController;
  RouteData? _currentRoute;
  List<LatLng> _routePoints = [];
  final ApiService _apiService = ApiService();
  final OptimizedDistanceService _distanceService = OptimizedDistanceService();

  final List<StaticPedestrian> _pedestrians = [];
  final List<PedestrianAlertData> _activeAlerts = [];
  
  StreamSubscription<Position>? _positionSub;
  Timer? _distanceCheckTimer;
  Timer? _cacheCleanupTimer;

  final LatLng _fallbackCenter = const LatLng(23.0225, 72.5714);
  static const double _collisionThresholdMeters = 2000.0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _initLocation();
    _fetchPedestriansFromBackend();
    _startCacheCleanup();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _distanceCheckTimer?.cancel();
    _cacheCleanupTimer?.cancel();
    super.dispose();
  }

  void _startCacheCleanup() {
    _cacheCleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _distanceService.cleanCache();
    });
  }

  Future<void> _initLocation() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      setState(() {
        _currentLocation = LatLng(pos.latitude, pos.longitude);
      });

      debugPrint('✅ Initial location: ${pos.latitude}, ${pos.longitude}');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(_currentLocation!, 15);
      });

      _startDistanceChecking();

    } catch (e) {
      debugPrint('❌ Error getting location: $e');
      setState(() {
        _currentLocation = _fallbackCenter;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(_fallbackCenter, 15);
      });
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      debugPrint('📍 GPS Update: ${position.latitude}, ${position.longitude}');

      final newLoc = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentLocation = newLoc;
      });

      _apiService.updateLocation(position.latitude, position.longitude);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(newLoc, _mapController.camera.zoom);
        } catch (e) {
          debugPrint('Map update error: $e');
        }
      });
    });
  }

  Future<bool> _handleLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('⚠️ Location services disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('⚠️ Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('⚠️ Location permission permanently denied');
      return false;
    }

    return true;
  }

  Future<void> _fetchPedestriansFromBackend() async {
    try {
      final List<rsu.Pedestrian> data = await _apiService.fetchPedestrians();
      debugPrint('📡 Fetched ${data.length} pedestrians from backend');

      setState(() {
        _pedestrians.clear();
        for (final p in data) {
          _pedestrians.add(StaticPedestrian(
            id: p.id,
            roadLocation: LatLng(p.lat, p.lon),
            isDetected: false,
          ));
        }
      });

      if (_currentLocation != null) {
        _checkAllPedestrianDistances();
      }
    } catch (e) {
      debugPrint('❌ Error fetching pedestrians: $e');
    }
  }

  Future<void> _spawnProxyPedestrian() async {
    if (_currentLocation == null) {
      debugPrint('⚠️ Current location not available');
      return;
    }

    final random = (DateTime.now().millisecondsSinceEpoch % 1000) / 1000.0;
    final offset = (random - 0.5) * 0.05;
    
    final testLat = _currentLocation!.latitude + offset;
    final testLon = _currentLocation!.longitude + offset;

    final testLocation = LatLng(testLat, testLon);

    debugPrint('📍 Spawning pedestrian near (${testLat.toStringAsFixed(5)}, ${testLon.toStringAsFixed(5)})');
    final snappedLocation = await _apiService.snapToRoad(testLocation);
    final finalLocation = snappedLocation ?? testLocation;

    final proxyPed = StaticPedestrian(
      id: 'ped_${DateTime.now().millisecondsSinceEpoch}',
      roadLocation: finalLocation,
      isDetected: false,
    );

    setState(() {
      _pedestrians.add(proxyPed);
    });

    debugPrint('✅ Spawned pedestrian at (${finalLocation.latitude.toStringAsFixed(5)}, ${finalLocation.longitude.toStringAsFixed(5)})');

    await _checkAllPedestrianDistances();
  }

  Future<void> _showRouteToPedestrian(StaticPedestrian ped) async {
    if (_currentLocation == null) return;

    try {
      final route = await AStarPathfinder.getRoute(_currentLocation!, ped.roadLocation);
      if (route.distanceMeters.isFinite && route.waypoints.isNotEmpty) {
        setState(() {
          _currentRoute = route;
          _routePoints = route.waypoints;
        });

        // Try to center the map on the route bounds (fitBounds not available).
        try {
          final bounds = LatLngBounds.fromPoints(_routePoints);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              // Compute simple center from bounds
              final lats = _routePoints.map((p) => p.latitude).toList();
              final lons = _routePoints.map((p) => p.longitude).toList();
              final minLat = lats.reduce((a, b) => a < b ? a : b);
              final maxLat = lats.reduce((a, b) => a > b ? a : b);
              final minLon = lons.reduce((a, b) => a < b ? a : b);
              final maxLon = lons.reduce((a, b) => a > b ? a : b);
              final center = LatLng((minLat + maxLat) / 2.0, (minLon + maxLon) / 2.0);
              _mapController.move(center, _mapController.camera.zoom);
            } catch (e) {
              debugPrint('Centering route error: $e');
            }
          });
        } catch (e) {
          debugPrint('Fit bounds error: $e');
        }
      } else {
        debugPrint('No valid route returned');
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
    }
  }

  void _clearRoute() {
    setState(() {
      _currentRoute = null;
      _routePoints = [];
    });
  }

  Future<void> _spawnMultiplePedestrians(int count) async {
    if (_currentLocation == null) {
      debugPrint('⚠️ Current location not available');
      return;
    }

    debugPrint('👥 Spawning $count pedestrians...');
    
    for (int i = 0; i < count; i++) {
      await _spawnProxyPedestrian();
      await Future.delayed(const Duration(milliseconds: 200));
    }
    
    debugPrint('✅ Spawned $count pedestrians');
  }

  void _startDistanceChecking() {
    _distanceCheckTimer?.cancel();
    _distanceCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_currentLocation != null) {
        _checkAllPedestrianDistances();
      }
    });
  }

  Future<void> _checkAllPedestrianDistances() async {
    if (_currentLocation == null || _pedestrians.isEmpty) return;

    debugPrint('🔍 Checking distances to ${_pedestrians.length} pedestrians...');

    try {
      final pedestrianLocations = _pedestrians.map((ped) => 
        PedestrianLocation(id: ped.id, location: ped.roadLocation)
      ).toList();

      final distances = await _distanceService.calculateDistancesToMultiplePedestrians(
        _currentLocation!,
        pedestrianLocations,
      );

      setState(() {
        for (final ped in _pedestrians) {
          final distance = distances[ped.id];
          
          if (distance != null) {
            ped.lastDetectionDistance = distance;

            if (distance <= _collisionThresholdMeters) {
              if (!ped.isDetected) {
                ped.isDetected = true;
                
                final alert = PedestrianAlertData(
                  pedestrianId: ped.id,
                  pedestrianLocation: ped.roadLocation,
                  distanceMeters: distance,
                  durationSeconds: distance / 15.0,
                  detectionTime: DateTime.now(),
                  isNew: true,
                );

                _activeAlerts.insert(0, alert);
                if (_activeAlerts.length > 10) {
                  _activeAlerts.removeLast();
                }

                _apiService.updatePedestrian(
                  ped.roadLocation.latitude,
                  ped.roadLocation.longitude,
                  pedestrianId: ped.id,
                );

                debugPrint('🚨 NEW ALERT: ${ped.id} at ${distance.toStringAsFixed(0)}m');
              }
            } else {
              if (ped.isDetected) {
                ped.isDetected = false;
                debugPrint('✓ ${ped.id} moved out of range');
              }
            }
          }
        }
      });
    } catch (e) {
      debugPrint('❌ Error checking distances: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("V2X Pedestrian Alert System"),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add 1 Pedestrian',
            onPressed: _spawnProxyPedestrian,
          ),
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: 'Add 5 Pedestrians',
            onPressed: () => _spawnMultiplePedestrians(5),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh from Backend',
            onPressed: _fetchPedestriansFromBackend,
          ),
          IconButton(
            icon: const Icon(Icons.directions),
            tooltip: 'Clear Route',
            onPressed: _clearRoute,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear All',
            onPressed: () {
              setState(() {
                _pedestrians.clear();
                _activeAlerts.clear();
                _distanceService.clearCache();
              });
            },
          ),
        ],
      ),

      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? _fallbackCenter,
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: const ['a', 'b', 'c'],
              ),

              // Route polyline layer (A* route)
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.blue.shade700,
                      strokeWidth: 4.0,
                    ),
                  ],
                ),

              MarkerLayer(
                markers: [
                  if (_currentLocation != null)
                    Marker(
                      width: 60,
                      height: 60,
                      point: _currentLocation!,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.directions_car,
                          color: Colors.white,
                          size: 35,
                        ),
                      ),
                    ),

                  ..._pedestrians.map((ped) {
                    final isDetected = ped.isDetected;
                    final distance = ped.lastDetectionDistance ?? double.infinity;
                    
                    return Marker(
                      width: 60,
                      height: 60,
                      point: ped.roadLocation,
                      child: GestureDetector(
                        onTap: () => _showRouteToPedestrian(ped),
                        child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (isDetected)
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.red, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.7),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              color: isDetected ? Colors.red : Colors.orange,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          if (distance != double.infinity)
                            Positioned(
                              bottom: -5,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isDetected ? Colors.red : Colors.orange,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${(distance / 1000).toStringAsFixed(1)}km',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      );
                  }),
                ],
              ),
            ],
          ),

          Positioned(
            top: 16,
            right: 16,
            child: Container(
              width: 350,
              constraints: const BoxConstraints(maxHeight: 350),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                  ),
                ],
                border: Border.all(
                  color: _activeAlerts.isNotEmpty ? Colors.red : Colors.green,
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Collision Alerts (${_activeAlerts.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_activeAlerts.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            '🚨 DANGER',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: _activeAlerts.isEmpty
                        ? const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                              SizedBox(width: 8),
                              Text(
                                '✓ No collision alerts',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: _activeAlerts.map((alert) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.red.withOpacity(0.4),
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text('🚨', style: TextStyle(fontSize: 14)),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                alert.pedestrianId,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '📍 ${(alert.distanceMeters / 1000).toStringAsFixed(2)}km (${alert.distanceMeters.toStringAsFixed(0)}m)',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'ETA: ${(alert.durationSeconds / 60).toStringAsFixed(1)} min',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.red.withOpacity(0.7),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),

          // FIXED: Stats panel with proper constraints
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 280, // ADDED: Maximum width constraint
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'System Status',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Pedestrian count row
                  Row(
                    mainAxisSize: MainAxisSize.min, // ADDED: Prevent overflow
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Pedestrians: ${_pedestrians.length}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Status info row - FIXED with proper wrapping
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(top: 2), // Align with text
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _distanceService.getStatusInfo(),
                          style: const TextStyle(fontSize: 9),
                          maxLines: 2, // ADDED: Allow 2 lines
                          overflow: TextOverflow.ellipsis,
                          softWrap: true, // ADDED: Enable wrapping
                        ),
                      ),
                    ],
                  ),
                  // GPS coordinates row
                  if (_currentLocation != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'GPS: ${_currentLocation!.latitude.toStringAsFixed(4)}, ${_currentLocation!.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 9),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'spawn1',
                  onPressed: _spawnProxyPedestrian,
                  backgroundColor: Colors.green,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add 1'),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'spawn5',
                  onPressed: () => _spawnMultiplePedestrians(5),
                  backgroundColor: Colors.orange,
                  icon: const Icon(Icons.group_add),
                  label: const Text('Add 5'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PedestrianAlertData {
  final String pedestrianId;
  final LatLng pedestrianLocation;
  final double distanceMeters;
  final double durationSeconds;
  final DateTime detectionTime;
  final bool isNew;

  PedestrianAlertData({
    required this.pedestrianId,
    required this.pedestrianLocation,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.detectionTime,
    required this.isNew,
  });
}