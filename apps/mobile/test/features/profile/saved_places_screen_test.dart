import 'dart:convert';

import 'dart:io';

import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/geocoding_repository.dart';
import 'package:arangcada/data/repositories/saved_places_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/features/profile/profile_detail_screens.dart';
import 'package:arangcada/features/search/destination_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

// Disk persistence is exercised separately below. Widget tests use immediate
// storage so their simulated clock never has to drive operating-system I/O.
class _MemoryPlaces extends SavedPlacesRepository {
  _MemoryPlaces() : super(null, 'widget-account');

  final _places = <DemoPlace>[];

  @override
  List<DemoPlace> get places => List.unmodifiable(_places);

  @override
  Future<void> save(DemoPlace place) async => _places.add(place);

  @override
  Future<void> remove(String id) async =>
      _places.removeWhere((p) => p.id == id);
}

void main() {
  late Directory directory;
  late Box<String> box;
  late SavedPlacesRepository repository;
  late DemoState state;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('saved_places_test_');
    Hive.init(directory.path);
    box = await Hive.openBox<String>('saved_places_test');
    repository = SavedPlacesRepository(box, 'account-a');
    state = DemoState();
  });

  tearDown(() async {
    state.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Widget harness(Widget screen) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => screen),
        GoRoute(
          path: '/home/ride-options',
          builder: (_, _) => const Scaffold(body: Text('Ride options')),
        ),
      ],
    );
    addTearDown(router.dispose);
    return ProviderScope(
      overrides: [
        demoStateProvider.overrideWithValue(state),
        savedPlacesRepositoryProvider.overrideWithValue(repository),
        geocodingRepositoryProvider.overrideWithValue(
          _Geocoder(DemoData.places[2]),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  test(
    'places survive reopening, deduplicate, and stay account scoped',
    () async {
      final place = DemoData.calambaCrossing;
      await repository.save(place);
      await repository.save(place);
      await box.close();
      box = await Hive.openBox<String>('saved_places_test');
      repository = SavedPlacesRepository(box, 'account-a');
      expect(repository.places, hasLength(1));
      expect(repository.places.single.name, place.name);
      expect(
        repository.places.single.coordinate.latitude,
        place.coordinate.latitude,
      );
      expect(SavedPlacesRepository(box, 'account-b').places, isEmpty);
      await repository.remove(place.id);
      expect(SavedPlacesRepository(box, 'account-a').places, isEmpty);
    },
  );

  test('unavailable storage does not silently pretend to save', () async {
    await expectLater(
      SavedPlacesRepository(null, 'account-a').save(DemoData.calambaCrossing),
      throwsStateError,
    );
  });

  testWidgets(
    'add saves a selected place without changing booking; remove works',
    (tester) async {
      repository = _MemoryPlaces();
      final previousDestination = DemoData.places.last;
      state.setDestination(previousDestination);
      await tester.pumpWidget(harness(const SavedPlacesScreen()));
      await tester.tap(find.text('Add a saved place'));
      await tester.pumpAndSettle();
      expect(find.text('Save a place'), findsOneWidget);
      await tester.tap(find.text('Rizal Shrine Calamba').last);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rizal Shrine Calamba').last);
      await tester.pumpAndSettle();
      expect(repository.places.single.name, 'Rizal Shrine Calamba');
      expect(state.destination, same(previousDestination));
      expect(find.text('No saved places'), findsNothing);
      await tester.tap(find.byTooltip('Remove Rizal Shrine Calamba'));
      await tester.pumpAndSettle();
      expect(repository.places, isEmpty);
      expect(find.text('No saved places'), findsOneWidget);
    },
  );

  testWidgets('saved place can be reused from booking search', (tester) async {
    repository = _MemoryPlaces();
    state.setPickup(DemoData.places.last);
    await repository.save(DemoData.calambaCrossing);
    await tester.pumpWidget(harness(const DestinationSearchScreen()));
    expect(find.text('Saved places'), findsOneWidget);
    await tester.tap(find.text(DemoData.calambaCrossing.name).first);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(state.destination, isNull);
    await tester.tap(find.text(DemoData.calambaCrossing.name).last);
    await tester.pumpAndSettle();
    expect(state.destination?.name, DemoData.calambaCrossing.name);
    expect(find.text('Ride options'), findsOneWidget);
  });

  testWidgets(
    'destination search updates its pickup label when pickup changes',
    (tester) async {
      await tester.pumpWidget(harness(const DestinationSearchScreen()));
      expect(find.text(DemoData.calambaCrossing.name), findsWidgets);

      state.setPickup(
        DemoPlace(
          id: 'changed-pickup',
          name: 'Changed pickup',
          address: 'Test address',
          coordinate: DemoData.calambaCrossing.coordinate,
        ),
      );
      await tester.pump();
      expect(find.text('Changed pickup'), findsOneWidget);
    },
  );

  testWidgets('canceling selection leaves storage and booking unchanged', (
    tester,
  ) async {
    repository = _MemoryPlaces();
    await tester.pumpWidget(harness(const SavedPlacesScreen()));
    await tester.tap(find.text('Add a saved place'));
    await tester.pumpAndSettle();
    // The picker deliberately hides the visual Back tooltip.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(repository.places, isEmpty);
    expect(state.destination, isNull);
  });

  test('Google places persist only IDs and resolve on reopening', () async {
    final place = DemoPlace(
      googleRetrievedAt: DateTime.now(),
      id: 'google:nu-l',
      name: 'National University Laguna',
      address: 'Milagrosa, Calamba',
      coordinate: GeoCoordinate(latitude: 14.1778, longitude: 121.1363),
    );
    await repository.save(place);
    expect(repository.places.single.name, 'Saved place');
    expect(box.get('saved_places:account-a'), '[{"id":"google:nu-l"}]');
    repository = SavedPlacesRepository(box, 'account-a');
    expect(repository.places, isEmpty);
    final later = DateTime.now();

    expect(await repository.refreshStale(_Geocoder(null), now: later), isTrue);
    expect(box.get('saved_places:account-a'), '[{"id":"google:nu-l"}]');
    expect(repository.places, isEmpty);

    final geocoder = _Geocoder(place);
    expect(await repository.refreshStale(geocoder, now: later), isTrue);
    await repository.refreshStale(geocoder, now: later);
    expect(geocoder.refreshes, 1);
    expect(repository.places.single.name, place.name);
    expect(repository.places.single.id, 'google:nu-l');
  });

  test('legacy Google content is purged for every stored account', () async {
    for (final account in ['account-a', 'account-b']) {
      await box.put(
        'saved_places:$account',
        jsonEncode([
          {'id': 'google:old', 'name': 'Google name', 'latitude': 14.2},
          {'id': 'home', 'name': 'My home'},
        ]),
      );
    }
    await box.put('saved_places:corrupt', 'not json');
    await SavedPlacesRepository.purgeGoogleContent(box);
    expect(box.get('saved_places:corrupt'), 'not json');
    for (final account in ['account-a', 'account-b']) {
      final rows = jsonDecode(box.get('saved_places:$account')!) as List;
      expect(rows.first, {'id': 'google:old'});
      expect(rows.last, {'id': 'home', 'name': 'My home'});
    }
  });

  test('booking rejects expired or unknown Google coordinate age', () {
    final now = DateTime.now();
    DemoPlace google(DateTime? at) => DemoPlace(
      id: 'google:p1',
      name: 'Place',
      address: 'Calamba',
      coordinate: DemoData.calambaCrossing.coordinate,
      googleRetrievedAt: at,
    );
    expect(google(null).googleCoordinateIsFresh(now), isFalse);
    expect(google(now).googleCoordinateIsFresh(now), isTrue);
    expect(
      google(
        now.subtract(const Duration(hours: 1)),
      ).googleCoordinateIsFresh(now),
      isFalse,
    );
    expect(DemoData.calambaCrossing.googleCoordinateIsFresh(now), isTrue);
  });

  test(
    'a place saved or removed during a refresh is kept as the user left it',
    () async {
      final old = DemoPlace(
        googleRetrievedAt: DateTime.now(),
        id: 'google:old',
        name: 'Old Google Place',
        address: 'Calamba',
        coordinate: GeoCoordinate(latitude: 14.2, longitude: 121.16),
      );
      const removed = DemoPlace(
        id: 'home',
        name: 'Home',
        address: 'Calamba',
        coordinate: GeoCoordinate(latitude: 14.21, longitude: 121.17),
      );
      const added = DemoPlace(
        id: 'work',
        name: 'Work',
        address: 'Calamba',
        coordinate: GeoCoordinate(latitude: 14.22, longitude: 121.18),
      );
      await repository.save(old);
      await repository.save(removed);

      // While the lookup is in flight the user removes one place and saves another.
      final geocoder = _Geocoder(old)
        ..duringRefresh = () async {
          await repository.remove(removed.id);
          await repository.save(added);
        };
      await repository.refreshStale(
        geocoder,
        now: DateTime.now().add(const Duration(days: 31)),
      );

      final ids = [
        for (final row
            in jsonDecode(box.get('saved_places:account-a')!) as List)
          (row as Map)['id'],
      ];
      expect(ids, ['google:old', 'work']);
    },
  );
}

class _Geocoder implements GeocodingRepository {
  _Geocoder(this.place);

  final DemoPlace? place;
  int refreshes = 0;
  Future<void> Function()? duringRefresh;

  @override
  Future<GeocodedPlace?> refresh(String placeId) async {
    refreshes++;
    await duringRefresh?.call();
    return _refreshed(placeId);
  }

  GeocodedPlace? _refreshed(String placeId) => place == null
      ? null
      : GeocodedPlace(
          id: 'google:$placeId',
          placeId: placeId,
          name: place!.name,
          context: place!.address,
          coordinate: place!.coordinate,
        );

  @override
  Future<List<GeocodedPlace>> search(String query) async {
    final found =
        DemoData.places.where((p) => p.name == query).firstOrNull ?? place;
    return found == null
        ? []
        : [
            GeocodedPlace(
              id: found.id,
              name: found.name,
              context: found.address,
              coordinate: found.coordinate,
            ),
          ];
  }

  @override
  Future<GeocodedPlace?> reverse(GeoCoordinate coordinate) async => null;

  @override
  Future<GeoCoordinate?> locate(GeocodedPlace place) async => place.coordinate;
}
