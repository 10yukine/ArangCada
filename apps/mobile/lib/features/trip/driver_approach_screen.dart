import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/painted_calamba_map.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/booking.dart';

class DriverApproachScreen extends ConsumerWidget {
  const DriverApproachScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Driver approaching')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final booking = state.activeBooking;
            if (booking == null ||
                booking.status != BookingStatus.approaching) {
              return const Center(child: Text('No approaching driver.'));
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                const PaintedCalambaMap(animateDriver: true),
                const SizedBox(height: AppSpacing.md),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: AppColors.clayFill,
                            child: Icon(
                              Icons.electric_rickshaw,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Marco is on the way',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const Text('Tricycle 024 · Calamba TODA'),
                              ],
                            ),
                          ),
                          Text(
                            state.forceEtaFallback ? '6–9 min' : '4–7 min',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: AppColors.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (state.forceEtaFallback)
                        const Text('ETA fallback · route estimate unavailable'),
                      Text('Pickup: ${booking.pickupName}'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: () {
                    booking.startTrip();
                    state.bookingChanged();
                    context.go('/trip/active');
                  },
                  child: const Text('Simulate Driver Arrival & Start Trip'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
