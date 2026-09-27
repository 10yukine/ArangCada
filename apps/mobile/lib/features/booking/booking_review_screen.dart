import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/money_format.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/fare/fare_matrix.dart';
import '../../core/network/api_exceptions.dart';
import '../../domain/models/booking.dart';
import '../../core/widgets/arang_dialog.dart';
import '../../core/widgets/arang_ui.dart';

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
        final espesyal = booking.rideType != RideType.pooling;
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
                child: Text(_submitting ? 'Sending request…' : 'Request Ride'),
              ),
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              children: [
                const Text('Fare', style: AppTypography.label),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  formatCentavos(quote.partyTotalCentavos),
                  style: AppTypography.display.copyWith(
                    fontSize: 36,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'LGU fare · locked when you request',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                ArangRouteStop(
                  destination: false,
                  label: 'Pickup',
                  name: booking.pickupName,
                ),
                // A short rail joins the two markers into one route.
                // Align stops the list from stretching the 2 px rail across.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(left: 9),
                    width: 2,
                    height: 18,
                    color: AppColors.border,
                  ),
                ),
                ArangRouteStop(
                  destination: true,
                  label: 'Drop-off',
                  name: booking.destinationName,
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.xs),
                _ReviewRow(
                  label: 'Ride',
                  value: espesyal
                      ? 'Espesyal na Byahe'
                      : 'Regular na Byahe',
                ),
                _ReviewRow(
                  label: 'Passengers',
                  value: espesyal
                      ? '${booking.passengerCount} · same fare'
                      : '${booking.passengerCount}',
                ),
                _ReviewRow(
                  label: 'Fare class',
                  value: booking.userFareClass.label,
                ),
                _ReviewRow(
                  label: 'Distance',
                  value:
                      '${(quote.distanceMeters / 1000).toStringAsFixed(1)} km'
                      ' · billed as ${quote.chargeableKm} km',
                ),
                // Cash is the only method in beta. A plain row says so; a
                // selector with a permanently disabled "Digital" did not.
                const _ReviewRow(label: 'Payment', value: 'Cash · pay your driver'),
                const SizedBox(height: AppSpacing.xs),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Digital payments are off during beta. Your driver and '
                  'arrival time are confirmed after you request.',
                  style: AppTypography.caption.copyWith(height: 1.45),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _submitting ? null : () => _cancel(context),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('Discard booking'),
                  ),
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
            width: 104,
            child: Text(
              label,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
