import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/core/widgets/arang_ui.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/data/repositories/notifications_repository.dart';
import 'package:arangcada/domain/models/app_notification.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:arangcada/features/driver/driver_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _LiveRide implements SupabaseRideRepository {
  int arrivedCalls = 0;
  int completeCalls = 0;

  @override
  Map<String, dynamic>? get activeTrip => {'id': 'test-trip'};

  @override
  Future<void> markArrived() async => arrivedCalls++;

  @override
  Future<void> completeTrip() async => completeCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoNotifications implements NotificationsRepository {
  @override
  List<AppNotificationRecord> history() => const [];

  @override
  Future<void> markRead(String id) async {}
}

/// [metersNorth] places the driver that far north of the point that matters
/// at this stage: the pickup while accepted, the drop-off while on the trip.
Future<(_LiveRide, DemoState)> _pump(
  WidgetTester tester, {
  required DriverTripStatus status,
  required double metersNorth,
  bool live = true,
  bool riderConsent = false,
}) async {
  final state = DemoState(
    initialUser: const DemoUser(
      email: 'driver@test.example',
      displayName: 'Test Driver',
      role: DemoRole.driver,
    ),
  );
  state.driverTrip.status = status;
  state.destination = DemoPlace(
    id: 'test-drop-off',
    name: 'Drop-off',
    address: 'Test drop-off',
    coordinate: GeoCoordinate(
      latitude: state.pickup.coordinate.latitude + 0.02,
      longitude: state.pickup.coordinate.longitude,
    ),
  );
  final target = status == DriverTripStatus.accepted
      ? state.pickup.coordinate
      : state.destination!.coordinate;
  state.liveDriverLocation = GeoCoordinate(
    latitude: target.latitude + metersNorth / 111320,
    longitude: target.longitude,
  );
  state.riderConfirmedPickup = riderConsent;
  state.riderRequestedStop = riderConsent;
  final rides = _LiveRide();
  addTearDown(state.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        demoStateProvider.overrideWithValue(state),
        driverScreenAwakeProvider.overrideWithValue((_) async {}),
        if (live) liveRideRepositoryProvider.overrideWithValue(rides),
        notificationsRepositoryProvider.overrideWithValue(_NoNotifications()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const DriverHomeScreen()),
    ),
  );
  await tester.pump();
  return (rides, state);
}

VoidCallback? _onPressed(WidgetTester tester, String label) => tester
    .widget<ArangButton>(find.widgetWithText(ArangButton, label))
    .onPressed;

void main() {
  testWidgets('arrival waits until the driver is within 100 m of the pickup', (
    tester,
  ) async {
    await _pump(tester, status: DriverTripStatus.accepted, metersNorth: 450);
    expect(_onPressed(tester, 'Arrived at Pickup'), isNull);
    expect(
      find.textContaining(RegExp(r'^4[45][0-9] m from the pickup')),
      findsOneWidget,
    );
    expect(find.textContaining('“My driver is here”'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('arrival is open within 100 m and reaches the server', (
    tester,
  ) async {
    final (rides, _) = await _pump(
      tester,
      status: DriverTripStatus.accepted,
      metersNorth: 80,
    );
    expect(_onPressed(tester, 'Arrived at Pickup'), isNotNull);
    expect(find.textContaining('from the pickup'), findsNothing);
    await tester.ensureVisible(find.text('Arrived at Pickup'));
    await tester.tap(find.text('Arrived at Pickup'));
    await tester.pump();
    expect(rides.arrivedCalls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the passenger confirming lifts the arrival distance rule', (
    tester,
  ) async {
    await _pump(
      tester,
      status: DriverTripStatus.accepted,
      metersNorth: 1500,
      riderConsent: true,
    );
    expect(_onPressed(tester, 'Arrived at Pickup'), isNotNull);
    expect(find.text('Your passenger confirmed you are here.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('completion waits until the driver is near the drop-off', (
    tester,
  ) async {
    await _pump(tester, status: DriverTripStatus.inProgress, metersNorth: 1500);
    expect(_onPressed(tester, 'Complete Trip'), isNull);
    expect(find.textContaining('1.5 km from the drop-off'), findsOneWidget);
    expect(find.textContaining('“Stop here”'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('completion is open at the drop-off or after "Stop here"', (
    tester,
  ) async {
    await _pump(tester, status: DriverTripStatus.inProgress, metersNorth: 60);
    expect(_onPressed(tester, 'Complete Trip'), isNotNull);
    await tester.pumpWidget(const SizedBox());

    await _pump(
      tester,
      status: DriverTripStatus.inProgress,
      metersNorth: 1500,
      riderConsent: true,
    );
    expect(_onPressed(tester, 'Complete Trip'), isNotNull);
    expect(find.text('Your passenger asked to stop here.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('demo trips keep both buttons open', (tester) async {
    await _pump(
      tester,
      status: DriverTripStatus.accepted,
      metersNorth: 1500,
      live: false,
    );
    expect(_onPressed(tester, 'Arrived at Pickup'), isNotNull);
    expect(find.textContaining('from the pickup'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
