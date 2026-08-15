enum RideType { pooling, special }

enum DiscountClass { full, discounted }

/// City Ordinance No. 743, s. 2022, transcribed in integer centavos.
///
/// Rows through 20 km are published values, never formula-generated. In
/// particular, the two printed Regular discount anomalies remain literal.
abstract final class FareMatrix {
  static const String version = 'ord-743-s2022';
  static const int printedMaxKm = 20;

  static const Map<int, int> poolingFullCentavos = {
    2: 1500,
    3: 1700,
    4: 1900,
    5: 2100,
    6: 2300,
    7: 2500,
    8: 2700,
    9: 2900,
    10: 3100,
    11: 3300,
    12: 3500,
    13: 3700,
    14: 3900,
    15: 4100,
    16: 4300,
    17: 4500,
    18: 4700,
    19: 4900,
    20: 5100,
  };

  static const Map<int, int> poolingDiscountedCentavos = {
    2: 1200,
    3: 1350,
    4: 1550,
    5: 1700,
    6: 1850,
    7: 2000,
    8: 2200,
    9: 2300,
    10: 2500,
    11: 2650,
    12: 2800,
    13: 3000,
    14: 3150,
    15: 3300,
    16: 3400,
    17: 3600,
    18: 3750,
    19: 3900,
    20: 4100,
  };

  static const Map<int, int> specialFullCentavos = {
    2: 6000,
    3: 6800,
    4: 7600,
    5: 8400,
    6: 9200,
    7: 10000,
    8: 10800,
    9: 11600,
    10: 12400,
    11: 13200,
    12: 14000,
    13: 14800,
    14: 15600,
    15: 16400,
    16: 17200,
    17: 18000,
    18: 18800,
    19: 19600,
    20: 20400,
  };

  static const Map<int, int> specialDiscountedCentavos = {
    2: 4800,
    3: 5400,
    4: 6100,
    5: 6700,
    6: 7400,
    7: 8000,
    8: 8600,
    9: 9300,
    10: 9900,
    11: 10600,
    12: 11200,
    13: 11800,
    14: 12500,
    15: 13100,
    16: 13800,
    17: 14400,
    18: 15000,
    19: 15700,
    20: 16300,
  };

  static Map<int, int> publishedRows(
    RideType rideType,
    DiscountClass discountClass,
  ) {
    return switch ((rideType, discountClass)) {
      (RideType.pooling, DiscountClass.full) => poolingFullCentavos,
      (RideType.pooling, DiscountClass.discounted) => poolingDiscountedCentavos,
      (RideType.special, DiscountClass.full) => specialFullCentavos,
      (RideType.special, DiscountClass.discounted) => specialDiscountedCentavos,
    };
  }

  static int incrementPast20Centavos(
    RideType rideType,
    DiscountClass discountClass,
  ) {
    return switch ((rideType, discountClass)) {
      (RideType.pooling, DiscountClass.full) => 200,
      (RideType.pooling, DiscountClass.discounted) => 160,
      (RideType.special, DiscountClass.full) => 800,
      (RideType.special, DiscountClass.discounted) => 640,
    };
  }

  static int fareForChargeableKm({
    required int chargeableKm,
    required RideType rideType,
    required DiscountClass discountClass,
  }) {
    if (chargeableKm < 2) {
      throw ArgumentError.value(chargeableKm, 'chargeableKm', 'Must be >= 2');
    }
    final rows = publishedRows(rideType, discountClass);
    if (chargeableKm <= printedMaxKm) return rows[chargeableKm]!;
    return rows[printedMaxKm]! +
        (chargeableKm - printedMaxKm) *
            incrementPast20Centavos(rideType, discountClass);
  }
}
