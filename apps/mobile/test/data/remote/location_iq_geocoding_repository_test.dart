import 'dart:convert';

import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/core/network/api_exceptions.dart';
import 'package:arangcada/data/remote/location_iq_geocoding_repository.dart';
import 'package:arangcada/data/repositories/geocoding_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  http.Response found(http.Request request) => http.Response(
    jsonEncode([
      {
        'place_id': '322167',
        'lat': '14.2046',
        'lon': '121.1553',
        'display_name': 'SM City Calamba, National Highway, Calamba, Laguna',
        'display_place': 'SM City Calamba',
        'display_address': 'National Highway, Calamba, Laguna',
      },
    ]),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  test(
    'a search is limited to Calamba and its results are marked as LocationIQ',
    () async {
      final requests = <http.Request>[];
      final repository = LocationIqGeocodingRepository(
        pins: _Pins(),
        key: 'test-key',
        minInterval: Duration.zero,
        client: MockClient((request) async {
          requests.add(request);
          return request.url.queryParameters['q'] == 'zzzz'
              ? http.Response('{"error":"Unable to geocode"}', 404)
              : found(request);
        }),
      );

      expect(await repository.search('sm'), isEmpty);
      expect(requests, isEmpty);

      final place = (await repository.search(' sm city ')).single;
      expect(place.id, 'locationiq:322167');
      expect(place.placeId, isNull);
      expect(place.name, 'SM City Calamba');
      expect(place.context, 'National Highway, Calamba, Laguna');
      expect(place.coordinate!.latitude, 14.2046);
      expect(place.coordinate!.longitude, 121.1553);
      expect(await repository.locate(place), place.coordinate);

      final sent = requests.single.url;
      expect(sent.host, 'api.locationiq.com');
      expect(sent.path, '/v1/autocomplete');
      expect(sent.queryParameters, {
        'key': 'test-key',
        'q': 'sm city',
        'countrycodes': 'ph',
        'viewbox': '121.00,14.28,121.24,14.12',
        'bounded': '1',
        'limit': '8',
        'dedupe': '1',
        'normalizecity': '1',
      });

      expect(await repository.search('zzzz'), isEmpty);
    },
  );

  test(
    'typing fast sends one request an interval, and only the last is shown',
    () async {
      final sentAt = <DateTime>[];
      const interval = Duration(milliseconds: 300);
      final repository = LocationIqGeocodingRepository(
        pins: _Pins(),
        key: 'test-key',
        minInterval: interval,
        client: MockClient((request) async {
          sentAt.add(DateTime.now());
          return found(request);
        }),
      );

      final results = await Future.wait([
        repository.search('sm c'),
        repository.search('sm ci'),
        repository.search('sm cit'),
      ]);

      expect(results.map((places) => places.length), [0, 0, 1]);
      expect(sentAt, hasLength(2));
      expect(
        sentAt[1].difference(sentAt[0]),
        greaterThanOrEqualTo(interval - const Duration(milliseconds: 20)),
      );
    },
  );

  test(
    'after a 429 nothing is sent for a while and no other provider is asked',
    () async {
      var calls = 0;
      final pins = _Pins();
      final repository = LocationIqGeocodingRepository(
        pins: pins,
        key: 'test-key',
        minInterval: Duration.zero,
        client: MockClient((request) async {
          calls++;
          return http.Response('{"error":"Rate Limited Minute"}', 429);
        }),
      );

      await expectLater(
        repository.search('sm city'),
        throwsA(isA<ApiRateLimitedException>()),
      );
      await expectLater(
        repository.search('rizal shrine'),
        throwsA(isA<ApiRateLimitedException>()),
      );
      expect(calls, 1);
      expect(pins.searches, 0);
    },
  );
}

class _Pins implements GeocodingRepository {
  int searches = 0;

  @override
  Future<List<GeocodedPlace>> search(String query) async {
    searches++;
    return const [];
  }

  @override
  Future<GeocodedPlace?> reverse(GeoCoordinate coordinate) async => null;

  @override
  Future<GeoCoordinate?> locate(GeocodedPlace place) async => place.coordinate;

  @override
  Future<GeocodedPlace?> refresh(String placeId) async => null;
}
