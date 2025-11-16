// lib/models/RSU.dart
// Model for a V2X-style pedestrian alert from the RSU backend.

class Pedestrian {
  final String id;              // unique alert id
  final int pedestriansCount;
  final double lat;
  final double lon;
  final DateTime timestamp;
  final String rsuId;
  final String obuId;

  Pedestrian({
    required this.id,
    required this.pedestriansCount,
    required this.lat,
    required this.lon,
    required this.timestamp,
    required this.rsuId,
    required this.obuId,
  });

  factory Pedestrian.fromMap(Map<String, dynamic> m) {
    // timestamp may be string or epoch
    final rawTs = m['timestamp'];
    DateTime ts;
    if (rawTs == null) {
      ts = DateTime.now();
    } else if (rawTs is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(rawTs);
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    final loc = m['location'] ?? {};
    final rawLat = loc['latitude'];
    final rawLon = loc['longitude'];

    return Pedestrian(
      id: (m['id'] ?? '').toString(),
      pedestriansCount: (m['pedestrians_count'] ?? 0) is int
          ? m['pedestrians_count'] as int
          : int.tryParse(m['pedestrians_count'].toString()) ?? 0,
      lat: rawLat is num ? rawLat.toDouble() : double.parse(rawLat.toString()),
      lon: rawLon is num ? rawLon.toDouble() : double.parse(rawLon.toString()),
      timestamp: ts,
      rsuId: (m['rsuid'] ?? '').toString(),
      obuId: (m['obuid'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pedestrians_count': pedestriansCount,
      'timestamp': timestamp.toIso8601String(),
      'location': {
        'latitude': lat,
        'longitude': lon,
      },
      'rsuid': rsuId,
      'obuid': obuId,
    };
  }
}
