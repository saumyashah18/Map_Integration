<<<<<<< HEAD
// Simple typed model for a pedestrian record used across the app.
// Fields: uid (String), lat (double), lon (double), timestamp (DateTime)

class Pedestrian {
	final String uid;
	final double lat;
	final double lon;
	final DateTime timestamp;

	Pedestrian({
		required this.uid,
		required this.lat,
		required this.lon,
		required this.timestamp,
	});

	factory Pedestrian.fromMap(Map<String, dynamic> m) {
		// Some backends use `id` or `uid` — accept both.
		final id = m['uid'] ?? m['id'] ?? m['_id'];
		// timestamp may be a String or int (epoch ms)
		DateTime ts;
		final rawTs = m['timestamp'] ?? m['time'] ?? m['ts'];
		if (rawTs == null) {
			ts = DateTime.now();
		} else if (rawTs is int) {
			ts = DateTime.fromMillisecondsSinceEpoch(rawTs);
		} else if (rawTs is String) {
			ts = DateTime.tryParse(rawTs) ?? DateTime.now();
		} else {
			ts = DateTime.now();
		}

		return Pedestrian(
			uid: id?.toString() ?? '',
			lat: (m['lat'] is num) ? (m['lat'] as num).toDouble() : double.parse(m['lat'].toString()),
			lon: (m['lon'] is num) ? (m['lon'] as num).toDouble() : double.parse(m['lon'].toString()),
			timestamp: ts,
		);
	}

	Map<String, dynamic> toMap() {
		return {
			'uid': uid,
			'lat': lat,
			'lon': lon,
			'timestamp': timestamp.toIso8601String(),
		};
	}
=======
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
>>>>>>> 9f1ec7bd36fd8e6d890f71bd07a90eb9793cf710
}
