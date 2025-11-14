// Optional helper example: connect to MongoDB directly from Dart (for local
// dev/debugging). This file is NOT required for the app to run — the app
// communicates with a Flask backend by default. Use this for quick manual
// DB work or to prototype server endpoints in Dart.

import 'package:mongo_dart/mongo_dart.dart';
import '../models/RSU.dart';
import '../utils/distance_calculator.dart' as dc;

/// Example: connect using a MongoDB connection string
/// e.g. mongodb://user:pass@host:port/db
class MongoExample {
  final String uri;
  final String collectionName;

  MongoExample({required this.uri, this.collectionName = 'pedestrians'}) : _db = Db(uri);

  final Db _db;

  Future<void> open() async {
    if (!_db.isConnected) await _db.open();
  }

  Future<void> close() async {
    await _db.close();
  }

  DbCollection get coll => _db.collection(collectionName);

  Future<Pedestrian> create(Pedestrian p) async {
    final doc = p.toMap();
    final result = await coll.insertOne(doc);
    if (result.isSuccess) {
      // Mongo may add an _id field
      final added = Map<String, dynamic>.from(doc);
      added['_id'] = result.id ?? added['_id'];
      return Pedestrian.fromMap(added);
    }
    throw Exception('Insert failed');
  }

  Future<Pedestrian?> getById(String uid) async {
    final doc = await coll.findOne(where.eq('uid', uid));
    if (doc == null) return null;
    return Pedestrian.fromMap(Map<String, dynamic>.from(doc));
  }

  Future<bool> deleteById(String uid) async {
    final res = await coll.deleteOne({'uid': uid});
    return res.isSuccess;
  }

  Future<List<Pedestrian>> nearbyByDistance(double lat, double lon, double rMeters) async {
    // If collection has GeoJSON field, prefer $geoNear. Otherwise fall back to scanning.
    final docs = await coll.find().toList();
    final list = docs.map((d) => Pedestrian.fromMap(Map<String, dynamic>.from(d))).where((p) {
      return dc.withinDistance(lat, lon, p.lat, p.lon, rMeters);
    }).toList();
    return list;
  }

  Future<List<Pedestrian>> nearbyByDisplacement(double lat, double lon, double rMeters) async {
    final docs = await coll.find().toList();
    final list = docs.map((d) => Pedestrian.fromMap(Map<String, dynamic>.from(d))).where((p) {
      return dc.withinDisplacement(lat, lon, p.lat, p.lon, rMeters);
    }).toList();
    return list;
  }
}
