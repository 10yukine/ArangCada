import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/geo/haversine.dart';
import '../../core/network/api_exceptions.dart';
import '../../core/widgets/adaptive_screen_frame.dart';
import '../../core/widgets/arang_ui.dart';
import '../../data/mock/demo_state.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/remote/location_iq_geocoding_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../demo/demo_data.dart';
import '../../domain/geo/service_area.dart';
import 'pin_on_map_screen.dart';

/// Destination picker following the prototype: pickup/destination card,
/// "use current location" and "pin on map" accelerators, then results.
///
/// Search uses the configured live geocoder. Typing is debounced and short queries
/// never reach the network, because a geocoder fired on every keystroke is
/// both slow and wasteful. Saved and popular places are local accelerators,
/// not a substitute for search.
///
/// Destination only: pickup always comes from the device's GPS (see
/// `PinOnMapScreen.pickupAnchor`), so a booking cannot start somewhere the
/// commuter is not.
class DestinationSearchScreen extends ConsumerStatefulWidget {
  const DestinationSearchScreen({this.selectOnly = false, super.key});

  /// Return a place to the caller without changing the current booking.
  final bool selectOnly;

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await refreshStaleSavedPlaces(ref) && mounted) setState(() {});
    });
  }

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
        _results = [
          ...places.where((place) {
            // Google suggestions carry no coordinate yet; Google already
            // restricts them to Calamba, and _select checks the real one.
            final coordinate = place.coordinate;
            return coordinate == null ||
                ServiceArea.contains(
                  coordinate,
                  allowCabuyaoTestException: internalTester,
                );
          }),
        ];
        _error = null;
        _searching = false;
      });
    } on ApiException catch (error) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _results = const [];
        _error = error.message;
        _searching = false;
      });
    }
  }

  void _searchPopular(DemoPlace place) {
    // These entries are search shortcuts, never authoritative coordinates.
    _controller.text = place.name;
    _onChanged(place.name);
  }

  void _selectSaved(DemoPlace place) {
    // Favorites saved from the old shortcut list need a fresh pin too.
    final legacy = DemoData.places.any(
      (seed) =>
          seed.name == place.name &&
          seed.coordinate.latitude == place.coordinate.latitude &&
          seed.coordinate.longitude == place.coordinate.longitude,
    );
    if (legacy) {
      _searchPopular(place);
      return;
    }
    // A saved Google place is a search result again each time it is used.
    if (place.id.startsWith('google:')) {
      _confirmOnMap(place);
      return;
    }
    _choose(place.name, place.address, place.coordinate);
  }

  Future<void> _select(GeocodedPlace result) async {
    final coordinate =
        result.coordinate ??
        await ref.read(geocodingRepositoryProvider).locate(result);
    if (!mounted) return;
    if (coordinate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't load that place. Try again, or pin it on the map.",
          ),
        ),
      );
      return;
    }
    await _confirmOnMap(
      DemoPlace(
        id: result.placeId == null ? 'search' : result.id,
        name: result.name,
        address: result.context,
        coordinate: coordinate,
        riderText: result.placeId == null ? null : _controller.text.trim(),
      ),
    );
  }

  /// The rider confirms a search result on the map, and the confirmed pin is
  /// what gets booked and tested against the service area (see
  /// PinOnMapScreen.suggested). An unmoved pin has the result's coordinates.
  Future<void> _confirmOnMap(DemoPlace suggested) async {
    final pin = await _openPin(suggested);
    if (!mounted || pin == null) return;
    final internalTester =
        ref.read(demoStateProvider).currentUser?.isInternalTester ?? false;
    if (!ServiceArea.contains(
      pin.coordinate,
      allowCabuyaoTestException: internalTester,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('That pin is outside ${ServiceArea.name}.')),
      );
      return;
    }
    _choose(pin.name, pin.address, pin.coordinate);
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
    ref.read(demoStateProvider).setDestination(place);
    // Ride options explains itself if GPS has not produced a pickup yet.
    context.go('/home/ride-options');
  }

  /// Pushed directly, not as a go_router route: the router rebuilds whenever
  /// app state changes, and a rebuild drops a route's `extra` and its result.
  Future<DemoPlace?> _openPin([DemoPlace? suggested]) =>
      Navigator.of(context).push<DemoPlace>(
        MaterialPageRoute(
          builder: (_) =>
              AdaptiveScreenFrame(child: PinOnMapScreen(suggested: suggested)),
        ),
      );

  Future<void> _pinOnMap() async {
    final place = await _openPin();
    if (!mounted || place == null) return;
    _choose(place.name, place.address, place.coordinate);
  }

  String _pickupLabel(DemoState state) {
    if (!state.hasPickup) return 'Current location';
    if (!ServiceArea.contains(
      state.pickup.coordinate,
      allowCabuyaoTestException: state.currentUser?.isInternalTester ?? false,
    )) {
      return 'Out of Service Area';
    }
    return state.pickup.name;
  }

  /// Destination input. Focused on arrival: typing where you are going is the
  /// whole point of this screen, so the keyboard is already up.
  Widget _searchField({required bool framed}) {
    final borderless = const OutlineInputBorder(borderSide: BorderSide.none);
    return TextField(
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: _onChanged,
      style: AppTypography.body,
      decoration: InputDecoration(
        hintText: widget.selectOnly
            ? 'Search a place in Calamba…'
            : 'Where are you going?',
        filled: framed,
        border: framed ? null : borderless,
        enabledBorder: framed ? null : borderless,
        focusedBorder: framed ? null : borderless,
        prefixIcon: framed
            ? const Icon(Icons.search, size: 22)
            : const Padding(
                padding: EdgeInsets.only(left: 11, right: 9),
                child: Align(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: ArangRouteMarker(destination: true),
                ),
              ),
        prefixIconConstraints: framed
            ? null
            : const BoxConstraints(minWidth: 40, minHeight: 48),
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
    );
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
          title: Text(widget.selectOnly ? 'Save a place' : 'Where to?'),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        // The same journey card as Home, opened up: pickup above,
                        // the destination being typed below it.
                        child: widget.selectOnly
                            ? _searchField(framed: true)
                            : DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.lg,
                                  ),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        11,
                                        12,
                                        16,
                                        10,
                                      ),
                                      child: Row(
                                        children: [
                                          const ArangRouteMarker(
                                            destination: false,
                                          ),
                                          const SizedBox(width: 9),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Pickup',
                                                  style: AppTypography.caption,
                                                ),
                                                Text(
                                                  _pickupLabel(state),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: AppTypography.bodySm
                                                      .copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 1, indent: 40),
                                    _searchField(framed: false),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    if (!widget.selectOnly)
                      SliverToBoxAdapter(
                        child: ArangRow(
                          icon: Icons.map_outlined,
                          iconBackground: AppColors.primaryFill,
                          iconForeground: AppColors.primary,
                          title: 'Choose on map',
                          subtitle: "Drop a pin when search can't find it",
                          showChevron: false,
                          onTap: _pinOnMap,
                        ),
                      ),
                    if (hasQuery)
                      _ResultsList(
                        searching: _searching,
                        error: _error,
                        results: _results,
                        onSelect: _select,
                      )
                    else
                      _Accelerators(
                        savedPlaces: ref
                            .watch(savedPlacesRepositoryProvider)
                            .places,
                        onPopular: _searchPopular,
                        onSelect: _selectSaved,
                      ),
                  ],
                ),
              ),
              if (!_searching &&
                  _error == null &&
                  hasQuery &&
                  _results.any((place) => place.placeId != null))
                const _GoogleMapsCredit(),
              if (!_searching &&
                  _error == null &&
                  hasQuery &&
                  _results.any(
                    (place) => place.id.startsWith(
                      LocationIqGeocodingRepository.idPrefix,
                    ),
                  ))
                const _LocationIqCredit(),
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

class _GoogleMapsCredit extends StatelessWidget {
  const _GoogleMapsCredit();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          'Google Maps',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 12,
            color: Color(0xFF5E5E5E),
          ),
        ),
      ),
    );
  }
}

/// LocationIQ's free plan asks for this link wherever its results are shown.
class _LocationIqCredit extends StatelessWidget {
  const _LocationIqCredit();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () => launchUrl(
          Uri.parse('https://locationiq.com'),
          mode: LaunchMode.externalApplication,
        ).catchError((_) => false),
        child: const Text(
          'Search by LocationIQ.com · © OpenStreetMap contributors',
          style: TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}

class _Accelerators extends StatelessWidget {
  const _Accelerators({
    required this.onSelect,
    required this.onPopular,
    required this.savedPlaces,
  });

  final ValueChanged<DemoPlace> onSelect;
  final ValueChanged<DemoPlace> onPopular;
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
            onTap: () => onPopular(place),
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
