import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/geo/haversine.dart';
import '../../core/network/api_exceptions.dart';
import '../../core/widgets/arang_ui.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../data/repositories/location_repository.dart';
import '../../demo/demo_data.dart';

/// Destination picker following the prototype: pickup/destination card,
/// "use current location" and "pin on map" accelerators, then results.
///
/// Search is live MapTiler geocoding. Typing is debounced and short queries
/// never reach the network, because a geocoder fired on every keystroke is
/// both slow and wasteful. Saved and popular places are local accelerators,
/// not a substitute for search.
class DestinationSearchScreen extends ConsumerStatefulWidget {
  const DestinationSearchScreen({this.pickingPickup = false, super.key});

  /// When true the screen sets the PICKUP instead of the destination.
  final bool pickingPickup;

  @override
  ConsumerState<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState
    extends ConsumerState<DestinationSearchScreen> {
  static const Duration _debounce = Duration(milliseconds: 400);

  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;

  List<GeocodedPlace> _results = const [];
  bool _searching = false;
  String? _error;
  bool _locating = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounceTimer?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _results = const [];
        _error = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounceTimer = Timer(_debounce, () => _search(value));
  }

  Future<void> _search(String query) async {
    try {
      final places = await ref.read(geocodingRepositoryProvider).search(query);
      if (!mounted) return;
      setState(() {
        _results = places;
        _error = null;
        _searching = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _searching = false;
      });
    }
  }

  void _choose(String name, String address, GeoCoordinate coordinate) {
    final place = DemoPlace(
      id: 'geo-${coordinate.latitude},${coordinate.longitude}',
      name: name,
      address: address,
      coordinate: coordinate,
    );
    final state = ref.read(demoStateProvider);
    if (widget.pickingPickup) {
      state.setPickup(place);
      context.pop();
      return;
    }
    state.setDestination(place);
    context.go('/home/ride-options');
  }

  /// Sets the PICKUP from GPS. This is a destination picker, so using the
  /// device position as the *destination* would be nonsensical -- it would
  /// book a ride to where the commuter already is.
  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    // Both repositories are captured before the first await, so nothing
    // touches `ref` after the widget may have been disposed.
    final locationRepository = ref.read(locationRepositoryProvider);
    final geocodingRepository = ref.read(geocodingRepositoryProvider);
    final demoState = ref.read(demoStateProvider);
    try {
      final fix = await locationRepository.currentLocation();
      if (!mounted) return;

      // Reverse geocoding is a label nicety and must not hold the user for the
      // full network timeout; a coordinate label is an acceptable answer.
      final place = await geocodingRepository
          .reverse(fix.coordinate)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (!mounted) return;

      demoState.setPickup(
        DemoPlace(
          id: 'gps',
          name: place?.name ?? 'Current location',
          address:
              place?.context ??
              '${fix.coordinate.latitude.toStringAsFixed(5)}, '
                  '${fix.coordinate.longitude.toStringAsFixed(5)}',
          coordinate: fix.coordinate,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pickup set to your current location.')),
      );
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    final hasQuery = _controller.text.trim().length >= 3;
    final canChoosePickup = state.currentUser?.canChoosePickup ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.pickingPickup ? 'Choose pickup' : 'Choose destination',
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ArangCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ArangRow(
                      icon: Icons.my_location,
                      title: state.pickup.name,
                      subtitle: canChoosePickup && !widget.pickingPickup
                          ? 'Pickup · tap to change'
                          : 'Pickup',
                      iconBackground: AppColors.greenFill,
                      iconForeground: AppColors.green,
                      showChevron: canChoosePickup && !widget.pickingPickup,
                      showDivider: true,
                      onTap: canChoosePickup && !widget.pickingPickup
                          ? () => context.push('/home/choose-pickup')
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: TextField(
                        controller: _controller,
                        autofocus: false,
                        textInputAction: TextInputAction.search,
                        onChanged: _onChanged,
                        decoration: InputDecoration(
                          hintText: 'Search for a place in Calamba',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear',
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    _controller.clear();
                                    _onChanged('');
                                  },
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ArangButton(
                      label: _locating ? 'Locating…' : 'Use current location',
                      icon: Icons.gps_fixed,
                      variant: ArangButtonVariant.ghost,
                      onPressed: _locating ? null : _useCurrentLocation,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: ArangButton(
                      label: 'Pin on map',
                      icon: Icons.place_outlined,
                      variant: ArangButtonVariant.ghost,
                      onPressed: () => context.push('/home/pin-on-map'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: hasQuery
                  ? _ResultsList(
                      searching: _searching,
                      error: _error,
                      results: _results,
                      onSelect: (p) => _choose(p.name, p.context, p.coordinate),
                    )
                  : _Accelerators(
                      onSelect: (place) =>
                          _choose(place.name, place.address, place.coordinate),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.searching,
    required this.error,
    required this.results,
    required this.onSelect,
  });

  final bool searching;
  final String? error;
  final List<GeocodedPlace> results;
  final ValueChanged<GeocodedPlace> onSelect;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return ListView.builder(
        itemCount: 4,
        itemBuilder: (context, i) => const _ResultSkeleton(),
      );
    }
    if (error != null) {
      return _Message(
        icon: Icons.search_off,
        title: 'Search unavailable',
        body: '$error\nYou can still pick a saved or popular place.',
      );
    }
    if (results.isEmpty) {
      return const _Message(
        icon: Icons.search_off,
        title: 'No matches',
        body: 'Try a different spelling, or pin the spot on the map.',
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final place = results[i];
        return ArangRow(
          icon: Icons.place_outlined,
          title: place.name,
          subtitle: place.context,
          showChevron: false,
          onTap: () => onSelect(place),
        );
      },
    );
  }
}

class _Accelerators extends StatelessWidget {
  const _Accelerators({required this.onSelect});

  final ValueChanged<DemoPlace> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: ArangSectionHead('Popular in Calamba'),
        ),
        for (final place in DemoData.places)
          ArangRow(
            icon: Icons.place_outlined,
            title: place.name,
            subtitle: place.address,
            showChevron: false,
            onTap: () => onSelect(place),
          ),
      ],
    );
  }
}

class _ResultSkeleton extends StatelessWidget {
  const _ResultSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.neutralFill,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: AppSizes.rowIcon,
            height: AppSizes.rowIcon,
            decoration: BoxDecoration(
              color: AppColors.neutralFill,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [bar(160, 12), const SizedBox(height: 7), bar(110, 10)],
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.sm),
            Text(title, style: AppTypography.h2),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}
