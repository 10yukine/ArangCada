import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/data/remote/openrouteservice_routing_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('unavailable routing returns no invented road geometry', () async {
    final repository = OpenRouteServiceRoutingRepository(
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    addTearDown(repository.dispose);

    final route = await repository.route(
      from: const GeoCoordinate(latitude: 14.17783, longitude: 121.13607),
      to: const GeoCoordinate(latitude: 14.2116, longitude: 121.1652),
    );

    expect(route.isFallback, isTrue);
    expect(route.geometry, isEmpty);
    expect(route.distanceMeters, 0);
    expect(route.durationSeconds, 0);
  });
}
