import 'package:flutter_test/flutter_test.dart';
import 'package:v2x_application/utils/distance_calculator.dart';

void main() {
  test('Haversine distance between same point is ~0', () {
    final d = distanceMeters(51.0, -0.1, 51.0, -0.1);
    expect(d, closeTo(0.0, 0.001));
  });

  test('Displacement vector and length are consistent with distance', () {
    final lat1 = 51.0, lon1 = -0.1;
    final lat2 = 51.0001, lon2 = -0.1001;
    final v = displacementMeters(lat1, lon1, lat2, lon2);
    final len = displacementLength(lat1, lon1, lat2, lon2);
    final dist = distanceMeters(lat1, lon1, lat2, lon2);
    // For small distances, displacement length should be close to haversine distance
    expect(len, closeTo(dist, 5.0));
    // dx/dy sanity
    expect(v.length, 2);
  });
}
