import 'dart:math';

import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/demo/demo_simulation.dart';
import 'package:arangcada/domain/fare/fare_calculator.dart';
import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:arangcada/features/booking/searching_for_driver_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
