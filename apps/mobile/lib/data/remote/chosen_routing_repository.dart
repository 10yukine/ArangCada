import '../../core/geo/haversine.dart';
import '../repositories/routing_repository.dart';

/// Sends each route request to Google Routes or to openrouteservice, never
/// one as a fallback for the other.
///
/// Google's terms keep another service's route off its map and its own off
/// another map, so the router follows the map: Google Routes with the Google
/// map, openrouteservice with MapLibre (see `useGoogleStack`). When Google
/// has no route (quota reached, an error) there is no line; booking and the
/// fare do not depend on it.
///
/// [useGoogle] is read on every request, so the owner's switch needs no
/// restart.
class ChosenRoutingRepository implements RoutingRepository {
  ChosenRoutingRepository({
    required this._google,
    required this._ors,
    required this._useGoogle,
  });

  final RoutingRepository _google;
  final RoutingRepository _ors;
  final bool Function() _useGoogle;
  late RoutingRepository _last = _google;

  @override
  String get attribution => _last.attribution;

  @override
  Future<RouteResult> route({
    required GeoCoordinate from,
    required GeoCoordinate to,
  }) {
    _last = _useGoogle() ? _google : _ors;
    return _last.route(from: from, to: to);
  }
}
