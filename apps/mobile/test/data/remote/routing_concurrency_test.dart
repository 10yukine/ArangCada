import 'dart:async';
import 'dart:convert';
import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/data/remote/fallback_routing_repository.dart';
import 'package:arangcada/data/remote/google_routes_routing_repository.dart';
import 'package:arangcada/data/remote/openrouteservice_routing_repository.dart';
import 'package:arangcada/data/repositories/routing_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Run with synthetic ORS_API_KEY and GOOGLE_ROUTES_API_KEY dart defines.
void main() {
  for (final google in [false, true]) {
    test(
      '${google ? "Google" : "ORS"} serializes distinct requests and observes cooldown',
      () async {
        final pending = Completer<http.Response>();
        var calls = 0;
        final client = MockClient((_) {
          calls++;
          return pending.future;
        });
        final RoutingRepository repository = google
            ? GoogleRoutesRoutingRepository(client: client)
            : OpenRouteServiceRoutingRepository(client: client);
        addTearDown(client.close);
        const from = GeoCoordinate(latitude: 14.2, longitude: 121.1);
        const to = GeoCoordinate(latitude: 14.3, longitude: 121.2);
        const other = GeoCoordinate(latitude: 14.4, longitude: 121.3);
        final first = repository.route(from: from, to: to);
        final second = repository.route(from: from, to: other);
        final duplicate = repository.route(from: from, to: to);
        await Future<void>.delayed(Duration.zero);
        expect(calls, 1);
        pending.complete(http.Response('{}', 429));
        final results = await Future.wait([first, second, duplicate]);
        expect(calls, 1);
        expect(results.every((r) => r.isFallback), isTrue);
      },
      skip:
          const String.fromEnvironment('ORS_API_KEY').isEmpty ||
          const String.fromEnvironment('GOOGLE_ROUTES_API_KEY').isEmpty,
    );
  }

  test(
    'both providers ask for toll-free routes; tricycles cannot use SLEX',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 500);
      });
      addTearDown(client.close);
      const from = GeoCoordinate(latitude: 14.2, longitude: 121.1);
      const to = GeoCoordinate(latitude: 14.3, longitude: 121.2);

      await GoogleRoutesRoutingRepository(
        client: client,
      ).route(from: from, to: to);
      await OpenRouteServiceRoutingRepository(
        client: client,
      ).route(from: from, to: to);

      expect(bodies[0]['routeModifiers'], {'avoidTolls': true});
      // TWO_WHEELER would bill every route as Compute Routes Enterprise.
      expect(bodies[0]['travelMode'], 'DRIVE');
      expect(bodies[1]['options'], {
        'avoid_features': ['tollways'],
      });
    },
    skip:
        const String.fromEnvironment('ORS_API_KEY').isEmpty ||
        const String.fromEnvironment('GOOGLE_ROUTES_API_KEY').isEmpty,
  );

  test(
    'Google over its daily quota hands routes to the free provider',
    () async {
      var googleCalls = 0;
      final client = MockClient((_) async {
        googleCalls++;
        // What Google returns once a Cloud Console quota cap is reached.
        return http.Response('{"error":{"status":"RESOURCE_EXHAUSTED"}}', 429);
      });
      addTearDown(client.close);
      final free = _FreeRouter();
      final repository = FallbackRoutingRepository(
        primary: GoogleRoutesRoutingRepository(client: client),
        secondary: free,
      );
      const from = GeoCoordinate(latitude: 14.2, longitude: 121.1);
      const to = GeoCoordinate(latitude: 14.3, longitude: 121.2);
      const other = GeoCoordinate(latitude: 14.4, longitude: 121.3);

      final first = await repository.route(from: from, to: to);
      expect(first.isFallback, isFalse);
      expect(repository.attribution, free.attribution);

      // During the cooldown Google is not asked again.
      await repository.route(from: from, to: other);
      expect(googleCalls, 1);
      expect(free.calls, 2);
    },
    skip: const String.fromEnvironment('GOOGLE_ROUTES_API_KEY').isEmpty,
  );
}

class _FreeRouter implements RoutingRepository {
  int calls = 0;

  @override
  String get attribution => 'Routing: openrouteservice';

  @override
  Future<RouteResult> route({
    required GeoCoordinate from,
    required GeoCoordinate to,
  }) async {
    calls++;
    return RouteResult(
      geometry: [from, to],
      distanceMeters: 1,
      durationSeconds: 1,
      isFallback: false,
      retrievedAt: DateTime(2026),
    );
  }
}
