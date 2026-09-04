import 'dart:math';

import 'package:arangcada/core/widgets/sos_hold_button.dart';
import 'package:arangcada/demo/demo_simulation.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/domain/fare/fare_calculator.dart';
import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:arangcada/features/trip/active_trip_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// SOS must be reachable without a gesture.
///
/// It was not. Chat, Call and SOS all lived inside the sheet's expanded branch,
/// so a rider had to notice the sheet could be dragged, and then drag it,
/// before they could report an emergency from inside a stranger's vehicle. That
/// is not a safety control; it is a safety control with a puzzle in front of it.
///
/// This asserts the collapsed state specifically, because the expanded state
/// always looked fine and that is exactly why it survived review.
void main() {
  DemoBooking inProgressBooking() =>
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
        ..beginSearching()
        ..matchDriver()
        ..beginDriverApproach()
        ..startTrip();

  Widget harness(DemoState state) => ProviderScope(
    overrides: [demoStateProvider.overrideWithValue(state)],
    child: const MaterialApp(home: ActiveTripScreen()),
  );

  testWidgets('SOS, Chat and Call are reachable without expanding the sheet', (
    tester,
  ) async {
    final state = DemoState();
    addTearDown(state.dispose);
    // The screen draws a route to state.destination and dereferences it, so a
    // booking alone is not enough to render.
    state.setDestination(DemoData.places[1]);
    state.setActiveBooking(inProgressBooking());

    await tester.pumpWidget(harness(state));
    await tester.pump();

    // No drag, no tap on the handle. This is the sheet as it first appears.
    expect(
      find.byType(SosHoldButton),
      findsOneWidget,
      reason:
          'SOS behind a drag gesture is unreachable at the moment it is needed',
    );
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
  });

  testWidgets('the fare detail stays behind the expand, unlike the controls', (
    tester,
  ) async {
    final state = DemoState();
    addTearDown(state.dispose);
    // The screen draws a route to state.destination and dereferences it, so a
    // booking alone is not enough to render.
    state.setDestination(DemoData.places[1]);
    state.setActiveBooking(inProgressBooking());

    await tester.pumpWidget(harness(state));
    await tester.pump();

    // The split is deliberate: urgent controls always, reading matter on
    // demand. If this ever finds the fare line collapsed, the peek has grown
    // back into a second full screen and the distinction has been lost.
    expect(
      find.textContaining('fare locked'),
      findsNothing,
      reason: 'detail belongs in the expanded state, not the peek',
    );
  });

  testWidgets('the finish button is reachable on arrival without expanding', (
    tester,
  ) async {
    // The sheet used to throw itself open the moment the ride ended, because
    // the finish button lived in the expanded branch and something had to
    // reveal it. The owner disliked a panel moving under their thumb, so the
    // button moved out instead. This asserts the button is reachable WITHOUT
    // that shove -- if it ever returns to the expanded branch, the temptation
    // to re-add the auto-expand comes back with it.
    final state = DemoState();
    addTearDown(state.dispose);
    state.setDestination(DemoData.places[1]);
    state.setActiveBooking(inProgressBooking());

    // A simulation that reaches the destination almost immediately, so the
    // arrival state can be observed without a real 10-second trip.
    final simulation = DemoSimulationService(
      durations: const DemoSimulationDurations(
        tripMin: Duration(milliseconds: 5),
        tripMax: Duration(milliseconds: 5),
      ),
      random: Random(3),
    );
    addTearDown(simulation.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          demoSimulationServiceProvider.overrideWithValue(simulation),
        ],
        child: const MaterialApp(home: ActiveTripScreen()),
      ),
    );
    await tester.pump();

    // Not arrived yet: the finish button has nothing to finish.
    expect(find.textContaining("I've arrived"), findsNothing);

    await tester.pump(const Duration(milliseconds: 40));

    expect(
      find.textContaining("I've arrived"),
      findsOneWidget,
      reason: 'arrival must surface the finish button in the collapsed sheet',
    );

    // It takes the slot Chat and Call had rather than being appended, so the
    // peek does not grow into a four-button stack at the moment the rider is
    // paying and getting out.
    expect(find.text('Chat'), findsNothing);
    expect(find.text('Call'), findsNothing);

    // SOS outlives arrival. The rider is still at the vehicle while they pay,
    // and "SOS starts where the ride does" must not be read as "and ends the
    // instant the wheels stop".
    expect(
      find.byType(SosHoldButton),
      findsOneWidget,
      reason: 'the safety control must not disappear on arrival',
    );
  });
}
