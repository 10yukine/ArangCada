import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/money_format.dart';
import '../../core/geo/haversine.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/map/live_map_view.dart';
import '../../core/widgets/map/route_preview_map.dart';
import '../../core/widgets/drag_sheet_scaffold.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/fare/fare_calculator.dart';
import '../../domain/fare/fare_matrix.dart';
import '../../domain/geo/service_area.dart';
import '../../domain/models/booking.dart';
import '../../demo/demo_data.dart';

/// Ride selection, following the approved prototype's `confirm` screen:
/// map on top, a sheet holding the pickup/drop card, ride options, and a
/// bottom bar carrying the fare beside the primary action.
///
/// The prototype's "Pay with" chips are replaced by passenger count. Payment
/// method belongs on the review screen.
///
/// Since 31 Aug 2026 Espesyal is the only bookable ride type (Calamba City
/// Hall), so there is no ride-type choice left to make here. Passenger count
/// does not change an Espesyal fare -- it is billed kada byahe -- but it is
/// captured here because dispatch and the driver need to know how many people
/// are waiting.
class RideOptionsScreen extends ConsumerStatefulWidget {
  const RideOptionsScreen({super.key});

  @override
  ConsumerState<RideOptionsScreen> createState() => _RideOptionsScreenState();
}

class _RideOptionsScreenState extends ConsumerState<RideOptionsScreen> {

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final destination = state.destination;
        if (destination == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Select a ride')),
            body: const Center(child: Text('Choose a destination first.')),
          );
        }

        final distanceMeters = haversineDistanceMeters(
          state.pickup.coordinate,
          destination.coordinate,
        );
        final rejection = ServiceArea.rejectionReason(
          pickup: state.pickup.coordinate,
          destination: destination.coordinate,
          allowCabuyaoTestException:
              state.currentUser?.isInternalTester ?? false,
        );

        final fare = ref.read(fareRepositoryProvider);
        final discountClass = state.userFareClass.discountClass;
        // Espesyal only since 31 Aug 2026 (Calamba City Hall withdrew pooling
        // as a bookable option). The RideType enum and the pooling fare data
        // are deliberately retained as the ordinance record of Regular na
        // Byahe -- see docs/LGU_FARE_MATRIX.md section 2a -- so the fare-matrix
        // reference screen can still show it. It is simply never offered here.
        const selected = RideType.special;
        final special = fare.quote(
          distanceMeters: distanceMeters,
          rideType: selected,
          passengerCount: state.passengerCount.clamp(1, 4),
          discountClass: discountClass,
        );
        final active = special;

        return Scaffold(
          body: DragSheetScaffold(
            // Tall enough that the collapsed peek already shows the addresses,
            // the passenger picker and the Review bar. The fare breakdown is
            // what expanding is for.
            collapsedHeight: 340,
            handleSemanticLabel: 'Show fare breakdown',
            background: RoutePreviewMap(
              from: state.pickup.coordinate,
              to: destination.coordinate,
              height: double.infinity,
              borderRadius: BorderRadius.zero,
              showCaption: false,
              // Keeps the compass AND the boundary chip out from under the
              // status bar; this map runs edge to edge.
              boundaries: const [
                MapBoundary(
                  points: DemoData.calambaPoblacionPrototypeBoundary,
                ),
              ],
            ),
            overlay: [
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 14,
                child: ArangIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  onPressed: () => context.pop(),
                ),
              ),
            ],
            footer: _ReviewBar(
              amount: formatCentavos(active.partyTotalCentavos),
              // `active` is now always non-null: with pooling withdrawn there
              // is exactly one quote and it is unconditional. Only the
              // service-area rejection can block review.
              onPressed: rejection != null
                  ? null
                  : () {
                      // The review screen renders DemoState.activeBooking.
                      // Pushing the route without creating the draft first
                      // lands on an empty screen.
                      state.setActiveBooking(
                        DemoBooking.draft(
                          pickupName: state.pickup.name,
                          destinationName: destination.name,
                          rideType: selected,
                          passengerCount: state.passengerCount,
                          userFareClass: state.userFareClass,
                          paymentMethod: PaymentMethod.cash,
                          fareQuote: active,
                        ),
                      );
                      context.push('/booking/review');
                    },
            ),
            sheetBuilder: (context, expanded) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LocationCard(
                  pickupName: state.pickup.name,
                  destinationName: destination.name,
                ),
                if (rejection != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _ZoneWarning(message: rejection),
                ],
                const SizedBox(height: AppSpacing.md),

                // The "Select a Ride" heading and its single selected card are
                // gone. Espesyal has been the only bookable ride type since
                // 31 Aug 2026, so a picker with one permanently chosen option
                // was a choice that could not be made, taking the room the
                // fare breakdown needed. What it actually carried -- the
                // distance and the ordinance the price comes from -- is kept.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Espesyal · private trip',
                        style: AppTypography.label,
                      ),
                    ),
                    Text(
                      '${(distanceMeters / 1000).toStringAsFixed(1)} km '
                      '· Ord. 743',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _PassengerRow(
                  count: state.passengerCount,
                  max: 4,
                  onChanged: state.setPassengerCount,
                ),
                if (expanded) ...[
                  const SizedBox(height: AppSpacing.md),
                  _FareBreakdown(quote: special),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.pickupName,
    required this.destinationName,
  });

  final String pickupName;
  final String destinationName;

  @override
  Widget build(BuildContext context) {
    return ArangCard(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          _Line(
            icon: Icons.my_location,
            background: AppColors.greenFill,
            foreground: AppColors.green,
            label: 'Pickup Location',
            value: pickupName,
          ),
          const Padding(
            padding: EdgeInsets.only(left: 46),
            child: Divider(height: 1, color: AppColors.dividerLight),
          ),
          _Line(
            icon: Icons.place_outlined,
            background: AppColors.primaryFill,
            foreground: AppColors.primaryText,
            label: 'Drop Location',
            value: destinationName,
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          ArangRowIcon(
            icon,
            background: background,
            foreground: foreground,
            size: 34,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.caption),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneWarning extends StatelessWidget {
  const _ZoneWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.dangerFill,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.wrong_location_outlined,
            size: 18,
            color: AppColors.dangerDeep,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                color: AppColors.dangerDeep,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PassengerRow extends StatelessWidget {
  const _PassengerRow({
    required this.count,
    required this.max,
    required this.onChanged,
  });

  final int count;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Passengers',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var value = 1; value <= max; value++)
                ArangChip(
                  label: '$value',
                  selected: value == count,
                  onTap: () => onChanged(value),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FareBreakdown extends StatelessWidget {
  const _FareBreakdown({required this.quote});

  final FareQuote quote;

  @override
  Widget build(BuildContext context) {
    final pooling = quote.rideType == RideType.pooling;
    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.dividerLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fare breakdown', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          _BreakdownLine(
            label: pooling ? 'Regular na Byahe' : 'Espesyal na Byahe',
            value: formatCentavos(quote.unitFareCentavos),
          ),
          _BreakdownLine(
            label: pooling ? 'Per passenger' : 'Per trip · 1–4 passengers',
            value: pooling ? '× ${quote.passengerCount}' : '× 1',
          ),
          _BreakdownLine(
            label: 'Billed distance',
            value: '${quote.chargeableKm} km',
          ),
          const Divider(height: AppSpacing.lg),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                formatCentavos(quote.partyTotalCentavos),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Fares follow Calamba City Ordinance No. 743, s. 2022. No surge '
            'pricing. Students, seniors and PWD get the published discounted '
            'rate once their ID is verified.',
            style: AppTypography.caption.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _BreakdownLine extends StatelessWidget {
  const _BreakdownLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fare on the left, action on the right -- the prototype's bottom CTA.
class _ReviewBar extends StatelessWidget {
  const _ReviewBar({required this.amount, required this.onPressed});

  final String? amount;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Review ride, ${amount ?? 'unavailable'}',
      child: Material(
        color: enabled ? AppColors.primary : AppColors.disabledFill,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  amount ?? '—',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: enabled ? Colors.white : AppColors.textDisabled,
                  ),
                ),
                Text(
                  'Review Ride',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: enabled ? Colors.white : AppColors.textDisabled,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
