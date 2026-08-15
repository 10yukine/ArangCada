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
      appBar: AppBar(title: const Text('Digital receipt')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final booking = state.activeBooking;
            if (booking == null || booking.status != BookingStatus.completed) {
              return const Center(child: Text('No completed trip receipt.'));
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
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
                        value: booking.receiptReference ?? 'DEMO-RIDE-024',
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
                        value: booking.paymentMethod.label,
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
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: const BoxDecoration(
                    color: AppColors.clayFill,
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppRadii.md),
                    ),
                  ),
                  child: const Text(
                    demoFundsDisclosure,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Back to Home'),
                ),
              ],
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
