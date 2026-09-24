import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/data/repositories/notifications_repository.dart';
import 'package:arangcada/domain/models/app_notification.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:arangcada/features/driver/driver_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('availability switch works at small width with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = DemoState(
      initialUser: const DemoUser(
        email: 'driver@arangcada.demo',
        displayName: 'Driver with a long name',
        role: DemoRole.driver,
      ),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          notificationsRepositoryProvider.overrideWithValue(_NoNotifications()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const DriverHomeScreen(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(state.driverTrip.isOnline, isTrue);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(state.driverTrip.isOnline, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('expired offer retries server expiry after an early rejection', (
    tester,
  ) async {
    final state = DemoState(
      initialUser: const DemoUser(
        email: 'driver@test.example',
        displayName: 'Test Driver',
        role: DemoRole.driver,
      ),
    );
    state.driverTrip.status = DriverTripStatus.incoming;
    final rides = _ExpiringRide();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          liveRideRepositoryProvider.overrideWithValue(rides),
          notificationsRepositoryProvider.overrideWithValue(_NoNotifications()),
        ],
        child: const MaterialApp(home: DriverHomeScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(rides.expireCalls, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(rides.expireCalls, 2);
  });
}

class _ExpiringRide implements SupabaseRideRepository {
  int expireCalls = 0;

  @override
  Map<String, dynamic>? get activeTrip => {
    'id': 'test-trip',
    'status': 'driver_assigned',
    'accept_by': '2020-01-01T00:00:00Z',
  };

  @override
  Future<void> expireRide() async => expireCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoNotifications implements NotificationsRepository {
  @override
  List<AppNotificationRecord> history() => const [];

  @override
  Future<void> markRead(String id) async {}
}
