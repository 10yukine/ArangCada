import '../fare/fare_calculator.dart';
import '../fare/fare_matrix.dart';

enum UserFareClass { regular, student, seniorCitizen, pwd }

extension UserFareClassDetails on UserFareClass {
  String get label => switch (this) {
    UserFareClass.regular => 'Regular',
    UserFareClass.student => 'Student',
    UserFareClass.seniorCitizen => 'Senior Citizen',
    UserFareClass.pwd => 'PWD',
  };

  DiscountClass get discountClass => this == UserFareClass.regular
      ? DiscountClass.full
      : DiscountClass.discounted;
}

enum PaymentMethod { cash, digital }

extension PaymentMethodDetails on PaymentMethod {
  String get label => switch (this) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.digital => 'Digital balance',
  };
}

enum BookingStatus {
  draft,
  confirmed,
  searching,
  matched,
  approaching,
  inProgress,
  completed,
  cancelled,
}

/// Mutable only while [status] is [BookingStatus.draft].
///
/// Once confirmed, the fare-bearing snapshot is locked and the object may
/// only move through explicit state-machine transitions.
class DemoBooking {
  DemoBooking.draft({
    required this.pickupName,
    required this.destinationName,
    required this.rideType,
    required this.passengerCount,
    required this.userFareClass,
    required this.paymentMethod,
    required this.fareQuote,
  });

  final String pickupName;
  final String destinationName;
  RideType rideType;
  int passengerCount;
  UserFareClass userFareClass;
  PaymentMethod paymentMethod;
  FareQuote fareQuote;
  BookingStatus status = BookingStatus.draft;
  String? receiptReference;

  bool get isFareLocked => status != BookingStatus.draft;

  void changePaymentMethod(PaymentMethod value) {
    _ensureDraft();
    paymentMethod = value;
  }

  void changeFareSelection({
    required RideType rideType,
    required int passengerCount,
    required UserFareClass userFareClass,
    required FareQuote fareQuote,
  }) {
    _ensureDraft();
    this.rideType = rideType;
    this.passengerCount = passengerCount;
    this.userFareClass = userFareClass;
    this.fareQuote = fareQuote;
  }

  void confirm() => _transition(BookingStatus.draft, BookingStatus.confirmed);

  void beginSearching() =>
      _transition(BookingStatus.confirmed, BookingStatus.searching);

  void matchDriver() =>
      _transition(BookingStatus.searching, BookingStatus.matched);

  void beginDriverApproach() =>
      _transition(BookingStatus.matched, BookingStatus.approaching);

  void startTrip() =>
      _transition(BookingStatus.approaching, BookingStatus.inProgress);

  void completeTrip() =>
      _transition(BookingStatus.inProgress, BookingStatus.completed);

  void cancelSearching() =>
      _transition(BookingStatus.searching, BookingStatus.cancelled);

  void _ensureDraft() {
    if (status != BookingStatus.draft) {
      throw StateError('Confirmed booking details and fare are locked.');
    }
  }

  void _transition(BookingStatus requiredStatus, BookingStatus nextStatus) {
    if (status != requiredStatus) {
      throw StateError(
        'Cannot move booking from ${status.name} to ${nextStatus.name}.',
      );
    }
    status = nextStatus;
  }
}
