import 'dart:convert';

import 'package:hive/hive.dart';

import '../../core/geo/haversine.dart';
import '../../demo/demo_data.dart';

/// Device-local places, partitioned by authenticated account ID.
class SavedPlacesRepository {
  SavedPlacesRepository(this.box, this.accountId);

  final Box<String>? box;
  final String? accountId;
  String get _key => 'saved_places:$accountId';

  List<DemoPlace> get places {
    if (accountId == null) return const [];
    final value = box?.get(_key);
    if (value == null) return const [];
    return (jsonDecode(value) as List<dynamic>).map((entry) {
      final row = entry as Map<String, dynamic>;
      return DemoPlace(
        id: row['id'] as String,
        name: row['name'] as String,
        address: row['address'] as String,
        coordinate: GeoCoordinate(
          latitude: (row['latitude'] as num).toDouble(),
          longitude: (row['longitude'] as num).toDouble(),
        ),
      );
    }).toList();
  }

  Future<void> save(DemoPlace place) =>
      _write([...places.where((p) => p.id != place.id), place]);

  Future<void> remove(String id) =>
      _write(places.where((p) => p.id != id).toList());

  Future<void> _write(List<DemoPlace> places) async {
    final storage = box;
    if (accountId == null || storage == null) {
      throw StateError('Saved places storage is unavailable.');
    }
    await storage.put(
      _key,
      jsonEncode([
        for (final place in places)
          {
            'id': place.id,
            'name': place.name,
            'address': place.address,
            'latitude': place.coordinate.latitude,
            'longitude': place.coordinate.longitude,
          },
      ]),
    );
  }
}
