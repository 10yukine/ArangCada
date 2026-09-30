import '../../core/geo/haversine.dart';

/// A place returned by forward or reverse geocoding.
class GeocodedPlace {
  const GeocodedPlace({
    required this.id,
    required this.name,
    required this.context,
    required this.coordinate,
    this.placeId,
  });

  final String id;

  /// Set for Google Places results. Google's terms allow storing this ID
  /// indefinitely, unlike the name and coordinate.
  final String? placeId;

  /// Primary label, e.g. "SM City Calamba".
  final String name;

  /// Locality line, e.g. "Real, Calamba, Laguna".
  final String context;

  /// Null for a Google suggestion until [GeocodingRepository.locate] is
  /// called, which is when Google bills for the location.
  final GeoCoordinate? coordinate;
}

abstract class GeocodingRepository {
  /// Forward search. Implementations must ignore responses that arrive after a
  /// newer query has been issued, and should bias results toward Calamba.
  Future<List<GeocodedPlace>> search(String query);

  /// Reverse lookup for "pin on map". Returning null is acceptable; callers
  /// must fall back to a coordinate label rather than blocking selection.
  Future<GeocodedPlace?> reverse(GeoCoordinate coordinate);

  /// The coordinate of a search result, fetched on selection when the result
  /// did not carry one. Null when it cannot be resolved.
  Future<GeoCoordinate?> locate(GeocodedPlace place);

  /// Current name, address and coordinate for a stored Google place ID, or
  /// null when unavailable. See `SavedPlacesRepository.refreshStale`.
  Future<GeocodedPlace?> refresh(String placeId);
}
