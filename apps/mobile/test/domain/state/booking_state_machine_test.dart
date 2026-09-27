import 'package:arangcada/domain/fare/fare_calculator.dart';
import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FareQuote quote() => const FareCalculator().quote(
    distanceMeters: 2400,
    rideType: RideType.special,
    passengerCount: 1,
    discountClass: DiscountClass.full,
  );

  DemoBooking draft() => DemoBooking.draft(
    pickupName: 'Calamba Crossing Terminal',
    destinationName: 'Calamba City Hall',
    rideType: RideType.special,
    passengerCount: 1,
    userFareClass: UserFareClass.regular,
    paymentMethod: PaymentMethod.cash,
    fareQuote: quote(),
  );

  test('all user fare classes map onto the published fare columns', () {
    expect(UserFareClass.regular.discountClass, DiscountClass.full);
    expect(UserFareClass.student.discountClass, DiscountClass.discounted);
    expect(UserFareClass.seniorCitizen.discountClass, DiscountClass.discounted);
    expect(UserFareClass.pwd.discountClass, DiscountClass.discounted);
  });

  test('booking mutation after confirmation throws', () {
    final booking = draft()..confirm();

    expect(
      () => booking.changePaymentMethod(PaymentMethod.cash),
      throwsStateError,
    );
  });

  test('booking state machine accepts its legal path', () {
    final booking = draft()
      ..confirm()
      ..beginSearching()
      ..matchDriver()
      ..beginDriverApproach()
      ..startTrip()
      ..completeTrip();

    expect(booking.status, BookingStatus.completed);
  });

  test('booking state machine rejects completion before trip start', () {
    final booking = draft()..confirm();

    expect(booking.completeTrip, throwsStateError);
  });
}
