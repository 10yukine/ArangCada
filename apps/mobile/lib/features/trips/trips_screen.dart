import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/dashboard_back_button.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/booking.dart';
import '../../domain/models/demo_user.dart';
import '../../domain/state/driver_trip_state_machine.dart';

/// The trip summary sits flat on the page -- a top divider and spacing mark
/// it off, not a bordered card. There is exactly one summary block here, so
/// a card would not be communicating hierarchy over anything else.
class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    final isDriver = state.currentUser?.role == DemoRole.driver;
    return Scaffold(
      appBar: AppBar(
        leading: DashboardBackButton(isDriver: isDriver),
        title: const Text('Trips'),
      ),
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
                  _TripSummary(
                    icon: status == DriverTripStatus.completed
                        ? Icons.check_circle
                        : Icons.directions_run,
                    iconColor: status == DriverTripStatus.completed
                        ? AppColors.green
                        : AppColors.coral,
                    title: status == DriverTripStatus.completed
                        ? 'Completed driver trip'
                        : 'Current driver trip',
                    subtitle: 'Joshua Ramos · Calamba Crossing to SM Calamba',
                    buttonLabel: status == DriverTripStatus.completed
                        ? 'View Summary'
                        : 'Resume',
                    onButtonPressed: () => context.go('/driver'),
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
                _TripSummary(
                  icon: booking.status == BookingStatus.completed
                      ? Icons.check_circle
                      : Icons.directions_run,
                  iconColor: booking.status == BookingStatus.completed
                      ? AppColors.green
                      : AppColors.coral,
                  title: booking.status == BookingStatus.completed
                      ? 'Completed trip'
                      : 'Active booking',
                  subtitle: '${booking.pickupName} → ${booking.destinationName}',
                  buttonLabel: booking.status == BookingStatus.completed
                      ? 'View Receipt'
                      : 'Resume',
                  onButtonPressed: () => context.go(_routeFor(booking.status)),
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

class _TripSummary extends StatelessWidget {
  const _TripSummary({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onButtonPressed,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onButtonPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle),
        const SizedBox(height: AppSpacing.md),
        FilledButton(onPressed: onButtonPressed, child: Text(buttonLabel)),
      ],
    );
  }
}
