import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/app/mobile_settings.dart';
import 'package:arangcada/data/remote/chosen_routing_repository.dart';
import 'package:arangcada/core/geo/route_progress.dart';
import 'package:arangcada/core/widgets/map/route_preview_map.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/routing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// A straight road running east for about 1.1 km, and the pickup at its end.
const _start = GeoCoordinate(latitude: 14.2100, longitude: 121.1600);
const _pickup = GeoCoordinate(latitude: 14.2100, longitude: 121.1700);
const _road = [
  _start,
  GeoCoordinate(latitude: 14.2100, longitude: 121.1650),
  _pickup,
];

/// A point [metersEast] along the road and [metersNorth] off it.
GeoCoordinate _at(double metersEast, {double metersNorth = 0}) => GeoCoordinate(
  latitude: 14.2100 + metersNorth / 111320,
  longitude: 121.1600 + metersEast / 107900,
);

class _CountingRouter implements RoutingRepository {
  final requests = <GeoCoordinate>[];

  @override
  String get attribution => '';

  @override
  Future<RouteResult> route({
    required GeoCoordinate from,
    required GeoCoordinate to,
  }) async {
    requests.add(from);
    return RouteResult(
      geometry: _road,
      distanceMeters: 1100,
      durationSeconds: 200,
      isFallback: false,
      retrievedAt: DateTime(2026),
    );
  }
}

void main() {
  Future<void> show(
    WidgetTester tester,
    RoutingRepository router,
    GeoCoordinate from, {
    GeoCoordinate to = _pickup,
    bool originMoves = true,
    Duration minRerouteInterval = Duration.zero,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [routingRepositoryProvider.overrideWithValue(router)],
        child: MaterialApp(
          home: Scaffold(
            body: RoutePreviewMap(
              from: from,
              to: to,
              originMoves: originMoves,
              minRerouteInterval: minRerouteInterval,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // This used to be one billable request every 40 m.
  testWidgets('a live map keeps its routing provider after settings change', (
    tester,
  ) async {
    final previous = serviceChoices.value;
    addTearDown(() => serviceChoices.value = previous);
    serviceChoices.value = (routing: 'ors_only', search: 'maptiler');
    final google = _CountingRouter();
    final ors = _CountingRouter();
    final chosen = ChosenRoutingRepository(
      google: google,
      ors: ors,
      useGoogle: () => useGoogleStack,
    );
    await show(tester, chosen, _start, originMoves: false);
    serviceChoices.value = (routing: 'google', search: 'google');
    await show(tester, chosen, _at(100), originMoves: false);
    expect(google.requests, isEmpty);
    expect(ors.requests, hasLength(2));
  });

  testWidgets('a driver following the route asks for it once', (tester) async {
    final router = _CountingRouter();
    await show(tester, router, _start);
    // A fix every ~28 m for a kilometre, with GPS drift beside the road.
    for (var meters = 28.0; meters <= 1000; meters += 28) {
      await show(tester, router, _at(meters, metersNorth: meters % 3 * 9));
    }
    expect(router.requests, hasLength(1));
  });

  testWidgets('a driver who leaves the route gets a new one', (tester) async {
    final router = _CountingRouter();
    await show(tester, router, _start);

    // One or two fixes off the road are not enough.
    await show(tester, router, _at(200, metersNorth: 90));
    await show(tester, router, _at(230, metersNorth: 120));
    expect(router.requests, hasLength(1));
    // Back on the road: the count starts over.
    await show(tester, router, _at(260));
    await show(tester, router, _at(290, metersNorth: 90));
    await show(tester, router, _at(320, metersNorth: 120));
    expect(router.requests, hasLength(1));

    await show(tester, router, _at(350, metersNorth: 150));
    expect(router.requests, hasLength(2));
    expect(
      router.requests.last.latitude,
      closeTo(_at(0, metersNorth: 150).latitude, 1e-9),
    );
  });

  testWidgets('re-routing waits out the minimum interval', (tester) async {
    final router = _CountingRouter();
    const minute = Duration(seconds: 60);
    await show(tester, router, _start, minRerouteInterval: minute);
    for (var i = 1; i <= 10; i++) {
      await show(
        tester,
        router,
        _at(100.0 + i * 28, metersNorth: 200),
        minRerouteInterval: minute,
      );
    }
    expect(router.requests, hasLength(1));
  });

  testWidgets('a new destination is routed at once', (tester) async {
    final router = _CountingRouter();
    await show(
      tester,
      router,
      _start,
      minRerouteInterval: const Duration(seconds: 60),
    );
    await show(
      tester,
      router,
      _at(28),
      to: const GeoCoordinate(latitude: 14.2150, longitude: 121.1700),
      minRerouteInterval: const Duration(seconds: 60),
    );
    expect(router.requests, hasLength(2));
  });

  testWidgets('fixed endpoints behave as before', (tester) async {
    final router = _CountingRouter();
    await show(tester, router, _start, originMoves: false);
    await show(tester, router, _at(20), originMoves: false);
    expect(router.requests, hasLength(1));
    await show(tester, router, _at(80), originMoves: false);
    expect(router.requests, hasLength(2));
  });

  test('progress measures the gap and keeps only the road ahead', () {
    final onRoad = routeProgress(_road, _at(700));
    expect(onRoad.offRouteMeters, lessThan(1));
    expect(onRoad.remaining, hasLength(2));
    expect(onRoad.remaining.last, same(_pickup));
    expect(onRoad.remaining.first.longitude, closeTo(_at(700).longitude, 1e-9));

    expect(
      routeProgress(_road, _at(300, metersNorth: 100)).offRouteMeters,
      closeTo(100, 1),
    );
    // Past the end: measured to the end point, nothing left but it.
    expect(routeProgress(_road, _at(1300)).remaining, hasLength(2));
    expect(routeProgress(const [], _start).offRouteMeters, double.infinity);
  });
}
