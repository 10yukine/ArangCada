import 'package:arangcada/app/theme/app_colors.dart';
import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/core/widgets/map/live_map_view.dart';
import 'package:arangcada/core/widgets/map/route_preview_map.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/routing_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo driver starts at Starbucks Olivarez Plaza', () {
    final location = DemoData.mockDriverLocation;

    expect(location.name, 'Starbucks Olivarez Plaza');
    expect(location.coordinate.latitude, closeTo(14.1792854, 0.0000001));
    expect(location.coordinate.longitude, closeTo(121.1365276, 0.0000001));
  });

  test('map diffs catch marker style and interior route changes', () {
    const point = GeoCoordinate(latitude: 14.21, longitude: 121.16);
    const end = GeoCoordinate(latitude: 14.22, longitude: 121.17);

    expect(
      mapMarkersEquivalent(
        const [MapMarker(coordinate: point, color: AppColors.primary)],
        const [MapMarker(coordinate: point, color: AppColors.green)],
      ),
      isFalse,
    );
    expect(
      mapRoutesEquivalent(
        const [point, GeoCoordinate(latitude: 14.215, longitude: 121.165), end],
        const [point, GeoCoordinate(latitude: 14.216, longitude: 121.165), end],
      ),
      isFalse,
    );
    expect(
      mapBoundariesEquivalent(
        const [
          MapBoundary(
            points: [
              point,
              GeoCoordinate(latitude: 14.215, longitude: 121.165),
              end,
            ],
          ),
        ],
        const [
          MapBoundary(
            points: [
              point,
              GeoCoordinate(latitude: 14.216, longitude: 121.165),
              end,
            ],
          ),
        ],
      ),
      isFalse,
    );
  });

  testWidgets('route framing includes exact pins above the measured sheet', (
    tester,
  ) async {
    const current = GeoCoordinate(latitude: 14.1792854, longitude: 121.1365276);
    const pickup = GeoCoordinate(latitude: 14.2116, longitude: 121.1652);
    const snappedStart = GeoCoordinate(latitude: 14.18, longitude: 121.137);
    const snappedEnd = GeoCoordinate(latitude: 14.211, longitude: 121.165);
    final controller = LiveMapViewController();

    Widget sheet(double height) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(key: controller.panelKey, height: height),
        ),
      ),
    );

    await tester.pumpWidget(sheet(320));
    var viewport = mapRouteViewport(
      route: const [snappedStart, snappedEnd],
      markers: const [
        MapMarker(coordinate: current, color: AppColors.green),
        MapMarker(coordinate: pickup, color: AppColors.primary),
      ],
      bottomInset: controller.bottomInset,
    );

    expect(
      viewport.bounds.southwest.latitude,
      closeTo(current.latitude, 1e-10),
    );
    expect(
      viewport.bounds.southwest.longitude,
      closeTo(current.longitude, 1e-10),
    );
    expect(viewport.bounds.northeast.latitude, closeTo(pickup.latitude, 1e-10));
    expect(
      viewport.bounds.northeast.longitude,
      closeTo(pickup.longitude, 1e-10),
    );
    expect(viewport.bottomPadding, 336);

    await tester.pumpWidget(sheet(140));
    viewport = mapRouteViewport(
      route: const [snappedStart, snappedEnd],
      markers: const [],
      bottomInset: controller.bottomInset,
    );
    expect(viewport.bottomPadding, 156);
  });

  testWidgets(
    'road route preserves provider geometry without fake connectors',
    (tester) async {
      const current = GeoCoordinate(latitude: 14.17783, longitude: 121.13607);
      const pickup = GeoCoordinate(latitude: 14.2116, longitude: 121.1652);
      const snappedStart = GeoCoordinate(
        latitude: 14.1774,
        longitude: 121.1357,
      );
      const snappedEnd = GeoCoordinate(latitude: 14.2113, longitude: 121.1650);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routingRepositoryProvider.overrideWithValue(
              _FixedRoutingRepository(const [snappedStart, snappedEnd]),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RoutePreviewMap(
                from: current,
                to: pickup,
                compassTopInset: 80,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final map = tester.widget<LiveMapView>(find.byType(LiveMapView));
      expect(map.route, const [snappedStart, snappedEnd]);
      expect(map.markers.first.coordinate, current);
      expect(map.markers.last.coordinate, pickup);
      expect(map.compassTopInset, 80);
    },
  );

  testWidgets('unavailable routing never draws a fabricated direct route', (
    tester,
  ) async {
    const current = GeoCoordinate(latitude: 14.17783, longitude: 121.13607);
    const pickup = GeoCoordinate(latitude: 14.2116, longitude: 121.1652);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routingRepositoryProvider.overrideWithValue(
            _FixedRoutingRepository(const [current, pickup], isFallback: true),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: RoutePreviewMap(from: current, to: pickup),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final map = tester.widget<LiveMapView>(find.byType(LiveMapView));
    expect(map.route, isEmpty);
    expect(map.markers, hasLength(2));
    expect(find.textContaining('Route preview unavailable'), findsOneWidget);
    expect(find.textContaining('direct line'), findsNothing);
  });

  testWidgets('visible map compass follows bearing and resets north on tap', (
    tester,
  ) async {
    var resetCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapCompass(bearing: 90, onPressed: () => resetCount++),
        ),
      ),
    );

    final resetNorth = find.byTooltip('Reset map north');
    expect(resetNorth, findsOneWidget);
    expect(tester.getSize(resetNorth), const Size(48, 48));

    final rotation = tester.widget<Transform>(
      find.ancestor(
        of: find.byIcon(Icons.navigation_rounded),
        matching: find.byType(Transform),
      ),
    );
    expect(rotation.transform.entry(0, 0), closeTo(0, 0.00001));
    expect(rotation.transform.entry(1, 0), closeTo(-1, 0.00001));

    await tester.tap(resetNorth);
    expect(resetCount, 1);
  });
}

class _FixedRoutingRepository implements RoutingRepository {
  const _FixedRoutingRepository(this.geometry, {this.isFallback = false});

  final List<GeoCoordinate> geometry;
  final bool isFallback;

  @override
  String get attribution => '';

  @override
  Future<RouteResult> route({
    required GeoCoordinate from,
    required GeoCoordinate to,
  }) async => RouteResult(
    geometry: geometry,
    distanceMeters: 0,
    durationSeconds: 0,
    isFallback: isFallback,
    retrievedAt: DateTime(2026),
  );
}
