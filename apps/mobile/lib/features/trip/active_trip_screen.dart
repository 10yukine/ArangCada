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
  bool _liveListenerAttached = false;

  @override
  void initState() {
    super.initState();
    final liveRides = ref.read(liveRideRepositoryProvider);
    if (liveRides == null) {
      _scheduleCompletion();
    } else {
      ref.read(demoStateProvider).addListener(_handleLiveTripChange);
      _liveListenerAttached = true;
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
      _sheetController.expand();
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

  static const Duration _confirmWindow = Duration(seconds: 60);
  Timer? _confirmTicker;
  bool _awaitingConfirmation = false;

  /// Opens the sheet from outside a gesture, for the one moment that needs it.
  final DragSheetController _sheetController = DragSheetController();
  int _secondsLeft = 0;

  void _retryAutomaticCompletion() {
    if (!mounted) return;
    _completionStarted = false;
    _scheduleCompletion();
  }

  @override
  void dispose() {
    if (_liveListenerAttached) {
      ref.read(demoStateProvider).removeListener(_handleLiveTripChange);
    }
    _confirmTicker?.cancel();
    _completionRun?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  void _handleLiveTripChange() {
    if (!mounted) return;
    final state = ref.read(demoStateProvider);
    if (state.activeBooking?.status == BookingStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/rating');
      });
      return;
    }
    final deadline = state.completionAvailableAt;
    if (deadline == null || _awaitingConfirmation) return;
    setState(() {
      _awaitingConfirmation = true;
      _sheetController.expand();
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
        if (mounted) context.go('/rating');
      } on Exception {
        _completionStarted = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trip completion is not available yet. Try again.'),
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
              return const Center(child: Text('No active trip.'));
            }
            return DragSheetScaffold(
              sheetKey: _mapController.panelKey,
              controller: _sheetController,
              collapsedHeight: 260,
              handleSemanticLabel: 'Trip details',
              handleTrailing: ArangIconButton(
                icon: Icons.center_focus_strong,
                tooltip: 'Center route',
                onPressed: () => _mapController.fitRoute(),
              ),
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
                compassTopInset:
                    MediaQuery.paddingOf(context).top +
                    AppSizes.minTapTarget +
                    16,
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
                  top: MediaQuery.paddingOf(context).top + 13,
                  left: 70,
                  child: const _TripStatusPill(),
                ),
              ],
              sheetBuilder: (context, expanded) => _ActiveTripSheetBody(
                booking: booking,
                expanded: expanded,
                eta: state.forceEtaFallback ? '15–20 min' : '12–16 min',
                etaFallback: state.forceEtaFallback,
                awaitingConfirmation: _awaitingConfirmation,
                secondsLeft: _secondsLeft,
                canConfirmArrival:
                    ref.read(liveRideRepositoryProvider) == null ||
                    _secondsLeft <= 0,
                onConfirmArrival: _confirmArrival,
                onMessage: () => context.push('/chat/thread-active'),
                onCall: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Calling is unavailable in this academic prototype. '
                      'No call was placed.',
                    ),
                  ),
                ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text('In progress', style: AppTypography.caption),
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
    required this.eta,
    required this.etaFallback,
    required this.awaitingConfirmation,
    required this.secondsLeft,
    required this.canConfirmArrival,
    required this.onConfirmArrival,
    required this.onMessage,
    required this.onCall,
    required this.onSos,
  });

  final DemoBooking booking;
  final bool expanded;
  final String eta;
  final bool etaFallback;
  final bool awaitingConfirmation;
  final int secondsLeft;
  final bool canConfirmArrival;
  final VoidCallback onConfirmArrival;
  final VoidCallback onMessage;
  final VoidCallback onCall;
  final Future<void> Function() onSos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The driver's face sits to the left of the destination and
        // their name, so the person carrying the ride is the first
        // thing read rather than a line of caption text under an
        // address. Matches the avatar driver_matched_screen already
        // shows; a placeholder icon until avatar upload lands
        // (specs.md Spec 8b), at which point only the child changes.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2, right: AppSpacing.sm),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primaryFill,
                child: Icon(Icons.person, size: 26, color: AppColors.primary),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'To ${booking.destinationName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        eta,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    etaFallback
                        ? 'Route estimate unavailable · fallback ETA'
                        : 'Marco Dela Cruz · Body no. 024',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!expanded) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            awaitingConfirmation ? 'Arrived · tap to finish' : 'On the way',
            style: AppTypography.bodySm,
          ),
        ],
        if (expanded)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${formatCentavos(booking.fareQuote.partyTotalCentavos)} · '
                '${booking.paymentMethod.label} · fare locked',
                style: AppTypography.bodySm,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (awaitingConfirmation) ...[
                const _ArrivedBanner(),
                const SizedBox(height: AppSpacing.sm),
                ArangButton(
                  label: "I've arrived — finish ride",
                  icon: Icons.flag_outlined,
                  onPressed: canConfirmArrival ? onConfirmArrival : null,
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    'Finishing automatically in ${secondsLeft}s',
                    style: AppTypography.caption,
                  ),
                ),
              ] else ...[
                const LinearProgressIndicator(minHeight: 3),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'On the way to your destination.',
                  style: AppTypography.caption,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
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
              const SizedBox(height: AppSpacing.xs),
              SosHoldButton(onCompleted: onSos),
            ],
          ),
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
