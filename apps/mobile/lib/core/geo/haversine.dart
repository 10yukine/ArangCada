import 'dart:math' as math;

class GeoCoordinate {
  const GeoCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// Preview-only straight-line distance using the IUGG mean Earth radius.
///
/// The server's PostGIS geodesic distance remains authoritative for real
/// bookings. openrouteservice distance must never be used for billed fare.
double haversineDistanceMeters(GeoCoordinate start, GeoCoordinate end) {
  _validateCoordinate(start);
  _validateCoordinate(end);

  const earthRadiusMeters = 6371008.8;
  final startLatitude = _toRadians(start.latitude);
  final endLatitude = _toRadians(end.latitude);
  final latitudeDelta = _toRadians(end.latitude - start.latitude);
  final longitudeDelta = _toRadians(end.longitude - start.longitude);

  final a =
      math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(startLatitude) *
          math.cos(endLatitude) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  final centralAngle = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * centralAngle;
}

void _validateCoordinate(GeoCoordinate coordinate) {
  final valid =
      coordinate.latitude.isFinite &&
      coordinate.longitude.isFinite &&
      coordinate.latitude >= -90 &&
      coordinate.latitude <= 90 &&
      coordinate.longitude >= -180 &&
      coordinate.longitude <= 180;
  if (!valid) {
    throw ArgumentError('Coordinates must be finite latitude/longitude values');
  }
}

double _toRadians(double degrees) => degrees * math.pi / 180;
