import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/core/widgets/map/live_map_view.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/geocoding_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/features/search/pin_on_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Geocoder implements GeocodingRepository {
  @override
  Future<List<GeocodedPlace>> search(String query) async => [];

  @override
  Future<GeocodedPlace?> reverse(GeoCoordinate coordinate) async => null;

  @override
  Future<GeoCoordinate?> locate(GeocodedPlace place) async => place.coordinate;

  @override
  Future<GeocodedPlace?> refresh(String placeId) async => null;
}

void main() {
  testWidgets('map pin returns a place without changing booking locations', (
    tester,
  ) async {
    final state = DemoState();
    addTearDown(state.dispose);
    DemoPlace? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          geocodingRepositoryProvider.overrideWithValue(_Geocoder()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  picked = await Navigator.of(context).push<DemoPlace>(
                    MaterialPageRoute(builder: (_) => const PinOnMapScreen()),
                  );
                },
                child: const Text('Open map'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open map'));
    await tester.pumpAndSettle();

    const coordinate = GeoCoordinate(latitude: 14.21, longitude: 121.16);
    final map = tester.widget<LiveMapView>(find.byType(LiveMapView));
    map.onMapTap!(coordinate);
    await tester.pump();
    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();

    expect(picked?.coordinate, coordinate);
    expect(state.pickup, DemoData.calambaCrossing);
    expect(state.destination, isNull);
  });

  test('clampToRadius keeps near points and pulls far ones to the edge', () {
    const anchor = GeoCoordinate(latitude: 14.2085, longitude: 121.1555);
    const near = GeoCoordinate(latitude: 14.2088, longitude: 121.1556);
    expect(clampToRadius(anchor, near, 100), near);

    const far = GeoCoordinate(latitude: 14.2185, longitude: 121.1655);
    final clamped = clampToRadius(anchor, far, 100);
    expect(haversineDistanceMeters(anchor, clamped), closeTo(100, 1));
  });

  testWidgets('pickup adjustment starts at GPS and cannot leave 100 m', (
    tester,
  ) async {
    final state = DemoState();
    addTearDown(state.dispose);
    const anchor = GeoCoordinate(latitude: 14.2085, longitude: 121.1555);
    DemoPlace? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          geocodingRepositoryProvider.overrideWithValue(_Geocoder()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  picked = await Navigator.of(context).push<DemoPlace>(
                    MaterialPageRoute(
                      builder: (_) =>
                          const PinOnMapScreen(pickupAnchor: anchor),
                    ),
                  );
                },
                child: const Text('Adjust'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Adjust'));
    await tester.pumpAndSettle();

    expect(find.text('Adjust pickup'), findsOneWidget);
    final map = tester.widget<LiveMapView>(find.byType(LiveMapView));
    // Street level, so the 100 m leash is big enough to aim within.
    expect(map.zoom, 18);
    // The chosen pin can be dragged; the GPS dot cannot.
    expect(map.markers.map((m) => m.draggable), [false, true]);
    // Pins can be moved again and again, not just once.
    map.onMapTap!(const GeoCoordinate(latitude: 14.2112, longitude: 121.1652));
    await tester.pump();
    // A tap about 1.5 km away lands on the 100 m edge instead.
    tester.widget<LiveMapView>(find.byType(LiveMapView)).onMapTap!(
      const GeoCoordinate(latitude: 14.2185, longitude: 121.1655),
    );
    await tester.pump();
    await tester.tap(find.text('Set pickup here'));
    await tester.pumpAndSettle();

    expect(picked?.id, adjustedPickupId);
    expect(
      haversineDistanceMeters(anchor, picked!.coordinate),
      lessThanOrEqualTo(pickupAdjustRadiusMeters + 0.5),
    );
    // The screen hands the place back; it never edits the booking itself.
    expect(state.destination, isNull);
  });
}
