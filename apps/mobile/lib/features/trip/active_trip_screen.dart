import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/map/route_preview_map.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/sos_hold_button.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/payment_repository.dart';
import '../../demo/demo_simulation.dart';
import '../../domain/models/booking.dart';

class ActiveTripScreen extends ConsumerStatefulWidget {
  const ActiveTripScreen({super.key});

  @override
  ConsumerState<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends ConsumerState<ActiveTripScreen> {
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
        builder: (context) => AlertDialog(
          title: const Text('Sandbox payment failed'),
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
          builder: (context) => AlertDialog(
            title: const Text('Digital payment failed'),
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
      builder: (context) => AlertDialog(
        title: const Text('Leave active trip screen?'),
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
        appBar: AppBar(title: const Text('Trip in progress')),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: state,
            builder: (context, _) {
              final booking = state.activeBooking;
              if (booking == null ||
                  booking.status != BookingStatus.inProgress) {
                return const Center(child: Text('No active trip.'));
              }
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  RoutePreviewMap(
                    from: state.pickup.coordinate,
                    to: state.destination!.coordinate,
                    height: 230,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Heading to ${booking.destinationName}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            Text(
                              state.forceEtaFallback
                                  ? '15–20 min'
                                  : '12–16 min',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: AppColors.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          state.forceEtaFallback
                              ? 'ETA fallback · route estimate unavailable'
                              : 'Predicted arrival range',
                        ),
                        const Divider(height: AppSpacing.lg),
                        Text(
                          '${formatCentavos(booking.fareQuote.partyTotalCentavos)} · ${booking.paymentMethod.label}',
                        ),
                        const Text('Fare locked at confirmation'),
                        const SizedBox(height: AppSpacing.sm),
                        if (_awaitingConfirmation) ...[
                          const _ArrivedBanner(),
                        ] else ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: AppSpacing.xs),
                          const Text('On the way to your destination.'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_awaitingConfirmation) ...[
                    ArangButton(
                      label: "I've arrived — finish ride",
                      icon: Icons.flag_outlined,
                      onPressed: _confirmArrival,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Finishing automatically in ${_secondsLeft}s if you '
                      'do not confirm.',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  ArangButton(
                    label: 'Message Driver',
                    icon: Icons.chat_outlined,
                    variant: ArangButtonVariant.ghost,
                    onPressed: () => context.push('/chat/thread-active'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SosHoldButton(onCompleted: _recordSos),
                  const SizedBox(height: AppSpacing.lg),
                ],
              );
            },
          ),
        ),
      ),
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
