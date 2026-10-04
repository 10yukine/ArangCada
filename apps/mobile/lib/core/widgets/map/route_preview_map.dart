import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/mobile_settings.dart';
import '../../../config/app_config.dart';
import '../../../core/geo/haversine.dart';
import '../../../core/geo/route_progress.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../data/remote/chosen_routing_repository.dart';
import '../../../data/repositories/routing_repository.dart';
import 'live_map_view.dart';

/// Map showing the road route between two points.
///
/// Requests the route ONCE, in `initState`, and again only when the endpoints
/// actually change. Never from `build()`, never on a map gesture, never on a
/// timer -- HeiGIT asked that unnecessary requests not be sent, and the
/// repository's cache only helps if callers stop asking.
///
/// With [originMoves] the start is a vehicle's live position. Asking again
/// every 40 m cost about 25 billable requests per kilometre driven, so the
/// route is requested once and followed on the device: the drawn line is
/// trimmed to what is still ahead, and a new request is made only after the
/// vehicle has clearly left the line, and never sooner than
/// [minRerouteInterval] after the last one.
///
/// The road distance shown here is informational. Billed fare uses Haversine
/// and is computed elsewhere; this widget must never feed the fare engine.
class RoutePreviewMap extends ConsumerStatefulWidget {
  const RoutePreviewMap({
    required this.from,
    required this.to,
    this.height = 190,
    this.borderRadius,
    this.showCaption = true,
    this.interactive = false,
    this.controller,
    this.boundaries = const [],
    this.additionalMarkers = const [],
    this.originMoves = false,
    this.minRerouteInterval = const Duration(seconds: 60),
    super.key,
  });

  final GeoCoordinate from;
  final GeoCoordinate to;
  final double height;
  final BorderRadius? borderRadius;

  /// Off when the map fills a screen and the caption lives in a sheet below.
  final bool showCaption;
  final bool interactive;
  final LiveMapViewController? controller;
  final List<MapBoundary> boundaries;
  final List<MapMarker> additionalMarkers;

  /// True when [from] is a live GPS position rather than a fixed point.
  final bool originMoves;
  final Duration minRerouteInterval;

  @override
  ConsumerState<RoutePreviewMap> createState() => _RoutePreviewMapState();
}

class _RoutePreviewMapState extends ConsumerState<RoutePreviewMap> {
  RouteResult? _route;
  bool _loading = true;
  late final bool _useGoogleMap;
  late final RoutingRepository _routing;

  /// Guards against an older lookup overwriting a newer one.
  int _loadToken = 0;

  // Following a moving origin: wider than GPS drift beside a road, and held
  // for several fixes so one bad fix does not buy a new route.
  static const double _offRouteMeters = 60;
  static const int _offRouteFixesNeeded = 3;
  int _offRouteFixes = 0;
  DateTime _requestedAt = DateTime.now();
  GeoCoordinate? _requestedFrom;

  @override
  void initState() {
    super.initState();
    _useGoogleMap = AppConfig.isGoogleMapsConfigured && useGoogleStack;
    final router = ref.read(routingRepositoryProvider);
    _routing = router is ChosenRoutingRepository
        ? router.forMap(useGoogle: _useGoogleMap)
        : router;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant RoutePreviewMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final toMoved = haversineDistanceMeters(oldWidget.to, widget.to) > 40;
    if (!widget.originMoves) {
      if (toMoved ||
          haversineDistanceMeters(oldWidget.from, widget.from) > 40) {
        _load();
      }
      return;
    }
    if (toMoved) {
      _load();
      return;
    }
    // Rebuilds arrive for many reasons; only a new position is a GPS fix.
    final newFix =
        oldWidget.from.latitude != widget.from.latitude ||
        oldWidget.from.longitude != widget.from.longitude;
    if (newFix) _followOrigin();
  }

  void _followOrigin() {
    if (_loading) return;
    final route = _route;
    final requestedFrom = _requestedFrom;
    final hasLine =
        route != null && !route.isFallback && route.geometry.length > 1;
    final offRoute = hasLine
        ? routeProgress(route.geometry, widget.from).offRouteMeters >
              _offRouteMeters
        // No line to follow (the routing service had none): judge by how far
        // the vehicle is from where the route was asked for.
        : requestedFrom != null &&
              haversineDistanceMeters(requestedFrom, widget.from) > 40;
    _offRouteFixes = offRoute ? _offRouteFixes + 1 : 0;
    if (_offRouteFixes >= _offRouteFixesNeeded &&
        DateTime.now().difference(_requestedAt) >= widget.minRerouteInterval) {
      _load();
    }
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final from = widget.from;
    final to = widget.to;
    _requestedAt = DateTime.now();
    _requestedFrom = from;
    _offRouteFixes = 0;
    setState(() => _loading = true);
    // The repository never throws: unavailable road routes are marked as
    // fallback, so there is no error branch to render here.
    final route = await _routing.route(from: from, to: to);
    if (!mounted || token != _loadToken) return;
    setState(() {
      _route = route;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final midpoint = GeoCoordinate(
      latitude: (widget.from.latitude + widget.to.latitude) / 2,
      longitude: (widget.from.longitude + widget.to.longitude) / 2,
    );

    final map = LiveMapView(
      useGoogleMap: _useGoogleMap,
      controller: widget.controller,
      center: midpoint,
      height: widget.height,
      borderRadius: widget.borderRadius,
      zoom: 14,
      route: route == null || route.isFallback
          ? const []
          : widget.originMoves
          ? routeProgress(route.geometry, widget.from).remaining
          : route.geometry,
      routeIsFallback: route?.isFallback ?? false,
      routeAttribution: route == null || route.isFallback
          ? ''
          : _routing.attribution,
      interactive: widget.interactive,
      boundaries: widget.boundaries,
      markers: [
        MapMarker(coordinate: widget.from, color: AppColors.green, radius: 7),
        MapMarker(coordinate: widget.to, color: AppColors.primary, radius: 7),
        ...widget.additionalMarkers,
      ],
    );

    // Filling a parent: the map is the whole widget. Wrapping it in a
    // shrink-wrapping Column would give an infinite-height child no room and
    // render nothing.
    if (!widget.showCaption) return map;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        map,
        if (widget.showCaption) ...[
          const SizedBox(height: 6),
          Text(
            _caption(route),
            style: AppTypography.caption.copyWith(fontSize: 11),
          ),
        ],
      ],
    );
  }

  String _caption(RouteResult? route) {
    if (_loading || route == null) return 'Loading route…';
    if (route.isFallback) {
      return 'Route preview unavailable. Fare is unaffected.';
    }
    // Google routes carry the line only (see GoogleRoutesConfig).
    if (route.distanceMeters <= 0) {
      return 'Fare is billed on straight-line distance.';
    }
    final km = (route.distanceMeters / 1000).toStringAsFixed(1);
    final mins = (route.durationSeconds / 60).round();
    return 'About $km km by road · roughly $mins min. '
        'Fare is billed on straight-line distance.';
  }
}
