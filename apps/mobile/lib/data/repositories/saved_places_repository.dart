import 'dart:convert';

import 'package:hive/hive.dart';

import '../../core/geo/haversine.dart';
import '../../demo/demo_data.dart';
import 'geocoding_repository.dart';

/// Device-local places, partitioned by authenticated account ID.
///
/// Places chosen from Google (id `google:<placeId>`) follow Google's terms:
/// the place ID may be kept, but the name and coordinate only for
/// [googleRetention]. Older ones are hidden until [refreshStale] fetches them
/// again, and stripped to the bare ID when it cannot.
class SavedPlacesRepository {
  SavedPlacesRepository(this.box, this.accountId);

  static const Duration googleRetention = Duration(days: 30);

  final Box<String>? box;
  final String? accountId;
  String get _key => 'saved_places:$accountId';

  List<Map<String, dynamic>> get _rows {
    if (accountId == null) return const [];
    final value = box?.get(_key);
    if (value == null) return const [];
    return [
      for (final entry in jsonDecode(value) as List<dynamic>)
        entry as Map<String, dynamic>,
    ];
  }

  static bool _stale(Map<String, dynamic> row, DateTime now) {
    if (!(row['id'] as String).startsWith('google:')) return false;
    if (row['latitude'] == null) return true;
    final savedAt = DateTime.tryParse(row['savedAt'] as String? ?? '');
    return savedAt == null || now.difference(savedAt) >= googleRetention;
  }

  List<DemoPlace> get places {
    final now = DateTime.now();
    return [
      for (final row in _rows)
        if (!_stale(row, now))
          DemoPlace(
            id: row['id'] as String,
            name: row['name'] as String,
            address: row['address'] as String,
            coordinate: GeoCoordinate(
              latitude: (row['latitude'] as num).toDouble(),
              longitude: (row['longitude'] as num).toDouble(),
            ),
          ),
    ];
  }

  Future<void> save(DemoPlace place) => _write([
    ..._rows.where((row) => row['id'] != place.id),
    _row(place, DateTime.now()),
  ]);

  Future<void> remove(String id) =>
      _write(_rows.where((row) => row['id'] != id).toList());

  /// Re-fetches Google places older than [googleRetention]. Returns true when
  /// anything changed, so the caller can rebuild.
  Future<bool> refreshStale(
    GeocodingRepository geocoding, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final rows = _rows;
    if (!rows.any((row) => _stale(row, at))) return false;
    var changed = false;
    final refreshed = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      if (!_stale(row, at)) continue;
      final id = row['id'] as String;
      final fresh = await geocoding.refresh(id.substring('google:'.length));
      final coordinate = fresh?.coordinate;
      if (fresh != null && coordinate != null) {
        refreshed[id] = _row(
          DemoPlace(
            id: id,
            name: fresh.name,
            address: fresh.context,
            coordinate: coordinate,
          ),
          at,
        );
        changed = true;
      } else {
        refreshed[id] = {'id': id};
        changed = changed || row.length > 1;
      }
    }
    // The lookups above can take seconds. Write onto what is stored now, not
    // onto the list read before them, so a place saved or removed meanwhile is
    // neither lost nor brought back.
    if (changed) {
      await _write([for (final row in _rows) refreshed[row['id']] ?? row]);
    }
    return changed;
  }

  static Map<String, dynamic> _row(DemoPlace place, DateTime savedAt) => {
    'id': place.id,
    'name': place.name,
    'address': place.address,
    'latitude': place.coordinate.latitude,
    'longitude': place.coordinate.longitude,
    'savedAt': savedAt.toIso8601String(),
  };

  Future<void> _write(List<Map<String, dynamic>> rows) async {
    final storage = box;
    if (accountId == null || storage == null) {
      throw StateError('Saved places storage is unavailable.');
    }
    await storage.put(_key, jsonEncode(rows));
  }
}
