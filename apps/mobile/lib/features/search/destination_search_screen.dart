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
import '../../demo/demo_data.dart';
import '../../domain/geo/service_area.dart';

/// Destination picker following the prototype: pickup/destination card,
/// "use current location" and "pin on map" accelerators, then results.
///
/// Search is live MapTiler geocoding. Typing is debounced and short queries
/// never reach the network, because a geocoder fired on every keystroke is
/// both slow and wasteful. Saved and popular places are local accelerators,
/// not a substitute for search.
class DestinationSearchScreen extends ConsumerStatefulWidget {
  const DestinationSearchScreen({
    this.pickingPickup = false,
    this.selectOnly = false,
    super.key,
  });

  /// Return a place to the caller without changing the current booking.
  final bool selectOnly;

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
  int _searchToken = 0;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounceTimer?.cancel();
    _searchToken++;
    if (value.trim().length < 3) {
      setState(() {
        _results = const [];
        _error = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final token = _searchToken;
    _debounceTimer = Timer(_debounce, () => _search(value, token));
  }

  Future<void> _search(String query, int token) async {
    try {
      final places = await ref.read(geocodingRepositoryProvider).search(query);
      if (!mounted || token != _searchToken) return;
      final internalTester =
          ref.read(demoStateProvider).currentUser?.isInternalTester ?? false;
      setState(() {
        _results = places.where((place) {
          return ServiceArea.contains(
            place.coordinate,
            allowCabuyaoTestException: internalTester,
          );
        }).toList();
        _error = null;
        _searching = false;
      });
    } on ApiException catch (error) {
      if (!mounted || token != _searchToken) return;
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
    if (widget.selectOnly) {
      Navigator.of(context).pop(place);
      return;
    }
    final state = ref.read(demoStateProvider);
    if (widget.pickingPickup) {
      state.setPickup(place);
      if (state.destination != null) {
        context.go('/home/ride-options');
      } else {
        context.pop();
      }
      return;
    }
    state.setDestination(place);
    context.go(state.hasPickup ? '/home/ride-options' : '/home/choose-pickup');
  }

  Future<void> _pinOnMap() async {
    final place = await context.push<DemoPlace>('/home/pin-on-map');
    if (!mounted || place == null) return;
    _choose(place.name, place.address, place.coordinate);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    final hasQuery = _controller.text.trim().length >= 3;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: const TooltipVisibility(visible: false, child: BackButton()),
          title: Text(
            widget.selectOnly
                ? 'Save a place'
                : widget.pickingPickup
                ? 'Choose pickup'
                : 'Choose destination',
          ),
        ),
        body: SafeArea(
          top: false,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!widget.selectOnly && !widget.pickingPickup)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.my_location,
                            color: AppColors.primary,
                          ),
                          title: Text(
                            state.hasPickup
                                ? (!ServiceArea.contains(
                                        state.pickup.coordinate,
                                      )
                                      ? 'Out of Service Area'
                                      : state.pickup.name)
                                : 'Current location',
                          ),
                          subtitle: const Text('Pickup'),
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _controller,
                        autofocus: false,
                        textInputAction: TextInputAction.search,
                        onChanged: _onChanged,
                        decoration: InputDecoration(
                          hintText: widget.pickingPickup
                              ? 'Search pickup location…'
                              : 'Search destination in Calamba…',
                          hintStyle: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                          prefixIcon: const Icon(Icons.search, size: 24),
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear',
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _controller.clear();
                                    _onChanged('');
                                  },
                                ),
                        ),
                      ),
                      if (!widget.selectOnly) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            label: const Text('Pin on map'),
                            icon: const Icon(Icons.place_outlined, size: 18),
                            onPressed: _pinOnMap,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Divider(),
                    ],
                  ),
                ),
              ),
              if (hasQuery)
                _ResultsList(
                  searching: _searching,
                  error: _error,
                  results: _results,
                  onSelect: (p) => _choose(p.name, p.context, p.coordinate),
                )
              else
                _Accelerators(
                  savedPlaces: ref.watch(savedPlacesRepositoryProvider).places,
                  onSelect: (place) =>
                      _choose(place.name, place.address, place.coordinate),
                ),
            ],
          ),
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
      return SliverList.builder(
        itemCount: 4,
        itemBuilder: (context, i) => const _ResultSkeleton(),
      );
    }
    if (error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _Message(
          icon: Icons.search_off,
          title: 'Search unavailable',
          body: '$error\nClear your search to pick a saved or popular place.',
        ),
      );
    }
    if (results.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _Message(
          icon: Icons.search_off,
          title: 'No matches',
          body: 'Try a different spelling, or pin the spot on the map.',
        ),
      );
    }
    return SliverList.builder(
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
  const _Accelerators({required this.onSelect, required this.savedPlaces});

  final ValueChanged<DemoPlace> onSelect;
  final List<DemoPlace> savedPlaces;

  @override
  Widget build(BuildContext context) {
    return SliverList.list(
      children: [
        if (savedPlaces.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: ArangSectionHead('Saved places'),
          ),
          for (final place in savedPlaces)
            ArangRow(
              icon: Icons.bookmark_border,
              title: place.name,
              subtitle: place.address,
              showChevron: false,
              onTap: () => onSelect(place),
            ),
        ],
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
