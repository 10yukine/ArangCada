import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/repositories/geocoding_repository.dart';
import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:go_router/go_router.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/features/search/destination_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search and shortcuts remain reachable above a tall keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final state = DemoState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [demoStateProvider.overrideWithValue(state)],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const DestinationSearchScreen(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Choose on map'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Choose on map').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('popular shortcuts use live pins instead of legacy coordinates', (
    tester,
  ) async {
    final state = DemoState();
    final geocoder = _LivePlaces();
    addTearDown(state.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const DestinationSearchScreen()),
        GoRoute(
          path: '/home/ride-options',
          builder: (_, _) => const Scaffold(body: Text('Ride options')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          geocodingRepositoryProvider.overrideWithValue(geocoder),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Rizal Shrine Calamba').last);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(geocoder.queries, ['Rizal Shrine Calamba']);
    expect(state.destination, isNull);
    expect(find.text('Popular in Calamba'), findsNothing);
    await tester.tap(find.text('Rizal Shrine Calamba').last);
    await tester.pumpAndSettle();
    expect(geocoder.lookups, 1);
    expect(
      state.destination!.coordinate.latitude,
      _LivePlaces.coordinate.latitude,
    );
    expect(
      state.destination!.coordinate.latitude,
      isNot(DemoData.places[2].coordinate.latitude),
    );
    expect(state.destination!.id, 'google:verified');
    expect(state.destination!.googleRetrievedAt, isNotNull);
    expect(find.text('Ride options'), findsOneWidget);
  });
}

class _LivePlaces implements GeocodingRepository {
  static const coordinate = GeoCoordinate(
    latitude: 14.2144,
    longitude: 121.1667,
  );
  final queries = <String>[];
  int lookups = 0;
  @override
  Future<List<GeocodedPlace>> search(String query) async {
    queries.add(query);
    return const [
      GeocodedPlace(
        id: 'google:verified',
        placeId: 'verified',
        name: 'Rizal Shrine Calamba',
        context: 'Calamba',
        coordinate: null,
      ),
    ];
  }

  @override
  Future<GeoCoordinate?> locate(GeocodedPlace place) async {
    lookups++;
    return coordinate;
  }

  @override
  Future<GeocodedPlace?> reverse(GeoCoordinate coordinate) async => null;
  @override
  Future<GeocodedPlace?> refresh(String placeId) async => null;
}
