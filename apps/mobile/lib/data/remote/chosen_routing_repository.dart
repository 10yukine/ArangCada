import '../../core/geo/haversine.dart';
import '../repositories/routing_repository.dart';

/// Tries [primary] first and falls back to [secondary] only when the primary
/// returned no usable road geometry (not configured, quota exhausted, rate
/// limited, or a genuine provider failure). Never calls both providers for a
/// route that the primary already answered -- that would double the request
/// volume against two paid/quota-limited services for one booking.
///
/// Built so Google Routes can be the primary provider (better unnamed-road
/// coverage) while openrouteservice stays as a free, always-available
/// fallback rather than being removed outright.
class FallbackRoutingRepository implements RoutingRepository {
  FallbackRoutingRepository({required this._primary, required this._secondary});

  final RoutingRepository _primary;
  final RoutingRepository _secondary;

  String _attribution = '';

  @override
  String get attribution => _attribution;

  @override
  Future<RouteResult> route({
    required GeoCoordinate from,
    required GeoCoordinate to,
  }) async {
    final primaryResult = await _primary.route(from: from, to: to);
    if (!primaryResult.isFallback) {
      _attribution = _primary.attribution;
      return primaryResult;
    }

    final secondaryResult = await _secondary.route(from: from, to: to);
    if (!secondaryResult.isFallback) {
      _attribution = _secondary.attribution;
      return secondaryResult;
    }

    // Neither provider had a usable route. Keep booking available without
    // inventing road geometry -- same contract every RoutingRepository
    // implementation already honors on its own.
    _attribution = '';
    return secondaryResult;
  }
}

/// Orders Google Routes and openrouteservice by the owner's setting, read on
/// every request so a change needs no restart (see app/mobile_settings.dart).
/// 'ors_only' never calls Google, which bills per request.
class ChosenRoutingRepository implements RoutingRepository {
  ChosenRoutingRepository({
    required RoutingRepository google,
    required RoutingRepository ors,
    required this._choice,
  }) : _orsOnly = ors,
       _orsFirst = FallbackRoutingRepository(primary: ors, secondary: google),
       _googleFirst = FallbackRoutingRepository(
         primary: google,
         secondary: ors,
       );

  final String Function() _choice;
  final RoutingRepository _orsOnly;
  final RoutingRepository _orsFirst;
  final RoutingRepository _googleFirst;
  late RoutingRepository _last = _googleFirst;

  @override
  String get attribution => _last.attribution;

  @override
  Future<RouteResult> route({
    required GeoCoordinate from,
    required GeoCoordinate to,
  }) {
    _last = switch (_choice()) {
      'ors_only' => _orsOnly,
      'ors' => _orsFirst,
      _ => _googleFirst,
    };
    return _last.route(from: from, to: to);
  }
}
