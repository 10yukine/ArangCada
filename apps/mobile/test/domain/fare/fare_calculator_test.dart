import 'package:arangcada/domain/fare/fare_calculator.dart';
import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calculator = FareCalculator();

  FareQuote quote({
    required double distanceMeters,
    RideType rideType = RideType.pooling,
    int passengerCount = 1,
    DiscountClass discountClass = DiscountClass.full,
  }) {
    return calculator.quote(
      distanceMeters: distanceMeters,
      rideType: rideType,
      passengerCount: passengerCount,
      discountClass: discountClass,
    );
  }

  group('started-kilometre boundaries', () {
    const cases = <(double, int)>[
      (0, 2),
      (2000, 2),
      (2000.001, 3),
      (2001, 3),
      (2999.999, 3),
      (3000, 3),
      (3000.001, 4),
      (19999.999, 20),
      (20000, 20),
      (20000.001, 21),
      (21000, 21),
      (21000.001, 22),
    ];

    for (final (distance, expectedKm) in cases) {
      test('$distance m bills the $expectedKm km row', () {
        expect(quote(distanceMeters: distance).chargeableKm, expectedKm);
      });
    }
  });

  test('20000.001 m extrapolates all four fare tables exactly', () {
    expect(quote(distanceMeters: 20000.001).unitFareCentavos, 5300);
    expect(
      quote(
        distanceMeters: 20000.001,
        discountClass: DiscountClass.discounted,
      ).unitFareCentavos,
      4260,
    );
    expect(
      quote(
        distanceMeters: 20000.001,
        rideType: RideType.special,
      ).unitFareCentavos,
      21200,
    );
    expect(
      quote(
        distanceMeters: 20000.001,
        rideType: RideType.special,
        discountClass: DiscountClass.discounted,
      ).unitFareCentavos,
      16940,
    );
  });

  test('special base is P60 per trip for 1, 2, and 3 passengers', () {
    for (final passengerCount in [1, 2, 3]) {
      final result = quote(
        distanceMeters: 2000,
        rideType: RideType.special,
        passengerCount: passengerCount,
      );
      expect(result.unitFareCentavos, 6000);
      expect(result.partyTotalCentavos, 6000);
      expect(result.farePerPassengerCentavos, isNull);
    }
  });

  test('pooling for 3 passengers is 3x the per-passenger fare', () {
    final result = quote(distanceMeters: 2000, passengerCount: 3);
    expect(result.farePerPassengerCentavos, 1500);
    expect(result.unitFareCentavos, 1500);
    expect(result.partyTotalCentavos, 4500);
  });

  group('passenger limits', () {
    test('pooling accepts min and max', () {
      expect(quote(distanceMeters: 0, passengerCount: 1), isA<FareQuote>());
      expect(quote(distanceMeters: 0, passengerCount: 4), isA<FareQuote>());
    });

    test('pooling rejects zero, negative, and max plus one', () {
      for (final count in [0, -1, 5]) {
        expect(
          () => quote(distanceMeters: 0, passengerCount: count),
          throwsArgumentError,
        );
      }
    });

    test('special accepts min and max', () {
      expect(
        quote(distanceMeters: 0, rideType: RideType.special),
        isA<FareQuote>(),
      );
      expect(
        quote(distanceMeters: 0, rideType: RideType.special, passengerCount: 3),
        isA<FareQuote>(),
      );
    });

    test('special rejects zero, negative, and max plus one', () {
      for (final count in [0, -1, 4]) {
        expect(
          () => quote(
            distanceMeters: 0,
            rideType: RideType.special,
            passengerCount: count,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  test('rejects NaN, infinity, and negative distance', () {
    for (final distance in [double.nan, double.infinity, -0.001]) {
      expect(() => quote(distanceMeters: distance), throwsArgumentError);
    }
  });
}
