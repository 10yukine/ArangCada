import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/widgets/trip_call_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/map/live_map_view.dart';
import '../../core/widgets/map/route_preview_map.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/sheet_drag_handle.dart';
import '../../core/nav/external_navigation.dart';
import '../../core/widgets/sos_hold_button.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/remote/supabase_ride_repository.dart';
import '../../demo/demo_data.dart';
import '../../demo/demo_simulation.dart';
import '../../domain/state/driver_trip_state_machine.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  final _mapController = LiveMapViewController();
  Timer? _countdownTimer;
  Timer? _completionTicker;
  DemoSimulationRun? _requestRun;
  int _secondsRemaining = 30;
  VoidCallback? _removeLiveStateListener;
  bool _actionPending = false;

  @override
  void initState() {
    super.initState();
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
        : DateTime.parse(
            deadline,
          ).difference(DateTime.now().toUtc()).inSeconds.clamp(0, 30);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        timer.cancel();
        _countdownTimer = null;
        final state = ref.read(demoStateProvider);
        if (state.driverTrip.status == DriverTripStatus.incoming) {
          if (liveRides == null) {
            state.driverTrip.declineRequest();
            state.driverChanged();
          } else {
            unawaited(_expireRequest());
          }
        }
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  Future<void> _expireRequest() async {
    try {
      await ref.read(liveRideRepositoryProvider)?.expireRide();
    } on Exception {
      // The server still rejects acceptance after its authoritative deadline.
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
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              children: [
                // Prototype driver header: who you are, which body number and
                // TODA you drive under. The bell reads the same real
                // PushNotificationService history the commuter side does
                // (device-local, not per-role) -- it used to be a hardcoded
                // "No new notices" snackbar; see .pipeline/changes.md's
                // driver-side audit entry.
                Row(
                  children: [
                    ArangAvatar(
                      name: state.currentUser?.displayName ?? 'Driver',
                      background: AppColors.primary,
                      foreground: Colors.white,
                      imageUrl: state.currentUser?.avatarUrl,
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
                            'Verified driver - ${state.liveTodaName ?? 'Calamba TODA'}',
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
                const SizedBox(height: 14),
                _EarningsCard(onView: () => context.push('/driver/earnings')),
                const SizedBox(height: 14),
                if (state.driverTrip.status == DriverTripStatus.available)
                  const SectionCard(
                    child: Column(
                      children: [
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        SizedBox(height: AppSpacing.sm),
                        Text(
                          'You are online',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: AppSpacing.xs),
                        Text(
                          'Waiting for ride requests in the Calamba TODA area.',
                          textAlign: TextAlign.center,
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
                const SizedBox(height: AppSpacing.md),
                // The waiting/request map shows the driver's relevant demo
                // jurisdiction. It is explicitly labelled because the seeded
                // polygon is not official LGU geometry.
                LiveMapView(
                  center: state.liveDriverLocation ?? state.pickup.coordinate,
                  height: 190,
                  zoom: 13.3,
                  showUserLocation: false,
                  interactive: false,
                  boundaries: const [
                    MapBoundary(
                      points: DemoData.calambaPoblacionPrototypeBoundary,
                    ),
                  ],
                  markers: [
                    MapMarker(
                      coordinate:
                          state.liveDriverLocation ?? state.pickup.coordinate,
                      color: AppColors.primary,
                      radius: 8,
                    ),
                  ],
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
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Incoming ride request',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              CircleAvatar(
                backgroundColor: AppColors.sky,
                child: Text('$secondsRemaining'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${state.liveCommuterName ?? 'Joshua Adia'} · 1 passenger · Special',
          ),
          Text(
            '${state.pickup.name} → '
            '${state.destination?.name ?? 'Calamba City Hall'}',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${formatCentavos(fare == null ? 9200 : (fare * 100).round())} cash fare',
            style: Theme.of(context).textTheme.labelLarge,
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

class _PickupModeCard extends ConsumerWidget {
  const _PickupModeCard({
    required this.mapController,
    required this.arrived,
    required this.onAction,
  });

  final LiveMapViewController mapController;
  final bool arrived;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    return Stack(
      children: [
        Positioned.fill(
          child: RoutePreviewMap(
            controller: mapController,
            from:
                state.liveDriverLocation ??
                DemoData.mockDriverLocation.coordinate,
            to: state.pickup.coordinate,
            height: double.infinity,
            borderRadius: BorderRadius.zero,
            showCaption: false,
            interactive: true,
            boundaries: const [
              MapBoundary(points: DemoData.calambaPoblacionPrototypeBoundary),
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
                ArangBadge(
                  arrived ? 'Waiting at pickup' : 'Navigate to pickup',
                  tone: ArangBadgeTone.green,
                ),
                const SizedBox(height: AppSpacing.sm),
                _PassengerRow(
                  name: state.liveCommuterName ?? 'Joshua Adia',
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
          child: RoutePreviewMap(
            controller: mapController,
            from: state.pickup.coordinate,
            to: state.destination?.coordinate ?? DemoData.places[1].coordinate,
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
                  name: state.liveCommuterName ?? 'Joshua Adia',
                  detail:
                      '${state.destination?.name ?? 'Calamba City Hall'} · Cash',
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
                      label: 'Message',
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
                      onPressed: () => openExternalNavigation(
                        state.destination?.coordinate ??
                            DemoData.places[1].coordinate,
                        label: state.destination?.name,
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
        Container(
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
          child: SingleChildScrollView(
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
    return ArangCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              // Status is never colour alone -- the sentence beside it says
              // the same thing in words.
              color: online ? AppColors.green : AppColors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  online ? "You're online" : "You're offline",
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  online
                      ? 'Receiving requests from the Calamba Crossing terminal queue.'
                      : 'Go online to join the terminal queue.',
                  style: AppTypography.caption.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          ArangChip(
            label: online ? 'Go offline' : 'Go online',
            selected: false,
            onTap: canToggle ? onToggle : null,
          ),
        ],
      ),
    );
  }
}

/// Today's earnings panel.
class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.onView});

  final VoidCallback onView;

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
                  "Today's earnings",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '9 trips · 6.5 hrs online',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ArangButton(
                    label: 'View earnings',
                    expand: false,
                    onPressed: onView,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            formatCentavos(36000),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
