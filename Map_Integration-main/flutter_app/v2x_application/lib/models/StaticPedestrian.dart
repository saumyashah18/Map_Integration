import 'package:latlong2/latlong.dart';

/// Represents a static pedestrian on the road (not moving)
/// Positioned at a real road location
class StaticPedestrian {
  final String id;
  final LatLng roadLocation;
  bool isDetected;
  double? lastDetectionDistance;

  StaticPedestrian({
    required this.id,
    required this.roadLocation,
    this.isDetected = false,
    this.lastDetectionDistance,
  });

  @override
  String toString() =>
      'StaticPedestrian($id at ${roadLocation.latitude.toStringAsFixed(5)}, ${roadLocation.longitude.toStringAsFixed(5)})';
}