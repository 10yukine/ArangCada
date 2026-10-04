import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/geo/haversine.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/map/live_map_view.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../demo/demo_data.dart';

/// Farthest a pickup pin may sit from the device's GPS fix. Pickup is always
/// where the commuter actually is (fake bookings for somewhere else are the
/// thing this prevents); the short leash only corrects GPS drift, e.g. the
/// right side of the street or the mall entrance instead of the roof.
const double pickupAdjustRadiusMeters = 100;

/// Place id of a pickup the commuter nudged away from the raw GPS point.
const String adjustedPickupId = 'gps-adjusted';

/// [point], pulled back along the line from [anchor] so it is at most
/// [maxMeters] away. At this scale a straight lat/lng interpolation is well
/// within GPS error, so no great-circle bearing math is needed.
GeoCoordinate clampToRadius(
  GeoCoordinate anchor,
  GeoCoordinate point,
  double maxMeters,
) {
  final distance = haversineDistanceMeters(anchor, point);
  if (distance <= maxMeters) return point;
  final t = maxMeters / distance;
  return GeoCoordinate(
    latitude: anchor.latitude + (point.latitude - anchor.latitude) * t,
    longitude: anchor.longitude + (point.longitude - anchor.longitude) * t,
  );
}

/// Drop a pin to choose a destination the geocoder does not know, or, with
/// [pickupAnchor], to fine-tune the pickup within [pickupAdjustRadiusMeters]
/// of the GPS fix. Reverse geocoding labels the point when it can; selection
/// is never blocked on the geocoder answering.
///
/// With [suggested] it shows a place found by search for the rider to confirm
/// or move. The confirmed pin is what is booked, checked against the service
/// area and stored, with no Google ID or name. A pin the rider leaves where
/// it was still has the search result's coordinates, so this step does not
/// by itself settle what Google's terms say about Places coordinates.
class PinOnMapScreen extends ConsumerStatefulWidget {
  const PinOnMapScreen({this.pickupAnchor, this.suggested, super.key});

  /// The GPS fix a pickup adjustment is leashed to. Null for destinations.
  final GeoCoordinate? pickupAnchor;

  /// The search result to confirm. Its name is shown here only; a Google
  /// name is never passed on (see [DemoPlace.riderText]).
  final DemoPlace? suggested;

  @override
  ConsumerState<PinOnMapScreen> createState() => _PinOnMapScreenState();
}

class _PinOnMapScreenState extends ConsumerState<PinOnMapScreen> {
  GeoCoordinate? _picked;
  String? _label;
  bool _resolving = false;
  int _resolveToken = 0;

  bool get _adjustingPickup => widget.pickupAnchor != null;

  @override
  void initState() {
    super.initState();
    final anchor = widget.pickupAnchor;
    if (anchor != null) {
      // Start on the GPS point; label it once the first frame is up.
      _picked = anchor;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onTap(anchor);
      });
    }
    final suggested = widget.suggested;
    if (suggested != null) {
      // No lookup: a search result's coordinate goes nowhere until the rider
      // has confirmed or moved the pin.
      _picked = suggested.coordinate;
      _label = suggested.name;
    }
  }

  Future<void> _onTap(GeoCoordinate tapped) async {
    final anchor = widget.pickupAnchor;
    final coordinate = anchor == null
        ? tapped
        : clampToRadius(anchor, tapped, pickupAdjustRadiusMeters);
    final token = ++_resolveToken;
    setState(() {
      _picked = coordinate;
      _label = null;
      _resolving = true;
    });
    GeocodedPlace? place;
    try {
      place = await ref.read(geocodingRepositoryProvider).reverse(coordinate);
    } catch (_) {
      // The pin coordinate remains usable when reverse geocoding fails.
    }
    if (!mounted || token != _resolveToken) return;
    setState(() {
      _label = place?.name;
      _resolving = false;
    });
  }

  void _confirm() {
    final coordinate = _picked;
    if (coordinate == null) return;
    final suggested = widget.suggested;
    final label =
        suggested != null && identical(coordinate, suggested.coordinate)
        // Unmoved: a Google place is named in the rider's own words.
        ? (suggested.id.startsWith('google:')
              ? suggested.riderLabel('Pinned location')
              : suggested.name)
        : _label ?? (_adjustingPickup ? 'Near you' : 'Pinned location');
    Navigator.of(context).pop(
      DemoPlace(
        id: _adjustingPickup
            ? adjustedPickupId
            : 'pin-${coordinate.latitude},${coordinate.longitude}',
        name: label,
        address:
            '${coordinate.latitude.toStringAsFixed(5)}, '
            '${coordinate.longitude.toStringAsFixed(5)}',
        coordinate: coordinate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    final centre = _picked ?? state.pickup.coordinate;
    final anchor = widget.pickupAnchor;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _adjustingPickup
              ? 'Adjust pickup'
              : widget.suggested != null
              ? 'Confirm location'
              : 'Pin on map',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: LiveMapView(
                    center: centre,
                    // At 15.5 the whole 100 m leash is ~30 dp across and every
                    // correcting tap lands on a pin; street level fits it.
                    zoom: _adjustingPickup
                        ? 18
                        : widget.suggested != null
                        ? 17
                        : 15.5,
                    borderRadius: BorderRadius.zero,
                    onMapTap: _onTap,
                    markers: [
                      // Where GPS says you are, so the leash is visible.
                      if (anchor != null)
                        MapMarker(
                          coordinate: anchor,
                          color: AppColors.skySoft,
                          radius: 6,
                        ),
                      if (_picked != null)
                        MapMarker(
                          coordinate: _picked!,
                          color: AppColors.primary,
                          radius: 9,
                          draggable: true,
                        ),
                    ],
                  ),
                ),
                if (_picked == null)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 14,
                    child: Center(child: _TapHint()),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _picked == null
                        ? 'No point selected'
                        : (_resolving
                              ? 'Looking up this place…'
                              : (_label ?? 'Pinned location')),
                    style: AppTypography.h2,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _adjustingPickup
                        ? 'Tap or drag the pin to the exact spot. '
                              'It stays within ${pickupAdjustRadiusMeters.round()} m of your location.'
                        : _picked == null
                        ? 'Tap anywhere on the map to drop a pin.'
                        : widget.suggested != null &&
                              identical(_picked, widget.suggested!.coordinate)
                        ? 'Check the pin. Tap or drag it if the spot is not exact.'
                        : '${_picked!.latitude.toStringAsFixed(5)}, '
                              '${_picked!.longitude.toStringAsFixed(5)}',
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ArangButton(
                    label: _adjustingPickup
                        ? 'Set pickup here'
                        : 'Use this location',
                    onPressed: _picked == null ? null : _confirm,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TapHint extends StatelessWidget {
  const _TapHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'Tap the map to drop a pin',
        style: AppTypography.caption,
      ),
    );
  }
}
