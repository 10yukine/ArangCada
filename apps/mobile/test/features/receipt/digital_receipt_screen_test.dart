import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/mock/mock_fare_repository.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:arangcada/features/receipt/digital_receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> render(
    WidgetTester tester,
    PaymentMethod payment, {
    int pickupChargeCentavos = 0,
    int? pickupDistanceMeters,
  }) async {
    final quote = const MockFareRepository().quote(
      distanceMeters: 1000,
      rideType: RideType.special,
      passengerCount: 1,
      discountClass: DiscountClass.full,
    );
    final booking =
        DemoBooking.draft(
            pickupName: 'Current location',
            destinationName: 'SM City Calamba',
            rideType: RideType.special,
            passengerCount: 1,
            userFareClass: UserFareClass.regular,
            paymentMethod: payment,
            fareQuote: quote,
          )
          ..status = BookingStatus.completed
          ..pickupChargeCentavos = pickupChargeCentavos
          ..pickupDistanceMeters = pickupDistanceMeters;
    final state = DemoState()..activeBooking = booking;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [demoStateProvider.overrideWithValue(state)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const DigitalReceiptScreen(),
        ),
      ),
    );
  }

  testWidgets('receipt states cash and nothing about sandbox money', (
    tester,
  ) async {
    await render(tester, PaymentMethod.cash);

    expect(find.text('Cash'), findsOneWidget);
    expect(find.textContaining('sandbox'), findsNothing);
    expect(find.textContaining('balance'), findsNothing);
  });

  testWidgets('the receipt lists a pickup charge with the driver distance', (
    tester,
  ) async {
    await render(tester, PaymentMethod.cash);
    expect(find.textContaining('Pickup charge'), findsNothing);

    await render(
      tester,
      PaymentMethod.cash,
      pickupChargeCentavos: 1000,
      pickupDistanceMeters: 1800,
    );
    expect(find.text('Pickup charge · driver 1.8 km away'), findsOneWidget);
    expect(find.text('₱10.00'), findsOneWidget);
  });

  // Asserted as an absence on purpose. The receipt renders after the rating
  // step has already been answered or deliberately skipped, so a route back
  // into it made a skip look like it had failed to register. Two earlier
  // attempts to remove this button came back -- once relabelled 'View
  // Rating', once kept only in the unrated branch -- which is exactly the
  // shape of regression a positive test cannot catch.
  testWidgets('the receipt offers no route back into the rating flow', (
    tester,
  ) async {
    await render(tester, PaymentMethod.cash);

    expect(find.text('Rate This Ride'), findsNothing);
    expect(find.textContaining('Rating'), findsNothing);
    expect(find.text('Back to Home'), findsOneWidget);
  });
}
