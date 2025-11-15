import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';

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

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _getCurrentLocation();
    _fetchPedestrians();
  }

  // 🛰️ Get user's current live location
Future<void> _getCurrentLocation() async {
  bool serviceEnabled;
  LocationPermission permission;

  // 1) Check if location services are enabled
  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enable location services.")),
      );
    }
    return;
  }

  // 2) Check permission
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
        const SnackBar(
          content: Text("Location permissions permanently denied."),
        ),
      );
    }
    return;
  }

  // 3) Get an initial position immediately
  try {
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentLocation = LatLng(pos.latitude, pos.longitude);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(_currentLocation!, 17);
      } catch (e) {
        debugPrint('Initial map move failed: $e');
      }
    });
  } catch (e) {
    debugPrint('Error getting initial position: $e');
  }

    // Listen for position changes
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best, // as precise as possible
      distanceFilter: 0,               // update on every tiny move (for testing)
    ),
  ).listen((Position position) {
    debugPrint(
        'New live position: ${position.latitude}, ${position.longitude}');

    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(_currentLocation!, 17);
      } catch (e) {
        debugPrint('MapController move skipped (not ready yet): $e');
      }
    });
  });
}

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("V2X Pedestrian Alert System"),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
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
    );
  }
}
