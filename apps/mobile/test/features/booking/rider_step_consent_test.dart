import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/domain/fare/fare_calculator.dart';
import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:arangcada/features/booking/driver_matched_screen.dart';
import 'package:arangcada/features/trip/active_trip_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _LiveRide implements SupabaseRideRepository {
  int confirmCalls = 0;
  int stopCalls = 0;

  @override
  Map<String, dynamic>? get activeTrip => null;

  @override
  Future<void> confirmDriverHere() async => confirmCalls++;

  @override
  Future<void> requestStopHere() async => stopCalls++;

  int keepRidingCalls = 0;
  @override
  Future<void> cancelStopRequest() async => keepRidingCalls++;

  @override
  Future<void> checkRiderDestinationArrival() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DemoBooking _booking(BookingStatus status) {
  final booking = DemoBooking.draft(
    pickupName: 'Pickup',
    destinationName: 'Destination',
    rideType: RideType.special,
    passengerCount: 1,
    userFareClass: UserFareClass.regular,
    paymentMethod: PaymentMethod.cash,
    fareQuote: const FareCalculator().quote(
      distanceMeters: 2400,
      rideType: RideType.special,
      passengerCount: 1,
      discountClass: DiscountClass.full,
    ),
  );
  return booking
    ..status = status
    ..driverAcceptedAt = DateTime.now().toUtc();
}

Future<(_LiveRide, DemoState)> _pump(
  WidgetTester tester,
  Widget screen,
  BookingStatus status, {
  bool live = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = DemoState();
  final rides = _LiveRide();
  addTearDown(state.dispose);
  state.setDestination(DemoData.places[1]);
  state.setActiveBooking(_booking(status));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        demoStateProvider.overrideWithValue(state),
        if (live) liveRideRepositoryProvider.overrideWithValue(rides),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pump();
  return (rides, state);
}

void main() {
  testWidgets('"My driver is here" asks first, then tells the server once', (
    tester,
  ) async {
    final (rides, state) = await _pump(
      tester,
      DriverMatchedScreen(now: () => DateTime.now().toUtc()),
      BookingStatus.approaching,
    );

    await tester.tap(find.text('My driver is here'));
    await tester.pumpAndSettle();
    expect(find.text('Is your driver here?'), findsOneWidget);
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    expect(rides.confirmCalls, 0);

    await tester.tap(find.text('My driver is here'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, they are here'));
    await tester.pumpAndSettle();
    expect(rides.confirmCalls, 1);

    state.riderConfirmedPickup = true;
    state.bookingChanged();
    await tester.pump();
    final done = find.widgetWithText(
      OutlinedButton,
      'You confirmed your driver is here',
    );
    expect(tester.widget<OutlinedButton>(done).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('demo waits have no "My driver is here"', (tester) async {
    await _pump(
      tester,
      DriverMatchedScreen(now: () => DateTime.now().toUtc()),
      BookingStatus.approaching,
      live: false,
    );
    expect(find.text('My driver is here'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    '"Get off early" asks first, tells the server once, and can be taken back',
    (tester) async {
      final (rides, state) = await _pump(
        tester,
        const ActiveTripScreen(),
        BookingStatus.inProgress,
      );

      await tester.tap(find.text('Get off early'));
      await tester.pumpAndSettle();
      expect(find.text('Get off early?'), findsOneWidget);
      await tester.tap(find.text('Keep riding'));
      await tester.pumpAndSettle();
      expect(rides.stopCalls, 0);

      await tester.tap(find.text('Get off early'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Get off early'));
      await tester.pumpAndSettle();
      expect(rides.stopCalls, 1);

      state.riderRequestedStop = true;
      state.bookingChanged();
      await tester.pump();
      expect(find.text('Get off early'), findsNothing);
      expect(
        find.text(
          'You asked to get off early. Your driver will end the trip where it '
          'is safe to stop.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Keep riding'));
      await tester.pump();
      expect(rides.keepRidingCalls, 1);
      state.riderRequestedStop = false;
      state.bookingChanged();
      await tester.pump();
      expect(find.text('Get off early'), findsOneWidget);
      expect(find.text('Keep riding'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('demo trips have no "Get off early"', (tester) async {
    await _pump(
      tester,
      const ActiveTripScreen(),
      BookingStatus.inProgress,
      live: false,
    );
    expect(find.text('Get off early'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
