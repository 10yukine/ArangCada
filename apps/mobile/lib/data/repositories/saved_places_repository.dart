import 'dart:convert';

import 'package:hive/hive.dart';

import '../../core/geo/haversine.dart';
import '../../demo/demo_data.dart';
import 'geocoding_repository.dart';

/// Device-local places, partitioned by authenticated account ID.
///
/// A Google place persists its ID and the rider's own words for it (what they
/// typed to find it), nothing of Google's. Its coordinate is resolved for the
/// current screen session and never written to disk.
class SavedPlacesRepository {
  SavedPlacesRepository(this.box, this.accountId);

  final Map<String, DemoPlace> _resolved = {};

  /// Remove legacy Google content for every account before the app starts.
  static Future<void> purgeGoogleContent(Box<String> box) async {
    for (final key in box.keys.toList()) {
      if (key is! String || !key.startsWith('saved_places:')) continue;
      final List<dynamic> rows;
      try {
        final decoded = jsonDecode(box.get(key)!);
        if (decoded is! List<dynamic> ||
            decoded.any((row) => row is! Map || row['id'] is! String)) {
          continue;
        }
        rows = decoded;
      } on FormatException {
        // Corrupt storage in another account must not block app startup.
        continue;
      }
      await box.put(
        key,
        jsonEncode([
          for (final row in rows)
            if ((row['id'] as String).startsWith('google:'))
              // 'label' is only ever the rider's own text; older builds wrote
              // Google's name under 'name', which is dropped here.
              {
                'id': row['id'],
                if (row['label'] is String) 'label': row['label'],
              }
            else
              row,
        ]),
      );
    }
  }

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

  List<DemoPlace> get places {
    _resolved.removeWhere(
      (_, place) => !place.googleCoordinateIsFresh(DateTime.now()),
    );
    return [
      for (final row in _rows)
        if ((row['id'] as String).startsWith('google:')) ...[
          ?_resolved[row['id']],
        ] else
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

  Future<void> save(DemoPlace place) async {
    if (!place.googleCoordinateIsFresh(DateTime.now())) {
      throw StateError('Choose that place again before saving.');
    }
    await _write([..._rows.where((row) => row['id'] != place.id), _row(place)]);
    if (place.id.startsWith('google:')) {
      _resolved[place.id] = DemoPlace(
        id: place.id,
        name: place.riderLabel('Saved place'),
        address: 'Calamba City',
        coordinate: place.coordinate,
        googleRetrievedAt: place.googleRetrievedAt,
        riderText: place.riderText,
      );
    }
  }

  Future<void> remove(String id) =>
      _write(_rows.where((row) => row['id'] != id).toList());

  /// Resolve persisted IDs when a saved-places screen opens.
  Future<bool> refreshStale(
    GeocodingRepository geocoding, {
    DateTime? now,
  }) async {
    final labels = {
      for (final row in _rows)
        if ((row['id'] as String).startsWith('google:'))
          row['id'] as String: row['label'] as String?,
    };
    final ids = labels.keys.toList();
    for (final id in ids) {
      if (_resolved[id]?.googleCoordinateIsFresh(now ?? DateTime.now()) ==
          true) {
        continue;
      }
      final fresh = await geocoding.refresh(id.substring('google:'.length));
      // Never resurrect an entry removed while the lookup was running.
      if (!_rows.any((row) => row['id'] == id)) continue;
      if (fresh?.coordinate case final coordinate?) {
        _resolved[id] = DemoPlace(
          id: id,
          name: labels[id] ?? fresh!.name,
          address: fresh!.context,
          coordinate: coordinate,
          googleRetrievedAt: now ?? DateTime.now(),
          riderText: labels[id],
        );
      } else {
        _resolved.remove(id);
      }
    }
    return ids.isNotEmpty;
  }

  static Map<String, dynamic> _row(DemoPlace place) =>
      place.id.startsWith('google:')
      ? {
          'id': place.id,
          if ((place.riderText ?? '').trim().isNotEmpty)
            'label': place.riderLabel(''),
        }
      : {
          'id': place.id,
          'name': place.name,
          'address': place.address,
          'latitude': place.coordinate.latitude,
          'longitude': place.coordinate.longitude,
        };

  Future<void> _write(List<Map<String, dynamic>> rows) async {
    final storage = box;
    if (accountId == null || storage == null) {
      throw StateError('Saved places storage is unavailable.');
    }
    await storage.put(_key, jsonEncode(rows));
  }
}
