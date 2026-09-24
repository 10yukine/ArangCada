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

/// Drop a pin to choose a destination the geocoder does not know.
///
/// The centre of the viewport is the selection, which is why the crosshair is
/// drawn as a fixed overlay rather than a map annotation. Reverse geocoding
/// labels the point when it can; when it cannot, the coordinate itself is the
/// label. Selection is never blocked on the geocoder answering.
class PinOnMapScreen extends ConsumerStatefulWidget {
  const PinOnMapScreen({super.key});

  @override
  ConsumerState<PinOnMapScreen> createState() => _PinOnMapScreenState();
}

class _PinOnMapScreenState extends ConsumerState<PinOnMapScreen> {
  GeoCoordinate? _picked;
  String? _label;
  bool _resolving = false;
  int _resolveToken = 0;

  Future<void> _onTap(GeoCoordinate coordinate) async {
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
    final label = _label ?? 'Pinned location';
    Navigator.of(context).pop(
      DemoPlace(
        id: 'pin-${coordinate.latitude},${coordinate.longitude}',
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

    return Scaffold(
      appBar: AppBar(title: const Text('Pin on map')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: LiveMapView(
                    center: centre,
                    zoom: 15.5,
                    borderRadius: BorderRadius.zero,
                    onMapTap: _onTap,
                    markers: [
                      if (_picked != null)
                        MapMarker(
                          coordinate: _picked!,
                          color: AppColors.primary,
                          radius: 9,
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
                    _picked == null
                        ? 'Tap anywhere on the map to drop a pin.'
                        : '${_picked!.latitude.toStringAsFixed(5)}, '
                              '${_picked!.longitude.toStringAsFixed(5)}',
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ArangButton(
                    label: 'Use this location',
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
