import 'fare_matrix.dart';

class FareQuote {
  const FareQuote({
    required this.unitFareCentavos,
    required this.partyTotalCentavos,
    required this.farePerPassengerCentavos,
    required this.baseFareCentavos,
    required this.additionalDistanceCentavos,
    required this.distanceMeters,
    required this.chargeableKm,
    required this.rideType,
    required this.passengerCount,
    required this.discountClass,
    required this.fareMatrixVersion,
    required this.createdAt,
    this.serviceSupplementCentavos = 0,
    this.systemFeeCentavos = 0,
  });

  /// Per passenger for pooling; per trip for special.
  final int unitFareCentavos;
  final int partyTotalCentavos;
  final int? farePerPassengerCentavos;
  final int baseFareCentavos;
  final int additionalDistanceCentavos;
  final double distanceMeters;
  final int chargeableKm;
  final RideType rideType;
  final int passengerCount;
  final DiscountClass discountClass;
  final String fareMatrixVersion;
  final DateTime createdAt;
  final int serviceSupplementCentavos;
  final int systemFeeCentavos;
  int get driverReceiptsCentavos => partyTotalCentavos - systemFeeCentavos;
}

class FareCalculator {
  const FareCalculator();

  /// What the driver's way to the pickup adds to [trip] for [billedMeters]
  /// beyond the free distance: the matrix's per-kilometre rate for the
  /// rider's fare class, counted by the metre and rounded to the peso, as the
  /// server does (20261016011642). With the most that can be billed, it is
  /// the largest pickup charge, which is what is quoted before booking.
  int pickupChargeCentavos(FareQuote trip, int billedMeters) {
    if (billedMeters <= 0) return 0;
    return (billedMeters * pickupRateCentavos(trip) / 100000).round() * 100;
  }

  /// Centavos per kilometre of the driver's way beyond the free distance.
  int pickupRateCentavos(FareQuote trip) =>
      FareMatrix.incrementPast20Centavos(trip.rideType, trip.discountClass);

  /// Only the excess above the service supplement is added at assignment.
  int maximumPickupExtraCentavos(FareQuote trip, int billedMeters) {
    final pickup = pickupChargeCentavos(trip, billedMeters);
    return pickup > trip.serviceSupplementCentavos
        ? pickup - trip.serviceSupplementCentavos
        : 0;
  }

  FareQuote quote({
    required double distanceMeters,
    required RideType rideType,
    required int passengerCount,
    required DiscountClass discountClass,
    bool appFareEnabled = false,
  }) {
    if (distanceMeters.isNaN ||
        distanceMeters.isInfinite ||
        distanceMeters < 0) {
      throw ArgumentError.value(
        distanceMeters,
        'distanceMeters',
        'Must be finite and non-negative',
      );
    }

    // Calamba City Hall, 31 Aug 2026: the LGU administrator raised the Espesyal
    // operating cap from the ordinance's printed 3 to 4 when pooling was
    // withdrawn as a bookable option. Both ride types now cap at 4.
    //
    // This mirrors fare_matrix.operating_max_passengers server-side. It is a
    // preview convenience only -- compute_fare_centavos() remains the
    // authoritative check, so a tampered client cannot book
    // a fifth passenger by editing this line.
    const maximumPassengers = 4;
    if (passengerCount < 1 || passengerCount > maximumPassengers) {
      throw ArgumentError.value(
        passengerCount,
        'passengerCount',
        'Must be between 1 and $maximumPassengers for ${rideType.name}',
      );
    }

    final chargeableKm = distanceMeters <= 2000
        ? 2
        : (distanceMeters / 1000).ceil();
    final unitFareCentavos = FareMatrix.fareForChargeableKm(
      chargeableKm: chargeableKm,
      rideType: rideType,
      discountClass: discountClass,
    );
    final baseFareCentavos = FareMatrix.fareForChargeableKm(
      chargeableKm: 2,
      rideType: rideType,
      discountClass: discountClass,
    );
    final isPooling = rideType == RideType.pooling;
    final appFare = appFareEnabled && !isPooling;
    final discounted = discountClass == DiscountClass.discounted;
    final premium = appFare
        ? (passengerCount <= 2
              ? 1000
              : passengerCount == 3
              ? 1500
              : 2000)
        : 0;
    final supplement = discounted ? premium * 4 ~/ 5 : premium;
    final systemFee = appFare ? (discounted ? 400 : 500) : 0;

    return FareQuote(
      unitFareCentavos: unitFareCentavos,
      partyTotalCentavos: isPooling
          ? unitFareCentavos * passengerCount
          : unitFareCentavos + supplement + systemFee,
      farePerPassengerCentavos: isPooling ? unitFareCentavos : null,
      baseFareCentavos: baseFareCentavos,
      additionalDistanceCentavos: unitFareCentavos - baseFareCentavos,
      distanceMeters: distanceMeters,
      chargeableKm: chargeableKm,
      rideType: rideType,
      passengerCount: passengerCount,
      discountClass: discountClass,
      fareMatrixVersion: appFare ? 'app-fare-v1' : FareMatrix.version,
      createdAt: DateTime.now().toUtc(),
      serviceSupplementCentavos: supplement,
      systemFeeCentavos: systemFee,
    );
  }
}
