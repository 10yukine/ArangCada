import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_dialog.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/drag_sheet_scaffold.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/trip_call_sheet.dart';
import '../../core/widgets/trip_share_sheet.dart';
import '../../core/widgets/map/live_map_view.dart';
import '../../data/mock/demo_state.dart';
import '../../data/providers/repository_providers.dart';
import '../../demo/demo_simulation.dart';
import '../../domain/models/booking.dart';

/// One screen for the whole wait: matched, on the way, and arrived.
///
/// This used to be two. `DriverMatchedScreen` showed a static confirmation and
/// then navigated to `DriverApproachScreen`, which repeated the same driver
/// card with different words. A commuter saw the screen change for no reason
/// they could act on, and the app kept two copies of "who is coming and how do
/// I reach them" that could drift apart.
///
/// The map is **live driver tracking**, not a route preview. The commuter does
/// not need to see which streets the driver takes to reach them -- that is the
/// driver's problem, and drawing it invites second-guessing a route the rider
/// has no say in. What they need is "where are they now, and are they getting
/// closer". The route only becomes the commuter's business once they are in the
/// vehicle, which is `active_trip_screen`.
///
/// ## No SOS here, deliberately
///
/// The project owner ruled on this on 4 Sep 2026 and the reasoning should
/// survive: the driver has no passenger yet, so an emergency report at this
/// point creates accountability against a driver for something that cannot have
/// happened in their vehicle. Waiting alone at a terminal is not a hazard this
/// app introduced or can answer for; a commuter in danger before pickup should
/// call 911, and ArangCada should not pretend to be that channel. SOS starts
/// where the ride does.
class DriverMatchedScreen extends ConsumerStatefulWidget {
  const DriverMatchedScreen({this.now, super.key});

  final DateTime Function()? now;

  @override
  ConsumerState<DriverMatchedScreen> createState() =>
      _DriverMatchedScreenState();
}

class _DriverMatchedScreenState extends ConsumerState<DriverMatchedScreen>
    with WidgetsBindingObserver {
  /// How long a commuter may cancel without it counting against them.
  static const _cancelWindowSeconds = 60;

  final _mapController = LiveMapViewController();
  DemoSimulationRun? _approachRun;
  DemoSimulationRun? _arrivalRun;
  Timer? _liveTransition;
  Timer? _cancelWindowTimer;

  int _secondsRemaining = 0;
  int _cancelSecondsRemaining = _cancelWindowSeconds;
  bool _arrived = false;
  bool _cancelling = false;
  DemoState? _liveState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = ref.read(demoStateProvider);
    final liveRides = ref.read(liveRideRepositoryProvider);

    if (liveRides != null) {
      // Attached unconditionally, not only when the status currently reads
      // `approaching`. A real trip can already be past that by the time this
      // screen finishes mounting, and a listener attached conditionally would
      // never fire again -- leaving the screen permanently stale no matter what
      // the driver did next.
      _arrived = liveRides.activeTrip?['status'] == 'arrived';
      state.addListener(_handleLiveTripChange);
      _liveState = state;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleLiveTripChange();
      });

      if (state.activeBooking?.status == BookingStatus.matched) {
        _liveTransition = Timer(const Duration(milliseconds: 700), () {
          if (!mounted) return;
          if (state.activeBooking?.status == BookingStatus.matched) {
            state.activeBooking!.beginDriverApproach();
            state.bookingChanged();
          }
        });
      }
    } else {
      _startDemoRun(state);
    }

    _startCancelWindow();
  }

  /// Drives the sandbox through matched -> approaching -> arrived -> in
  /// progress. Previously split across two screens, which is why the approach
  /// simulation had to be re-scheduled after a navigation.
  void _startDemoRun(DemoState state) {
    final status = state.activeBooking?.status;
    if (status == BookingStatus.matched) {
      _approachRun = ref
          .read(demoSimulationServiceProvider)
          .scheduleDriverApproachStart(
            state: state,
            onApproachStarted: () {
              if (mounted) _scheduleArrival(state);
            },
          );
    } else if (status == BookingStatus.approaching) {
      _scheduleArrival(state);
    }
  }

  void _scheduleArrival(DemoState state) {
    _arrivalRun = ref
        .read(demoSimulationServiceProvider)
        .scheduleDriverArrival(
          state: state,
          onEtaChanged: (seconds) {
            if (mounted) setState(() => _secondsRemaining = seconds);
          },
          onArrived: () {
            if (mounted) setState(() => _arrived = true);
          },
          onTripStarted: () {
            if (mounted) context.go('/trip/active');
          },
        );
    if (mounted) {
      setState(() => _secondsRemaining = _arrivalRun!.totalSeconds);
    }
  }

  void _startCancelWindow() {
    _cancelWindowTimer?.cancel();
    _cancelSecondsRemaining = _remainingCancellationSeconds();
    _cancelWindowTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _cancelSecondsRemaining = _remainingCancellationSeconds());
    });
  }

  int _remainingCancellationSeconds() {
    final acceptedAt = ref
        .read(demoStateProvider)
        .activeBooking
        ?.driverAcceptedAt;
    if (acceptedAt == null) return 0;
    final remaining = acceptedAt
        .add(const Duration(seconds: _cancelWindowSeconds))
        .difference(widget.now?.call() ?? DateTime.now().toUtc());
    return (remaining.inMilliseconds / 1000).ceil().clamp(
      0,
      _cancelWindowSeconds,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _cancelSecondsRemaining = _remainingCancellationSeconds());
    }
  }

  void _handleLiveTripChange() {
    if (!mounted) return;
    final state = ref.read(demoStateProvider);
    if (state.activeBooking == null ||
        state.activeBooking?.status == BookingStatus.cancelled) {
      _liveTransition?.cancel();
      _cancelWindowTimer?.cancel();
      return;
    }
    if (state.activeBooking?.status == BookingStatus.inProgress) {
      // Deferred a frame: this callback can itself run from a post-frame
      // callback registered in initState, and navigating from inside a
      // ChangeNotifier listener risks tearing down the tree mid-notification.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            state.activeBooking?.status == BookingStatus.inProgress) {
          context.go('/trip/active');
        }
      });
      return;
    }
    final arrived =
        ref.read(liveRideRepositoryProvider)?.activeTrip?['status'] ==
        'arrived';
    if (_arrived != arrived) setState(() => _arrived = arrived);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveState?.removeListener(_handleLiveTripChange);
    _approachRun?.cancel();
    _arrivalRun?.cancel();
    _liveTransition?.cancel();
    _cancelWindowTimer?.cancel();
    super.dispose();
  }

  Future<void> _cancelRide() async {
    if (_cancelling) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ArangDialog(
        title: 'Cancel ride?',
        content: const Text(
          'Your driver is already heading to the pickup point. Cancel this '
          'ride request?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Ride'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel Ride'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final state = ref.read(demoStateProvider);
    final status = state.activeBooking?.status;
    if (_cancelling ||
        _arrived ||
        _remainingCancellationSeconds() <= 0 ||
        (status != BookingStatus.matched &&
            status != BookingStatus.approaching)) {
      return;
    }
    final liveRides = ref.read(liveRideRepositoryProvider);
    if (liveRides == null) {
      _approachRun?.cancel();
      _arrivalRun?.cancel();
      _cancelWindowTimer?.cancel();
      state.activeBooking = null;
      state.bookingChanged();
    } else {
      setState(() => _cancelling = true);
      try {
        await liveRides.cancelRide();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not cancel the ride. Try again.'),
            ),
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _cancelling = false);
      }
    }
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final booking = state.activeBooking;
          final waiting =
              booking != null &&
              (booking.status == BookingStatus.matched ||
                  booking.status == BookingStatus.approaching);
          if (!waiting) {
            final cancelled = booking?.status == BookingStatus.cancelled;
            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  EmptyStateCard(
                    icon: cancelled ? Icons.cancel_outlined : Icons.route,
                    title: cancelled
                        ? 'Ride cancelled'
                        : 'No driver on the way',
                    message: 'Open Trips to check your latest ride.',
                    actionLabel: 'View trips',
                    onAction: () => context.go('/trips'),
                  ),
                ],
              ),
            );
          }

          final driverName = state.liveDriverName ?? 'Marco Dela Cruz';
          final toda = state.liveTodaName ?? 'Calamba TODA';
          final live = ref.read(liveRideRepositoryProvider) != null;
          final eta = _arrived
              ? 'Arrived'
              : state.forceEtaFallback
              ? 'Updating'
              : live
              ? 'Live GPS'
              : '$_secondsRemaining sec';
          final cancellable = !_arrived && _cancelSecondsRemaining > 0;

          return DragSheetScaffold(
            sheetKey: _mapController.panelKey,
            collapsedHeight: 400,
            handleSemanticLabel: 'Driver details',
            background: LiveMapView(
              controller: _mapController,
              // Centred on the driver, not the route. Where they are now is the
              // only thing the commuter can act on while waiting.
              center: state.liveDriverLocation ?? state.pickup.coordinate,
              borderRadius: BorderRadius.zero,
              interactive: true,
              markers: [
                MapMarker(
                  coordinate: state.pickup.coordinate,
                  color: AppColors.green,
                  radius: 8,
                ),
                if (state.liveDriverLocation != null)
                  MapMarker(
                    coordinate: state.liveDriverLocation!,
                    color: AppColors.primary,
                    radius: 10,
                  ),
              ],
            ),
            aboveSheet: ArangIconButton(
              icon: Icons.center_focus_strong,
              tooltip: 'Center map',
              onPressed: () => _mapController.recenter(),
            ),
            footer: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.dangerDark,
              ),
              onPressed: cancellable && !_cancelling ? _cancelRide : null,
              child: Text(
                _cancelling
                    ? 'Cancelling ride…'
                    : cancellable
                    ? 'Cancel ride · '
                          '0:${_cancelSecondsRemaining.toString().padLeft(2, '0')}'
                    : 'Cancellation window has expired',
              ),
            ),
            sheetBuilder: (context, expanded) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _arrived ? 'Meet your driver.' : 'Your ride is coming.',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _arrived
                      ? 'Head to your pickup point.'
                      : 'Pickup · ${booking.pickupName}',
                  style: AppTypography.bodySm,
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ArangAvatar(
                      name: driverName,
                      size: 52,
                      imageUrl: state.liveCounterpartAvatarUrl,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(driverName, style: AppTypography.h2),
                          Text('Tricycle · $toda'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  eta,
                  style: AppTypography.label.copyWith(color: AppColors.primary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _arrived
                      ? 'Your driver is at the pickup point. The trip will '
                            'start automatically.'
                      : 'Driver is heading to your pickup point.',
                ),
                if (state.forceEtaFallback) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'ETA fallback · route estimate unavailable',
                    style: AppTypography.caption,
                  ),
                ],

                // Always reachable, collapsed or not. Reaching the driver is
                // the whole reason a commuter looks at this screen while they
                // wait.
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        label: const Text('Message'),
                        icon: const Icon(Icons.chat_outlined),
                        onPressed: () => context.push('/chat/thread-active'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: OutlinedButton.icon(
                        label: const Text('Call'),
                        icon: const Icon(Icons.call_outlined),
                        onPressed: () => showTripCallSheet(context),
                      ),
                    ),
                  ],
                ),
                // Family can follow along from the moment a driver is on the
                // way. Live trips only: a demo trip has no server link.
                if (ref.read(liveRideRepositoryProvider) != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => showTripShareSheet(context),
                      icon: const Icon(Icons.share_location_outlined),
                      label: const Text('Share trip'),
                    ),
                  ),

                if (expanded) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Divider(),
                  const SizedBox(height: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pickup',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(booking.pickupName),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Destination',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(booking.destinationName),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
