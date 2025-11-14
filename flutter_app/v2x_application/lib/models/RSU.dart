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
			'Ruid': uid,
			'Guid': uid,
			'lat': lat,
			'lon': lon,
			'timestamp': timestamp.toIso8601String(),
		};
	}
}
