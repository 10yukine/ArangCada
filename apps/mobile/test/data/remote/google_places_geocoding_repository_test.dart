import 'dart:convert';

import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/data/remote/google_places_geocoding_repository.dart';
import 'package:arangcada/data/repositories/geocoding_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Run with synthetic GOOGLE_PLACES_API_KEY and GOOGLE_MAPS_API_KEY defines.
void main() {
  const skip =
      String.fromEnvironment('GOOGLE_PLACES_API_KEY') == '' ||
      String.fromEnvironment('GOOGLE_MAPS_API_KEY') == '';

  test(
    'one search shares a session token that the location lookup ends',
    () async {
      final requests = <http.Request>[];
      final repository = GooglePlacesGeocodingRepository(
        fallback: _Fallback(),
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('places:autocomplete')) {
            return http.Response(
              jsonEncode({
                'suggestions': [
                  {
                    'placePrediction': {
                      'placeId': 'nu-l',
                      'structuredFormat': {
                        'mainText': {'text': 'National University Laguna'},
                        'secondaryText': {'text': 'Milagrosa, Calamba'},
                      },
                    },
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'location': {'latitude': 14.1778, 'longitude': 121.1363},
            }),
            200,
          );
        }),
      );
      addTearDown(repository.dispose);

      await repository.search('Nati');
      final results = await repository.search('National');
      expect(results.single.name, 'National University Laguna');
      expect(results.single.placeId, 'nu-l');
      expect(results.single.coordinate, isNull);

      final coordinate = await repository.locate(results.single);
      expect(coordinate!.latitude, 14.1778);

      String token(http.Request r) => jsonDecode(r.body)['sessionToken'];
      expect(token(requests[0]), token(requests[1]));
      final details = requests[2];
      expect(details.url.path, endsWith('/places/nu-l'));
      // Only the location: the cheapest Place Details tier.
      expect(details.headers['X-Goog-FieldMask'], 'location');
      expect(details.url.queryParameters['sessionToken'], token(requests[0]));

      // The next search starts a new session.
      await repository.search('SM City');
      expect(token(requests[3]), isNot(token(requests[0])));
    },
    skip: skip,
  );

  test(
    'a quota rejection hands search to the fallback without asking again',
    () async {
      var googleCalls = 0;
      final fallback = _Fallback();
      final repository = GooglePlacesGeocodingRepository(
        fallback: fallback,
        client: MockClient((_) async {
          googleCalls++;
          return http.Response(
            '{"error":{"status":"RESOURCE_EXHAUSTED"}}',
            429,
          );
        }),
      );
      addTearDown(repository.dispose);

      expect((await repository.search('NU Laguna')).single.name, 'MapTiler');
      expect((await repository.search('SM City')).single.name, 'MapTiler');
      expect(googleCalls, 1);
      expect(fallback.searches, 2);
    },
    skip: skip,
  );

  http.Response suggestions(http.Request request) =>
      request.url.path.endsWith('places:autocomplete')
      ? http.Response(
          jsonEncode({
            'suggestions': [
              {
                'placePrediction': {
                  'placeId': 'p1',
                  'structuredFormat': {
                    'mainText': {'text': 'Place'},
                  },
                },
              },
            ],
          }),
          200,
        )
      : http.Response(
          jsonEncode({
            'location': {'latitude': 14.2, 'longitude': 121.1},
          }),
          200,
        );

  test('suggested content is not cached between searches', () async {
    final requests = <http.Request>[];
    final repository = GooglePlacesGeocodingRepository(
      fallback: _Fallback(),
      client: MockClient((request) async {
        requests.add(request);
        return suggestions(request);
      }),
    );
    addTearDown(repository.dispose);

    await repository.search('SM City');
    final again = await repository.search('  sm city ');
    expect(again.single.placeId, 'p1');
    expect(requests, hasLength(2));
  }, skip: skip);

  test('saved place refresh requests only Essentials location', () async {
    final requests = <http.Request>[];
    final repository = GooglePlacesGeocodingRepository(
      fallback: _Fallback(),
      client: MockClient((request) async {
        requests.add(request);
        return suggestions(request);
      }),
    );
    addTearDown(repository.dispose);
    expect((await repository.refresh('p1'))!.coordinate, isNotNull);
    expect(requests.single.headers['X-Goog-FieldMask'], 'location');
  }, skip: skip);

  test('a token left unused for three minutes is replaced', () async {
    final requests = <http.Request>[];
    var clock = DateTime(2026, 10, 2, 12);
    final repository = GooglePlacesGeocodingRepository(
      fallback: _Fallback(),
      now: () => clock,
      client: MockClient((request) async {
        requests.add(request);
        return suggestions(request);
      }),
    );
    addTearDown(repository.dispose);
    String token(http.Request r) => jsonDecode(r.body)['sessionToken'];

    final first = await repository.search('Rizal');
    clock = clock.add(const Duration(minutes: 2));
    await repository.search('Rizal Shrine');
    expect(token(requests[1]), token(requests[0]));

    // The person walked away; the search screen was left without a choice.
    clock = clock.add(const Duration(minutes: 4));
    await repository.search('Crossing');
    expect(token(requests[2]), isNot(token(requests[0])));

    // A choice made long after the last keystroke carries no stale token.
    clock = clock.add(const Duration(minutes: 4));
    await repository.locate(first.single);
    expect(
      requests[3].url.queryParameters.containsKey('sessionToken'),
      isFalse,
    );
  }, skip: skip);

  test('switched off, every search goes to the fallback', () async {
    var googleCalls = 0;
    var enabled = false;
    final fallback = _Fallback();
    final repository = GooglePlacesGeocodingRepository(
      fallback: fallback,
      enabled: () => enabled,
      client: MockClient((request) async {
        googleCalls++;
        return suggestions(request);
      }),
    );
    addTearDown(repository.dispose);

    expect((await repository.search('NU Laguna')).single.name, 'MapTiler');
    expect(googleCalls, 0);
    enabled = true;
    expect((await repository.search('NU Laguna')).single.placeId, 'p1');
    expect(googleCalls, 1);
  }, skip: skip);
}

class _Fallback implements GeocodingRepository {
  int searches = 0;

  @override
  Future<List<GeocodedPlace>> search(String query) async {
    searches++;
    return const [
      GeocodedPlace(
        id: 'maptiler',
        name: 'MapTiler',
        context: 'Calamba',
        coordinate: GeoCoordinate(latitude: 14.2, longitude: 121.1),
      ),
    ];
  }

  @override
  Future<GeocodedPlace?> reverse(GeoCoordinate coordinate) async => null;

  @override
  Future<GeoCoordinate?> locate(GeocodedPlace place) async => place.coordinate;

  @override
  Future<GeocodedPlace?> refresh(String placeId) async => null;
}
