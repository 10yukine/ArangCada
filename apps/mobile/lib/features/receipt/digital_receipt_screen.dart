import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/fare/fare_matrix.dart';
import '../../domain/models/booking.dart';
import '../wallet/wallet_sheets.dart';

class DigitalReceiptScreen extends ConsumerWidget {
  const DigitalReceiptScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(
        // Same destination as "Back to Home" below -- this is a `go()`
        // route with nothing on the Navigator stack to pop to.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () => context.go('/home'),
        ),
        title: const Text('Digital receipt'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final booking = state.activeBooking;
            if (booking == null || booking.status != BookingStatus.completed) {
              return const Center(child: Text('No completed trip receipt.'));
            }
            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (AppSpacing.md * 2),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 64,
                        color: AppColors.green,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Trip completed',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SectionCard(
                        child: Column(
                          children: [
                            _ReceiptRow(
                              label: 'Reference',
                              value: booking.receiptReference ?? 'SBX-RIDE-024',
                            ),
                            _ReceiptRow(
                              label: 'Route',
                              value:
                                  '${booking.pickupName} → ${booking.destinationName}',
                            ),
                            _ReceiptRow(
                              label: 'Ride',
                              value: booking.rideType == RideType.pooling
                                  ? 'Pooling'
                                  : 'Special',
                            ),
                            _ReceiptRow(
                              label: 'Fare class',
                              value: booking.userFareClass.label,
                            ),
                            _ReceiptRow(
                              label: 'Payment',
                              value: state.paymentFallbackToCash
                                  ? 'Cash · switched after sandbox payment failure'
                                  : booking.paymentMethod.label,
                            ),
                            const Divider(height: AppSpacing.lg),
                            _ReceiptRow(
                              label: 'Total fare',
                              value: formatCentavos(
                                booking.fareQuote.partyTotalCentavos,
                              ),
                              emphasize: true,
                            ),
                          ],
                        ),
                      ),
                      if (booking.paymentMethod == PaymentMethod.digital) ...[
                        const SizedBox(height: AppSpacing.md),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: const BoxDecoration(
                            color: AppColors.primaryFill,
                            borderRadius: BorderRadius.all(
                              Radius.circular(AppRadii.md),
                            ),
                          ),
                          child: const Text(
                            demoFundsDisclosure,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      // No button here leads back into the rating flow, in
                      // either state. Rating is over by the time the receipt
                      // renders -- whether it was submitted or skipped -- and
                      // re-offering it made a deliberate "skip" look like it
                      // had failed to register. A prior version relabeled the
                      // button "View Rating" instead of removing it, which
                      // still read as an invitation to rate again; keeping it
                      // only in the unrated branch had the same effect. The
                      // receipt now states the outcome and offers exactly one
                      // action.
                      if (state.tripRating != null) ...[
                        Text(
                          'You rated this ride ${state.tripRating} out of 5.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      FilledButton(
                        onPressed: () => context.go('/home'),
                        child: const Text('Back to Home'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: emphasize
                  ? Theme.of(context).textTheme.headlineSmall
                  : Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}
