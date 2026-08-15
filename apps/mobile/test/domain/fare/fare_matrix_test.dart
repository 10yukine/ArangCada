import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pins all 76 published Ordinance 743 values literally', () {
    const expectedPoolingFull = <int, int>{
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
    const expectedPoolingDiscounted = <int, int>{
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
    const expectedSpecialFull = <int, int>{
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
    const expectedSpecialDiscounted = <int, int>{
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

    expect(FareMatrix.poolingFullCentavos, expectedPoolingFull);
    expect(FareMatrix.poolingDiscountedCentavos, expectedPoolingDiscounted);
    expect(FareMatrix.specialFullCentavos, expectedSpecialFull);
    expect(FareMatrix.specialDiscountedCentavos, expectedSpecialDiscounted);
    expect(
      FareMatrix.poolingFullCentavos.length +
          FareMatrix.poolingDiscountedCentavos.length +
          FareMatrix.specialFullCentavos.length +
          FareMatrix.specialDiscountedCentavos.length,
      76,
    );
  });
}
