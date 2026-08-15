import '../../core/geo/haversine.dart';

/// Client-side check for "is this inside the area ArangCada serves?".
///
/// This is a **guard rail, not the authority.** Real TODA jurisdiction is a
/// PostGIS polygon evaluated server-side (`supabase/migrations/*geofence_rpc*`),
/// because a client can be modified and a boundary decision affects who is
/// allowed to earn a fare. This exists so a commuter is told immediately
/// instead of being allowed to build a booking that the server will refuse.
///
/// The polygon below approximates Calamba City's extent. It is deliberately
/// slightly generous: refusing a legitimate ride at the edge is worse than
/// letting one through for the server to reject.
abstract final class ServiceArea {
  const ServiceArea._();

  static const String name = 'Calamba City';

  /// Approximate Calamba boundary, clockwise. Sourced from the city's extent,
  /// not from the seeded TODA polygons, which are still placeholders.
  static const List<GeoCoordinate> _boundary = [
    GeoCoordinate(latitude: 14.2870, longitude: 121.0480),
    GeoCoordinate(latitude: 14.2760, longitude: 121.1450),
    GeoCoordinate(latitude: 14.2450, longitude: 121.2180),
    GeoCoordinate(latitude: 14.1900, longitude: 121.2450),
    GeoCoordinate(latitude: 14.1350, longitude: 121.2050),
    GeoCoordinate(latitude: 14.1180, longitude: 121.1250),
    GeoCoordinate(latitude: 14.1520, longitude: 121.0600),
    GeoCoordinate(latitude: 14.2150, longitude: 121.0320),
  ];

  /// Ray-casting point-in-polygon. Mirrors what `ST_Covers` decides on the
  /// server, minus the exact boundary semantics -- which is why the server
  /// remains authoritative.
  static bool contains(GeoCoordinate point) {
    var inside = false;
    for (var i = 0, j = _boundary.length - 1; i < _boundary.length; j = i++) {
      final a = _boundary[i];
      final b = _boundary[j];
      final intersects =
          (a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude;
      if (intersects) inside = !inside;
    }
    return inside;
  }

  /// Null when the trip is serviceable, otherwise the reason to show.
  static String? rejectionReason({
    required GeoCoordinate pickup,
    required GeoCoordinate destination,
  }) {
    final pickupOk = contains(pickup);
    final destinationOk = contains(destination);
    if (pickupOk && destinationOk) return null;
    if (!pickupOk && !destinationOk) {
      return 'Both your pickup and destination are outside the $name service '
          'area. ArangCada tricycles operate within Calamba only.';
    }
    if (!destinationOk) {
      return 'This destination is outside the $name service area. Booking is '
          'not allowed.';
    }
    return 'Your pickup point is outside the $name service area. Booking is '
        'not allowed.';
  }
}
