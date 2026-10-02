import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/data/repositories/location_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:arangcada/features/rating/driver_rating_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Rides implements SupabaseRideRepository {
  _Rides({this.goOnlineFails = false});

  final bool goOnlineFails;
  int finishCalls = 0;

  @override
  Future<void> refreshFeedbackState() async {}

  @override
  Future<void> finishDriverTrip() async {
    finishCalls++;
    if (goOnlineFails) {
      throw const LocationFailure(LocationFailureReason.timeout, 'no fix');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpLive(WidgetTester tester, _Rides rides) async {
  final state = DemoState(
    initialUser: const DemoUser(
      email: 'driver@example.com',
      displayName: 'Connected Driver',
      role: DemoRole.driver,
    ),
  );
  addTearDown(state.dispose);
  state.driverTrip.status = DriverTripStatus.completed;
  final router = GoRouter(
    initialLocation: '/driver/rating',
    routes: [
      GoRoute(
        path: '/driver',
        builder: (_, _) => const Scaffold(body: Text('driver home')),
      ),
      GoRoute(
        path: '/driver/rating',
        builder: (_, _) => const DriverRatingScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        demoStateProvider.overrideWithValue(state),
        liveRideRepositoryProvider.overrideWithValue(rides),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.tap(find.text('Skip'));
  await tester.pumpAndSettle();
}

void main() {
  // complete_trip leaves the driver offline on the server. Leaving the rating
  // screen has to go back online there, not only on this phone.
  testWidgets('leaving the rating screen closes the trip on the server', (
    tester,
  ) async {
    final rides = _Rides();
    await _pumpLive(tester, rides);

    expect(rides.finishCalls, 1);
    expect(find.text('driver home'), findsOneWidget);
    expect(find.text(SupabaseRideRepository.driverOfflineNotice), findsNothing);
  });

  testWidgets('the driver is told when going back online failed', (
    tester,
  ) async {
    final rides = _Rides(goOnlineFails: true);
    await _pumpLive(tester, rides);

    expect(rides.finishCalls, 1);
    expect(find.text('driver home'), findsOneWidget);
    expect(
      find.text(SupabaseRideRepository.driverOfflineNotice),
      findsOneWidget,
    );
  });

  testWidgets('passenger rating shows the completed trip actual route', (
    tester,
  ) async {
    final state = DemoState(
      initialUser: const DemoUser(
        email: 'driver@example.com',
        displayName: 'Connected Driver',
        role: DemoRole.driver,
      ),
    );
    addTearDown(state.dispose);
    state.pickup = DemoPlace(
      id: 'gps',
      name: 'Current location',
      address: 'Cabuyao, Laguna',
      coordinate: DemoData.calambaCrossing.coordinate,
    );
    state.destination = DemoData.places.firstWhere(
      (place) => place.name == 'SM City Calamba',
    );
    state.driverTrip.status = DriverTripStatus.completed;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [demoStateProvider.overrideWithValue(state)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const DriverRatingScreen(),
        ),
      ),
    );

    expect(find.text('Current location → SM City Calamba'), findsOneWidget);
    expect(
      find.text('Calamba Crossing Terminal → Calamba City Hall'),
      findsNothing,
    );
  });
}
