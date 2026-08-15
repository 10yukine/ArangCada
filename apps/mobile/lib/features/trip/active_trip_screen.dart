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
import '../../domain/models/booking.dart';

class ActiveTripScreen extends ConsumerWidget {
  const ActiveTripScreen({super.key});

  Future<void> _recordSos(BuildContext context, WidgetRef ref) async {
    await ref.read(safetyRepositoryProvider).recordDemoAlert();
    if (!context.mounted) return;
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

  Future<void> _completeTrip(
    BuildContext context,
    WidgetRef ref,
    DemoBooking booking,
  ) async {
    try {
      await ref.read(paymentRepositoryProvider).completeRidePayment(booking);
    } on InsufficientBalanceException {
      if (!context.mounted) return;
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
      return;
    }
    booking
      ..completeTrip()
      ..receiptReference = 'DEMO-RIDE-20260815-024';
    ref.read(demoStateProvider).bookingChanged();
    if (context.mounted) context.go('/receipt');
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
  Widget build(BuildContext context, WidgetRef ref) {
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
                              '12–16 min',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: AppColors.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text('Predicted ETA range · demo estimate'),
                        const Divider(height: AppSpacing.lg),
                        Text(
                          '${formatCentavos(booking.fareQuote.partyTotalCentavos)} · ${booking.paymentMethod.label}',
                        ),
                        const Text('Fare locked at confirmation'),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SosHoldButton(onCompleted: () => _recordSos(context, ref)),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: () => _completeTrip(context, ref, booking),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Simulate Trip Completion'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
