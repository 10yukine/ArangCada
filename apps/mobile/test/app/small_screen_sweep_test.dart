import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/location_repository.dart';
import 'package:arangcada/data/repositories/notifications_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/domain/fare/fare_calculator.dart';
import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:arangcada/domain/models/app_notification.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/auth/login_screen.dart';
import 'package:arangcada/features/auth/sign_up_screen.dart';
import 'package:arangcada/features/auth/verify_phone_screen.dart';
import 'package:arangcada/features/booking/booking_review_screen.dart';
import 'package:arangcada/features/booking/ride_options_screen.dart';
import 'package:arangcada/features/driver/driver_earnings_screen.dart';
import 'package:arangcada/features/driver/driver_screens.dart';
import 'package:arangcada/features/fare/fare_matrix_screen.dart';
import 'package:arangcada/features/home/commuter_home_screen.dart';
import 'package:arangcada/features/profile/delete_account_screen.dart';
import 'package:arangcada/features/profile/profile_screen.dart';
import 'package:arangcada/features/rating/driver_app_feedback_screen.dart';
import 'package:arangcada/features/rating/rating_screen.dart';
import 'package:arangcada/features/receipt/digital_receipt_screen.dart';
import 'package:arangcada/features/search/destination_search_screen.dart';
import 'package:arangcada/features/trips/trips_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Loc extends LocationRepository {
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<LocationFix> currentLocation() async => LocationFix(
    coordinate: const GeoCoordinate(latitude: 14.2085, longitude: 121.1555),
    accuracyMeters: 18,
    timestamp: DateTime.utc(2026, 9, 28),
  );
}

class _NoNotes implements NotificationsRepository {
  @override
  List<AppNotificationRecord> history() => const [];
  @override
  Future<void> markRead(String id) async {}
}

DemoBooking _booking({bool completed = false}) {
  final booking = DemoBooking.draft(
    pickupName: 'Current location',
    destinationName: 'SM City Calamba, National Highway',
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
  );
  if (completed) booking.status = BookingStatus.completed;
  return booking;
}

DemoState _state(DemoRole role, {DemoBooking? booking}) {
  final state = DemoState(
    initialUser: DemoUser(
      email: 'sweep@example.com',
      displayName: 'Maria Clara Santos-Dela Cruz',
      role: role,
      mobileNumber: '+639171234567',
      phoneVerified: role == DemoRole.driver,
    ),
  );
  state.setPickup(
    const DemoPlace(
      id: 'gps',
      name: 'Current location',
      address: '',
      coordinate: GeoCoordinate(latitude: 14.2085, longitude: 121.1555),
    ),
  );
  state.setDestination(DemoData.places[3]);
  if (booking != null) state.setActiveBooking(booking);
  return state;
}

/// Every key screen at the smallest supported phone (320 x 640) with the
/// app's 1.3x text ceiling. A RenderFlex overflow or any other build error
/// fails the screen by name.
void main() {
  final screens = <String, (DemoRole, DemoBooking?, Widget)>{
    'login': (DemoRole.commuter, null, const LoginScreen()),
    'sign up': (DemoRole.commuter, null, const SignUpScreen()),
    'verify phone': (DemoRole.commuter, null, const VerifyPhoneScreen()),
    'commuter home': (DemoRole.commuter, null, const CommuterHomeScreen()),
    'destination search': (
      DemoRole.commuter,
      null,
      const DestinationSearchScreen(),
    ),
    'ride options': (DemoRole.commuter, null, const RideOptionsScreen()),
    'booking review': (
      DemoRole.commuter,
      _booking(),
      const BookingReviewScreen(),
    ),
    'rating': (
      DemoRole.commuter,
      _booking(completed: true),
      const RatingScreen(),
    ),
    'receipt': (
      DemoRole.commuter,
      _booking(completed: true),
      const DigitalReceiptScreen(),
    ),
    'trips': (DemoRole.commuter, null, const TripsScreen()),
    'profile': (DemoRole.commuter, null, const ProfileScreen()),
    'fare matrix': (DemoRole.commuter, null, const FareMatrixScreen()),
    'driver home': (DemoRole.driver, null, const DriverHomeScreen()),
    'driver earnings': (DemoRole.driver, null, const DriverEarningsScreen()),
    'driver app feedback': (
      DemoRole.driver,
      null,
      const DriverAppFeedbackScreen(),
    ),
    'delete account': (DemoRole.commuter, null, const DeleteAccountScreen()),
  };

  for (final MapEntry(key: name, value: (role, booking, screen))
      in screens.entries) {
    testWidgets('$name fits 320x640 at 1.3x text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = _state(role, booking: booking);
      addTearDown(state.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            demoStateProvider.overrideWithValue(state),
            locationRepositoryProvider.overrideWithValue(_Loc()),
            notificationsRepositoryProvider.overrideWithValue(_NoNotes()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: screen,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: name);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
