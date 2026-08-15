import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/painted_calamba_map.dart';
import '../../core/widgets/section_card.dart';
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

  void _onCompletionDue() {
    if (!mounted || _completionStarted) return;
    final booking = ref.read(demoStateProvider).activeBooking;
    if (booking?.status != BookingStatus.inProgress) return;
    _completionStarted = true;
    _completeTrip(booking!);
  }

  void _retryAutomaticCompletion() {
    if (!mounted) return;
    _completionStarted = false;
    _scheduleCompletion();
  }

  @override
  void dispose() {
    _completionRun?.cancel();
    super.dispose();
  }

  Future<void> _recordSos() async {
    await ref.read(safetyRepositoryProvider).recordDemoAlert();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.shield_outlined, color: AppColors.danger),
        title: const Text('Safety alert recorded'),
        content: const Text(
          'Demo safety alert recorded for ArangCada administrators. No emergency service was contacted.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeTrip(DemoBooking booking) async {
    final state = ref.read(demoStateProvider);
    if (state.forcePaymentFailure &&
        booking.paymentMethod == PaymentMethod.digital) {
      final switchToCash = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Demo payment failed'),
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
              'The demo balance changed after confirmation. Top up from Wallet, then retry completion. No charge was made.',
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
      ..receiptReference = 'DEMO-RIDE-20260815-024';
    state.bookingChanged();
    if (mounted) context.go('/rating');
  }

  Future<void> _handleBack(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave active trip screen?'),
        content: const Text(
          'The demo trip will stay active and can be resumed from Trips.',
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
                  const PaintedCalambaMap(height: 250),
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
                        const LinearProgressIndicator(),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'Trip progress updates automatically. Your receipt will appear when the ride ends.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
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
