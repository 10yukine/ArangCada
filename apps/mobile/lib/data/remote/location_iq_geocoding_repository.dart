import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../core/geo/haversine.dart';
import '../../core/network/api_exceptions.dart';
import '../repositories/geocoding_repository.dart';

/// LocationIQ place search (autocomplete), in builds made for it: see
/// [AppConfig.isLocationIqConfigured]. Its coordinates are not Google's, so
/// they may be tested against the service area and stored.
///
/// The app does not hold the provider key. It sends the typed text to the
/// `place-search` Edge Function with the rider's session; the function adds
/// the key, the box around Calamba and a daily budget for each account.
///
/// The provider's free plan allows 2 requests a second, 60 a minute and 5,000
/// a day for everyone together, so:
///  * this device sends at most one request a second, and a query typed over
///    while it waits is dropped,
///  * queries shorter than [_minQueryLength] never reach the network,
///  * a 429 (the provider is busy, or this account has used its day's budget)
///    or a server-side failure stops requests for [_busyFor]. Search then
///    says it is busy and the rider can still pin the place on the map,
///  * nothing is cached.
///
/// No other provider answers for it, so a result is always LocationIQ's own
/// (id `locationiq:…`) and the search screen credits it as such. The caller
/// still tests each result against the service area. Pin labels stay with
/// [_pins].
class LocationIqGeocodingRepository implements GeocodingRepository {
  LocationIqGeocodingRepository({
    required this._pins,
    required this._accessToken,
    Uri? endpoint,
    this._anonKey = AppConfig.supabaseAnonKey,
    this._minInterval = const Duration(seconds: 1),
    http.Client? client,
  }) : _endpoint =
           endpoint ??
           Uri.parse('${AppConfig.supabaseUrl}/functions/v1/place-search'),
       _client = client ?? http.Client();

  final GeocodingRepository _pins;

  /// The signed-in rider's access token, read for each request so a refreshed
  /// session is picked up. Null when nobody is signed in.
  final String? Function() _accessToken;
  final Uri _endpoint;
  final String _anonKey;
  final Duration _minInterval;
  final http.Client _client;

  static const String idPrefix = 'locationiq:';
  static const int _minQueryLength = 3;
  static const int _maxQueryLength = 80;
  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _busyFor = Duration(minutes: 1);

  int _requestSeq = 0;
  DateTime _nextRequestAt = DateTime(0);
  DateTime _busyUntil = DateTime(0);

  void _checkAvailability() {
    if (DateTime.now().isBefore(_busyUntil)) {
      throw const ApiRateLimitedException('Place search is busy.');
    }
  }

  @override
  Future<List<GeocodedPlace>> search(String query) async {
    final trimmed = query.trim();
    final seq = ++_requestSeq;
    if (trimmed.length < _minQueryLength) return const [];
    _checkAvailability();

    final wait = _nextRequestAt.difference(DateTime.now());
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
      if (seq != _requestSeq) return const [];
    }
    // A previous request may have paused search while this query waited.
    _checkAvailability();

    final token = _accessToken();
    if (token == null) {
      throw const ApiUnauthorizedException('Sign in to search for a place.');
    }
    _nextRequestAt = DateTime.now().add(_minInterval);

    late http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: {
              'Authorization': 'Bearer $token',
              'apikey': _anonKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'q': trimmed.length > _maxQueryLength
                  ? trimmed.substring(0, _maxQueryLength)
                  : trimmed,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiNetworkException('Place search timed out.');
    } catch (_) {
      throw const ApiNetworkException();
    }

    // Limits apply even when a newer keystroke supersedes the result.
    if (response.statusCode == 429 || response.statusCode >= 500) {
      _busyUntil = DateTime.now().add(_busyFor);
    }
    // A newer keystroke already issued a request; this answer is stale.
    if (seq != _requestSeq) return const [];

    switch (response.statusCode) {
      case 200:
        return _parse(response.body);
      case 401 || 403:
        // The session, not the service: the next search uses the fresh token.
        throw const ApiUnauthorizedException('Place search is unavailable.');
      case 429 || >= 500:
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
