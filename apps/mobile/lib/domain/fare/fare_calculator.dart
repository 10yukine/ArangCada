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
}

class FareCalculator {
  const FareCalculator();

  FareQuote quote({
    required double distanceMeters,
    required RideType rideType,
    required int passengerCount,
    required DiscountClass discountClass,
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

    final maximumPassengers = rideType == RideType.pooling ? 4 : 3;
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

    return FareQuote(
      unitFareCentavos: unitFareCentavos,
      partyTotalCentavos: isPooling
          ? unitFareCentavos * passengerCount
          : unitFareCentavos,
      farePerPassengerCentavos: isPooling ? unitFareCentavos : null,
      baseFareCentavos: baseFareCentavos,
      additionalDistanceCentavos: unitFareCentavos - baseFareCentavos,
      distanceMeters: distanceMeters,
      chargeableKm: chargeableKm,
      rideType: rideType,
      passengerCount: passengerCount,
      discountClass: discountClass,
      fareMatrixVersion: FareMatrix.version,
      createdAt: DateTime.now().toUtc(),
    );
  }
}
