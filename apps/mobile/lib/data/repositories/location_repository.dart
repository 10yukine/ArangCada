import '../../core/geo/haversine.dart';

/// Why a location fix is unavailable. Every case has a recovery path that
/// ends in manual pickup selection -- none of them may block booking.
enum LocationFailureReason {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  unavailable,
}

class LocationFix {
  const LocationFix({
    required this.coordinate,
    required this.accuracyMeters,
    required this.timestamp,
  });

  final GeoCoordinate coordinate;
  final double accuracyMeters;
  final DateTime timestamp;

  /// A fix this coarse should not be presented as a precise pickup point.
  bool get isCoarse => accuracyMeters > 150;
}

class LocationFailure implements Exception {
  const LocationFailure(this.reason, this.message);

  final LocationFailureReason reason;
  final String message;

  @override
  String toString() => 'LocationFailure(${reason.name}): $message';
}

abstract class LocationRepository {
  /// Requests permission if needed and returns a single fix.
  ///
  /// Throws [LocationFailure] rather than returning null so callers must
  /// handle the specific reason. Implementations must only ever request
  /// while-in-use precision for commuter pickup.
  Future<LocationFix> currentLocation();

  Future<bool> hasPermission();
}
