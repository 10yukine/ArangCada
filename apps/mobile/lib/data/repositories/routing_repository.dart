import '../../core/geo/haversine.dart';

/// A drawable road route plus its operational figures.
///
/// IMPORTANT: [distanceMeters] here is the *road* distance from
/// openrouteservice. It is for display and operational use only. Billable fare
/// distance is always the straight-line Haversine distance between the fixed
/// pickup and destination -- see `domain/fare/`. Routing must never reach the
/// fare calculator, and neither must [durationSeconds].
class RouteResult {
  const RouteResult({
    required this.geometry,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.isFallback,
    required this.retrievedAt,
  });

  /// Ordered polyline points, already decoded from GeoJSON.
  final List<GeoCoordinate> geometry;

  /// Road distance. Informational. NOT the billing distance.
  final double distanceMeters;

  /// Road duration. Informational. NOT an input to fare.
  final double durationSeconds;

  /// True when the routing service supplied no usable road geometry. The UI
  /// stays usable but must not invent or draw a substitute route.
  final bool isFallback;

  final DateTime retrievedAt;
}

abstract class RoutingRepository {
  /// Returns a route between two points.
  ///
  /// Implementations must not issue a network request when the endpoints have
  /// not materially moved since the last successful lookup, and must not retry
  /// automatically after a quota rejection.
  Future<RouteResult> route({
    required GeoCoordinate from,
    required GeoCoordinate to,
  });

  /// Attribution that must be displayed wherever a result from this repository
  /// is drawn. Empty when the result was a local fallback.
  String get attribution;
}
