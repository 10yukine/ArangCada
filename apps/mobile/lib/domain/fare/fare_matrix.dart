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

  static FareStrategy strategyFor(
    RideType rideType,
    DiscountClass discountClass,
  ) {
    final strategy = _fareStrategies[(rideType, discountClass)];
    if (strategy == null) {
      throw ArgumentError('Unsupported fare combination');
    }
    return strategy;
  }

  static Map<int, int> publishedRows(
    RideType rideType,
    DiscountClass discountClass,
  ) => strategyFor(rideType, discountClass).publishedRows;

  static int incrementPast20Centavos(
    RideType rideType,
    DiscountClass discountClass,
  ) => strategyFor(rideType, discountClass).incrementPast20Centavos;

  static int fareForChargeableKm({
    required int chargeableKm,
    required RideType rideType,
    required DiscountClass discountClass,
  }) => strategyFor(rideType, discountClass).fareForChargeableKm(chargeableKm);
}

/// Strategy contract for one fare rule combination.
///
/// Each concrete strategy keeps the published fare table and its extrapolation
/// increment together so FareMatrix does not duplicate selection logic.
abstract class FareStrategy {
  const FareStrategy();

  Map<int, int> get publishedRows;
  int get incrementPast20Centavos;

  int fareForChargeableKm(int chargeableKm) {
    if (chargeableKm < 2) {
      throw ArgumentError.value(chargeableKm, 'chargeableKm', 'Must be >= 2');
    }

    const maxKm = FareMatrix.printedMaxKm;
    final rows = publishedRows;
    if (chargeableKm <= maxKm) return rows[chargeableKm]!;
    return rows[maxKm]! + (chargeableKm - maxKm) * incrementPast20Centavos;
  }
}

class PoolingFullFare extends FareStrategy {
  const PoolingFullFare();

  @override
  Map<int, int> get publishedRows => FareMatrix.poolingFullCentavos;

  @override
  int get incrementPast20Centavos => 200;
}

class PoolingDiscountedFare extends FareStrategy {
  const PoolingDiscountedFare();

  @override
  Map<int, int> get publishedRows => FareMatrix.poolingDiscountedCentavos;

  @override
  int get incrementPast20Centavos => 160;
}

class SpecialFullFare extends FareStrategy {
  const SpecialFullFare();

  @override
  Map<int, int> get publishedRows => FareMatrix.specialFullCentavos;

  @override
  int get incrementPast20Centavos => 800;
}

class SpecialDiscountedFare extends FareStrategy {
  const SpecialDiscountedFare();

  @override
  Map<int, int> get publishedRows => FareMatrix.specialDiscountedCentavos;

  @override
  int get incrementPast20Centavos => 640;
}

const _fareStrategies = <(RideType, DiscountClass), FareStrategy>{
  (RideType.pooling, DiscountClass.full): PoolingFullFare(),
  (RideType.pooling, DiscountClass.discounted): PoolingDiscountedFare(),
  (RideType.special, DiscountClass.full): SpecialFullFare(),
  (RideType.special, DiscountClass.discounted): SpecialDiscountedFare(),
};
