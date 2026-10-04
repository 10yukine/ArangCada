import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../core/geo/haversine.dart';
import '../../core/network/api_exceptions.dart';
import '../repositories/geocoding_repository.dart';

/// LocationIQ place search (autocomplete), in builds made for it: see
/// [AppConfig.locationIqKey]. Its coordinates are not Google's, so they may
/// be tested against the service area and stored.
///
/// The free plan allows 2 requests a second, 60 a minute and 5,000 a day for
/// the whole key, so:
///  * this device sends at most one request a second, and a query typed over
///    while it waits is dropped,
///  * queries shorter than [_minQueryLength] never reach the network,
///  * a 429 stops requests for [_busyFor]. Search then says it is busy and the
///    rider can still pin the place on the map,
///  * nothing is cached.
///
/// No other provider answers for it, so a result is always LocationIQ's own
/// (id `locationiq:…`) and the search screen credits it as such. Results are
/// limited to a box around Calamba; the caller still tests each one against
/// the service area. Pin labels stay with [_pins].
class LocationIqGeocodingRepository implements GeocodingRepository {
  LocationIqGeocodingRepository({
    required this._pins,
    this._key = AppConfig.locationIqKey,
    this._minInterval = const Duration(seconds: 1),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final GeocodingRepository _pins;
  final String _key;
  final Duration _minInterval;
  final http.Client _client;

  static const String idPrefix = 'locationiq:';
  static const int _minQueryLength = 3;
  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _busyFor = Duration(minutes: 1);

  /// Two corners of a box around Calamba: lon,lat,lon,lat.
  static const String _viewbox = '121.00,14.28,121.24,14.12';

  int _requestSeq = 0;
  DateTime _nextRequestAt = DateTime(0);
  DateTime _busyUntil = DateTime(0);
  ApiException? _disabledFailure;

  void _checkAvailability() {
    if (_disabledFailure case final failure?) throw failure;
    if (DateTime.now().isBefore(_busyUntil)) {
      throw const ApiRateLimitedException('Place search is busy.');
    }
  }

  @override
  Future<List<GeocodedPlace>> search(String query) async {
    final trimmed = query.trim();
    final seq = ++_requestSeq;
    if (trimmed.length < _minQueryLength) return const [];
    if (_key.isEmpty) {
      throw const ApiNotConfiguredException('Place search is not configured.');
    }
    _checkAvailability();

    final wait = _nextRequestAt.difference(DateTime.now());
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
      if (seq != _requestSeq) return const [];
    }
    // A previous request may have disabled search while this query waited.
    _checkAvailability();
    _nextRequestAt = DateTime.now().add(_minInterval);

    final uri = Uri.https('api.locationiq.com', '/v1/autocomplete', {
      'key': _key,
      'q': trimmed,
      'countrycodes': 'ph',
      'viewbox': _viewbox,
      'bounded': '1',
      'limit': '8',
      'dedupe': '1',
      'normalizecity': '1',
    });

    late http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const ApiNetworkException('Place search timed out.');
    } catch (_) {
      throw const ApiNetworkException();
    }

    // Provider limits apply even when a newer keystroke supersedes the result.
    switch (response.statusCode) {
      case 401:
        _disabledFailure = const ApiUnauthorizedException(
          'Place search is unavailable.',
        );
      case 403:
        _disabledFailure = const ApiQuotaException(
          'Place search is unavailable.',
        );
      case 429:
        _busyUntil = DateTime.now().add(_busyFor);
    }
    // A newer keystroke already issued a request; this answer is stale.
    if (seq != _requestSeq) return const [];

    switch (response.statusCode) {
      case 200:
        return _parse(response.body);
      case 404:
        // LocationIQ's "nothing found".
        return const [];
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
  Future<GeocodedPlace?> reverse(GeoCoordinate coordinate) =>
      _pins.reverse(coordinate);

  @override
  Future<GeoCoordinate?> locate(GeocodedPlace place) async => place.coordinate;

  @override
  Future<GeocodedPlace?> refresh(String placeId) async => null;

  List<GeocodedPlace> _parse(String body) {
    try {
      final results = <GeocodedPlace>[];
      for (final raw in jsonDecode(body) as List<dynamic>) {
        final place = raw as Map<String, dynamic>;
        final latitude = double.tryParse('${place['lat']}');
        final longitude = double.tryParse('${place['lon']}');
        if (latitude == null || longitude == null) continue;
        final displayName = place['display_name'] as String? ?? 'Unknown place';
        results.add(
          GeocodedPlace(
            id: '$idPrefix${place['place_id']}',
            name:
                place['display_place'] as String? ??
                displayName.split(',').first,
            context: place['display_address'] as String? ?? 'Calamba City',
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
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
