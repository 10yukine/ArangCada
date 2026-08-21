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
/// method belongs on the review screen; passenger count is what actually moves
/// the Pooling fare, so it belongs here next to the prices it changes.
class RideOptionsScreen extends ConsumerStatefulWidget {
  const RideOptionsScreen({super.key});

  @override
  ConsumerState<RideOptionsScreen> createState() => _RideOptionsScreenState();
}

class _RideOptionsScreenState extends ConsumerState<RideOptionsScreen> {
  bool _expanded = false;

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
        );

        final fare = ref.read(fareRepositoryProvider);
        final discountClass = state.userFareClass.discountClass;
        final pooling = fare.quote(
          distanceMeters: distanceMeters,
          rideType: RideType.pooling,
          passengerCount: state.passengerCount.clamp(1, 4),
          discountClass: discountClass,
        );
        final special = state.passengerCount <= 3
            ? fare.quote(
                distanceMeters: distanceMeters,
                rideType: RideType.special,
                passengerCount: state.passengerCount,
                discountClass: discountClass,
              )
            : null;

        final selected = state.selectedRideType;
        final active = selected == RideType.special ? special : pooling;

        return Scaffold(
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RoutePreviewMap(
                        from: state.pickup.coordinate,
                        to: destination.coordinate,
                        height: double.infinity,
                        borderRadius: BorderRadius.zero,
                        showCaption: false,
                        boundaries: const [
                          MapBoundary(
                            points: DemoData.calambaPoblacionPrototypeBoundary,
                          ),
                        ],
                        boundaryLabel: 'Prototype boundary · evaluation only',
                      ),
                    ),
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
                ),
              ),
              _RideSheet(
                expanded: _expanded,
                onToggle: () => setState(() => _expanded = !_expanded),
                pickupName: state.pickup.name,
                destinationName: destination.name,
                distanceMeters: distanceMeters,
                rejection: rejection,
                pooling: pooling,
                special: special,
                selected: selected,
                passengerCount: state.passengerCount,
                onSelectType: state.setSelectedRideType,
                onPassengerCount: state.setPassengerCount,
                active: active,
                onReview: (rejection == null && active != null)
                    ? () {
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
                      }
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RideSheet extends StatelessWidget {
  const _RideSheet({
    required this.expanded,
    required this.onToggle,
    required this.pickupName,
    required this.destinationName,
    required this.distanceMeters,
    required this.rejection,
    required this.pooling,
    required this.special,
    required this.selected,
    required this.passengerCount,
    required this.onSelectType,
    required this.onPassengerCount,
    required this.active,
    required this.onReview,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final String pickupName;
  final String destinationName;
  final double distanceMeters;
  final String? rejection;
  final FareQuote pooling;
  final FareQuote? special;
  final RideType selected;
  final int passengerCount;
  final ValueChanged<RideType> onSelectType;
  final ValueChanged<int> onPassengerCount;
  final FareQuote? active;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final km = (distanceMeters / 1000).toStringAsFixed(1);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.66,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x141F1E1D),
            blurRadius: 10,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              label: expanded ? 'Hide fare breakdown' : 'Show fare breakdown',
              child: InkWell(
                onTap: onToggle,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.disabledFill,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LocationCard(
                      pickupName: pickupName,
                      destinationName: destinationName,
                    ),
                    if (rejection != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _ZoneWarning(message: rejection!),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Expanded(
                          child: Text('Select a Ride', style: AppTypography.h2),
                        ),
                        Text('$km km · Ord. 743', style: AppTypography.caption),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _RideOption(
                      title: 'Special',
                      subtitle: special == null
                          ? 'Private trip · up to 3 passengers'
                          : 'Private trip · '
                                '${formatCentavos(special!.partyTotalCentavos)}',
                      icon: Icons.person_outline,
                      selected: selected == RideType.special,
                      enabled: special != null,
                      onTap: () => onSelectType(RideType.special),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _RideOption(
                      title: 'Pooling',
                      subtitle:
                          'Shared trip · '
                          '${formatCentavos(pooling.unitFareCentavos)} each',
                      icon: Icons.groups_outlined,
                      selected: selected == RideType.pooling,
                      enabled: true,
                      onTap: () => onSelectType(RideType.pooling),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _PassengerRow(
                      count: passengerCount,
                      max: selected == RideType.special ? 3 : 4,
                      onChanged: onPassengerCount,
                    ),
                    if (expanded && active != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _FareBreakdown(quote: active!),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: _ReviewBar(
                amount: active == null
                    ? null
                    : formatCentavos(active!.partyTotalCentavos),
                onPressed: onReview,
              ),
            ),
          ],
        ),
      ),
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
            background: AppColors.clayFill,
            foreground: AppColors.clayText,
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

class _RideOption extends StatelessWidget {
  const _RideOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '$title. $subtitle',
      child: AnimatedContainer(
        duration: AppMotion.button,
        decoration: BoxDecoration(
          color: selected ? AppColors.clayFill : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    ArangRowIcon(
                      icon,
                      background: AppColors.surface,
                      foreground: AppColors.clayText,
                      size: 38,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(subtitle, style: AppTypography.caption),
                        ],
                      ),
                    ),
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      size: 22,
                      color: selected
                          ? AppColors.primary
                          : AppColors.borderStrong,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Occupies the prototype's "Pay with" row. Payment method is chosen on the
/// review screen; passenger count is what actually moves the Pooling fare.
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
            label: pooling ? 'Per passenger' : 'Per trip · 1–3 passengers',
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
