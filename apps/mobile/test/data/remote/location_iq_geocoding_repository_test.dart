import 'dart:async';
import 'dart:convert';

import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/core/network/api_exceptions.dart';
import 'package:arangcada/data/remote/location_iq_geocoding_repository.dart';
import 'package:arangcada/data/repositories/geocoding_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final endpoint = Uri.parse(
    'https://project.example/functions/v1/place-search',
  );

  LocationIqGeocodingRepository repositoryWith(
    MockClient client, {
    GeocodingRepository? pins,
    Duration minInterval = Duration.zero,
    String? Function()? accessToken,
  }) {
    final repository = LocationIqGeocodingRepository(
      pins: pins ?? _Pins(),
      accessToken: accessToken ?? () => 'rider-token',
      endpoint: endpoint,
      anonKey: 'anon-key',
      minInterval: minInterval,
      client: client,
    );
    addTearDown(repository.dispose);
    return repository;
  }

  // The session is refreshed by the app; a refusal says nothing about the
  // search service, so it must not switch search off.
  for (final status in [401, 403]) {
    test('a $status is not remembered: the next search is sent', () async {
      var calls = 0;
      final repository = repositoryWith(
        MockClient((request) async {
          calls++;
          return http.Response('{}', status);
        }),
      );
      await expectLater(
        repository.search('sm city'),
        throwsA(isA<ApiUnauthorizedException>()),
      );
      await expectLater(
        repository.search('rizal shrine'),
        throwsA(isA<ApiUnauthorizedException>()),
      );
      expect(calls, 2);
    });
  }

  for (final status in [429, 502]) {
    test('a $status stops requests for a while', () async {
      var calls = 0;
      final pins = _Pins();
      final repository = repositoryWith(
        pins: pins,
        MockClient((request) async {
          calls++;
          return http.Response('{"error":"place search is busy"}', status);
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
      // No other provider answers in its place.
      expect(pins.searches, 0);
    });

    test('a superseded $status also stops a queued request', () async {
      var calls = 0;
      final response = Completer<http.Response>();
      final repository = repositoryWith(
        minInterval: const Duration(milliseconds: 80),
        MockClient((request) {
          calls++;
          return response.future;
        }),
      );
      final first = repository.search('sm city');
      final queued = repository.search('rizal shrine');
      final stopped = expectLater(
        queued,
        throwsA(isA<ApiRateLimitedException>()),
      );
      response.complete(http.Response('{}', status));
      expect(await first, isEmpty);
      await stopped;
      expect(calls, 1);
    });
  }

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
    'a search sends only the text, with the rider session and no provider key',
    () async {
      final requests = <http.Request>[];
      final repository = repositoryWith(
        MockClient((request) async {
          requests.add(request);
          return jsonDecode(request.body)['q'] == 'zzzz'
              ? http.Response('[]', 200)
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

      final sent = requests.single;
      expect(sent.method, 'POST');
      expect(sent.url, endpoint);
      expect(sent.headers['Authorization'], 'Bearer rider-token');
      expect(sent.headers['apikey'], 'anon-key');
      expect(jsonDecode(sent.body), {'q': 'sm city'});

      expect(await repository.search('zzzz'), isEmpty);

      await repository.search('x' * 200);
      expect((jsonDecode(requests.last.body)['q'] as String).length, 80);
    },
  );

  test('nothing is sent when nobody is signed in', () async {
    var calls = 0;
    final repository = repositoryWith(
      accessToken: () => null,
      MockClient((request) async {
        calls++;
        return found(request);
      }),
    );
    await expectLater(
      repository.search('sm city'),
      throwsA(isA<ApiUnauthorizedException>()),
    );
    expect(calls, 0);
  });

  test(
    'typing fast sends one request an interval, and only the last is shown',
    () async {
      final sentAt = <DateTime>[];
      const interval = Duration(milliseconds: 300);
      final repository = repositoryWith(
        minInterval: interval,
        MockClient((request) async {
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
