import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_typography.dart';
import '../../../config/app_config.dart';
import '../../../config/map_style.dart';
import '../../geo/haversine.dart';

/// A point drawn on the map. Rendered as a circle so the build needs no
/// image assets and no per-platform symbol registration.
class MapMarker {
  const MapMarker({
    required this.coordinate,
    required this.color,
    this.radius = 7,
    this.strokeColor = Colors.white,
  });

  final GeoCoordinate coordinate;
  final Color color;
  final double radius;
  final Color strokeColor;
}

/// A visual-only map polygon. Jurisdiction remains a server-side decision.
class MapBoundary {
  const MapBoundary({
    required this.points,
    this.fillColor = AppColors.primary,
    this.fillOpacity = 0.08,
    this.outlineColor = AppColors.primary,
  });

  final List<GeoCoordinate> points;
  final Color fillColor;
  final double fillOpacity;
  final Color outlineColor;
}

/// Lets a panel-mounted control restore the current route bounds without
/// exposing MapLibre or requesting the route again.
class LiveMapViewController {
  _LiveMapViewState? _state;
  final GlobalKey panelKey = GlobalKey();

  double get bottomInset => panelKey.currentContext?.size?.height ?? 0;

  Future<void> fitRoute() => _state?._fitRoute() ?? Future.value();
  Future<void> recenter() => _state?._recenter() ?? Future.value();
}

@visibleForTesting
({LatLngBounds bounds, double bottomPadding}) mapRouteViewport({
  required List<GeoCoordinate> route,
  required List<MapMarker> markers,
  double bottomInset = 0,
}) {
  final coordinates = [
    ...route,
    for (final marker in markers) marker.coordinate,
  ];
  var minLat = coordinates.first.latitude;
  var maxLat = minLat;
  var minLng = coordinates.first.longitude;
  var maxLng = minLng;
  for (final coordinate in coordinates) {
    minLat = math.min(minLat, coordinate.latitude);
    maxLat = math.max(maxLat, coordinate.latitude);
    minLng = math.min(minLng, coordinate.longitude);
    maxLng = math.max(maxLng, coordinate.longitude);
  }
  return (
    bounds: LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    ),
    bottomPadding: math.max(60, bottomInset + 16),
  );
}

@visibleForTesting
bool mapMarkersEquivalent(List<MapMarker> a, List<MapMarker> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (haversineDistanceMeters(a[i].coordinate, b[i].coordinate) > 5 ||
        a[i].color != b[i].color ||
        a[i].radius != b[i].radius ||
        a[i].strokeColor != b[i].strokeColor) {
      return false;
    }
  }
  return true;
}

@visibleForTesting
bool mapRoutesEquivalent(List<GeoCoordinate> a, List<GeoCoordinate> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (haversineDistanceMeters(a[i], b[i]) >= 5) return false;
  }
  return true;
}

@visibleForTesting
bool mapBoundariesEquivalent(List<MapBoundary> a, List<MapBoundary> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!mapRoutesEquivalent(a[i].points, b[i].points) ||
        a[i].fillColor != b[i].fillColor ||
        a[i].fillOpacity != b[i].fillOpacity ||
        a[i].outlineColor != b[i].outlineColor) {
      return false;
    }
  }
  return true;
}

/// Real MapLibre surface rendering MapTiler vector tiles.
///
/// Deliberately a `StatefulWidget` that keeps its controller: the map is
/// expensive to create, so it must not be rebuilt when a parent's state
/// changes. Markers and the route are diffed onto the existing style instead.
///
/// Attribution is mandatory and always visible -- MapTiler and OpenStreetMap
/// for the basemap, plus openrouteservice whenever a real ORS route is drawn.
class LiveMapView extends StatefulWidget {
  const LiveMapView({
    required this.center,
    this.zoom = 14.5,
    this.markers = const [],
    this.route = const [],
    this.boundaries = const [],
    this.routeIsFallback = false,
    this.showUserLocation = false,
    this.interactive = true,
    this.onMapTap,
    this.controller,
    this.height,
    this.borderRadius,
    super.key,
  });

  final GeoCoordinate center;
  final double zoom;
  final List<MapMarker> markers;
  final List<GeoCoordinate> route;
  final List<MapBoundary> boundaries;

  /// True when no ORS road route is available. Suppresses routing attribution
  /// because nothing was routed.
  final bool routeIsFallback;

  final bool showUserLocation;
  final bool interactive;
  final void Function(GeoCoordinate)? onMapTap;
  final LiveMapViewController? controller;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  State<LiveMapView> createState() => _LiveMapViewState();
}

class _LiveMapViewState extends State<LiveMapView> {
  MapLibreMapController? _controller;
  bool _styleReady = false;
  bool _styleFailed = false;

  final ValueNotifier<double> _bearing = ValueNotifier(0);
  final List<Circle> _circles = [];
  final List<Fill> _fills = [];
  Line? _routeLine;
  Timer? _styleTimeout;
  Future<void> _syncTail = Future.value();

  /// If MapTiler never answers -- dead tile server, captive portal, no data --
  /// stop showing a spinner forever and degrade to the unavailable state so
  /// the rest of the screen stays usable (task rule: tiles failing must not
  /// take down booking).
  static const Duration _styleLoadBudget = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _styleTimeout = Timer(_styleLoadBudget, () {
      if (mounted && !_styleReady) setState(() => _styleFailed = true);
    });
  }

  @override
  void dispose() {
    _styleTimeout?.cancel();
    _bearing.dispose();
    if (widget.controller?._state == this) widget.controller?._state = null;
    super.dispose();
  }

  Future<void> _onStyleLoaded() async {
    _styleTimeout?.cancel();
    if (!mounted) return;
    setState(() => _styleReady = true);
    await _queueSync(
      markersChanged: true,
      routeChanged: true,
      boundariesChanged: true,
    );
    if (widget.route.isEmpty) {
      await _recenter();
    }
  }

  @override
  void didUpdateWidget(covariant LiveMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) {
        oldWidget.controller?._state = null;
      }
      widget.controller?._state = this;
    }
    if (!_styleReady) return;
    final markersChanged = !mapMarkersEquivalent(
      oldWidget.markers,
      widget.markers,
    );
    final routeChanged = !mapRoutesEquivalent(oldWidget.route, widget.route);
    final boundariesChanged = !mapBoundariesEquivalent(
      oldWidget.boundaries,
      widget.boundaries,
    );
    final centerMoved =
        haversineDistanceMeters(oldWidget.center, widget.center) > 25;
    if (markersChanged || routeChanged || boundariesChanged) {
      _queueSync(
        markersChanged: markersChanged,
        routeChanged: routeChanged,
        boundariesChanged: boundariesChanged,
      );
    }
    if (centerMoved && widget.route.isEmpty) _recenter();
  }

  Future<void> _queueSync({
    required bool markersChanged,
    required bool routeChanged,
    required bool boundariesChanged,
  }) {
    _syncTail = _syncTail.then(
      (_) => _sync(
        markersChanged: markersChanged,
        routeChanged: routeChanged,
        boundariesChanged: boundariesChanged,
      ),
    );
    return _syncTail;
  }

  Future<void> _sync({
    required bool markersChanged,
    required bool routeChanged,
    required bool boundariesChanged,
  }) async {
    final controller = _controller;
    if (controller == null || !_styleReady) return;

    try {
      if (boundariesChanged) {
        for (final fill in _fills) {
          await controller.removeFill(fill);
        }
        _fills.clear();
        for (final boundary in widget.boundaries) {
          if (boundary.points.length < 4) continue;
          _fills.add(
            await controller.addFill(
              FillOptions(
                geometry: [
                  [
                    for (final point in boundary.points)
                      LatLng(point.latitude, point.longitude),
                  ],
                ],
                fillColor: _hex(boundary.fillColor),
                fillOpacity: boundary.fillOpacity,
                fillOutlineColor: _hex(boundary.outlineColor),
              ),
            ),
          );
        }
      }

      if (routeChanged) {
        if (_routeLine != null) {
          await controller.removeLine(_routeLine!);
          _routeLine = null;
        }

        if (widget.route.length >= 2) {
          _routeLine = await controller.addLine(
            LineOptions(
              geometry: [
                for (final p in widget.route) LatLng(p.latitude, p.longitude),
              ],
              lineColor: '#1262D0',
              lineWidth: 5,
              lineOpacity: widget.routeIsFallback ? 0.55 : 0.95,
            ),
          );
        }
      }

      if (markersChanged) {
        for (final circle in _circles) {
          await controller.removeCircle(circle);
        }
        _circles.clear();

        for (final marker in widget.markers) {
          final circle = await controller.addCircle(
            CircleOptions(
              geometry: LatLng(
                marker.coordinate.latitude,
                marker.coordinate.longitude,
              ),
              circleRadius: marker.radius,
              circleColor: _hex(marker.color),
              circleStrokeColor: _hex(marker.strokeColor),
              circleStrokeWidth: 2.5,
            ),
          );
          _circles.add(circle);
        }
      }

      if (routeChanged && widget.route.length >= 2) await _fitRoute();
    } catch (_) {
      // A style that failed to load leaves the controller usable but empty.
      // Never let annotation failures take down the screen.
    }
  }

  static String _hex(Color color) {
    final value =
        // ignore: deprecated_member_use - toARGB32 is not in this Flutter min.
        color.value & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0')}';
  }

  Future<void> _fitRoute() async {
    final controller = _controller;
    if (controller == null || widget.route.length < 2) return;
    final viewport = mapRouteViewport(
      route: widget.route,
      markers: widget.markers,
      bottomInset: widget.controller?.bottomInset ?? 0,
    );
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        viewport.bounds,
        left: 48,
        right: 48,
        top: 60,
        bottom: viewport.bottomPadding,
      ),
    );
  }

  Future<void> _recenter() async {
    await _controller?.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(widget.center.latitude, widget.center.longitude),
      ),
    );
  }

  void _onCameraMove(CameraPosition position) {
    if (!mounted || !widget.interactive) return;
    if ((_bearing.value - position.bearing).abs() < 0.01) return;
    _bearing.value = position.bearing;
  }

  void _resetNorth() {
    _controller?.animateCamera(
      CameraUpdate.bearingTo(0),
      duration: const Duration(milliseconds: 250),
    );
  }

  void _retry() {
    _styleTimeout?.cancel();
    setState(() {
      _styleFailed = false;
      _styleReady = false;
    });
    _styleTimeout = Timer(_styleLoadBudget, () {
      if (mounted && !_styleReady) setState(() => _styleFailed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final radius =
        widget.borderRadius ??
        const BorderRadius.all(Radius.circular(AppRadii.card));

    Widget content;
    if (!AppConfig.isMapTilerConfigured) {
      // No key configured at all -- retrying cannot help.
      content = const _MapUnavailable();
    } else if (_styleFailed) {
      // Configured but the style never loaded in time (a real bug this
      // was: a transient network drop or a resume-from-sleep hiccup set
      // this once and there was no way back -- the map stayed dead for the
      // rest of the widget's life). Retry rebuilds a fresh MapLibreMap
      // below, which starts a new load attempt from scratch.
      content = _MapUnavailable(onRetry: _retry);
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          MapLibreMap(
            styleString: MapStyle.streetsStyleUrl,
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.center.latitude, widget.center.longitude),
              zoom: widget.zoom,
            ),
            onMapCreated: (controller) => _controller = controller,
            onStyleLoadedCallback: _onStyleLoaded,
            myLocationEnabled: widget.showUserLocation,
            // Forces MapLibre onto a TextureView on Android. Flutter composites
            // platform views through an ImageReader texture (TLHC); MapLibre's
            // default SurfaceView cannot be captured by it, which renders a
            // blank map with "BufferQueue has no connected producer" in logcat.
            // The plugin ties textureMode to (translucent || hybrid), so
            // requesting translucency is the reliable lever.
            translucentTextureSurface: true,
            compassEnabled: false,
            trackCameraPosition: widget.interactive,
            onCameraMove: widget.interactive ? _onCameraMove : null,
            logoEnabled: false,
            // The library's own attribution button is hidden because this
            // widget renders required attribution as persistent text below,
            // which cannot be missed or scrolled away.
            attributionButtonPosition: AttributionButtonPosition.bottomRight,
            scrollGesturesEnabled: widget.interactive,
            zoomGesturesEnabled: widget.interactive,
            rotateGesturesEnabled: widget.interactive,
            tiltGesturesEnabled: widget.interactive,
            onMapClick: widget.onMapTap == null
                ? null
                : (point, latLng) => widget.onMapTap!(
                    GeoCoordinate(
                      latitude: latLng.latitude,
                      longitude: latLng.longitude,
                    ),
                  ),
          ),
          if (!_styleReady)
            const ColoredBox(
              color: AppColors.neutralFill,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            ),
          if (widget.interactive)
            Positioned(
              // Same y as the floating back button opposite it. Callers used
              // to pass this inset, every one of them computing the identical
              // safe-area expression -- except the active-trip screen, which
              // carried an extra 64px from when the compass sat on the LEFT and
              // had to dodge the back button. It moved right; the dodge stayed;
              // the two controls stopped lining up. A parameter with one
              // correct value is a parameter waiting to be passed wrongly.
              top: MediaQuery.paddingOf(context).top + 8,
              right: 8,
              child: ValueListenableBuilder<double>(
                valueListenable: _bearing,
                builder: (context, bearing, _) {
                  // Only when the map is actually off north. A permanent
                  // "reset north" button on a map nobody has turned is a
                  // control that spends its whole life doing nothing -- but
                  // deleting it would strand anyone who rotates the map by
                  // accident with a two-finger twist and no way back. It
                  // appears exactly when there is something to escape from,
                  // which is how Google Maps and Waze both behave.
                  final level = bearing.abs() < 0.5;
                  return IgnorePointer(
                    ignoring: level,
                    child: AnimatedOpacity(
                      opacity: level ? 0 : 1,
                      duration: AppMotion.button,
                      child: MapCompass(
                        bearing: bearing,
                        onPressed: _resetNorth,
                      ),
                    ),
                  );
                },
              ),
            ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 5,
            child: MapAttribution(
              includeRouting:
                  widget.route.length >= 2 && !widget.routeIsFallback,
            ),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(height: widget.height, child: content),
    );
  }
}

/// Visible north indicator whose needle follows the current map bearing.
class MapCompass extends StatelessWidget {
  const MapCompass({required this.bearing, required this.onPressed, super.key});

  final double bearing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Deliberately identical to ArangIconButton: same 42dp circle, same border,
    // same 20dp glyph. It was 48dp with a 24dp icon and an elevation the other
    // map controls do not have, so the one button a user never presses was the
    // largest and heaviest thing floating over the map.
    // 42dp circle inside a 48dp tap target -- the same trick ArangIconButton
    // uses. Matching the visual size alone would have quietly cut the tap
    // target from 48 to 42, below the accessibility minimum, which is a real
    // regression hiding inside a cosmetic change.
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: AppSizes.minTapTarget,
        minHeight: AppSizes.minTapTarget,
      ),
      child: Center(
        child: Tooltip(
          message: 'Reset map north',
          child: Material(
            color: AppColors.surface,
            shape: const CircleBorder(
              side: BorderSide(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: AppSizes.iconButton,
                height: AppSizes.iconButton,
                child: Transform.rotate(
                  angle: -bearing * math.pi / 180,
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: AppColors.danger,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Required provider attribution. Always rendered, never behind a control.
class MapAttribution extends StatelessWidget {
  const MapAttribution({this.includeRouting = false, super.key});

  final bool includeRouting;

  @override
  Widget build(BuildContext context) {
    final text = includeRouting
        ? '© MapTiler © OpenStreetMap · Routing: openrouteservice'
        : '© MapTiler © OpenStreetMap contributors';
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.86),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.neutralFill,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.map_outlined,
                size: 28,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Map unavailable',
                style: AppTypography.label.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Everything else still works.',
                textAlign: TextAlign.center,
                style: AppTypography.caption,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.xs),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
