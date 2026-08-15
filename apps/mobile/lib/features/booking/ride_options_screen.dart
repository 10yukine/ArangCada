import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/format/money_format.dart';
import '../../core/geo/haversine.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/fare/fare_calculator.dart';
import '../../domain/fare/fare_matrix.dart';
import '../../domain/models/booking.dart';

class RideOptionsScreen extends ConsumerWidget {
  const RideOptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final destination = state.destination;
        if (destination == null) {
          return const Scaffold(
            body: Center(child: Text('Choose a destination first.')),
          );
        }

        final distanceMeters = haversineDistanceMeters(
          state.pickup.coordinate,
          destination.coordinate,
        );
        final fareRepository = ref.watch(fareRepositoryProvider);
        final pooling = fareRepository.quote(
          distanceMeters: distanceMeters,
          rideType: RideType.pooling,
          passengerCount: state.passengerCount,
          discountClass: state.userFareClass.discountClass,
        );
        final FareQuote? special = state.passengerCount <= 3
            ? fareRepository.quote(
                distanceMeters: distanceMeters,
                rideType: RideType.special,
                passengerCount: state.passengerCount,
                discountClass: state.userFareClass.discountClass,
              )
            : null;

        return Scaffold(
          appBar: AppBar(title: const Text('Ride options')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                SectionCard(
                  child: Column(
                    children: [
                      _RouteRow(
                        icon: Icons.radio_button_checked,
                        color: AppColors.primary,
                        title: state.pickup.name,
                        subtitle: 'Pickup',
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 19),
                        child: Divider(height: AppSpacing.lg),
                      ),
                      _RouteRow(
                        icon: Icons.location_on,
                        color: AppColors.coral,
                        title: destination.name,
                        subtitle: 'Destination',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${(distanceMeters / 1000).toStringAsFixed(1)} km measured · '
                  'billed as ${pooling.chargeableKm} km',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Passengers',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    for (var count = 1; count <= 4; count++)
                      ChoiceChip(
                        label: Text('$count'),
                        selected: state.passengerCount == count,
                        side: BorderSide(
                          color: state.passengerCount == count
                              ? AppColors.coral
                              : AppColors.borderStrong,
                        ),
                        onSelected: (_) => state.setPassengerCount(count),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Fare class',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Column(
                  children: [
                    for (var row = 0; row < 2; row++) ...[
                      Row(
                        children: [
                          for (var column = 0; column < 2; column++) ...[
                            if (column > 0)
                              const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: SizedBox(
                                width: double.infinity,
                                child: ChoiceChip(
                                  label: Center(
                                    child: Text(
                                      UserFareClass
                                          .values[row * 2 + column]
                                          .label,
                                    ),
                                  ),
                                  selected:
                                      state.userFareClass ==
                                      UserFareClass.values[row * 2 + column],
                                  side: BorderSide(
                                    color:
                                        state.userFareClass ==
                                            UserFareClass.values[row * 2 +
                                                column]
                                        ? AppColors.coral
                                        : AppColors.borderStrong,
                                  ),
                                  onSelected: (_) => state.setUserFareClass(
                                    UserFareClass.values[row * 2 + column],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (row == 0) const SizedBox(height: AppSpacing.xs),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'One class applies to everyone in this booking. Mixed '
                  'discount classes are not supported in the demo.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Eligibility verification may be required.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _FareOptionCard(
                  title: 'Pooling',
                  subtitle: 'Regular na Byahe · per passenger · up to 4',
                  icon: Icons.groups_outlined,
                  quote: pooling,
                  onSelected: () {
                    state.setActiveBooking(
                      DemoBooking.draft(
                        pickupName: state.pickup.name,
                        destinationName: destination.name,
                        rideType: RideType.pooling,
                        passengerCount: state.passengerCount,
                        userFareClass: state.userFareClass,
                        paymentMethod: PaymentMethod.cash,
                        fareQuote: pooling,
                      ),
                    );
                    context.push('/booking/review');
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _FareOptionCard(
                  title: 'Special',
                  subtitle: 'Espesyal na Byahe · per trip · up to 3',
                  icon: Icons.electric_rickshaw_outlined,
                  quote: special,
                  onSelected: special == null
                      ? null
                      : () {
                          state.setActiveBooking(
                            DemoBooking.draft(
                              pickupName: state.pickup.name,
                              destinationName: destination.name,
                              rideType: RideType.special,
                              passengerCount: state.passengerCount,
                              userFareClass: state.userFareClass,
                              paymentMethod: PaymentMethod.cash,
                              fareQuote: special,
                            ),
                          );
                          context.push('/booking/review');
                        },
                  unavailableMessage: special == null
                      ? 'Special rides allow only 1–3 passengers.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Preview from City Ordinance No. 743, s. 2022. Final fare '
                  'will be confirmed by trusted server logic in production.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              Text(title, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      ],
    );
  }
}

class _FareOptionCard extends StatelessWidget {
  const _FareOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.quote,
    required this.onSelected,
    this.unavailableMessage,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final FareQuote? quote;
  final VoidCallback? onSelected;
  final String? unavailableMessage;

  @override
  Widget build(BuildContext context) {
    final currentQuote = quote;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.clayFill,
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (currentQuote != null)
                Text(
                  formatCentavos(currentQuote.partyTotalCentavos),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: AppColors.primary),
                ),
            ],
          ),
          if (currentQuote == null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              unavailableMessage ?? 'Unavailable',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.danger),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            _FareDetail(
              label: currentQuote.rideType == RideType.pooling
                  ? 'Per passenger × ${currentQuote.passengerCount}'
                  : 'Per trip',
              value: formatCentavos(currentQuote.unitFareCentavos),
            ),
            _FareDetail(
              label: 'First 2 km',
              value: formatCentavos(currentQuote.baseFareCentavos),
            ),
            _FareDetail(
              label: 'Additional distance',
              value: formatCentavos(currentQuote.additionalDistanceCentavos),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(onPressed: onSelected, child: Text('Review $title')),
          ],
        ],
      ),
    );
  }
}

class _FareDetail extends StatelessWidget {
  const _FareDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Text(value, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
