import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:arangcada/features/trips/trips_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Future<void> render(
    WidgetTester tester,
    DemoRole role, {
    bool samples = false,
  }) async {
    final state = DemoState(
      initialUser: DemoUser(
        email: '${role.name}@arangcada.demo',
        displayName: role == DemoRole.driver ? 'Mang Ben D.' : 'Ana Santos',
        role: role,
      ),
    );
    if (samples) state.setSampleContent(true);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [demoStateProvider.overrideWithValue(state)],
        child: MaterialApp(theme: AppTheme.light, home: const TripsScreen()),
      ),
    );
  }

  testWidgets('first-run trip histories stay honestly empty for both roles', (
    tester,
  ) async {
    await render(tester, DemoRole.commuter);
    expect(find.text('No trips yet'), findsOneWidget);
    expect(find.text('Calamba Crossing → SM Calamba'), findsNothing);

    await render(tester, DemoRole.driver);
    expect(find.text('No driver trips yet'), findsOneWidget);
    expect(find.text('Crossing Market → City Hall'), findsNothing);
  });

  testWidgets('commuter sample trips match the approved history filters', (
    tester,
  ) async {
    await render(tester, DemoRole.commuter, samples: true);

    expect(find.text('Trip history'), findsOneWidget);
    expect(find.text('Latest completed trip: Jul 3'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Special'), findsWidgets);
    expect(find.text('Pooling'), findsWidgets);
    expect(find.text('Calamba Crossing → SM Calamba'), findsOneWidget);
    expect(find.text('₱60.00'), findsNWidgets(2));

    await tester.tap(find.text('Pooling').first);
    await tester.pumpAndSettle();
    expect(find.text('City Hall → Crossing Market'), findsOneWidget);
    expect(find.text('Calamba Crossing → SM Calamba'), findsNothing);
  });

  testWidgets('driver history never shows sample trips', (tester) async {
    await render(tester, DemoRole.driver, samples: true);

    expect(find.text('No driver trips yet'), findsOneWidget);
    expect(find.text('Crossing Market → City Hall'), findsNothing);
  });

  testWidgets('Go Online from empty driver trips changes availability', (
    tester,
  ) async {
    final state = DemoState(
      initialUser: const DemoUser(
        email: 'driver@arangcada.demo',
        displayName: 'Driver',
        role: DemoRole.driver,
      ),
    );
    addTearDown(state.dispose);
    final router = GoRouter(
      initialLocation: '/trips',
      routes: [
        GoRoute(path: '/trips', builder: (_, _) => const TripsScreen()),
        GoRoute(
          path: '/driver',
          builder: (_, _) => const Scaffold(body: Text('Driver dashboard')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          liveRideRepositoryProvider.overrideWithValue(null),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(state.driverTrip.isOnline, isFalse);
    await tester.tap(find.text('Go Online'));
    await tester.pumpAndSettle();
    expect(state.driverTrip.isOnline, isTrue);
    expect(find.text('Driver dashboard'), findsOneWidget);
  });

  testWidgets('live Go Online calls availability RPC before leaving Trips', (
    tester,
  ) async {
    final state = DemoState(
      initialUser: const DemoUser(
        email: 'driver@example.com',
        displayName: 'Driver',
        role: DemoRole.driver,
      ),
    );
    final rides = _EmptyDriverRides();
    addTearDown(state.dispose);
    final router = GoRouter(
      initialLocation: '/trips',
      routes: [
        GoRoute(path: '/trips', builder: (_, _) => const TripsScreen()),
        GoRoute(
          path: '/driver',
          builder: (_, _) => const Scaffold(body: Text('Driver dashboard')),
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go Online'));
    await tester.pumpAndSettle();
    expect(rides.onlineCalls, 1);
    expect(find.text('Driver dashboard'), findsOneWidget);
  });

  testWidgets('real driver without live connection stays offline', (
    tester,
  ) async {
    final state = DemoState(
      initialUser: const DemoUser(
        email: 'driver@example.com',
        displayName: 'Driver',
        role: DemoRole.driver,
      ),
    );
    addTearDown(state.dispose);
    final router = GoRouter(
      initialLocation: '/trips',
      routes: [
        GoRoute(path: '/trips', builder: (_, _) => const TripsScreen()),
        GoRoute(
          path: '/driver',
          builder: (_, _) => const Scaffold(body: Text('Driver dashboard')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          liveRideRepositoryProvider.overrideWithValue(null),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go Online'));
    await tester.pump();
    expect(state.driverTrip.isOnline, isFalse);
    expect(find.text('Driver dashboard'), findsNothing);
    expect(find.text('Live driver connection unavailable.'), findsOneWidget);
  });

  testWidgets(
    'completed driver state without a trip shows no fabricated summary',
    (tester) async {
      final state = DemoState(
        initialUser: const DemoUser(
          email: 'driver@arangcada.demo',
          displayName: 'Mang Ben D.',
          role: DemoRole.driver,
        ),
      );
      state.driverTrip.status = DriverTripStatus.completed;
      addTearDown(state.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [demoStateProvider.overrideWithValue(state)],
          child: MaterialApp(theme: AppTheme.light, home: const TripsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No driver trips yet'), findsOneWidget);
      expect(find.text('Joshua Ramos'), findsNothing);
      expect(find.text('Trip summary'), findsNothing);
    },
  );
}

class _EmptyDriverRides extends ChangeNotifier
    implements SupabaseRideRepository {
  int onlineCalls = 0;

  @override
  List<Map<String, dynamic>> get trips => const [];

  @override
  Future<void> setDriverOnline(bool online) async {
    if (online) onlineCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
