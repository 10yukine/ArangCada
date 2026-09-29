import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/widgets/trip_call_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_dialog.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/map/live_map_view.dart';
import '../../core/widgets/map/route_preview_map.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/sheet_drag_handle.dart';
import '../../core/nav/external_navigation.dart';
import '../../core/widgets/sos_hold_button.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/remote/supabase_ride_repository.dart';
import '../../demo/demo_simulation.dart';
import '../../domain/state/driver_trip_state_machine.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen>
    with WidgetsBindingObserver {
  final _mapController = LiveMapViewController();
  Timer? _countdownTimer;
  Timer? _completionTicker;
  DemoSimulationRun? _requestRun;
  int _secondsRemaining = 30;
  VoidCallback? _removeLiveStateListener;
  bool _actionPending = false;
  bool _expirePending = false;
  Timer? _gpsTimer;
  LocationFix? _dashboardFix;
  LocationFailure? _locationError;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          ref.read(demoStateProvider).currentUser?.isDemoAccount != false) {
        return;
      }
      _locateDriver();
      _startGpsTimer();
    });
    final state = ref.read(demoStateProvider);
    if (ref.read(liveRideRepositoryProvider) != null) {
      state.addListener(_handleLiveDriverState);
      _removeLiveStateListener = () {
        state.removeListener(_handleLiveDriverState);
      };
    }
    if (state.driverTrip.status == DriverTripStatus.incoming) {
      _startCountdown();
    } else if (state.driverTrip.status == DriverTripStatus.available) {
      _scheduleRequest();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (ref.read(demoStateProvider).currentUser?.isDemoAccount != false) return;
    if (state == AppLifecycleState.resumed) {
      _locateDriver();
      _startGpsTimer();
    } else {
      _gpsTimer?.cancel();
    }
  }

  void _startGpsTimer() {
    _gpsTimer?.cancel();
    _gpsTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _locateDriver(),
    );
  }

  Future<void> _locateDriver() async {
    if (_locating || !mounted) return;
    setState(() => _locating = true);
    try {
      final fix = await ref.read(locationRepositoryProvider).currentLocation();
      if (!mounted) return;
      setState(() {
        _dashboardFix = fix.isCoarse ? null : fix;
        _locationError = fix.isCoarse
            ? const LocationFailure(
                LocationFailureReason.unavailable,
                'GPS is approximate. Enable precise location and try again.',
              )
            : null;
      });
    } on LocationFailure catch (failure) {
      if (mounted) {
        setState(() {
          _dashboardFix = null;
          _locationError = failure;
        });
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _handleLiveDriverState() {
    if (!mounted) return;
    final state = ref.read(demoStateProvider);
    if (state.driverTrip.status == DriverTripStatus.incoming &&
        _countdownTimer == null) {
      _startCountdown();
    }
    if (state.driverTrip.status != DriverTripStatus.incoming) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }
    if (state.driverTrip.status == DriverTripStatus.inProgress &&
        state.completionAvailableAt != null &&
        _completionTicker == null) {
      _completionTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted ||
            SupabaseRideRepository.completionSecondsRemaining(
                  state.completionAvailableAt!,
                ) <=
                0) {
          timer.cancel();
          _completionTicker = null;
        }
        if (mounted) setState(() {});
      });
    }
    setState(() {});
  }

  void _scheduleRequest() {
    _requestRun?.cancel();
    if (ref.read(liveRideRepositoryProvider) != null) return;
    final state = ref.read(demoStateProvider);
    if (state.driverTrip.status != DriverTripStatus.available) return;
    _requestRun = ref
        .read(demoSimulationServiceProvider)
        .scheduleDriverRequest(
          state: state,
          onRequestReceived: () {
            if (!mounted) return;
            _startCountdown();
            setState(() {});
          },
        );
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    final liveRides = ref.read(liveRideRepositoryProvider);
    final deadline = liveRides?.activeTrip?['accept_by'] as String?;
    _secondsRemaining = deadline == null
        ? 30
        : (DateTime.parse(
                    deadline,
                  ).difference(DateTime.now().toUtc()).inMilliseconds /
                  1000)
              .ceil()
              .clamp(0, 30);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
        return;
      }
      final state = ref.read(demoStateProvider);
      if (state.driverTrip.status != DriverTripStatus.incoming) return;
      if (liveRides == null) {
        timer.cancel();
        _countdownTimer = null;
        state.driverTrip.declineRequest();
        state.driverChanged();
      } else if (timer.tick % 3 == 0) {
        unawaited(_expireRequest());
      }
    });
  }

  Future<void> _expireRequest() async {
    if (_expirePending) return;
    _expirePending = true;
    try {
      await ref.read(liveRideRepositoryProvider)?.expireRide();
    } on Exception {
      // A client timer can reach zero before the server's deadline. Retry.
    } finally {
      _expirePending = false;
    }
  }

  Future<void> _acceptRequest() async {
    if (_actionPending) return;
    _actionPending = true;
    _requestRun?.cancel();
    _countdownTimer?.cancel();
    _countdownTimer = null;
    final state = ref.read(demoStateProvider);
    final liveRides = ref.read(liveRideRepositoryProvider);
    try {
      if (liveRides == null) {
        state.driverTrip.acceptRequest();
        ref
            .read(chatRepositoryProvider)
            .ensureActiveTripThread(
              commuterName: 'Joshua Adia',
              driverName: state.currentUser?.displayName ?? 'Driver',
              bodyNumber: '024',
              todaName: 'Calamba TODA',
            );
        state.driverChanged();
      } else {
        await liveRides.acceptRide();
      }
      if (mounted) setState(() {});
    } on Exception {
      _showLiveActionError('Could not accept this ride. It may have expired.');
    } finally {
      _actionPending = false;
    }
  }

  Future<void> _declineRequest() async {
    _requestRun?.cancel();
    _countdownTimer?.cancel();
    _countdownTimer = null;
    final state = ref.read(demoStateProvider);
    final liveRides = ref.read(liveRideRepositoryProvider);
    try {
      if (liveRides == null) {
        state.driverTrip.declineRequest();
        state.driverChanged();
      } else {
        await liveRides.declineRide();
      }
      if (mounted) setState(() {});
    } on Exception {
      _showLiveActionError('Could not decline this request. Try again.');
    }
  }

  void _showLiveActionError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleAvailability() async {
    if (_actionPending) return;
    _actionPending = true;
    final state = ref.read(demoStateProvider);
    final liveRides = ref.read(liveRideRepositoryProvider);
    try {
      if (liveRides != null) {
        await liveRides.setDriverOnline(!state.driverTrip.isOnline);
      } else if (state.driverTrip.isOnline) {
        _requestRun?.cancel();
        state.driverTrip.goOffline();
        state.driverChanged();
      } else {
        if (state.driverTrip.status == DriverTripStatus.declined) {
          state.driverTrip.goOffline();
        }
        state.driverTrip.goOnline();
        _scheduleRequest();
        state.driverChanged();
      }
    } on Exception {
      _showLiveActionError(
        'Could not change availability. Check driver approval, required '
        'feedback, GPS, and connection.',
      );
    } finally {
      _actionPending = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _advancePickup() async {
    final state = ref.read(demoStateProvider);
    final liveRides = ref.read(liveRideRepositoryProvider);
    try {
      if (liveRides == null) {
        if (state.driverTrip.status == DriverTripStatus.accepted) {
          state.driverTrip.markArrivedAtPickup();
        } else {
          state.driverTrip.startTrip();
        }
        state.driverChanged();
      } else if (state.driverTrip.status == DriverTripStatus.accepted) {
        await liveRides.markArrived();
      } else {
        await liveRides.startTrip();
      }
    } on Exception {
      _showLiveActionError('Could not update the trip. Please try again.');
    }
  }

  /// Driver-side cancel while heading to or waiting at the pickup. A last
  /// resort: the owner's rule is that a driver who does not want a ride
  /// declines it rather than accepting it, and a cancellation after
  /// accepting is reported to TODA/LGU administrators and may be penalised.
  /// The server requires a reason and records it for their review.
  Future<void> _cancelPickup() async {
    final liveRides = ref.read(liveRideRepositoryProvider);
    if (liveRides == null) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _DriverCancelDialog(),
    );
    if (reason == null || !mounted) return;
    try {
      await liveRides.cancelRideAsDriver(reason);
      ref.read(chatRepositoryProvider).closeActiveTripThread();
    } on Exception {
      _showLiveActionError('Could not cancel the ride. Please try again.');
    }
  }

  Future<void> _completeTrip() async {
    final state = ref.read(demoStateProvider);
    final liveRides = ref.read(liveRideRepositoryProvider);
    try {
      if (liveRides == null) {
        state.driverTrip.completeTrip();
        state.driverChanged();
      } else {
        await liveRides.completeTrip();
      }
      ref.read(chatRepositoryProvider).closeActiveTripThread();
      if (mounted) context.go('/driver/rating');
    } on Exception {
      _showLiveActionError('Could not complete the trip. Please try again.');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gpsTimer?.cancel();
    _removeLiveStateListener?.call();
    _countdownTimer?.cancel();
    _completionTicker?.cancel();
    _requestRun?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            if (state.driverTrip.status == DriverTripStatus.accepted ||
                state.driverTrip.status == DriverTripStatus.arrivedAtPickup) {
              return _PickupModeCard(
                mapController: _mapController,
                arrived:
                    state.driverTrip.status == DriverTripStatus.arrivedAtPickup,
                onAction: _advancePickup,
                // Live trips only: a demo trip has no server ride to cancel.
                onCancel: ref.read(liveRideRepositoryProvider) == null
                    ? null
                    : _cancelPickup,
              );
            }
            if (state.driverTrip.status == DriverTripStatus.inProgress) {
              return _DriverTripModeCard(
                mapController: _mapController,
                onComplete: _completeTrip,
              );
            }
            // Read fresh on every rebuild of this ListenableBuilder, same
            // reasoning as the commuter home screen's identical read: there
            // is no server-pushed invalidation for a local Hive cache, so
            // "how stale can the dot be" is bounded by how often this
            // screen already rebuilds.
            final hasUnreadNotifications = ref
                .read(notificationsRepositoryProvider)
                .history()
                .any((item) => !item.read);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                // Prototype driver header: who you are, which body number and
                // TODA you drive under. The bell reads the same real
                // PushNotificationService history the commuter side does
                // (device-local, not per-role) -- it used to be a hardcoded
                // "No new notices" snackbar
                // driver-side audit entry.
                Row(
                  children: [
                    Semantics(
                      button: true,
                      label: 'Profile',
                      child: InkWell(
                        onTap: () => context.push('/driver/profile'),
                        borderRadius: BorderRadius.circular(24),
                        child: ArangAvatar(
                          name: state.currentUser?.displayName ?? 'Driver',
                          background: AppColors.primary,
                          foreground: Colors.white,
                          imageUrl: state.currentUser?.avatarUrl,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello, ${(state.currentUser?.displayName ?? 'Driver').split(' ').first}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            state.liveTodaName == null
                                ? 'Driver account'
                                : 'Driver · ${state.liveTodaName}',
                            style: const TextStyle(
                              fontSize: 13,
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
                ),
                const SizedBox(height: 14),
                _AvailabilityCard(
                  online: state.driverTrip.isOnline,
                  canToggle:
                      !_actionPending &&
                      !state.driverFeedbackPending &&
                      (state.driverTrip.status == DriverTripStatus.available ||
                          state.driverTrip.status == DriverTripStatus.offline ||
                          state.driverTrip.status == DriverTripStatus.declined),
                  onToggle: _toggleAvailability,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (state.driverTrip.status == DriverTripStatus.available)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Icon(Icons.radar, color: AppColors.primary),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Ready for requests. Keep the app open while you wait.',
                            style: AppTypography.bodySm,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (state.driverTrip.status == DriverTripStatus.incoming)
                  _IncomingRequestCard(
                    secondsRemaining: _secondsRemaining,
                    onAccept: _acceptRequest,
                    onDecline: _declineRequest,
                  ),
                // `completed` is a brief transitional state -- completing a
                // trip now pushes straight to /driver/rating -- but a driver
                // can still land here by backing out of that screen before
                // finishing, so it keeps a real exit and the same layout
                // position as `incoming` rather than a cramped afterthought
                // below the map.
                if (state.driverTrip.status == DriverTripStatus.completed)
                  _TripCompletedCard(
                    // A driver who rates the passenger and then backs out of
                    // /driver/rating before tapping its separate "Done"
                    // button (the only thing that calls finishDriverTrip())
                    // lands back here with status still `completed` --
                    // that recovery path is intentional (see the comment
                    // above this card). What was not intentional: this
                    // button always read "Rate Passenger" regardless of
                    // driverTripRating, so a driver who HAD already rated
                    // was invited straight back into a rating screen that
                    // could only show them their own already-submitted
                    // rating, with no way out except the same easy-to-miss
                    // "Done" button -- a genuine stuck loop. Once rated,
                    // this offers the one action that actually escapes
                    // `completed`, instead of re-opening rating.
                    alreadyRated: state.driverTripRating != null,
                    onRate: () => context.push('/driver/rating'),
                    onFinish: state.finishDriverTrip,
                  ),
                // Same row treatment as the commuter dashboard's shortcuts.
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const ArangRowIcon(
                    Icons.payments_outlined,
                    background: AppColors.primaryFill,
                    foreground: AppColors.primary,
                  ),
                  title: const Text(
                    'Earnings & settlements',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  subtitle: const Text(
                    'Review your trip earnings',
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
                  onTap: () => context.push('/driver/earnings'),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Your location',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    ArangBadge(
                      _dashboardFix == null ? 'GPS unavailable' : 'Live GPS',
                      tone: _dashboardFix == null
                          ? ArangBadgeTone.neutral
                          : ArangBadgeTone.brand,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_dashboardFix != null)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LiveMapView(
                      center: _dashboardFix!.coordinate,
                      height: 180,
                      zoom: 14.5,
                      showUserLocation: true,
                      interactive: true,
                      markers: [
                        MapMarker(
                          coordinate: _dashboardFix!.coordinate,
                          color: AppColors.primary,
                          radius: 8,
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(
                    height: 180,
                    child: Center(child: Text('Waiting for device GPS…')),
                  ),
                if (_locationError != null)
                  ListTile(
                    leading: const Icon(Icons.location_off_outlined),
                    title: Text(_locationError!.message),
                    trailing: TextButton(
                      onPressed: _locating ? null : _locateDriver,
                      child: const Text('Try again'),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TripCompletedCard extends StatelessWidget {
  const _TripCompletedCard({
    required this.alreadyRated,
    required this.onRate,
    required this.onFinish,
  });

  final bool alreadyRated;
  final VoidCallback onRate;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: AppColors.green, size: 42),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Trip completed',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            alreadyRated
                ? 'Your rating was submitted. Finish to go back online.'
                : 'Rate your passenger to finish and go back online.',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          ArangButton(
            label: alreadyRated ? 'Finish' : 'Rate Passenger',
            onPressed: alreadyRated ? onFinish : onRate,
          ),
        ],
      ),
    );
  }
}

class _IncomingRequestCard extends ConsumerWidget {
  const _IncomingRequestCard({
    required this.secondsRemaining,
    required this.onAccept,
    required this.onDecline,
  });

  final int secondsRemaining;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    final trip = ref.read(liveRideRepositoryProvider)?.activeTrip;
    final fare = trip?['fare_estimate'] as num?;
    // The server gives a driver at most 30 s to answer an offer.
    const window = 30;
    final urgent = secondsRemaining <= 10;
    final timeColor = urgent ? AppColors.danger : AppColors.primary;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('New ride request', style: AppTypography.h2),
              ),
              Text(
                '${secondsRemaining}s',
                style: AppTypography.label.copyWith(
                  color: timeColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // A draining bar reads faster than a number while driving.
          Semantics(
            label: 'Respond within $secondsRemaining seconds',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (secondsRemaining / window).clamp(0.0, 1.0),
                minHeight: 6,
                color: timeColor,
                backgroundColor: AppColors.primaryFill,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.liveCommuterName ?? 'Passenger',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Text(
                      'Espesyal na Byahe · cash',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              Text(
                fare == null
                    ? 'Fare unavailable'
                    : formatCentavos((fare * 100).round()),
                style: fare == null
                    ? AppTypography.caption
                    : AppTypography.displaySm.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ArangRouteStop(
            destination: false,
            label: 'Pickup',
            name: state.pickup.name,
          ),
          const SizedBox(height: AppSpacing.sm),
          ArangRouteStop(
            destination: true,
            label: 'Drop-off',
            name: state.destination?.name ?? 'Destination',
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerDark,
                    side: const BorderSide(color: AppColors.dangerBorder),
                  ),
                  onPressed: onDecline,
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Warns that cancelling is reported and may be penalised, and makes the
/// driver pick a reason before Cancel ride is enabled. Pops the reason key.
class _DriverCancelDialog extends StatefulWidget {
  const _DriverCancelDialog();

  @override
  State<_DriverCancelDialog> createState() => _DriverCancelDialogState();
}

class _DriverCancelDialogState extends State<_DriverCancelDialog> {
  String? _reason;

  @override
  Widget build(BuildContext context) {
    return ArangDialog(
      title: 'Cancel this ride?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cancelling after accepting is reported to your TODA and LGU '
            'administrators and may lead to penalties. If you do not want a '
            'ride, decline it instead of accepting.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Why are you cancelling?', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xxs),
          for (final MapEntry(key: key, value: label)
              in SupabaseRideRepository.driverCancelReasons.entries)
            InkWell(
              onTap: () => setState(() => _reason = key),
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Icon(
                      _reason == key
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: _reason == key
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: Text(label)),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep ride'),
        ),
        FilledButton(
          onPressed: _reason == null
              ? null
              : () => Navigator.pop(context, _reason),
          child: const Text('Cancel ride'),
        ),
      ],
    );
  }
}

class _PickupModeCard extends ConsumerWidget {
  const _PickupModeCard({
    required this.mapController,
    required this.arrived,
    required this.onAction,
    this.onCancel,
  });

  final VoidCallback? onCancel;

  final LiveMapViewController mapController;
  final bool arrived;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    return Stack(
      children: [
        Positioned.fill(
          child: state.liveDriverLocation == null
              ? const Center(child: Text('Waiting for device GPS…'))
              : RoutePreviewMap(
                  controller: mapController,
                  from: state.liveDriverLocation!,
                  to: state.pickup.coordinate,
                  height: double.infinity,
                  borderRadius: BorderRadius.zero,
                  showCaption: false,
                  interactive: true,
                ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _DriverMapSheet(
            key: mapController.panelKey,
            onCenterRoute: () => mapController.fitRoute(),
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ArangBadge(
                  arrived ? 'Waiting at pickup' : 'Navigate to pickup',
                  tone: ArangBadgeTone.green,
                ),
                const SizedBox(height: AppSpacing.sm),
                _PassengerRow(
                  name: state.liveCommuterName ?? 'Passenger',
                  detail: '${state.pickup.name} · Cash',
                  imageUrl: state.liveCounterpartAvatarUrl,
                ),
              ],
            ),
            actions: [
              if (!arrived) ...[
                ArangButton(
                  label: 'Open in Maps',
                  icon: Icons.navigation_outlined,
                  variant: ArangButtonVariant.ghost,
                  onPressed: () => openExternalNavigation(
                    state.pickup.coordinate,
                    label: state.pickup.name,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              ArangButton(
                label: arrived ? 'Start Trip' : 'Arrived at Pickup',
                onPressed: onAction,
              ),
              if (onCancel != null)
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.dangerDark,
                  ),
                  child: const Text('Cancel ride'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverTripModeCard extends ConsumerWidget {
  const _DriverTripModeCard({
    required this.mapController,
    required this.onComplete,
  });

  final LiveMapViewController mapController;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    return Stack(
      children: [
        Positioned.fill(
          child: state.destination == null
              ? const Center(child: Text('Trip destination unavailable'))
              : RoutePreviewMap(
                  controller: mapController,
                  from: state.pickup.coordinate,
                  to: state.destination!.coordinate,
                  height: double.infinity,
                  borderRadius: BorderRadius.zero,
                  showCaption: false,
                  interactive: true,
                  additionalMarkers: [
                    if (state.liveDriverLocation != null)
                      MapMarker(
                        coordinate: state.liveDriverLocation!,
                        color: AppColors.primaryText,
                        radius: 9,
                      ),
                  ],
                ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _DriverMapSheet(
            key: mapController.panelKey,
            onCenterRoute: () => mapController.fitRoute(),
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ArangBadge('On trip', tone: ArangBadgeTone.green),
                const SizedBox(height: AppSpacing.sm),
                _PassengerRow(
                  name: state.liveCommuterName ?? 'Passenger',
                  detail: '${state.destination?.name ?? 'Destination'} · Cash',
                  imageUrl: state.liveCounterpartAvatarUrl,
                ),
                if (state.completionAvailableAt != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Destination reached · completion available in '
                    '${SupabaseRideRepository.completionSecondsRemaining(state.completionAvailableAt!)}s',
                    style: AppTypography.caption,
                  ),
                ],
              ],
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: ArangButton(
                      label: 'Chat',
                      icon: Icons.chat_outlined,
                      variant: ArangButtonVariant.ghost,
                      onPressed: () => context.push('/chat/thread-active'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: ArangButton(
                      label: 'Call',
                      icon: Icons.call_outlined,
                      variant: ArangButtonVariant.ghost,
                      onPressed: () => showTripCallSheet(context),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: ArangButton(
                      label: 'Maps',
                      icon: Icons.navigation_outlined,
                      variant: ArangButtonVariant.ghost,
                      onPressed: state.destination == null
                          ? null
                          : () => openExternalNavigation(
                              state.destination!.coordinate,
                              label: state.destination!.name,
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              SosHoldButton(
                onCompleted: () => showSafetyReportFlow(
                  context: context,
                  driver: true,
                  onSubmit: () =>
                      ref.read(safetyRepositoryProvider).recordDemoAlert(),
                  onSubmitReason: ref
                      .read(liveRideRepositoryProvider)
                      ?.createSafetyReport,
                  connected: ref.read(liveRideRepositoryProvider) != null,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              ArangButton(label: 'Complete Trip', onPressed: onComplete),
            ],
          ),
        ),
      ],
    );
  }
}

class _PassengerRow extends StatelessWidget {
  const _PassengerRow({
    required this.name,
    required this.detail,
    this.imageUrl,
  });

  final String name;
  final String detail;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ArangAvatar(
          name: name,
          size: 40,
          background: AppColors.primaryFill,
          foreground: AppColors.primaryText,
          imageUrl: imageUrl,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleLarge),
              Text(detail, style: AppTypography.caption),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverMapSheet extends StatefulWidget {
  const _DriverMapSheet({
    required this.header,
    required this.actions,
    required this.onCenterRoute,
    super.key,
  });

  /// Always visible, whether the sheet is expanded or collapsed: enough to
  /// know who the passenger is and what is happening without touching the
  /// handle.
  final Widget header;

  /// Only shown when expanded -- the action buttons and SOS.
  /// Before this the sheet had no collapse state to speak of; the handle
  /// existed only as decoration.
  final List<Widget> actions;
  final VoidCallback onCenterRoute;

  @override
  State<_DriverMapSheet> createState() => _DriverMapSheetState();
}

class _DriverMapSheetState extends State<_DriverMapSheet>
    with SingleTickerProviderStateMixin {
  // Starts expanded, matching the sheet's previous always-full appearance.
  bool _expanded = true;
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: AppMotion.sheet,
    value: 1,
  );

  static const _dragExtent = 260.0;

  void _setExpanded(bool expanded) {
    setState(() => _expanded = expanded);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _reveal.value = expanded ? 1 : 0;
    } else {
      _reveal.animateTo(
        expanded ? 1 : 0,
        duration: AppMotion.sheet,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _drag(double dy) {
    _reveal.value = (_reveal.value - dy / _dragExtent).clamp(0.0, 1.0);
  }

  void _endDrag(double velocity) {
    final expand =
        velocity < -250 || (velocity.abs() <= 250 && _reveal.value >= 0.5);
    _setExpanded(expand);
  }

  /// Expanded: a pull past the top of the panel's content closes it.
  bool _onScroll(ScrollNotification notification) {
    if (!_expanded) return false;
    if (notification is OverscrollNotification &&
        notification.overscroll < 0 &&
        notification.dragDetails != null) {
      _drag(-notification.overscroll);
    } else if (notification is ScrollEndNotification && _reveal.value < 1) {
      _endDrag(notification.dragDetails?.primaryVelocity ?? 0);
    }
    return false;
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 20, bottom: AppSpacing.xs),
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox.square(
              dimension: AppSizes.minTapTarget,
              child: ArangIconButton(
                icon: Icons.center_focus_strong,
                tooltip: 'Center route',
                onPressed: widget.onCenterRoute,
              ),
            ),
          ),
        ),
        // The whole panel is a drag surface, not just the handle: collapsed,
        // a vertical swipe anywhere moves it (taps still reach its buttons);
        // expanded, the content scrolls and a pull past the top closes it.
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: _expanded
              ? null
              : (details) => _drag(details.delta.dy),
          onVerticalDragEnd: _expanded
              ? null
              : (details) => _endDrag(details.primaryVelocity ?? 0),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.52,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadii.sheet),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadowLight,
                  blurRadius: 10,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: SingleChildScrollView(
                physics: _expanded
                    ? const AlwaysScrollableScrollPhysics(
                        parent: ClampingScrollPhysics(),
                      )
                    : const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SheetDragHandle(
                      expanded: _expanded,
                      onToggle: () => _setExpanded(!_expanded),
                      onDragUpdate: _drag,
                      onDragEnd: _endDrag,
                    ),
                    widget.header,
                    SizeTransition(
                      sizeFactor: _reveal,
                      alignment: Alignment.topCenter,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.md),
                          ...widget.actions,
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const _VisibleMapAttribution(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VisibleMapAttribution extends StatelessWidget {
  const _VisibleMapAttribution();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '© MapTiler © OpenStreetMap · routing: openrouteservice when available',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 9, color: AppColors.textMuted),
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({
    required this.online,
    required this.canToggle,
    required this.onToggle,
  });

  final bool online;
  final bool canToggle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    online ? "You're online" : 'Ready when you are.',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    online
                        ? 'You can receive ride requests.'
                        : 'Go online to join the terminal queue.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Going online is this screen's main action, so the switch is
            // drawn larger and states its current mode in words.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: online ? 'Go offline' : 'Go online',
                  child: Transform.scale(
                    scale: 1.2,
                    child: Switch(
                      value: online,
                      onChanged: canToggle ? (_) => onToggle() : null,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                ExcludeSemantics(
                  child: Text(
                    online ? 'Online' : 'Offline',
                    style: AppTypography.label.copyWith(
                      color: online ? AppColors.primary : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
