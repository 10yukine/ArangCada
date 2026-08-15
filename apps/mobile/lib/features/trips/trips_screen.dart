import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/booking.dart';

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final booking = state.activeBooking;
            if (booking == null || booking.status == BookingStatus.cancelled) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: EmptyStateCard(
                  icon: Icons.route_outlined,
                  title: 'No demo trips yet',
                  message: 'Completed and active demo rides will appear here.',
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            booking.status == BookingStatus.completed
                                ? Icons.check_circle
                                : Icons.directions_run,
                            color: booking.status == BookingStatus.completed
                                ? AppColors.green
                                : AppColors.coral,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              booking.status == BookingStatus.completed
                                  ? 'Completed demo trip'
                                  : 'Active demo booking',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${booking.pickupName} → ${booking.destinationName}',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: () => context.go(_routeFor(booking.status)),
                        child: Text(
                          booking.status == BookingStatus.completed
                              ? 'View Receipt'
                              : 'Resume',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _routeFor(BookingStatus status) => switch (status) {
    BookingStatus.draft => '/booking/review',
    BookingStatus.confirmed || BookingStatus.searching => '/booking/searching',
    BookingStatus.matched => '/booking/driver-matched',
    BookingStatus.approaching => '/trip/approach',
    BookingStatus.inProgress => '/trip/active',
    BookingStatus.completed => '/receipt',
    BookingStatus.cancelled => '/home',
  };
}
