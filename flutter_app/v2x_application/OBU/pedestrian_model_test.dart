import 'package:flutter_test/flutter_test.dart';
import 'package:v2x_application/models/RSU.dart';

void main() {
  test('fromMap accepts id/_id/uid and parses timestamps', () {
    final nowIso = DateTime.now().toIso8601String();
    final nowEpoch = DateTime.now().millisecondsSinceEpoch;

    final m1 = {'id': 'p1', 'lat': 1.0, 'lon': 2.0, 'timestamp': nowIso};
    final p1 = Pedestrian.fromMap(m1);
    expect(p1.uid, 'p1');

    final m2 = {'_id': 'p2', 'lat': 1.1, 'lon': 2.1, 'timestamp': nowEpoch};
    final p2 = Pedestrian.fromMap(m2);
    expect(p2.uid, 'p2');

    final m3 = {'uid': 'p3', 'lat': '3.1', 'lon': '4.2'}; // no ts; fallback ok
    final p3 = Pedestrian.fromMap(m3);
    expect(p3.uid, 'p3');
    expect(p3.lat, closeTo(3.1, 0.0001));
  });
}
