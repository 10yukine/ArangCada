import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/arang_ui.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/payment_repository.dart';
import '../../domain/fare/fare_matrix.dart';
import '../../core/network/api_exceptions.dart';
import '../../domain/models/booking.dart';
import '../wallet/wallet_sheets.dart';
import '../../core/widgets/arang_dialog.dart';

class BookingReviewScreen extends ConsumerWidget {
  const BookingReviewScreen({super.key});

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    DemoBooking booking,
  ) async {
    final liveRides = ref.read(liveRideRepositoryProvider);
    if (liveRides != null &&
        (booking.rideType != RideType.special ||
            booking.paymentMethod != PaymentMethod.cash)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connected testing currently supports Special + Cash.'),
        ),
      );
      return;
    }
    try {
      ref.read(paymentRepositoryProvider).ensureCanConfirm(booking);
    } on InsufficientBalanceException catch (exception) {
      if (!context.mounted) return;
      final action = await showInsufficientBalanceSheet(context, exception);
      if (!context.mounted || action == null) return;
      if (action == InsufficientBalanceAction.topUp) {
        await showTopUpSheet(context, ref);
      } else {
        booking.changePaymentMethod(PaymentMethod.cash);
        ref.read(demoStateProvider).bookingChanged();
      }
      return;
    }

    try {
      if (liveRides == null) {
        booking
          ..confirm()
          ..beginSearching();
        ref.read(demoStateProvider).bookingChanged();
      } else {
        await liveRides.requestRide(booking);
      }
      if (context.mounted) context.go('/booking/searching');
    } catch (error) {
      if (!context.mounted) return;
      // The server usually knows exactly what is wrong -- "pickup is outside
      // all approved or developer-test TODA jurisdictions" is a complete
      // answer. This used to replace every failure with a guess naming three
      // unrelated causes, so a commuter standing outside Calamba was told to
      // check their connection.
      //
      // `catch` without a type on purpose: requestRide also throws StateError
      // for its own preconditions, and StateError is an Error rather than an
      // Exception, so `on Exception` let those escape entirely.
      final message = switch (error) {
        ApiException(:final message) => message,
        StateError(:final message) => message,
        _ =>
          'Booking could not be sent. Check your location, driver '
              'availability, and connection.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => ArangDialog(
        title: 'Discard this booking?',
        content: const Text(
          'Your pickup, destination and ride choice will be kept, but nothing '
          'is booked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep reviewing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave == true && context.mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final booking = state.activeBooking;
        if (booking == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Review booking')),
            body: Center(
              child: FilledButton(
                onPressed: () => context.go('/home'),
                child: const Text('Start a booking'),
              ),
            ),
          );
        }
        final quote = booking.fareQuote;
        return Scaffold(
          appBar: AppBar(title: const Text('Review booking')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                SectionCard(
                  child: Column(
                    children: [
                      _ReviewRow(label: 'Pickup', value: booking.pickupName),
                      _ReviewRow(
                        label: 'Destination',
                        value: booking.destinationName,
                      ),
                      _ReviewRow(
                        label: 'Ride type',
                        value: booking.rideType == RideType.pooling
                            ? 'Pooling · Regular na Byahe'
                            : 'Special · Espesyal na Byahe',
                      ),
                      _ReviewRow(
                        label: 'Passengers',
                        value: '${booking.passengerCount}',
                      ),
                      _ReviewRow(
                        label: 'Discount',
                        value: booking.userFareClass.label,
                      ),
                      _ReviewRow(
                        label: 'Distance',
                        value:
                            '${(quote.distanceMeters / 1000).toStringAsFixed(1)} km, '
                            'billed as ${quote.chargeableKm} km',
                      ),
                      const _ReviewRow(
                        label: 'Estimated pickup',
                        value: '4–7 minutes',
                      ),
                      const _ReviewRow(
                        label: 'Predicted ETA',
                        value: '12–16 minutes',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Label and control on one line. Stacked, this block cost
                      // three rows of height and pushed the screen past a
                      // single page for the sake of a two-option choice --
                      // so the review screen scrolled even though everything
                      // on it fitted.
                      //
                      // The icons come off the segments for the same reason:
                      // "Cash" and "Digital" are unambiguous words, and the
                      // icons were what made the control too wide to sit
                      // beside its own label.
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Payment method',
                              style: AppTypography.label,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          SegmentedButton<PaymentMethod>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            segments: [
                              const ButtonSegment(
                                value: PaymentMethod.cash,
                                label: Text('Cash'),
                              ),
                              if (ref.read(liveRideRepositoryProvider) == null)
                                const ButtonSegment(
                                  value: PaymentMethod.digital,
                                  label: Text('Digital'),
                                ),
                            ],
                            selected: {booking.paymentMethod},
                            onSelectionChanged: booking.isFareLocked
                                ? null
                                : (selection) {
                                    booking.changePaymentMethod(
                                      selection.single,
                                    );
                                    state.bookingChanged();
                                  },
                          ),
                        ],
                      ),
                      // Only under Digital, because it is only true then. A
                      // balance shown beside a cash fare invites the reader to
                      // work out a relationship that does not exist.
                      if (booking.paymentMethod == PaymentMethod.digital) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Account balance',
                                style: AppTypography.caption,
                              ),
                            ),
                            Text(
                              formatCentavos(state.walletBalanceCentavos),
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SectionCard(
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long, color: AppColors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(child: Text('Estimated fare')),
                      Text(
                        formatCentavos(quote.partyTotalCentavos),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Row(
                  children: [
                    Icon(Icons.lock_outline, size: 18),
                    SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text('Fare locks when booking is confirmed'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                ArangButton(
                  label: 'Confirm Booking',
                  onPressed: booking.isFareLocked
                      ? null
                      : () => _confirm(context, ref, booking),
                ),
                const SizedBox(height: AppSpacing.xs),
                // Backing out of a review must be possible without the system
                // back gesture being the only way.
                ArangButton(
                  label: 'Cancel',
                  variant: ArangButtonVariant.ghost,
                  onPressed: () => _cancel(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
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
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}
