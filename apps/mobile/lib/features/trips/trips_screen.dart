import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/booking.dart';
import '../../domain/models/demo_user.dart';
import '../../domain/state/driver_trip_state_machine.dart';

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    final isDriver = state.currentUser?.role == DemoRole.driver;
    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            if (isDriver) {
              final status = state.driverTrip.status;
              final hasRide =
                  status == DriverTripStatus.accepted ||
                  status == DriverTripStatus.arrivedAtPickup ||
                  status == DriverTripStatus.inProgress ||
                  status == DriverTripStatus.completed;
              if (!hasRide) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: EmptyStateCard(
                    icon: Icons.route_outlined,
                    title: 'No driver trips yet',
                    message: 'Accepted and completed rides will appear here.',
                    actionLabel: 'Go Online',
                    onAction: () => context.go('/driver'),
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
                        Text(
                          status == DriverTripStatus.completed
                              ? 'Completed driver trip'
                              : 'Current driver trip',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'Joshua Ramos · Calamba Crossing to SM Calamba',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton(
                          onPressed: () => context.go('/driver'),
                          child: Text(
                            status == DriverTripStatus.completed
                                ? 'View Summary'
                                : 'Resume',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            final booking = state.activeBooking;
            if (booking == null || booking.status == BookingStatus.cancelled) {
              return Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: EmptyStateCard(
                  icon: Icons.route_outlined,
                  title: 'No trips yet',
                  message: 'Completed and active rides will appear here.',
                  actionLabel: 'Book a Ride',
                  onAction: () => context.go('/home'),
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
                                  ? 'Completed trip'
                                  : 'Active booking',
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
