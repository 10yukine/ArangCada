import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../core/geo/haversine.dart';
import '../repositories/location_repository.dart';

/// Device GPS via geolocator.
///
/// Only while-in-use precision is requested. Background location is not asked
/// for, because showing a commuter's pickup point does not need it, and asking
/// for more than a feature needs is a privacy problem, not a convenience.
///
/// `permission_handler` is deliberately NOT used: geolocator performs its own
/// permission requests, and permission_handler v14 fails to compile against
/// the installed Android SDK.
class GeolocatorLocationRepository implements LocationRepository {
  const GeolocatorLocationRepository();

  static const Duration _timeout = Duration(seconds: 12);

  @override
  Future<bool> hasPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @override
  Future<LocationFix> currentLocation() async {
    // Every plugin call is inside the try. isLocationServiceEnabled,
    // checkPermission and requestPermission can all throw a PlatformException,
    // and callers only catch LocationFailure -- an escape here becomes an
    // uncaught async error at startup.
    try {
      return await _resolve();
    } on LocationFailure {
      rethrow;
    } on TimeoutException {
      throw const LocationFailure(
        LocationFailureReason.timeout,
        'Could not get a location fix in time.',
      );
    } catch (_) {
      throw const LocationFailure(
        LocationFailureReason.unavailable,
        'Location is unavailable right now.',
      );
    }
  }

  Future<LocationFix> _resolve() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
        LocationFailureReason.serviceDisabled,
        'Location services are turned off on this device.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        LocationFailureReason.permissionDeniedForever,
        'Location permission is blocked. Enable it in system settings, or '
        'choose your pickup manually.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure(
        LocationFailureReason.permissionDenied,
        'Location permission was declined.',
      );
    }

    {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _timeout,
        ),
      );
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180 ||
          (position.latitude == 0 && position.longitude == 0) ||
          position.accuracy <= 0 ||
          !position.accuracy.isFinite ||
          DateTime.now().difference(position.timestamp).abs() >
              const Duration(seconds: 30)) {
        throw const LocationFailure(
          LocationFailureReason.unavailable,
          'No recent GPS fix is available. Try again or choose a pickup manually.',
        );
      }
      return LocationFix(
        coordinate: GeoCoordinate(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
        accuracyMeters: position.accuracy,
        timestamp: position.timestamp,
      );
    }
  }
}
