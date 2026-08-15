import '../../domain/fare/fare_calculator.dart';
import '../../domain/fare/fare_matrix.dart';

/// Fare preview seam.
///
/// Production replaces the mock with `SupabaseFareRepository`, which calls
/// the existing trusted `public.compute_fare` RPC. Client quotes are previews,
/// never the final fare authority.
abstract interface class FareRepository {
  FareQuote quote({
    required double distanceMeters,
    required RideType rideType,
    required int passengerCount,
    required DiscountClass discountClass,
  });
}
