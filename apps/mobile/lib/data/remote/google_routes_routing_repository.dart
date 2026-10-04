import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../config/google_routes_config.dart';
import '../../core/geo/haversine.dart';
import '../../core/network/api_exceptions.dart';
import '../repositories/routing_repository.dart';

/// Google Routes API (v2) client.
///
/// Same operational discipline as `OpenRouteServiceRoutingRepository`, and
/// for the same reason -- routing calls cost real money per request:
///
///  * One request per materially-changed origin/destination pair. Endpoints
///    that move less than [_significantMoveMeters] reuse the cached route.
///  * At most one in-flight request; concurrent callers await the same future.
///  * Results are cached by rounded coordinate key for [_cacheTtl].
///  * HTTP 429 starts a cooldown. No retry loop.
///  * HTTP 403/401 (bad key, API not enabled, billing not active) disables
///    further automatic requests for the rest of the session.
///  * Every failure returns an unavailable route without inventing road
///    geometry, so booking is never blocked by the routing service being down.
///
/// Only the route's line is requested and kept; its distance and duration
/// are not, so they are always 0 here.
class GoogleRoutesRoutingRepository implements RoutingRepository {
  GoogleRoutesRoutingRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 12);
  static const Duration _cacheTtl = Duration(minutes: 30);
  static const double _significantMoveMeters = 40;
  static const int _maxCacheEntries = 40;

  final Map<String, _CachedRoute> _cache = {};
  Future<RouteResult>? _inFlight;
  String? _inFlightKey;

  DateTime? _rateLimitedUntil;
  bool _quotaExhausted = false;

  @override
  String get attribution => 'Routing: Google Routes API';

  static String _key(GeoCoordinate from, GeoCoordinate to) {
    String r(double v) => v.toStringAsFixed(4); // ~11 m grid
    return '${r(from.latitude)},${r(from.longitude)}'
        '->${r(to.latitude)},${r(to.longitude)}';
  }

  RouteResult? _reusable(GeoCoordinate from, GeoCoordinate to) {
    final now = DateTime.now();
    _cache.removeWhere(
      (_, entry) => now.difference(entry.result.retrievedAt) >= _cacheTtl,
    );

    final exact = _cache[_key(from, to)];
    if (exact != null) return exact.result;

    for (final entry in _cache.values) {
      if (haversineDistanceMeters(entry.from, from) < _significantMoveMeters &&
          haversineDistanceMeters(entry.to, to) < _significantMoveMeters) {
        return entry.result;
      }
    }
    return null;
  }

  void _store(
    String key,
    GeoCoordinate from,
    GeoCoordinate to,
    RouteResult result,
  ) {
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CachedRoute(from: from, to: to, result: result);
  }

  bool get _suspended {
    if (_quotaExhausted) return true;
    final until = _rateLimitedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  @override
  Future<RouteResult> route({
    required GeoCoordinate from,
    required GeoCoordinate to,
  }) {
    final cached = _reusable(from, to);
    if (cached != null) return Future.value(cached);

    if (!GoogleRoutesConfig.isConfigured || _suspended) {
      return Future.value(_unavailableRoute());
    }

    final key = _key(from, to);
    if (_inFlight != null && _inFlightKey == key) return _inFlight!;
    if (_inFlight != null) {
      // Recheck cache and quota after the current request completes.
      return _inFlight!.then((_) => route(from: from, to: to));
    }

    _inFlightKey = key;
    final future = _request(from, to)
        .then((result) {
          _store(key, from, to, result);
          return result;
        })
        .catchError((Object error) {
          if (error is ApiRateLimitedException) {
            _rateLimitedUntil = DateTime.now().add(error.cooldown);
          } else if (error is ApiQuotaException ||
              error is ApiUnauthorizedException) {
            _quotaExhausted = true;
          }
          debugPrint(
            'Google Routes unavailable (${error.runtimeType}); '
            'no road geometry available.',
          );
          return _unavailableRoute();
        })
        .whenComplete(() {
          _inFlight = null;
          _inFlightKey = null;
        });

    _inFlight = future;
    return future;
  }

  Future<RouteResult> _request(GeoCoordinate from, GeoCoordinate to) async {
    final uri = Uri.parse(
      '${GoogleRoutesConfig.baseUrl}/directions/v2:computeRoutes',
    );

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              // Key and field mask travel as headers only, never in a query
              // string, which would land in provider access logs.
              'X-Goog-Api-Key': GoogleRoutesConfig.apiKey,
              'X-Goog-FieldMask': GoogleRoutesConfig.fieldMask,
              'Content-Type': 'application/json',
              ...AppConfig.googleAppIdentityHeaders,
            },
            // Only the two coordinates required for this lookup are sent --
            // no names, ride ids, or user identifiers (SECURITY.md).
            body: jsonEncode({
              'origin': {
                'location': {
                  'latLng': {
                    'latitude': from.latitude,
                    'longitude': from.longitude,
                  },
                },
              },
              'destination': {
                'location': {
                  'latLng': {
                    'latitude': to.latitude,
                    'longitude': to.longitude,
                  },
                },
              },
              'travelMode': GoogleRoutesConfig.travelMode,
              // Tricycles cannot use SLEX/CALAX. Avoiding tolls is not a
              // billing trigger, so this stays on Routes Essentials.
              'routeModifiers': {'avoidTolls': true},
              'polylineQuality': 'OVERVIEW',
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiNetworkException('Routing timed out.');
    } catch (_) {
      // Deliberately not interpolating the error: it can echo the request,
      // including the API key header, into logs.
      throw const ApiNetworkException();
    }

    switch (response.statusCode) {
      case 200:
        return _parse(response.body);
      case 401:
      case 403:
        // Google returns 403 for an invalid/unrestricted-wrong key, an API
        // not enabled on the project, or billing not active -- all equally
        // "stop asking for the rest of this session".
        throw const ApiUnauthorizedException();
      case 429:
        throw const ApiRateLimitedException();
      default:
        throw const ApiUnexpectedException('Route unavailable.');
    }
  }

  RouteResult _parse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final routes = json['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return _unavailableRoute();
      final route = routes.first as Map<String, dynamic>;

      final encoded =
          (route['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
              as String?;
      final geometry = encoded == null
          ? const <GeoCoordinate>[]
          : _decodePolyline(encoded);
      if (geometry.length < 2) return _unavailableRoute();

      // Only the line is requested (GoogleRoutesConfig.fieldMask).
      return RouteResult(
        geometry: geometry,
        distanceMeters: 0,
        durationSeconds: 0,
        isFallback: false,
        retrievedAt: DateTime.now(),
      );
    } catch (_) {
      return _unavailableRoute();
    }
  }

  /// Decodes Google's encoded polyline algorithm format (precision 5),
  /// the same format used across the Directions/Routes/Roads APIs.
  /// https://developers.google.com/maps/documentation/utilities/polylinealgorithm
  static List<GeoCoordinate> _decodePolyline(String encoded) {
    final points = <GeoCoordinate>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += deltaLat;

      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += deltaLng;

      points.add(GeoCoordinate(latitude: lat / 1e5, longitude: lng / 1e5));
    }
    return points;
  }

  /// Keeps booking available without presenting invented roads as a route.
  RouteResult _unavailableRoute() {
    return RouteResult(
      geometry: const [],
      distanceMeters: 0,
      durationSeconds: 0,
      isFallback: true,
      retrievedAt: DateTime.now(),
    );
  }

  void dispose() => _client.close();
}

class _CachedRoute {
  const _CachedRoute({
    required this.from,
    required this.to,
    required this.result,
  });

  final GeoCoordinate from;
  final GeoCoordinate to;
  final RouteResult result;
}
