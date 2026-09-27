import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/map/live_map_view.dart';
import '../../core/widgets/drag_sheet_scaffold.dart';
import '../../core/widgets/map/route_preview_map.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/trip_call_sheet.dart';
import '../../core/widgets/trip_share_sheet.dart';
import '../../core/widgets/sos_hold_button.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/remote/supabase_ride_repository.dart';
import '../../data/repositories/payment_repository.dart';
import '../../demo/demo_simulation.dart';
import '../../domain/models/booking.dart';
import '../../core/widgets/arang_dialog.dart';

class ActiveTripScreen extends ConsumerStatefulWidget {
  const ActiveTripScreen({super.key});

  @override
  ConsumerState<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends ConsumerState<ActiveTripScreen> {
  final _mapController = LiveMapViewController();
  DemoSimulationRun? _completionRun;
  bool _completionStarted = false;
  Listenable? _liveState;

  @override
  void initState() {
    super.initState();
    final liveRides = ref.read(liveRideRepositoryProvider);
    if (liveRides == null) {
      _scheduleCompletion();
    } else {
      _liveState = ref.read(demoStateProvider);
      _liveState!.addListener(_handleLiveTripChange);
      _handleLiveTripChange();
    }
  }

  void _scheduleCompletion() {
    _completionRun?.cancel();
    final state = ref.read(demoStateProvider);
    if (state.activeBooking?.status != BookingStatus.inProgress) return;
    _completionRun = ref
        .read(demoSimulationServiceProvider)
        .scheduleTripCompletion(
          state: state,
          onCompletionDue: _onCompletionDue,
        );
  }

  /// Reaching the destination does NOT end the ride. The commuter confirms.
  /// A 60-second countdown auto-confirms so a distracted rider -- or a demo --
  /// never stalls, and confirming early cancels it.
  void _onCompletionDue() {
    if (!mounted || _completionStarted || _awaitingConfirmation) return;
    final booking = ref.read(demoStateProvider).activeBooking;
    if (booking?.status != BookingStatus.inProgress) return;
    setState(() {
      _awaitingConfirmation = true;
      _secondsLeft = _confirmWindow.inSeconds;
    });
    _confirmTicker?.cancel();
    _confirmTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft -= 1);
      if (_secondsLeft <= 0) {
        timer.cancel();
        _confirmArrival();
      }
    });
  }

  void _confirmArrival() {
    if (!mounted || _completionStarted) return;
    _confirmTicker?.cancel();
    final booking = ref.read(demoStateProvider).activeBooking;
    if (booking?.status != BookingStatus.inProgress) return;
    _completionStarted = true;
    setState(() => _awaitingConfirmation = false);
    _completeTrip(booking!);
  }

  /// Three minutes, not one.
  ///
  /// This is a fallback for a distracted rider, not the normal way a ride ends
  /// -- the rider confirming is. Sixty seconds was easy to blow through: most
  /// rides are cash, and finding the fare, waiting for change and climbing out
  /// of a tricycle regularly takes longer than that, so the ride auto-finished
  /// while the rider was still sitting in it.
  static const Duration _confirmWindow = Duration(minutes: 3);
  Timer? _confirmTicker;
  bool _awaitingConfirmation = false;

  int _secondsLeft = 0;

  void _retryAutomaticCompletion() {
    if (!mounted) return;
    _completionStarted = false;
    _scheduleCompletion();
  }

  @override
  void dispose() {
    _liveState?.removeListener(_handleLiveTripChange);
    _confirmTicker?.cancel();
    _completionRun?.cancel();
    super.dispose();
  }

  void _handleLiveTripChange() {
    if (!mounted) return;
    final state = ref.read(demoStateProvider);
    if (state.activeBooking?.status != BookingStatus.inProgress) {
      _confirmTicker?.cancel();
    }
    if (state.activeBooking?.status == BookingStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/rating');
      });
      return;
    }
    if (state.activeBooking?.status != BookingStatus.inProgress) return;
    if (_completionStarted) return;
    final deadline = state.completionAvailableAt;
    if (deadline == null || _awaitingConfirmation) return;
    setState(() {
      _awaitingConfirmation = true;
      _secondsLeft = SupabaseRideRepository.completionSecondsRemaining(
        deadline,
      );
    });
    _confirmTicker?.cancel();
    _confirmTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = SupabaseRideRepository.completionSecondsRemaining(
        deadline,
      );
      setState(() => _secondsLeft = remaining);
      if (remaining <= 0) {
        timer.cancel();
        _confirmArrival();
      }
    });
  }

  Future<void> _recordSos() async {
    final liveRides = ref.read(liveRideRepositoryProvider);
    await showSafetyReportFlow(
      context: context,
      driver: false,
      onSubmit: () => ref.read(safetyRepositoryProvider).recordDemoAlert(),
      onSubmitReason: liveRides?.createSafetyReport,
      connected: liveRides != null,
    );
  }

  Future<void> _completeTrip(DemoBooking booking) async {
    final liveRides = ref.read(liveRideRepositoryProvider);
    if (liveRides != null) {
      try {
        await liveRides.completeTrip();
        if (!mounted || booking.status == BookingStatus.cancelled) return;
        if (mounted) context.go('/rating');
      } catch (_) {
        if (mounted && booking.status != BookingStatus.cancelled) {
          // No realtime update is guaranteed after a rejected/offline request.
          // Restore the action locally, without automatically resending it.
          setState(() {
            _completionStarted = false;
            _awaitingConfirmation = true;
            _secondsLeft = 0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not confirm trip completion. Check your connection and try again.',
              ),
            ),
          );
        }
      }
      return;
    }
    final state = ref.read(demoStateProvider);
    if (state.forcePaymentFailure &&
        booking.paymentMethod == PaymentMethod.digital) {
      final switchToCash = await showDialog<bool>(
        context: context,
        builder: (context) => ArangDialog(
          title: 'Sandbox payment failed',
          content: const Text(
            'The payment provider declined this simulated charge. No funds moved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Retry'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Switch to Cash'),
            ),
          ],
        ),
      );
      if (switchToCash != true || !mounted) {
        _retryAutomaticCompletion();
        return;
      }
      state.setPaymentFallbackToCash(true);
    } else {
      try {
        await ref.read(paymentRepositoryProvider).completeRidePayment(booking);
      } on InsufficientBalanceException {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => ArangDialog(
            title: 'Digital payment failed',
            content: const Text(
              'The sandbox balance changed after confirmation. Top up from Wallet, then retry completion. No charge was made.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        _retryAutomaticCompletion();
        return;
      }
    }
    booking
      ..completeTrip()
      ..receiptReference = 'SBX-RIDE-20260815-024';
    state.bookingChanged();
    ref.read(chatRepositoryProvider).closeActiveTripThread();
    if (mounted) context.go('/rating');
  }

  Future<void> _handleBack(BuildContext context) async {
    if (ref.read(demoStateProvider).activeBooking?.status !=
        BookingStatus.inProgress) {
      context.go('/trips');
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => ArangDialog(
        title: 'Leave active trip screen?',
        content: const Text(
          'The trip will stay active and can be resumed from Trips.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave Screen'),
          ),
        ],
      ),
    );
    if (leave == true && context.mounted) context.go('/trips');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack(context);
      },
      child: Scaffold(
        body: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final booking = state.activeBooking;
            if (booking == null || booking.status != BookingStatus.inProgress) {
              final cancelled = booking?.status == BookingStatus.cancelled;
              return SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    EmptyStateCard(
                      icon: cancelled ? Icons.cancel_outlined : Icons.route,
                      title: cancelled ? 'Trip cancelled' : 'No active trip',
                      message: cancelled
                          ? 'This ride has ended. Open Trips to review its status.'
                          : 'Open Trips to check your latest ride.',
                      actionLabel: 'View trips',
                      onAction: () => context.go('/trips'),
                    ),
                  ],
                ),
              );
            }
            return DragSheetScaffold(
              sheetKey: _mapController.panelKey,
              collapsedHeight: 330,
              handleSemanticLabel: 'Trip details',
              background: RoutePreviewMap(
                controller: _mapController,
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
              aboveSheet: ArangIconButton(
                icon: Icons.center_focus_strong,
                tooltip: 'Center route',
                onPressed: () => _mapController.fitRoute(),
              ),
              overlay: [
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  left: 14,
                  child: ArangIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Back',
                    onPressed: () => _handleBack(context),
                  ),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  left: 70,
                  child: const _TripStatusPill(),
                ),
              ],
              sheetBuilder: (context, expanded) => _ActiveTripSheetBody(
                booking: booking,
                expanded: expanded,
                etaFallback: state.forceEtaFallback,
                driverName: state.liveDriverName ?? 'Your driver',
                todaName: state.liveTodaName,
                driverAvatarUrl: state.liveCounterpartAvatarUrl,
                awaitingConfirmation: _awaitingConfirmation,
                secondsLeft: _secondsLeft,
                canConfirmArrival:
                    ref.read(liveRideRepositoryProvider) == null ||
                    _secondsLeft <= 0,
                onConfirmArrival: _confirmArrival,
                onMessage: () => context.push('/chat/thread-active'),
                onCall: () => showTripCallSheet(context),
                // Live trips only: a demo trip has no server link to share.
                onShare: ref.read(liveRideRepositoryProvider) == null
                    ? null
                    : () => showTripShareSheet(context),
                onSos: _recordSos,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TripStatusPill extends StatelessWidget {
  const _TripStatusPill();

  @override
  Widget build(BuildContext context) {
    // Height, not vertical padding. It sits beside the floating back button,
    // and padding-derived height left the two a few pixels apart -- close
    // enough to read as misaligned rather than as a deliberate difference.
    // Everything floating over the map is now AppSizes.iconButton tall.
    return Container(
      height: AppSizes.iconButton,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 8,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text('In progress', style: AppTypography.label),
        ],
      ),
    );
  }
}

/// The content of the active-trip sheet, and nothing else.
///
/// This was a StatefulWidget carrying its own AnimationController, drag
/// handling, snap-on-release and reduced-motion branch. All of that moved into
/// DragSheetScaffold -- it was extracted FROM here in the first place -- so
/// keeping a second copy meant two sheets in the same app that could drift
/// apart in feel. What is left is the part that was ever specific to a trip.
class _ActiveTripSheetBody extends StatelessWidget {
  const _ActiveTripSheetBody({
    required this.booking,
    required this.expanded,
    required this.todaName,
    required this.etaFallback,
    required this.driverName,
    this.driverAvatarUrl,
    required this.awaitingConfirmation,
    required this.secondsLeft,
    required this.canConfirmArrival,
    required this.onConfirmArrival,
    required this.onMessage,
    required this.onCall,
    required this.onShare,
    required this.onSos,
  });

  final DemoBooking booking;
  final bool expanded;
  final String? todaName;
  final bool etaFallback;
  final String driverName;
  final String? driverAvatarUrl;
  final bool awaitingConfirmation;
  final int secondsLeft;
  final bool canConfirmArrival;
  final VoidCallback onConfirmArrival;
  final VoidCallback onMessage;
  final VoidCallback onCall;
  final VoidCallback? onShare;
  final Future<void> Function() onSos;

  /// "2:54", not "174s". Past a minute, raw seconds stop being a duration a
  /// reader can feel.
  static String _countdown(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The driver's face sits to the left of the destination and
        // their name, so the person carrying the ride is the first
        // thing read rather than a line of caption text under an
        // address. Matches the avatar driver_matched_screen already
        // shows -- ArangAvatar falls back to initials on its own when
        // driverAvatarUrl is null, same as everywhere else this session
        // wired a real photo in.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: AppSpacing.sm),
              child: ArangAvatar(
                name: driverName,
                size: 44,
                imageUrl: driverAvatarUrl,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // No arrival time here until one is actually computed;
                      // the "In progress" chip on the map carries the status.
                      Expanded(
                        child: Text(
                          'To ${booking.destinationName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    etaFallback
                        ? 'Route estimate unavailable'
                        : todaName == null
                        ? driverName
                        : '$driverName · $todaName',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          awaitingConfirmation ? 'Arrived · tap to finish' : 'On the way',
          style: AppTypography.bodySm,
        ),

        // Detail only. What the ride costs and how far along it is are worth
        // reading, but neither is urgent.
        if (expanded) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${formatCentavos(booking.fareQuote.partyTotalCentavos)} · '
            '${booking.paymentMethod.label} · fare locked',
            style: AppTypography.bodySm,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (awaitingConfirmation)
            const _ArrivedBanner()
          else ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'On the way to your destination.',
              style: AppTypography.caption,
            ),
          ],
        ],

        if (awaitingConfirmation) ...[
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Finishing automatically in ${_countdown(secondsLeft)}',
              style: AppTypography.caption,
            ),
          ),
        ],

        // ALWAYS VISIBLE, collapsed or not. These were inside the expanded
        // branch, which meant SOS -- the control a rider reaches for when
        // something is going wrong inside a stranger's vehicle -- required
        // noticing the sheet could be dragged, and then dragging it. A safety
        // control behind a gesture is not a safety control.
        const SizedBox(height: AppSpacing.sm),
        if (awaitingConfirmation)
          // Finish takes the slot Chat and Call had. The tricycle has stopped
          // and the rider is looking at the driver, so "message" and "call" have
          // done their job; the only thing left to do is end the ride. Swapping
          // rather than appending keeps the peek the same height at the exact
          // moment the rider is also paying and climbing out.
          ArangButton(
            label: "I've arrived — finish ride",
            icon: Icons.flag_outlined,
            onPressed: canConfirmArrival ? onConfirmArrival : null,
          )
        else
          Row(
            children: [
              Expanded(
                child: ArangButton(
                  label: 'Chat',
                  icon: Icons.chat_outlined,
                  variant: ArangButtonVariant.ghost,
                  onPressed: onMessage,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: ArangButton(
                  label: 'Call',
                  icon: Icons.call_outlined,
                  variant: ArangButtonVariant.ghost,
                  onPressed: onCall,
                ),
              ),
            ],
          ),
        if (!awaitingConfirmation && onShare != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.share_location_outlined),
              label: const Text('Share trip'),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        // SOS outlives arrival deliberately. "SOS starts where the ride does"
        // has a mirror: it must not end before the rider has actually left the
        // vehicle, and they are still at it while they pay.
        SosHoldButton(onCompleted: onSos),
        const SizedBox(height: AppSpacing.xs),
        const Center(
          child: Text(
            '© MapTiler © OpenStreetMap · routing: openrouteservice when available',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Shown once the tricycle reaches the drop-off point. The ride is not over
/// until the commuter says so.
class _ArrivedBanner extends StatelessWidget {
  const _ArrivedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.greenFill,
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.where_to_vote_outlined,
            size: 18,
            color: AppColors.greenDark,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'You have reached your destination. Confirm to finish and see '
              'your receipt.',
              style: AppTypography.caption.copyWith(
                color: AppColors.greenDark,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
