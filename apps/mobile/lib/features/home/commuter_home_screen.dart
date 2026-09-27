import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/map/live_map_view.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/location_repository.dart';
import '../../domain/geo/service_area.dart';
import '../../core/geo/haversine.dart';
import '../../demo/demo_data.dart';
import '../search/pin_on_map_screen.dart';
import '../../core/widgets/philippine_peso_icon.dart';

/// Commuter dashboard: streamlined, transit-first interface.
/// Anchored on the commuter's profile identity, rapid trip planning,
/// live TODA map overview, and local Calamba fare transparency.
class CommuterHomeScreen extends ConsumerStatefulWidget {
  const CommuterHomeScreen({super.key});

  @override
  ConsumerState<CommuterHomeScreen> createState() => _CommuterHomeScreenState();
}

class _CommuterHomeScreenState extends ConsumerState<CommuterHomeScreen>
    with WidgetsBindingObserver {
  Timer? _gpsTimer;
  bool _autoGpsEnabled = false;
  LocationFix? _fix;
  LocationFailure? _locationError;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      _autoGpsEnabled = true;
      await _locate(silent: user.isDemoAccount);
      if (mounted) {
        _startGpsTimer();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gpsTimer?.cancel();
    super.dispose();
  }

  void _startGpsTimer() {
    _gpsTimer?.cancel();
    _gpsTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _locate(silent: true),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_autoGpsEnabled) return;
    if (state == AppLifecycleState.resumed) {
      _locate(silent: true);
      _startGpsTimer();
    } else {
      _gpsTimer?.cancel();
    }
  }

  Future<void> _locate({bool silent = false}) async {
    if (_locating) return;
    final state = ref.read(demoStateProvider);
    final pickupBeforeRequest = state.pickup;
    setState(() {
      _locating = true;
      if (!silent) _locationError = null;
    });
    try {
      final repository = ref.read(locationRepositoryProvider);
      final fix = await repository.currentLocation();
      if (!mounted) return;
      // Pickup follows GPS. A nudged pin is kept only while the commuter is
      // still near it; walk away and pickup snaps back to where they are.
      final nudgedButStale =
          state.hasPickup &&
          state.pickup.id == adjustedPickupId &&
          haversineDistanceMeters(fix.coordinate, state.pickup.coordinate) >
              pickupAdjustRadiusMeters * 1.5;
      if (!fix.isCoarse &&
          identical(state.pickup, pickupBeforeRequest) &&
          (!state.hasPickup || state.pickup.id == 'gps' || nudgedButStale)) {
        state.setPickup(
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
        _locationError = fix.isCoarse
            ? const LocationFailure(
                LocationFailureReason.unavailable,
                'GPS is approximate. Enable precise location.',
              )
            : null;
      });
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _fix = null;
        _locationError = failure;
      });
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
        final user = state.currentUser;
        final firstName = (user?.displayName ?? 'there').split(' ').first;
        final centre = _fix?.coordinate;
        final connected = ref.read(liveRideRepositoryProvider) != null;
        final hasUnreadNotifications = ref
            .read(notificationsRepositoryProvider)
            .history()
            .any((item) => !item.read);

        final colors = Theme.of(context).colorScheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                _HomeHeader(
                  name: firstName,
                  imageUrl: user?.avatarUrl,
                  hasUnreadNotifications: hasUnreadNotifications,
                ),
                const SizedBox(height: 18),
                Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    side: const BorderSide(color: AppColors.border, width: 1.2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                color: AppColors.primaryFill,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.my_location,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Pickup',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _locating &&
                                            _fix == null &&
                                            !state.hasPickup
                                        ? 'Finding your location…'
                                        : _pickupLabel(
                                            state.hasPickup
                                                ? state.pickup.name
                                                : 'Current location',
                                          ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Adjust pickup pin',
                              icon: const Icon(
                                Icons.edit_location_alt_outlined,
                                size: 20,
                                color: AppColors.primary,
                              ),
                              onPressed: _fix == null || _fix!.isCoarse
                                  ? null
                                  : _adjustPickup,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 64, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: InkWell(
                          onTap: () => context.push('/home/search'),
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(AppRadii.md),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.22,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.search,
                                  size: 20,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    state.destination?.name ??
                                        'Where are you going?',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_locationError != null && !state.hasPickup) ...[
                  const SizedBox(height: 12),
                  _LocationNotice(
                    failure: _locationError!,
                    busy: _locating,
                    onRetry: _locate,
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const ArangRowIcon(
                    Icons.bookmark_border,
                    background: AppColors.primaryFill,
                    foreground: AppColors.primary,
                  ),
                  title: const Text(
                    'Saved places',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  subtitle: const Text(
                    'Keep your usual stops close',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  onTap: () => context.push('/profile/saved-places'),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primaryFill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const PhilippinePesoIcon(
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  title: const Text(
                    'Know your fare',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  subtitle: const Text(
                    'Official Calamba LGU rates & eligible discounts',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  onTap: () => context.push('/fare-matrix'),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Around you',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ArangBadge(
                      _fix == null
                          ? 'GPS unavailable'
                          : _fix!.isCoarse
                          ? 'Approximate GPS'
                          : 'Live GPS',
                      tone: _fix != null
                          ? ArangBadgeTone.brand
                          : ArangBadgeTone.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (centre != null)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LiveMapView(
                      center: centre,
                      height: MediaQuery.textScalerOf(context).scale(180),
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      zoom: 14.5,
                      showUserLocation: true,
                      interactive: true,
                      markers: [
                        MapMarker(
                          coordinate: centre,
                          color: colors.primary,
                          radius: 8,
                        ),
                        if (connected && state.liveDriverLocation != null)
                          MapMarker(
                            coordinate: state.liveDriverLocation!,
                            color: colors.primary,
                            radius: 7,
                          ),
                      ],
                    ),
                  )
                else
                  const SizedBox(
                    height: 180,
                    child: Center(child: Text('Waiting for device GPS…')),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Your driver appears here once assigned.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _adjustPickup() async {
    final fix = _fix;
    if (fix == null) return;
    final place = await context.push<DemoPlace>(
      '/home/adjust-pickup',
      extra: fix.coordinate,
    );
    if (!mounted || place == null) return;
    ref.read(demoStateProvider).setPickup(place);
  }

  String _pickupLabel(String configuredName) {
    if (ref.read(demoStateProvider).hasPickup &&
        ref.read(demoStateProvider).pickup.id != 'gps') {
      return configuredName;
    }
    if (_fix != null) {
      if (!ServiceArea.contains(_fix!.coordinate)) {
        return 'Out of Service Area';
      }
      return _fix!.isCoarse
          ? '$configuredName · approximate location only'
          : configuredName;
    }
    if (_locationError != null) {
      return 'Location unavailable';
    }
    return configuredName;
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.name,
    required this.imageUrl,
    required this.hasUnreadNotifications,
  });

  final String name;
  final String? imageUrl;
  final bool hasUnreadNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Profile',
          child: InkWell(
            onTap: () => context.push('/profile'),
            borderRadius: BorderRadius.circular(24),
            child: ArangAvatar(name: name, imageUrl: imageUrl, size: 44),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Hello, $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Ready for your next ride?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
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

class _LocationNotice extends StatelessWidget {
  const _LocationNotice({
    required this.failure,
    required this.busy,
    required this.onRetry,
  });

  final LocationFailure failure;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.amberFill,
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)),
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
              const Expanded(
                child: Text(
                  'Location unavailable',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.amberText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            failure.message,
            style: const TextStyle(fontSize: 12, color: AppColors.amberText),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: ArangButton(
              label: busy ? 'Trying…' : 'Try again',
              variant: ArangButtonVariant.ghost,
              onPressed: busy ? null : onRetry,
            ),
          ),
        ],
      ),
    );
  }
}
