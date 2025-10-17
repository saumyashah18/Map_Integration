import 'dart:math';

/// Utility functions to compute distance and displacement between two WGS84
/// coordinates (latitude, longitude in degrees).
///
/// - distanceMeters: Haversine great-circle distance in meters.
/// - displacementMeters: returns a 2D vector [dx, dy] in meters where dx is
///   eastward displacement and dy is northward displacement (approx via
///   equirectangular projection; accurate for small distances).

const double _earthRadiusMeters = 6371000.0;

double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
	final phi1 = lat1 * pi / 180.0;
	final phi2 = lat2 * pi / 180.0;
	final dphi = (lat2 - lat1) * pi / 180.0;
	final dlambda = (lon2 - lon1) * pi / 180.0;

	final a = sin(dphi / 2) * sin(dphi / 2) +
			cos(phi1) * cos(phi2) * sin(dlambda / 2) * sin(dlambda / 2);
	final c = 2 * atan2(sqrt(a), sqrt(1 - a));
	return _earthRadiusMeters * c;
}

/// Returns [dx, dy] in meters where dx is eastward, dy is northward.
/// Uses equirectangular approximation — accurate for small distances (tens of km).
List<double> displacementMeters(double lat1, double lon1, double lat2, double lon2) {
	final latRad = (lat1 + lat2) / 2.0 * pi / 180.0;
	final dLat = (lat2 - lat1) * pi / 180.0;
	final dLon = (lon2 - lon1) * pi / 180.0;

	final dx = dLon * _earthRadiusMeters * cos(latRad); // east
	final dy = dLat * _earthRadiusMeters; // north
	return [dx, dy];
}

/// Euclidean length of displacement vector in meters
double displacementLength(double lat1, double lon1, double lat2, double lon2) {
	final d = displacementMeters(lat1, lon1, lat2, lon2);
	return sqrt(d[0] * d[0] + d[1] * d[1]);
}

/// Helper: whether great-circle distance <= r meters
bool withinDistance(double lat1, double lon1, double lat2, double lon2, double rMeters) {
	return distanceMeters(lat1, lon1, lat2, lon2) <= rMeters;
}

/// Helper: whether displacement (as great-circle distance) <= r meters
/// Note: displacement for filtering uses great-circle (Haversine) distance
/// rather than equirectangular approximation.
bool withinDisplacement(double lat1, double lon1, double lat2, double lon2, double rMeters) {
	return distanceMeters(lat1, lon1, lat2, lon2) <= rMeters;
}
