import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
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

class _PickupRide implements SupabaseRideRepository {
  int cancelCalls = 0;
  String? reason;

  @override
  Map<String, dynamic>? get activeTrip => {
    'id': 'test-trip',
    'status': 'accepted',
  };

  @override
  Future<void> cancelRideAsDriver(String reason) async {
    cancelCalls++;
    this.reason = reason;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoNotifications implements NotificationsRepository {
  @override
  List<AppNotificationRecord> history() => const [];

  @override
  Future<void> markRead(String id) async {}
}

Future<(_PickupRide, DemoState)> _pump(
  WidgetTester tester, {
  required bool live,
}) async {
  final state = DemoState(
    initialUser: const DemoUser(
      email: 'driver@test.example',
      displayName: 'Test Driver',
      role: DemoRole.driver,
    ),
  );
  state.driverTrip.status = DriverTripStatus.accepted;
  final rides = _PickupRide();
  addTearDown(state.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        demoStateProvider.overrideWithValue(state),
        if (live) liveRideRepositoryProvider.overrideWithValue(rides),
        notificationsRepositoryProvider.overrideWithValue(_NoNotifications()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const DriverHomeScreen()),
    ),
  );
  await tester.pump();
  return (rides, state);
}

void main() {
  testWidgets('driver cancel warns, needs a reason, and sends it', (
    tester,
  ) async {
    final (rides, _) = await _pump(tester, live: true);

    await tester.ensureVisible(find.text('Cancel ride'));
    await tester.tap(find.text('Cancel ride'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this ride?'), findsOneWidget);

    // Backing out keeps the ride.
    await tester.tap(find.text('Keep ride'));
    await tester.pumpAndSettle();
    expect(rides.cancelCalls, 0);

    await tester.tap(find.text('Cancel ride'));
    await tester.pumpAndSettle();
    expect(find.textContaining('may lead to penalties'), findsOneWidget);
    // No reason chosen yet: the confirm button is disabled.
    final confirm = find.widgetWithText(FilledButton, 'Cancel ride');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(find.text('Passenger did not show up'));
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(rides.cancelCalls, 1);
    expect(rides.reason, 'passenger_no_show');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('demo trips offer no cancel (no server ride to cancel)', (
    tester,
  ) async {
    await _pump(tester, live: false);
    expect(find.text('Cancel ride'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
