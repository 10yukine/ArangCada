import '../../core/geo/haversine.dart';

/// A place returned by forward or reverse geocoding.
class GeocodedPlace {
  const GeocodedPlace({
    required this.id,
    required this.name,
    required this.context,
    required this.coordinate,
  });

  final String id;

  /// Primary label, e.g. "SM City Calamba".
  final String name;

  /// Locality line, e.g. "Real, Calamba, Laguna".
  final String context;

  final GeoCoordinate coordinate;
}

abstract class GeocodingRepository {
  /// Forward search. Implementations must ignore responses that arrive after a
  /// newer query has been issued, and should bias results toward Calamba.
  Future<List<GeocodedPlace>> search(String query);

  /// Reverse lookup for "pin on map". Returning null is acceptable; callers
  /// must fall back to a coordinate label rather than blocking selection.
  Future<GeocodedPlace?> reverse(GeoCoordinate coordinate);
}
