import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/mobile_settings.dart';
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
  final _mapController = LiveMapViewController();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        if (!state.hasPickup) {
          return Scaffold(
            appBar: AppBar(title: const Text('Select a ride')),
            // Pickup is the device's GPS position, never typed in.
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'We need your location for pickup',
                      style: AppTypography.h2,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Turn on precise location, then try again from Home.',
                      style: AppTypography.bodySm,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('Back to Home'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
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
        // Byahe -- so the fare-matrix
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
            sheetKey: _mapController.panelKey,
            // Passenger controls and the fare stay pinned in the footer.
            // Expanding reveals the detailed fare breakdown.
            collapsedHeight: 420,
            handleSemanticLabel: 'Show fare breakdown',
            background: RoutePreviewMap(
              controller: _mapController,
              from: state.pickup.coordinate,
              to: destination.coordinate,
              height: double.infinity,
              borderRadius: BorderRadius.zero,
              showCaption: false,
              interactive: true,
            ),
            aboveSheet: ArangIconButton(
              icon: Icons.center_focus_strong,
              tooltip: 'Center route',
              onPressed: () => _mapController.fitRoute(),
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
            footer: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PassengerRow(
                  count: state.passengerCount,
                  max: 4,
                  onChanged: state.setPassengerCount,
                ),
                const SizedBox(height: AppSpacing.sm),
                _ReviewBar(
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
              ],
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
                if (expanded) ...[
                  const SizedBox(height: AppSpacing.md),
                  _FareSummary(
                    distanceKm: distanceMeters / 1000,
                    amount: formatCentavos(special.partyTotalCentavos),
                    discounted: discountClass == DiscountClass.discounted,
                  ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          _Line(destination: false, label: 'Pickup', value: pickupName),
          const Padding(
            padding: EdgeInsets.only(left: 32),
            child: Divider(height: 1, color: AppColors.dividerLight),
          ),
          _Line(destination: true, label: 'Drop-off', value: destinationName),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.destination,
    required this.label,
    required this.value,
  });

  final bool destination;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          ArangRouteMarker(destination: destination),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.sm,
          runSpacing: 2,
          children: [
            const Text('Espesyal · Passengers', style: AppTypography.label),
            // Espesyal is billed per trip, so the count never moves the
            // price. Saying so stops people under-reporting to save money.
            Text('Same fare for 1–$max', style: AppTypography.caption),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            selectedBackgroundColor: AppColors.primaryFill,
            selectedForegroundColor: AppColors.primaryText,
          ),
          segments: [
            for (var value = 1; value <= max; value++)
              ButtonSegment(value: value, label: Text('$value')),
          ],
          selected: {count},
          onSelectionChanged: (values) => onChanged(values.single),
        ),
      ],
    );
  }
}

class _FareSummary extends StatelessWidget {
  const _FareSummary({
    required this.distanceKm,
    required this.amount,
    required this.discounted,
  });

  final double distanceKm;
  final String amount;
  final bool discounted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Espesyal na Byahe', style: AppTypography.h2),
              const SizedBox(height: 2),
              Text(
                'Private trip · ${distanceKm.toStringAsFixed(1)} km · '
                'LGU fare, no surge'
                '${discounted ? ' · discount applied' : ''}',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          amount,
          style: AppTypography.displaySm.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
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
    final pickupCap = const FareCalculator().pickupChargeCapCentavos(
      quote,
      pickupChargeMaxMeters.value,
    );
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
          if (pickupCap > 0)
            _BreakdownLine(
              label: 'Pickup charge, added when a driver is found',
              value: 'up to ${formatCentavos(pickupCap)}',
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
          if (pickupCap > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              "The pickup charge covers your driver's way to you. Its distance "
              "is added to your trip's, so the nearer the driver, the less it "
              'is.',
              style: AppTypography.caption.copyWith(height: 1.45),
            ),
          ],
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

/// The bottom action. Its semantics include the fare shown in the sheet.
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
            // Keep the fare visible even when the sheet content is clipped.
            child: Text(
              'Review Ride · ${amount ?? 'Unavailable'}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: enabled ? Colors.white : AppColors.textDisabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
