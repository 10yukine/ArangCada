import 'dart:math';

import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/demo/demo_simulation.dart';
import 'package:arangcada/domain/fare/fare_calculator.dart';
import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:arangcada/features/booking/searching_for_driver_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('live search retries dispatch as drivers come online', (
    tester,
  ) async {
    final state = DemoState();
    final booking =
        DemoBooking.draft(
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
          )
          ..confirm()
          ..beginSearching();
    state.setActiveBooking(booking);
    final rides = _SearchingRide();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          liveRideRepositoryProvider.overrideWithValue(rides),
        ],
        child: const MaterialApp(home: SearchingForDriverScreen()),
      ),
    );
    await tester.pump();
    expect(rides.retryCalls, 1);

    await tester.pump(const Duration(seconds: 15));
    expect(rides.retryCalls, 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
    expect(rides.retryCalls, 2);
  });

  testWidgets('live search reports when the widened search finds no driver', (
    tester,
  ) async {
    final state = DemoState();
    final booking =
        DemoBooking.draft(
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
          )
          ..confirm()
          ..beginSearching();
    state.setActiveBooking(booking);
    final rides = _SearchingRide();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          liveRideRepositoryProvider.overrideWithValue(rides),
        ],
        child: const MaterialApp(home: SearchingForDriverScreen()),
      ),
    );

    rides.status = 'no_driver_available';
    booking.status = BookingStatus.cancelled;
    state.bookingChanged();
    await tester.pump();
    expect(find.text('No drivers available right now'), findsOneWidget);
    expect(find.text('Book another ride'), findsOneWidget);
  });

  testWidgets('live search closes an overdue driver offer', (tester) async {
    final state = DemoState();
    final booking =
        DemoBooking.draft(
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
          )
          ..confirm()
          ..beginSearching();
    state.setActiveBooking(booking);
    final rides = _SearchingRide()..status = 'driver_assigned';
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          liveRideRepositoryProvider.overrideWithValue(rides),
        ],
        child: const MaterialApp(home: SearchingForDriverScreen()),
      ),
    );
    await tester.pump();
    expect(rides.expireCalls, 1);
    expect(rides.retryCalls, 0);
  });

  testWidgets(
    'booking advances from searching to matched when the timer fires',
    (tester) async {
      final state = DemoState();
      final booking =
          DemoBooking.draft(
              pickupName: 'Calamba Crossing Terminal',
              destinationName: 'Calamba City Hall',
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
            )
            ..confirm()
            ..beginSearching();
      state.setActiveBooking(booking);

      final simulation = DemoSimulationService(
        durations: const DemoSimulationDurations(
          driverMatchMin: Duration(milliseconds: 5),
          driverMatchMax: Duration(milliseconds: 5),
        ),
        random: Random(7),
      );
      addTearDown(simulation.dispose);
      addTearDown(state.dispose);

      var matchedCallbackRan = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            demoStateProvider.overrideWithValue(state),
            demoSimulationServiceProvider.overrideWithValue(simulation),
          ],
          child: MaterialApp(
            home: SearchingForDriverScreen(
              onMatched: () => matchedCallbackRan = true,
            ),
          ),
        ),
      );

      expect(booking.status, BookingStatus.searching);
      expect(find.text('Cancel ride request'), findsOneWidget);
      expect(find.textContaining('Simulate Driver Match'), findsNothing);

      await tester.pump(const Duration(milliseconds: 4));
      expect(booking.status, BookingStatus.searching);

      await tester.pump(const Duration(milliseconds: 1));
      expect(booking.status, BookingStatus.matched);
      expect(matchedCallbackRan, isTrue);
    },
  );
}

class _SearchingRide implements SupabaseRideRepository {
  int retryCalls = 0;
  int expireCalls = 0;
  String status = 'searching_driver';

  @override
  Map<String, dynamic>? get activeTrip => {
    'id': 'test-trip',
    'status': status,
    'accept_by': '2020-01-01T00:00:00Z',
  };

  @override
  Future<void> retryDispatch() async => retryCalls++;

  @override
  Future<void> expireRide() async => expireCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
