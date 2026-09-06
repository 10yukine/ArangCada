import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/geo/haversine.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/map/live_map_view.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/location_repository.dart';
import '../../domain/geo/service_area.dart';
import '../../demo/demo_data.dart';

/// Commuter home, following the approved prototype's composition: greeting
/// row, destination field, Plan Your Ride, discount card, then a compact
/// "Drivers Nearby You" map.
///
/// Deliberately NOT a full-screen map. The prototype puts a small map card at
/// the foot of a scrolling page, which is what a commuter needs before a
/// destination exists.
class CommuterHomeScreen extends ConsumerStatefulWidget {
  const CommuterHomeScreen({super.key});

  @override
  ConsumerState<CommuterHomeScreen> createState() => _CommuterHomeScreenState();
}

class _CommuterHomeScreenState extends ConsumerState<CommuterHomeScreen> {
  LocationFix? _fix;
  LocationFailure? _locationError;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    // Connected commuters must start from device GPS, so request while-in-use
    // access immediately. Hidden local demos keep their no-prompt behavior.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final user = ref.read(demoStateProvider).currentUser;
      if (user == null) return;
      if (user.isDemoAccount) {
        final granted = await ref
            .read(locationRepositoryProvider)
            .hasPermission();
        if (!mounted || !granted) return;
      }
      if (!mounted) return;
      await _locate(silent: user.isDemoAccount);
    });
  }

  Future<void> _locate({bool silent = false}) async {
    if (_locating) return;
    setState(() {
      _locating = true;
      if (!silent) _locationError = null;
    });
    try {
      final repository = ref.read(locationRepositoryProvider);
      final fix = await repository.currentLocation();
      if (!mounted) return;
      // A fix must become the actual booking origin. Labelling it while
      // leaving DemoState.pickup untouched would price the ride from a
      // different point than the one shown.
      final internalTester =
          ref.read(demoStateProvider).currentUser?.isInternalTester ?? false;
      if (!fix.isCoarse &&
          ServiceArea.contains(
            fix.coordinate,
            allowCabuyaoTestException: internalTester,
          )) {
        ref
            .read(demoStateProvider)
            .setPickup(
              DemoPlace(
                id: 'gps',
                name: 'Current location',
                address:
                    '${fix.coordinate.latitude.toStringAsFixed(5)}, '
                    '${fix.coordinate.longitude.toStringAsFixed(5)}',
                coordinate: fix.coordinate,
              ),
            );
      }
      setState(() {
        _fix = fix;
        _locationError = null;
      });
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      setState(() => _locationError = failure);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final firstName = (state.currentUser?.displayName ?? 'there')
            .split(' ')
            .first;
        final centre = _fix?.coordinate ?? state.pickup.coordinate;
        final connected = ref.read(liveRideRepositoryProvider) != null;
        // Read fresh on every rebuild of this ListenableBuilder, same as
        // `connected` above -- there is no server-pushed invalidation for a
        // local Hive cache, so "how stale can the dot be" is bounded by
        // how often this screen already rebuilds, not by anything new.
        final hasUnreadNotifications = ref
            .read(notificationsRepositoryProvider)
            .history()
            .any((item) => !item.read);

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              children: [
                _GreetingRow(
                  name: firstName,
                  imageUrl: state.currentUser?.avatarUrl,
                  hasUnreadNotifications: hasUnreadNotifications,
                ),
                const SizedBox(height: 14),
                ArangField(
                  icon: Icons.search,
                  text:
                      state.destination?.name ?? 'Where would you like to go?',
                  muted: state.destination == null,
                  onTap: () => context.push('/home/search'),
                ),
                const SizedBox(height: 14),
                if (state.destination != null)
                  _CurrentSelection(
                    pickupName: _pickupLabel(state.pickup.name),
                    destinationName: state.destination!.name,
                    onEdit: () => context.push('/home/search'),
                  )
                else
                  _PlanYourRide(
                    pickupName: _pickupLabel(state.pickup.name),
                    onTap: () => context.push('/home/search'),
                  ),
                // Below Plan Your Ride, not above it. Booking is why the app
                // gets opened; the fare matrix is reference material. It sat
                // between the search field and the primary action, so the first
                // thing a commuter met was a link to a table. It stays on the
                // screen -- the LGU rates are part of what this project has to
                // show a panel -- just underneath the thing people came to do.
                const SizedBox(height: AppSpacing.sm),
                const _DiscountCard(),
                if (_locationError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _LocationNotice(
                    failure: _locationError!,
                    busy: _locating,
                    onRetry: _locate,
                    onManual: () => context.push('/home/search'),
                  ),
                ],
                ArangSectionHead(
                  'Drivers Nearby You',
                  color: AppColors.textMuted,
                  trailing: Text(
                    _fix != null ? 'Near you' : 'Calamba',
                    style: AppTypography.caption,
                  ),
                ),
                LiveMapView(
                  center: centre,
                  height: 168,
                  zoom: 14.2,
                  // The one-shot fix is already drawn below. Enabling
                  // MapLibre's native puck here starts a retained 1-second
                  // location stream even after the user leaves this tab.
                  showUserLocation: false,
                  interactive: false,
                  markers: [
                    MapMarker(
                      coordinate: centre,
                      color: AppColors.primary,
                      radius: 8,
                    ),
                    if (connected && state.liveDriverLocation != null)
                      MapMarker(
                        coordinate: state.liveDriverLocation!,
                        color: AppColors.primaryText,
                        radius: 7,
                      ),
                    if (!connected)
                      for (final offset in _nearbyDriverOffsets)
                        MapMarker(
                          coordinate: GeoCoordinate(
                            latitude: centre.latitude + offset.$1,
                            longitude: centre.longitude + offset.$2,
                          ),
                          color: AppColors.primaryText,
                          radius: 5.5,
                        ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  connected
                      ? 'Assigned driver location updates during an active trip.'
                      : 'Tricycle positions are illustrative until TODA dispatch '
                            'is connected.',
                  style: AppTypography.caption.copyWith(fontSize: 11),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A coarse fix is never promoted to the booking pickup, so the label says
  /// so instead of implying precision the device did not provide.
  String _pickupLabel(String configuredName) {
    if (_fix == null) return configuredName;
    final internalTester =
        ref.read(demoStateProvider).currentUser?.isInternalTester ?? false;
    if (!ServiceArea.contains(
      _fix!.coordinate,
      allowCabuyaoTestException: internalTester,
    )) {
      return '$configuredName · you are outside ${ServiceArea.name}';
    }
    return _fix!.isCoarse
        ? '$configuredName · approximate location only'
        : configuredName;
  }
}

/// Deterministic offsets so markers do not jump on every rebuild.
const _nearbyDriverOffsets = <(double, double)>[
  (0.0031, -0.0024),
  (-0.0018, 0.0035),
  (0.0042, 0.0019),
  (-0.0036, -0.0031),
];

class _GreetingRow extends StatelessWidget {
  const _GreetingRow({
    required this.name,
    required this.hasUnreadNotifications,
    this.imageUrl,
  });

  final String name;
  final String? imageUrl;
  final bool hasUnreadNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ArangAvatar(name: name, imageUrl: imageUrl),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const Text(
                'Ready for your next ride?',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        ArangIconButton(
          icon: Icons.notifications_outlined,
          tooltip: 'Notifications',
          showDot: hasUnreadNotifications,
          onPressed: () => context.push('/notifications'),
        ),
      ],
    );
  }
}

class _DiscountCard extends StatelessWidget {
  const _DiscountCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.primaryFill,
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Student, Senior & PWD fares',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                // The published matrix prints its own discounted amounts, and
                // two rows are NOT a flat 20% of the full fare. Never state a
                // blanket percentage here.
                const Text(
                  'Discounted rates follow the LGU fare matrix.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ArangButton(
                    label: 'View fare matrix',
                    expand: false,
                    onPressed: () => context.push('/fare-matrix'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(
            Icons.local_offer_outlined,
            size: 34,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _PlanYourRide extends StatelessWidget {
  const _PlanYourRide({required this.pickupName, required this.onTap});

  final String pickupName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ArangSectionHead('Plan Your Ride'),
        ArangCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ArangRow(
                icon: Icons.my_location,
                title: pickupName,
                subtitle: 'Pickup Location',
                iconBackground: AppColors.greenFill,
                iconForeground: AppColors.green,
                showChevron: false,
                onTap: onTap,
              ),
              ArangRow(
                icon: Icons.place_outlined,
                title: 'Where are you going?',
                subtitle: 'Drop Location',
                iconBackground: AppColors.primaryFill,
                iconForeground: AppColors.primaryText,
                showDivider: false,
                onTap: onTap,
                trailing: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward,
                    size: 17,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CurrentSelection extends StatelessWidget {
  const _CurrentSelection({
    required this.pickupName,
    required this.destinationName,
    required this.onEdit,
  });

  final String pickupName;
  final String destinationName;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ArangSectionHead('Plan Your Ride'),
        ArangCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ArangRow(
                icon: Icons.my_location,
                title: pickupName,
                subtitle: 'Pickup Location',
                iconBackground: AppColors.greenFill,
                iconForeground: AppColors.green,
                showChevron: false,
                onTap: onEdit,
              ),
              ArangRow(
                icon: Icons.place_outlined,
                title: destinationName,
                subtitle: 'Drop Location',
                iconBackground: AppColors.primaryFill,
                iconForeground: AppColors.primaryText,
                showDivider: false,
                onTap: onEdit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationNotice extends StatelessWidget {
  const _LocationNotice({
    required this.failure,
    required this.busy,
    required this.onRetry,
    required this.onManual,
  });

  final LocationFailure failure;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final blocked =
        failure.reason == LocationFailureReason.permissionDeniedForever;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.amberFill,
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_off_outlined,
                size: 18,
                color: AppColors.amberText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Location unavailable',
                  style: AppTypography.label.copyWith(
                    color: AppColors.amberText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            failure.message,
            style: AppTypography.caption.copyWith(color: AppColors.amberText),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: ArangButton(
                  label: 'Choose pickup',
                  variant: ArangButtonVariant.ghost,
                  onPressed: onManual,
                ),
              ),
              if (!blocked) ...[
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: ArangButton(
                    label: busy ? 'Trying…' : 'Try again',
                    variant: ArangButtonVariant.ghost,
                    onPressed: busy ? null : onRetry,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
