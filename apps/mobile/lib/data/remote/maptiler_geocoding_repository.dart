import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../core/geo/haversine.dart';
import '../../core/network/api_exceptions.dart';
import '../repositories/geocoding_repository.dart';

/// MapTiler forward/reverse geocoding.
///
/// Request discipline (the search box fires on every keystroke otherwise):
///  * callers debounce; this class additionally drops responses belonging to
///    a superseded query via a monotonic request counter,
///  * queries shorter than [_minQueryLength] never reach the network,
///  * results are biased to Calamba with a proximity hint and a bounding box,
///  * identical queries are served from a small in-memory cache.
///
/// SECURITY.md: only the query string and coordinates are sent. The key is a
/// client-restricted MapTiler credential supplied at compile time.
class MapTilerGeocodingRepository implements GeocodingRepository {
  MapTilerGeocodingRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const int _minQueryLength = 3;
  static const Duration _timeout = Duration(seconds: 10);

  /// Calamba City centre, used as the proximity hint.
  static const GeoCoordinate _calamba = GeoCoordinate(
    latitude: 14.2117,
    longitude: 121.1653,
  );

  /// Calamba and its immediate neighbours (Los Banos, Cabuyao, Sto Tomas).
  ///
  /// MapTiler treats bbox as a hard filter and proximity only as a soft bias,
  /// so this has to be tight. An earlier, wider box spanning Laguna let
  /// Dasmarinas in Cavite (120.94 E) dominate a search for "Robinsons".
  static const String _bbox = '121.00,14.10,121.35,14.35';

  final Map<String, List<GeocodedPlace>> _cache = {};
  int _requestSeq = 0;

  @override
  Future<List<GeocodedPlace>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < _minQueryLength) return const [];
    if (!AppConfig.isMapTilerConfigured) {
      throw const ApiNotConfiguredException('Place search is not configured.');
    }

    final cacheKey = trimmed.toLowerCase();
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final seq = ++_requestSeq;

    final uri = Uri.parse(
      'https://api.maptiler.com/geocoding/${Uri.encodeComponent(trimmed)}.json',
    ).replace(
      queryParameters: {
        'key': AppConfig.mapTilerKey,
        'proximity': '${_calamba.longitude},${_calamba.latitude}',
        'bbox': _bbox,
        'country': 'ph',
        'limit': '8',
      },
    );

    late http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const ApiNetworkException('Place search timed out.');
    } catch (_) {
      throw const ApiNetworkException();
    }

    // A newer keystroke already issued a request; this answer is stale.
    if (seq != _requestSeq) return const [];

    switch (response.statusCode) {
      case 200:
        final places = _parse(response.body);
        _cache[cacheKey] = places;
        return places;
      case 401:
        throw const ApiUnauthorizedException('Place search is unavailable.');
      case 403:
        throw const ApiQuotaException('Place search is unavailable.');
      case 429:
        throw const ApiRateLimitedException('Place search is busy.');
      default:
        throw const ApiUnexpectedException('Place search failed.');
    }
  }

  @override
  Future<GeocodedPlace?> reverse(GeoCoordinate coordinate) async {
    if (!AppConfig.isMapTilerConfigured) return null;
    final uri =
        Uri.parse(
          'https://api.maptiler.com/geocoding/'
          '${coordinate.longitude},${coordinate.latitude}.json',
        ).replace(
          queryParameters: {'key': AppConfig.mapTilerKey, 'limit': '1'},
        );

    try {
      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final places = _parse(response.body);
      return places.isEmpty ? null : places.first;
    } catch (_) {
      // Reverse geocoding is a nicety. Never block pin selection on it.
      return null;
    }
  }

  List<GeocodedPlace> _parse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>? ?? const [];
      final seen = <String>{};
      final results = <GeocodedPlace>[];

      for (final raw in features) {
        final feature = raw as Map<String, dynamic>;
        final center = feature['center'] as List<dynamic>?;
        if (center == null || center.length < 2) continue;

        final name =
            (feature['text'] as String?) ??
            (feature['place_name'] as String?) ??
            'Unknown place';

        final placeName = (feature['place_name'] as String?) ?? name;
        // "SM City Calamba, Real, Calamba, Laguna" -> drop the leading name
        // so the row reads name over locality rather than repeating itself.
        var context = placeName;
        if (context.toLowerCase().startsWith(name.toLowerCase())) {
          context = context.substring(name.length);
        }
        context = context.replaceFirst(RegExp(r'^[,\s]+'), '');

        final key = '${name.toLowerCase()}|$context'.toLowerCase();
        if (!seen.add(key)) continue;

        results.add(
          GeocodedPlace(
            id: (feature['id'] as String?) ?? key,
            name: name,
            context: context.isEmpty ? 'Calamba City' : context,
            coordinate: GeoCoordinate(
              longitude: (center[0] as num).toDouble(),
              latitude: (center[1] as num).toDouble(),
            ),
          ),
        );
      }
      return results;
    } catch (_) {
      throw const ApiUnexpectedException('Place search returned bad data.');
    }
  }

  void dispose() => _client.close();
}
