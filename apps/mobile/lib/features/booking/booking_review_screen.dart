import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/format/money_format.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/fare/fare_matrix.dart';
import '../../core/network/api_exceptions.dart';
import '../../domain/models/booking.dart';
import '../../core/widgets/arang_dialog.dart';

class BookingReviewScreen extends ConsumerStatefulWidget {
  const BookingReviewScreen({super.key});

  @override
  ConsumerState<BookingReviewScreen> createState() =>
      _BookingReviewScreenState();
}

class _BookingReviewScreenState extends ConsumerState<BookingReviewScreen> {
  bool _submitting = false;

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    DemoBooking booking,
  ) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await _sendBooking(context, ref, booking);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _sendBooking(
    BuildContext context,
    WidgetRef ref,
    DemoBooking booking,
  ) async {
    final liveRides = ref.read(liveRideRepositoryProvider);
    if (booking.paymentMethod == PaymentMethod.digital) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digital payments are disabled during beta testing. Choose Cash.'),
        ),
      );
      return;
    }
    if (liveRides != null && booking.rideType != RideType.special) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connected testing currently supports Special + Cash.'),
        ),
      );
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
  Widget build(BuildContext context) {
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
        final colors = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Review booking')),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: FilledButton(
                onPressed: booking.isFareLocked || _submitting
                    ? null
                    : () => _confirm(context, ref, booking),
                child: Text(
                  _submitting ? 'Sending request…' : 'Confirm Booking',
                ),
              ),
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              children: [
                Text(
                  'YOUR RIDE',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.6,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatCentavos(quote.partyTotalCentavos),
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Estimated fare · locks on confirmation',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                _RouteStop(
                  label: 'PICKUP',
                  name: booking.pickupName,
                  icon: Icons.my_location,
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: VerticalDivider(),
                  ),
                ),
                _RouteStop(
                  label: 'DESTINATION',
                  name: booking.destinationName,
                  icon: Icons.place_outlined,
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                _ReviewRow(
                  label: 'Ride',
                  value: booking.rideType == RideType.pooling
                      ? 'Pooling · Regular na Byahe'
                      : 'Special · Espesyal na Byahe',
                ),
                _ReviewRow(
                  label: 'Passengers',
                  value: '${booking.passengerCount}',
                ),
                _ReviewRow(
                  label: 'Fare class',
                  value: booking.userFareClass.label,
                ),
                _ReviewRow(
                  label: 'Distance',
                  value:
                      '${(quote.distanceMeters / 1000).toStringAsFixed(1)} km · billed as ${quote.chargeableKm} km',
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 24),
                Text('Payment', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SegmentedButton<PaymentMethod>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: colors.primaryContainer,
                    selectedForegroundColor: colors.onPrimaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: PaymentMethod.cash,
                      icon: Icon(Icons.payments_outlined),
                      label: Text('Cash'),
                    ),
                    ButtonSegment(
                      value: PaymentMethod.digital,
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      label: Text('Digital'),
                      enabled: false,
                    ),
                  ],
                  selected: {booking.paymentMethod},
                  onSelectionChanged: booking.isFareLocked || _submitting
                      ? null
                      : (selection) {
                          booking.changePaymentMethod(selection.single);
                          state.bookingChanged();
                        },
                ),
                const SizedBox(height: 8),
                Text(
                  'Digital payments are disabled during beta testing. Pay your driver in cash.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                Text(
                  'Driver availability and arrival time are confirmed after dispatch.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _submitting ? null : () => _cancel(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RouteStop extends StatelessWidget {
  const _RouteStop({
    required this.label,
    required this.name,
    required this.icon,
  });
  final String label;
  final String name;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colors.primary, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
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
