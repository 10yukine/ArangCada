import 'dart:async';

import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/domain/fare/fare_calculator.dart';
import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:arangcada/features/booking/driver_matched_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('cancellation deadline survives remount and background time', (
    tester,
  ) async {
    final state = DemoState();
    final rides = _LiveRide();
    addTearDown(state.dispose);
    var now = DateTime.utc(2026, 9, 23, 12);
    state.setActiveBooking(
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
        ..status = BookingStatus.approaching
        ..driverAcceptedAt = now.subtract(const Duration(seconds: 40)),
    );
    Widget screen() => ProviderScope(
      overrides: [
        demoStateProvider.overrideWithValue(state),
        liveRideRepositoryProvider.overrideWithValue(rides),
      ],
      child: MaterialApp(home: DriverMatchedScreen(now: () => now)),
    );
    await tester.pumpWidget(screen());
    await tester.pump();
    expect(find.text('Cancel ride · 0:20'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    now = now.add(const Duration(seconds: 10));
    await tester.pumpWidget(screen());
    await tester.pump();
    expect(find.text('Cancel ride · 0:10'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 15));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Cancellation window has expired'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Cancellation window has expired'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'failed cancellation keeps its deadline and permits a safe retry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final state = DemoState();
      final rides = _LiveRide();
      var now = DateTime.now().toUtc();
      addTearDown(state.dispose);
      state.setDestination(DemoData.places[1]);
      state.setActiveBooking(
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
          ..beginSearching()
          ..matchDriver(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            demoStateProvider.overrideWithValue(state),
            liveRideRepositoryProvider.overrideWithValue(rides),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: DriverMatchedScreen(now: () => now),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Message'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Message').hitTestable(), findsOneWidget);
      expect(find.text('Call').hitTestable(), findsOneWidget);
      for (final error in [Exception('offline'), StateError('rejected')]) {
        await tester.tap(find.textContaining('Cancel ride ·'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel Ride'));
        await tester.pumpAndSettle();
        expect(find.text('Cancelling ride…'), findsOneWidget);
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Cancelling ride…'),
              )
              .onPressed,
          isNull,
        );
        rides.pending.completeError(error);
        await tester.pumpAndSettle();
        expect(find.textContaining('Cancel ride ·'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // The error snackbar temporarily covers the bottom cancellation button.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      expect(rides.calls, 2);
      // Confirmation cannot keep an expired cancellation window open.
      await tester.tap(find.textContaining('Cancel ride ·'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 65));
      await tester.pump(const Duration(seconds: 65));
      await tester.tap(find.text('Cancel Ride'));
      await tester.pumpAndSettle();
      expect(rides.calls, 2);
      expect(find.text('Cancellation window has expired'), findsOneWidget);
    },
  );

  for (final hasBooking in [true, false]) {
    testWidgets('waiting screen recovers when booking exists: $hasBooking', (
      tester,
    ) async {
      final state = DemoState();
      addTearDown(state.dispose);
      state.setDestination(DemoData.places[1]);
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
            ..beginSearching()
            ..matchDriver();
      if (hasBooking) state.setActiveBooking(booking);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DriverMatchedScreen()),
          GoRoute(
            path: '/trips',
            builder: (_, _) => const Scaffold(body: Text('Trip history')),
          ),
          GoRoute(
            path: '/trip/active',
            builder: (_, _) =>
                const Scaffold(body: Text('Unexpected active ride')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            demoStateProvider.overrideWithValue(state),
            liveRideRepositoryProvider.overrideWithValue(_LiveRide()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      if (hasBooking) {
        booking.status = BookingStatus.cancelled;
        state.bookingChanged();
      }
      await tester.pumpAndSettle();
      expect(
        find.text(hasBooking ? 'Ride cancelled' : 'No driver on the way'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 65));
      expect(find.text('Unexpected active ride'), findsNothing);
      await tester.tap(find.text('View trips'));
      await tester.pumpAndSettle();
      expect(find.text('Trip history'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _LiveRide implements SupabaseRideRepository {
  int calls = 0;
  late Completer<void> pending;
  @override
  Future<void> cancelRide() {
    calls++;
    pending = Completer<void>();
    return pending.future;
  }

  @override
  Map<String, dynamic>? get activeTrip => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
