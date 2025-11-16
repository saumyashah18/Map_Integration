<<<<<<< HEAD
=======
import 'dart:async';

>>>>>>> 9f1ec7bd36fd8e6d890f71bd07a90eb9793cf710
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
<<<<<<< HEAD
import '../services/api_service.dart';
=======

import '../services/api_service.dart';
import '../models/RSU.dart'; // for Pedestrian
>>>>>>> 9f1ec7bd36fd8e6d890f71bd07a90eb9793cf710

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _currentLocation;
  late final MapController _mapController;
  final ApiService _apiService = ApiService();
  List<LatLng> _pedestrianLocations = [];

<<<<<<< HEAD
=======
  // Live GPS stream subscription
  StreamSubscription<Position>? _positionSub;

  // Fallback location (Ahmedabad)
  final LatLng _fallbackCenter = const LatLng(23.0225, 72.5714);

>>>>>>> 9f1ec7bd36fd8e6d890f71bd07a90eb9793cf710
  @override
  void initState() {
    super.initState();
    _mapController = MapController();
<<<<<<< HEAD
    _getCurrentLocation();
    _fetchPedestrians();
  }

  // 🛰️ Get user's current live location
  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enable location services.")),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Location permission denied.")),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permissions permanently denied.")),
        );
      }
      return;
    }

    // Listen for position changes
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((Position position) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
      // Ensure the map has been rendered before moving the camera.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(_currentLocation!, 17);
        } catch (e) {
          // If MapController isn't ready yet, ignore and it will be moved when the map renders or next position update
          // ignore: avoid_print
          debugPrint('MapController move skipped (not ready yet): $e');
=======

    // Ask permission + start live GPS as soon as this screen runs
    _initLocation();

    // Fetch pedestrians from backend
    _fetchPedestrians();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  // Full location init: permission + initial position + live stream
  Future<void> _initLocation() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    // Get initial position once (so we can center quickly)
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = LatLng(pos.latitude, pos.longitude);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(_currentLocation!, 17);
      });
    } catch (e) {
      debugPrint('Error getting initial position: $e');
    }

    // Start live GPS stream (real-time updates)
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0, // update on every movement (for testing)
      ),
    ).listen((Position position) {
      debugPrint(
          'New live position: ${position.latitude}, ${position.longitude}');

      final newLoc = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentLocation = newLoc;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(newLoc, 17);
        } catch (e) {
          debugPrint('MapController move skipped: $e');
>>>>>>> 9f1ec7bd36fd8e6d890f71bd07a90eb9793cf710
        }
      });
    });
  }

<<<<<<< HEAD
  // 🌐 Fetch pedestrian data from API
  Future<void> _fetchPedestrians() async {
    try {
      final data = await _apiService.fetchPedestrians();
      setState(() {
        _pedestrianLocations = data
            .map((p) => LatLng(p['lat'], p['lon']))
            .toList();
      });
    } catch (e) {
      // ignore: avoid_print
      debugPrint('Error fetching pedestrians: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to fetch pedestrian data")),
        );
      }
    }
  }

=======
  // Handle location permission + service
  Future<bool> _handleLocationPermission() async {
    // 1) Check if location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showMsg("Please enable location services (GPS).");
      return false;
    }

    // 2) Check existing permission
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      // Ask the user when app/screen runs
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showMsg("Location permission denied.");
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showMsg(
        "Location permission permanently denied. "
        "Please enable it from Settings.",
      );
      return false;
    }

    // Granted (while in use / always)
    return true;
  }

  // Fetch pedestrian data from API
  Future<void> _fetchPedestrians() async {
    try {
      final List<Pedestrian> data = await _apiService.fetchPedestrians();

      setState(() {
        _pedestrianLocations = data
            .map<LatLng>((p) => LatLng(p.lat, p.lon))
            .toList();
      });
    } catch (e) {
      debugPrint('Error fetching pedestrians: $e');
      _showMsg("Failed to fetch pedestrian data");
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

>>>>>>> 9f1ec7bd36fd8e6d890f71bd07a90eb9793cf710
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("V2X Pedestrian Alert System"),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
<<<<<<< HEAD
            onPressed: _fetchPedestrians, // manually refresh pedestrian data
          ),
        ],
      ),
      body: _currentLocation == null
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation!,
                initialZoom: 17,
              ),
              children: [
                // Base map layer
                TileLayer(
                  urlTemplate:
                      "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                  subdomains: ['a', 'b', 'c'],
                ),

                // Vehicle and pedestrian markers
                MarkerLayer(
                  markers: [
                    // Your vehicle marker (blue car)
                    Marker(
                      width: 60,
                      height: 60,
                      point: _currentLocation!,
                      child: const Icon(
                        Icons.directions_car,
                        color: Colors.blue,
                        size: 40,
                      ),
                    ),

                    // Pedestrian markers (red pins)
                    ..._pedestrianLocations.map(
                      (p) => Marker(
                        width: 40,
                        height: 40,
                        point: p,
                        child: const Icon(
                          Icons.person_pin_circle,
                          color: Colors.red,
                          size: 35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
=======
            onPressed: _fetchPedestrians,
          ),
        ],
      ),

      // Map always shows; uses fallback until GPS lock is ready
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentLocation ?? _fallbackCenter,
          initialZoom: 17,
        ),
        children: [
          // Base map layer (OpenStreetMap)
          TileLayer(
            urlTemplate:
                "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            subdomains: ['a', 'b', 'c'],
          ),

          // Markers layer: car (live GPS) + pedestrians
          MarkerLayer(
            markers: [
              // Car marker (only when GPS exists)
              if (_currentLocation != null)
                Marker(
                  width: 60,
                  height: 60,
                  point: _currentLocation!,
                  child: const Icon(
                    Icons.directions_car,
                    color: Colors.blue,
                    size: 40,
                  ),
                ),

              // Pedestrian markers (from API)
              ..._pedestrianLocations.map(
                (p) => Marker(
                  width: 40,
                  height: 40,
                  point: p,
                  child: const Icon(
                    Icons.person_pin_circle,
                    color: Colors.red,
                    size: 35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
>>>>>>> 9f1ec7bd36fd8e6d890f71bd07a90eb9793cf710
    );
  }
}
