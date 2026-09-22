import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/ors_config.dart';
import '../../core/geo/haversine.dart';
import '../../core/network/api_exceptions.dart';
import '../repositories/routing_repository.dart';

/// openrouteservice Directions client.
///
/// HeiGIT provides this project's Collaborative plan for NON-COMMERCIAL
/// academic use and explicitly asked that unnecessary requests not be sent.
/// That constraint shapes this class, so read before changing it:
///
///  * One request per materially-changed origin/destination pair. Endpoints
///    that move less than [_significantMoveMeters] reuse the cached route.
///  * At most one in-flight request; concurrent callers await the same future.
///  * Results are cached by rounded coordinate key for [_cacheTtl].
///  * HTTP 429 (per-minute limit) starts a cooldown. No retry loop.
///  * HTTP 403 (authorization invalid or daily allowance spent) disables
///    further automatic requests for the rest of the session.
///  * Every failure returns an unavailable route without inventing road
///    geometry, so booking is never blocked by the routing service being down.
///
/// It must never be called from `build()`, from a map pan handler, or on a
/// timer. And its distance/duration must never reach the fare calculator.
class OpenRouteServiceRoutingRepository implements RoutingRepository {
  OpenRouteServiceRoutingRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 12);
  static const Duration _cacheTtl = Duration(minutes: 30);

  /// Below this, an endpoint change is GPS jitter, not a new route.
  static const double _significantMoveMeters = 40;

  /// Cached against the *requested* endpoints, not the returned geometry.
  /// ORS snaps geometry to the road network, so comparing a new request to a
  /// snapped endpoint can read a sub-40m move as a material change.
  final Map<String, _CachedRoute> _cache = {};

  /// Bounds the session cache. Without this the map grows for the whole app
  /// session and every miss scans more dead entries.
  static const int _maxCacheEntries = 40;
  Future<RouteResult>? _inFlight;
  String? _inFlightKey;

  DateTime? _rateLimitedUntil;
  bool _quotaExhausted = false;

  @override
  String get attribution =>
      'Routing: openrouteservice · © OpenStreetMap contributors';

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

    if (OrsConfig.apiKey.isEmpty || _suspended) {
      return Future.value(_unavailableRoute());
    }

    final key = _key(from, to);
    // Collapse concurrent identical requests instead of racing the API.
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
            // Do not keep hammering an endpoint that has refused us.
            _quotaExhausted = true;
          }
          debugPrint(
            'ORS route unavailable (${error.runtimeType}); '
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
      '${OrsConfig.baseUrl}/v2/directions/${OrsConfig.profile}/geojson',
    );

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              // Key travels in the header only. Never in a query string,
              // which would land in provider access logs and crash reports.
              'Authorization': OrsConfig.apiKey,
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/geo+json',
            },
            // Only the two coordinates required for this lookup are sent --
            // no names, ride ids, or user identifiers (SECURITY.md).
            body: jsonEncode({
              'coordinates': [
                [from.longitude, from.latitude],
                [to.longitude, to.latitude],
              ],
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiNetworkException('Routing timed out.');
    } catch (_) {
      // Deliberately not interpolating the error: it can echo the request,
      // including the Authorization header, into logs.
      throw const ApiNetworkException();
    }

    switch (response.statusCode) {
      case 200:
        return _parse(response.body);
      case 401:
        throw const ApiUnauthorizedException();
      case 403:
        throw const ApiQuotaException();
      case 429:
        throw const ApiRateLimitedException();
      default:
        throw const ApiUnexpectedException('Route unavailable.');
    }
  }

  RouteResult _parse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>;
      if (features.isEmpty) return _unavailableRoute();
      final feature = features.first as Map<String, dynamic>;

      final coords =
          (feature['geometry'] as Map<String, dynamic>)['coordinates']
              as List<dynamic>;
      final geometry = <GeoCoordinate>[
        for (final point in coords)
          // GeoJSON numbers decode as int when integral; `as double` would
          // throw and silently discard a valid road route.
          GeoCoordinate(
            longitude: ((point as List<dynamic>)[0] as num).toDouble(),
            latitude: (point[1] as num).toDouble(),
          ),
      ];
      if (geometry.length < 2) return _unavailableRoute();

      final summary =
          ((feature['properties'] as Map<String, dynamic>)['summary']
              as Map<String, dynamic>?) ??
          const {};

      return RouteResult(
        geometry: geometry,
        distanceMeters: (summary['distance'] as num?)?.toDouble() ?? 0,
        durationSeconds: (summary['duration'] as num?)?.toDouble() ?? 0,
        isFallback: false,
        retrievedAt: DateTime.now(),
      );
    } catch (_) {
      return _unavailableRoute();
    }
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
