import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/report_issue_sheet.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/booking.dart';
import '../wallet/wallet_sheets.dart';

class DigitalReceiptScreen extends ConsumerWidget {
  const DigitalReceiptScreen({this.tripId, super.key});

  final String? tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    final rides = ref.watch(liveRideRepositoryProvider);
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
          listenable: Listenable.merge([state, rides]),
          builder: (context, _) {
            final booking = state.activeBooking;
            final connectedReceipt = tripId != null || rides != null;
            final selectedId = tripId ?? state.liveTripId;
            Map<String, dynamic>? trip;
            for (final row in rides?.trips ?? <Map<String, dynamic>>[]) {
              if (row['id'] == selectedId) {
                trip = row;
                break;
              }
            }
            if (connectedReceipt
                ? trip == null || trip['status'] != 'completed'
                : booking == null ||
                      booking.status != BookingStatus.completed) {
              return const Center(child: Text('No completed trip receipt.'));
            }
            final rawFare = trip?['final_fare'] ?? trip?['fare_estimate'];
            final reference = connectedReceipt
                ? (trip!['receipt_ref'] as String? ?? 'TRIP-${trip['id']}')
                : booking!.receiptReference ?? 'SBX-RIDE-024';
            final route = connectedReceipt
                ? '${trip!['pickup_label'] ?? 'Pickup'} → ${trip['destination_label'] ?? 'Destination'}'
                : '${booking!.pickupName} → ${booking.destinationName}';
            final ride = connectedReceipt
                ? trip!['ride_type']
                : booking!.rideType.name;
            final payment = connectedReceipt
                ? trip!['payment_method']
                : booking!.paymentMethod.name;
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
                            _ReceiptRow(label: 'Reference', value: reference),
                            _ReceiptRow(label: 'Route', value: route),
                            _ReceiptRow(
                              label: 'Ride',
                              value: ride == 'pooling' ? 'Pooling' : 'Special',
                            ),
                            if (!connectedReceipt)
                              _ReceiptRow(
                                label: 'Fare class',
                                value: booking!.userFareClass.label,
                              ),
                            _ReceiptRow(
                              label: 'Payment',
                              value: connectedReceipt
                                  ? (payment == 'cash'
                                        ? 'Cash'
                                        : payment?.toString() ?? 'Unavailable')
                                  : state.paymentFallbackToCash
                                  ? 'Cash · switched after sandbox payment failure'
                                  : booking!.paymentMethod.label,
                            ),
                            const Divider(height: AppSpacing.lg),
                            _ReceiptRow(
                              label: 'Total fare',
                              value: connectedReceipt
                                  ? rawFare is num
                                        ? formatCentavos(
                                            (rawFare * 100).round(),
                                          )
                                        : 'Unavailable'
                                  : formatCentavos(
                                      booking!.fareQuote.partyTotalCentavos,
                                    ),
                              emphasize: true,
                            ),
                          ],
                        ),
                      ),
                      if (!connectedReceipt &&
                          booking!.paymentMethod == PaymentMethod.digital) ...[
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
                      if (!connectedReceipt && state.tripRating != null) ...[
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
                      const SizedBox(height: AppSpacing.xs),
                      TextButton(
                        onPressed: () => showReportIssueFlow(
                          context: context,
                          driver: false,
                          onSubmit: rides == null || selectedId == null
                              ? null
                              : (category, description) =>
                                    rides.createComplaint(
                                      selectedId,
                                      category,
                                      description,
                                    ),
                        ),
                        child: const Text('Report an issue with this trip'),
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
