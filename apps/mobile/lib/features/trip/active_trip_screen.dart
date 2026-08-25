import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/map/live_map_view.dart';
import '../../core/widgets/map/route_preview_map.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/sheet_drag_handle.dart';
import '../../core/widgets/sos_hold_button.dart';
import '../../data/providers/repository_providers.dart';
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

  @override
  void initState() {
    super.initState();
    _scheduleCompletion();
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
  /// A 30-second countdown auto-confirms so a distracted rider -- or a demo --
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

  static const Duration _confirmWindow = Duration(seconds: 30);
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
    _confirmTicker?.cancel();
    _completionRun?.cancel();
    super.dispose();
  }

  Future<void> _recordSos() async {
    await showSafetyReportFlow(
      context: context,
      driver: false,
      onSubmit: () => ref.read(safetyRepositoryProvider).recordDemoAlert(),
    );
  }

  Future<void> _completeTrip(DemoBooking booking) async {
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
            return Stack(
              children: [
                Positioned.fill(
                  child: RoutePreviewMap(
                    controller: _mapController,
                    from: state.pickup.coordinate,
                    to: state.destination!.coordinate,
                    height: double.infinity,
                    borderRadius: BorderRadius.zero,
                    showCaption: false,
                    interactive: true,
                    compassTopInset:
                        MediaQuery.paddingOf(context).top +
                        AppSizes.minTapTarget +
                        16,
                  ),
                ),
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
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _ActiveTripSheet(
                    key: _mapController.panelKey,
                    booking: booking,
                    eta: state.forceEtaFallback ? '15–20 min' : '12–16 min',
                    etaFallback: state.forceEtaFallback,
                    awaitingConfirmation: _awaitingConfirmation,
                    secondsLeft: _secondsLeft,
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
                    onCenterRoute: () => _mapController.fitRoute(),
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

class _ActiveTripSheet extends StatefulWidget {
  const _ActiveTripSheet({
    required this.booking,
    required this.eta,
    required this.etaFallback,
    required this.awaitingConfirmation,
    required this.secondsLeft,
    required this.onConfirmArrival,
    required this.onMessage,
    required this.onCall,
    required this.onSos,
    required this.onCenterRoute,
    super.key,
  });

  final DemoBooking booking;
  final String eta;
  final bool etaFallback;
  final bool awaitingConfirmation;
  final int secondsLeft;
  final VoidCallback onConfirmArrival;
  final VoidCallback onMessage;
  final VoidCallback onCall;
  final Future<void> Function() onSos;
  final VoidCallback onCenterRoute;

  @override
  State<_ActiveTripSheet> createState() => _ActiveTripSheetState();
}

class _ActiveTripSheetState extends State<_ActiveTripSheet>
    with SingleTickerProviderStateMixin {
  // Starts expanded: this is what the sheet always showed before the handle
  // became functional, so a rider mid-trip sees no behaviour change until
  // they actually touch the handle.
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
  void didUpdateWidget(covariant _ActiveTripSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Arrival needs the full sheet in view for the confirm button; a
    // collapsed peek at that exact moment would hide the one action that
    // matters.
    if (widget.awaitingConfirmation && !oldWidget.awaitingConfirmation) {
      _expanded = true;
      _reveal.animateTo(1, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
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
            maxHeight: MediaQuery.sizeOf(context).height * 0.54,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadii.sheet),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x141F1E1D),
                blurRadius: 10,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SheetDragHandle(
                    expanded: _expanded,
                    onToggle: () => _setExpanded(!_expanded),
                    onDragUpdate: _drag,
                    onDragEnd: _endDrag,
                  ),
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
                        widget.eta,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.etaFallback
                        ? 'Route estimate unavailable · fallback ETA'
                        : 'Marco Dela Cruz · Body no. 024',
                    style: AppTypography.caption,
                  ),
                  if (!_expanded) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      widget.awaitingConfirmation
                          ? 'Arrived · tap to finish'
                          : 'On the way',
                      style: AppTypography.bodySm,
                    ),
                  ],
                  SizeTransition(
                    sizeFactor: _reveal,
                    alignment: Alignment.topCenter,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          '${formatCentavos(booking.fareQuote.partyTotalCentavos)} · '
                          '${booking.paymentMethod.label} · fare locked',
                          style: AppTypography.bodySm,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (widget.awaitingConfirmation) ...[
                          const _ArrivedBanner(),
                          const SizedBox(height: AppSpacing.sm),
                          ArangButton(
                            label: "I've arrived — finish ride",
                            icon: Icons.flag_outlined,
                            onPressed: widget.onConfirmArrival,
                          ),
                          const SizedBox(height: 4),
                          Center(
                            child: Text(
                              'Finishing automatically in ${widget.secondsLeft}s',
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
                                onPressed: widget.onMessage,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: ArangButton(
                                label: 'Call',
                                icon: Icons.call_outlined,
                                variant: ArangButtonVariant.ghost,
                                onPressed: widget.onCall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        SosHoldButton(onCompleted: widget.onSos),
                      ],
                    ),
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
              ),
            ),
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
