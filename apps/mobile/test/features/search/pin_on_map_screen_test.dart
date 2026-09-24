import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/core/widgets/map/live_map_view.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/geocoding_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/features/search/pin_on_map_screen.dart';
import 'package:arangcada/features/search/destination_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Geocoder implements GeocodingRepository {
  @override
  Future<List<GeocodedPlace>> search(String query) async => [];

  @override
  Future<GeocodedPlace?> reverse(GeoCoordinate coordinate) async => null;
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

  testWidgets('pin selected from pickup search changes pickup and returns', (
    tester,
  ) async {
    final state = DemoState();
    addTearDown(state.dispose);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, route) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/home/choose-pickup'),
              child: const Text('Choose pickup'),
            ),
          ),
          routes: [
            GoRoute(
              path: 'choose-pickup',
              builder: (context, route) =>
                  const DestinationSearchScreen(pickingPickup: true),
            ),
            GoRoute(
              path: 'pin-on-map',
              pageBuilder: (context, route) =>
                  const MaterialPage<DemoPlace>(child: PinOnMapScreen()),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          geocodingRepositoryProvider.overrideWithValue(_Geocoder()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Choose pickup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin on map'));
    await tester.pumpAndSettle();

    const coordinate = GeoCoordinate(latitude: 14.21, longitude: 121.16);
    tester.widget<LiveMapView>(find.byType(LiveMapView)).onMapTap!(coordinate);
    await tester.pump();
    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();

    expect(state.pickup.coordinate, coordinate);
    expect(state.destination, isNull);
    expect(find.text('Choose pickup'), findsOneWidget);
  });
}
