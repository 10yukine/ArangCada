import 'dart:async';

import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/domain/fare/fare_calculator.dart';
import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:arangcada/features/booking/booking_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingRide implements SupabaseRideRepository {
  final request = Completer<void>();
  int calls = 0;
  @override
  Future<void> requestRide(DemoBooking booking) {
    calls++;
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'confirmation stays reachable and ignores duplicate taps while sending',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = DemoState();
      addTearDown(state.dispose);
      state.setActiveBooking(
        DemoBooking.draft(
          pickupName: 'A long pickup address in Calamba City',
          destinationName: 'A long destination address near the city centre',
          rideType: RideType.special,
          passengerCount: 4,
          userFareClass: UserFareClass.regular,
          paymentMethod: PaymentMethod.cash,
          fareQuote: const FareCalculator().quote(
            distanceMeters: 2400,
            rideType: RideType.special,
            passengerCount: 4,
            discountClass: DiscountClass.full,
          ),
        ),
      );
      final rides = _PendingRide();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            demoStateProvider.overrideWithValue(state),
            liveRideRepositoryProvider.overrideWithValue(rides),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const BookingReviewScreen(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Digital'), 200);
      final paymentOptions = tester.widget<SegmentedButton<PaymentMethod>>(
        find.byType(SegmentedButton<PaymentMethod>),
      );
      expect(
        paymentOptions.segments.singleWhere(
          (segment) => segment.value == PaymentMethod.digital,
        ).enabled,
        isFalse,
      );
      expect(find.text('Confirm Booking').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Confirm Booking'));
      await tester.tap(find.text('Confirm Booking'));
      await tester.pump();
      expect(rides.calls, 1);
      expect(find.text('Sending request…'), findsOneWidget);
      rides.request.completeError(
        StateError('Request unavailable. Try again.'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Request unavailable. Try again.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
