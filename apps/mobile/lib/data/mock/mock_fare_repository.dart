import '../../domain/fare/fare_calculator.dart';
import '../../domain/fare/fare_matrix.dart';
import '../repositories/fare_repository.dart';

class MockFareRepository implements FareRepository {
  const MockFareRepository({this.calculator = const FareCalculator()});

  final FareCalculator calculator;

  @override
  FareQuote quote({
    required double distanceMeters,
    required RideType rideType,
    required int passengerCount,
    required DiscountClass discountClass,
  }) {
    return calculator.quote(
      distanceMeters: distanceMeters,
      rideType: rideType,
      passengerCount: passengerCount,
      discountClass: discountClass,
    );
  }
}
