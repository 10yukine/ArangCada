import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/geo/haversine.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../data/repositories/routing_repository.dart';
import 'live_map_view.dart';

/// Map showing the road route between two fixed points.
///
/// Requests the route ONCE, in `initState`, and again only when the endpoints
/// actually change. Never from `build()`, never on a map gesture, never on a
/// timer -- HeiGIT asked that unnecessary requests not be sent, and the
/// repository's cache only helps if callers stop asking.
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
    super.key,
  });

  final GeoCoordinate from;
  final GeoCoordinate to;
  final double height;
  final BorderRadius? borderRadius;

  /// Off when the map fills a screen and the caption lives in a sheet below.
  final bool showCaption;

  @override
  ConsumerState<RoutePreviewMap> createState() => _RoutePreviewMapState();
}

class _RoutePreviewMapState extends ConsumerState<RoutePreviewMap> {
  RouteResult? _route;
  bool _loading = true;

  /// Guards against an older lookup overwriting a newer one.
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant RoutePreviewMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moved =
        haversineDistanceMeters(oldWidget.from, widget.from) > 40 ||
        haversineDistanceMeters(oldWidget.to, widget.to) > 40;
    if (moved) _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final from = widget.from;
    final to = widget.to;
    setState(() => _loading = true);
    // The repository never throws: it degrades to a straight line and marks
    // the result isFallback, so there is no error branch to render here.
    final route = await ref
        .read(routingRepositoryProvider)
        .route(from: from, to: to);
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
      center: midpoint,
      height: widget.height,
      borderRadius: widget.borderRadius,
      zoom: 14,
      route: route?.geometry ?? const [],
      routeIsFallback: route?.isFallback ?? false,
      interactive: false,
      markers: [
        MapMarker(coordinate: widget.from, color: AppColors.green, radius: 7),
        MapMarker(coordinate: widget.to, color: AppColors.primary, radius: 7),
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
      // Honest: nothing was routed, so do not imply a road route or claim
      // openrouteservice produced this line.
      return 'Route preview unavailable — showing a direct line. '
          'Fare is unaffected.';
    }
    final km = (route.distanceMeters / 1000).toStringAsFixed(1);
    final mins = (route.durationSeconds / 60).round();
    return 'About $km km by road · roughly $mins min. '
        'Fare is billed on straight-line distance.';
  }
}
