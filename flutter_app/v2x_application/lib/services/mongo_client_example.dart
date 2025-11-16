// Optional helper example: connect to MongoDB directly from Dart (for local
// dev/debugging). This file is NOT required for the app to run — the app
// communicates with a Flask backend by default. Use this for quick manual
// DB work or to prototype server endpoints in Dart.

import 'dart:io';
import 'package:flutter/foundation.dart';
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

// Simple CLI seeder. Run with a Mongo URI as the first argument or set MONGO_URI
// env var. Example:
//   dart run lib/services/mongo_client_example.dart mongodb://localhost:27017/v2x
// This will insert a few sample pedestrians with uid/timestamp/lat/lon.
Future<void> main(List<String> args) async {
  final uri = args.isNotEmpty ? args[0] : (Platform.environment['MONGO_URI'] ?? 'mongodb://localhost:27017/v2x');
  final example = MongoExample(uri: uri);
  try {
    await example.open();
final samples = [
  Pedestrian(uid: 'p_sample_1', lat: 51.5007, lon: -0.1246, timestamp: DateTime.now(), id: '', pedestriansCount: 0, rsuId: '', obuId: ''),
  Pedestrian(uid: 'p_sample_2', lat: 51.5010, lon: -0.1250, timestamp: DateTime.now().subtract(const Duration(minutes: 5)), id: '', pedestriansCount: 0, rsuId: '', obuId: ''),
  Pedestrian(uid: 'p_sample_3', lat: 51.4995, lon: -0.1240, timestamp: DateTime.now().subtract(const Duration(minutes: 10)), id: '', pedestriansCount: 0, rsuId: '', obuId: ''),
];

    for (final p in samples) {
      try {
        final pMap = p.toMap();
        final key = (pMap['uid'] ?? pMap['id']) as String?;
        if (key == null || key.isEmpty) {
          if (kDebugMode) {
            print('Skipping sample with missing id: $pMap');
          }
          continue;
        }

        final existing = await example.getById(key);
        if (existing == null) {
          final created = await example.create(p);
          final createdMap = created.toMap();
          final createdKey = (createdMap['uid'] ?? createdMap['id']) as String? ?? '';
          if (kDebugMode) {
            print('Inserted: $createdKey');
          }
        } else {
          final existingMap = existing.toMap();
          final existingKey = (existingMap['uid'] ?? existingMap['id']) as String? ?? '';
          if (kDebugMode) {
            print('Exists: $existingKey');
          }
        }
      } catch (e) {
        final pMap = p.toMap();
        final key = (pMap['uid'] ?? pMap['id']) as String? ?? '';
        if (kDebugMode) {
          print('Error seeding $key: $e');
        }
      }
    }
    await example.close();
  } catch (e) {
    if (kDebugMode) {
      print('Error: $e');
    }
    await example.close();
  }
}

