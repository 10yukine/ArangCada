import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../core/geo/haversine.dart';
import '../../core/network/api_exceptions.dart';
import '../repositories/geocoding_repository.dart';

/// Google Places (New) search, falling back to [_fallback] (MapTiler).
///
/// Cost discipline:
///  * Every keystroke of one search shares a session token, and the session
///    ends with a single Place Details call asking only for `location`. Google
///    bills the first 12 Autocomplete requests plus the terminating Place
///    Details Essentials request; later Autocomplete requests in that session
///    have no charge. A token left unused for [_sessionLife]
///    is replaced, because Google stops honouring an old one.
///  * HTTP 429 (a Cloud Console quota cap reached) hands searches to the
///    fallback for [_cooldown]; 401/403 does so for the rest of the session.
///  * Pin labels (reverse lookups) always use the fallback: Google charges
///    for those and the pin already has its coordinate.
///
/// Terms: results carry `placeId`; the screen shows the "Google Maps" credit
/// beside them. Suggestions are not cached between searches.
class GooglePlacesGeocodingRepository implements GeocodingRepository {
  GooglePlacesGeocodingRepository({
    required this._fallback,
    http.Client? client,
    bool Function()? enabled,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _enabled = enabled ?? (() => true),
       _now = now ?? DateTime.now;

  final GeocodingRepository _fallback;
  final http.Client _client;

  /// False while the owner has switched Google search off (app_release).
  final bool Function() _enabled;
  final DateTime Function() _now;

  static const String _baseUrl = 'https://places.googleapis.com/v1';
  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _cooldown = Duration(minutes: 5);
  static const int _minQueryLength = 3;
  static const Duration _sessionLife = Duration(minutes: 3);

  /// Same Calamba box as the MapTiler search, as a hard restriction.
  static const Map<String, Object> _calamba = {
    'rectangle': {
      'low': {'latitude': 14.10, 'longitude': 121.00},
      'high': {'latitude': 14.35, 'longitude': 121.35},
    },
  };

  String? _session;
  DateTime? _sessionUsedAt;
  int _requestSeq = 0;
  DateTime? _suspendedUntil;
  bool _disabled = false;

  bool get _useGoogle {
    if (!AppConfig.isGooglePlacesConfigured || _disabled || !_enabled()) {
      return false;
    }
    final until = _suspendedUntil;
    return until == null || _now().isAfter(until);
  }

  /// The token for the search in progress; a new one when there is none or
  /// the last one has gone unused too long.
  String _sessionToken() {
    final usedAt = _sessionUsedAt;
    if (_session == null ||
        usedAt == null ||
        _now().difference(usedAt) >= _sessionLife) {
      _session = const Uuid().v4();
    }
    _sessionUsedAt = _now();
    return _session!;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-Goog-Api-Key': AppConfig.googlePlacesApiKey,
  };

  @override
  Future<List<GeocodedPlace>> search(String query) async {
    final trimmed = query.trim();
    final seq = ++_requestSeq;
    if (trimmed.length < _minQueryLength) return const [];
    if (!_useGoogle) return _fallback.search(query);

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/places:autocomplete'),
            headers: {
              ..._headers,
              'X-Goog-FieldMask':
                  'suggestions.placePrediction.placeId,'
                  'suggestions.placePrediction.structuredFormat',
            },
            body: jsonEncode({
              'input': trimmed,
              'sessionToken': _sessionToken(),
              'includedRegionCodes': ['ph'],
              'locationRestriction': _calamba,
            }),
          )
          .timeout(_timeout);
    } catch (_) {
      return _fallback.search(query);
    }

    // A newer keystroke already issued a request; this answer is stale.
    if (seq != _requestSeq) return const [];
    if (!_accept(response.statusCode)) return _fallback.search(query);

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final places = [
        for (final raw in json['suggestions'] as List<dynamic>? ?? const [])
          if ((raw as Map<String, dynamic>)['placePrediction']
              case final Map<String, dynamic> prediction)
            _suggestion(prediction),
      ];
      return places;
    } catch (_) {
      throw const ApiUnexpectedException('Place search returned bad data.');
    }
  }

  static GeocodedPlace _suggestion(Map<String, dynamic> prediction) {
    final format = prediction['structuredFormat'] as Map<String, dynamic>?;
    String text(String key) =>
        ((format?[key] as Map<String, dynamic>?)?['text'] as String?) ?? '';
    final placeId = prediction['placeId'] as String;
    final secondary = text('secondaryText');
    return GeocodedPlace(
      id: 'google:$placeId',
      placeId: placeId,
      name: text('mainText'),
      context: secondary.isEmpty ? 'Calamba City' : secondary,
      coordinate: null,
    );
  }

  @override
  Future<GeoCoordinate?> locate(GeocodedPlace place) async {
    final placeId = place.placeId;
    if (placeId == null) return place.coordinate;
    // A stale token is not sent; abandoned autocomplete requests remain billable.
    final usedAt = _sessionUsedAt;
    final session = usedAt != null && _now().difference(usedAt) < _sessionLife
        ? _session
        : null;
    // The session ends here whether or not the lookup succeeds.
    _session = null;
    final json = await _details(placeId, 'location', session: session);
    return json == null ? null : _coordinate(json);
  }

  @override
  Future<GeocodedPlace?> refresh(String placeId) async {
    final json = await _details(placeId, 'location');
    final coordinate = json == null ? null : _coordinate(json);
    if (coordinate == null) return null;
    // Labels come from the existing fallback, not a Pro-tier Google field.
    GeocodedPlace? label;
    try {
      label = await _fallback.reverse(coordinate);
    } catch (_) {
      // A label failure must not prevent resolving a saved coordinate.
    }
    return GeocodedPlace(
      id: 'google:$placeId',
      placeId: placeId,
      name: label?.name ?? 'Saved place',
      context: label?.context ?? 'Calamba City',
      coordinate: coordinate,
    );
  }

  Future<Map<String, dynamic>?> _details(
    String placeId,
    String fields, {
    String? session,
  }) async {
    if (!_useGoogle) return null;
    try {
      final response = await _client
          .get(
            Uri.parse(
              '$_baseUrl/places/${Uri.encodeComponent(placeId)}',
            ).replace(queryParameters: {'sessionToken': ?session}),
            headers: {..._headers, 'X-Goog-FieldMask': fields},
          )
          .timeout(_timeout);
      if (!_accept(response.statusCode)) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static GeoCoordinate? _coordinate(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>?;
    final lat = location?['latitude'] as num?;
    final lng = location?['longitude'] as num?;
    if (lat == null || lng == null) return null;
    return GeoCoordinate(latitude: lat.toDouble(), longitude: lng.toDouble());
  }

  /// True for 200. Otherwise records why Google should be skipped for now.
  bool _accept(int status) {
    switch (status) {
      case 200:
        return true;
      case 429:
        _suspendedUntil = _now().add(_cooldown);
      case 401 || 403:
        // Bad key, API not enabled or billing off: nothing will fix itself.
        _disabled = true;
    }
    return false;
  }

  @override
  Future<GeocodedPlace?> reverse(GeoCoordinate coordinate) =>
      _fallback.reverse(coordinate);

  void dispose() => _client.close();
}
