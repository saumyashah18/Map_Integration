// ignore: file_names
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';
import '../models/RSU.dart'; // for Pedestrian

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

  // Live GPS stream subscription
  StreamSubscription<Position>? _positionSub;

  // Fallback location (Ahmedabad)
  final LatLng _fallbackCenter = const LatLng(23.0225, 72.5714);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

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
        // ignore: deprecated_member_use
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
        }
      });
    });
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("V2X Pedestrian Alert System"),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPedestrians,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Set API base URL',
            onPressed: () async {
              final controller = TextEditingController(text: _apiService.baseUrl);
              final result = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('API Base URL'),
                  content: TextField(
                    controller: controller,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'https://<your-ngrok-id>.ngrok-free.app',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final candidate = controller.text.trim();
                        if (candidate.isEmpty) {
                          showDialog(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Invalid URL'),
                              content: const Text('Please enter a URL to test.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(c).pop(),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                          return;
                        }

                        final testUrl = candidate.endsWith('/')
                            ? '${candidate}get-pedestrians'
                            : '$candidate/get-pedestrians';

                        try {
                          final res = await http
                              .get(Uri.parse(testUrl))
                              .timeout(const Duration(seconds: 10));
                          final ct = res.headers['content-type'] ?? '';
                          final snippet = res.body.length > 400
                              ? res.body.substring(0, 400)
                              : res.body;
                          showDialog(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: Text('Test result: ${res.statusCode}'),
                              content: SingleChildScrollView(
                                child: Text('Content-Type: $ct\n\n$snippet'),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(c).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        } catch (e) {
                          showDialog(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Test failed'),
                              content: Text(e.toString()),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(c).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                      child: const Text('Test'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              );

              if (result != null && result.isNotEmpty) {
                _apiService.updateBaseUrl(result);
                _showMsg('Base URL updated');
                await _fetchPedestrians();
              }
            },
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
    );
  }
}
