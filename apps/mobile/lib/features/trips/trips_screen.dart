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
            final liveRides = ref.read(liveRideRepositoryProvider);
            // Illustrative sandbox history for the pre-connection demo only.
            // Once a real Supabase session is live, actual trip records
            // always win -- this branch never runs when liveRides != null.
            if (liveRides == null && state.sampleContentEnabled) {
              return isDriver
                  ? const _DriverSampleHistory()
                  : const _CommuterSampleHistory();
            }
            if (liveRides != null) {
              final trips = liveRides.trips.where((trip) {
                final status = trip['status'] as String?;
                return status != 'cancelled_by_rider' &&
                    status != 'no_driver_available';
              }).toList();
              if (trips.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: EmptyStateCard(
                    icon: Icons.route_outlined,
                    title: isDriver ? 'No driver trips yet' : 'No trips yet',
                    message: 'Accepted and completed rides will appear here.',
                    actionLabel: isDriver ? 'Go Online' : 'Book a Ride',
                    onAction: () => context.go(isDriver ? '/driver' : '/home'),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: trips.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final trip = trips[index];
                  final status = trip['status'] as String;
                  final completed = status == 'completed';
                  final driverCancelled = status == 'cancelled_by_driver';
                  final route = isDriver
                      ? '/driver'
                      : completed
                      ? '/receipt'
                      : driverCancelled
                      ? '/home'
                      : _routeFor(
                          state.activeBooking?.status ??
                              BookingStatus.searching,
                        );
                  return _TripSummary(
                    icon: completed
                        ? Icons.check_circle
                        : driverCancelled
                        ? Icons.cancel_outlined
                        : Icons.directions_run,
                    iconColor: completed
                        ? AppColors.green
                        : driverCancelled
                        ? AppColors.danger
                        : AppColors.sky,
                    title: completed
                        ? 'Completed trip'
                        : driverCancelled
                        ? 'Driver-cancelled trip'
                        : 'Active booking',
                    subtitle:
                        '${trip['pickup_label'] ?? 'Pickup'} → '
                        '${trip['destination_label'] ?? 'Destination'}',
                    buttonLabel: completed ? 'View Summary' : 'View',
                    onButtonPressed: () => context.go(route),
                  );
                },
              );
            }
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
                        : AppColors.sky,
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
                      : AppColors.sky,
                  title: booking.status == BookingStatus.completed
                      ? 'Completed trip'
                      : 'Active booking',
                  subtitle:
                      '${booking.pickupName} → ${booking.destinationName}',
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
    BookingStatus.approaching => '/booking/driver-matched',
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

class _SampleTrip {
  const _SampleTrip({
    required this.route,
    required this.type,
    required this.fare,
    required this.dateLabel,
    this.commuterName,
  });

  final String route;
  final String type; // 'Special' or 'Pooling'
  final String fare;
  final String dateLabel;
  final String? commuterName;
}

/// Illustrative sandbox history so the commuter Trips screen is not empty
/// before a real account has any Supabase-backed trips yet. Fixed demo data,
/// never a live record.
class _CommuterSampleHistory extends StatefulWidget {
  const _CommuterSampleHistory();

  @override
  State<_CommuterSampleHistory> createState() =>
      _CommuterSampleHistoryState();
}

class _CommuterSampleHistoryState extends State<_CommuterSampleHistory> {
  static const _trips = [
    _SampleTrip(
      route: 'Calamba Crossing → SM Calamba',
      type: 'Special',
      fare: '₱60.00',
      dateLabel: 'Jul 3',
    ),
    _SampleTrip(
      route: 'City Hall → Crossing Market',
      type: 'Pooling',
      fare: '₱15.00',
      dateLabel: 'Jun 28',
    ),
    _SampleTrip(
      route: 'SM Calamba → Crossing Market',
      type: 'Special',
      fare: '₱60.00',
      dateLabel: 'Jun 20',
    ),
  ];

  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final trips = _filter == 'All'
        ? _trips
        : _trips.where((trip) => trip.type == _filter).toList();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Trip history', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Latest completed trip: ${_trips.first.dateLabel}',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            for (final option in const ['All', 'Special', 'Pooling'])
              ChoiceChip(
                label: Text(option),
                selected: _filter == option,
                onSelected: (_) => setState(() => _filter = option),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (final trip in trips) ...[
          _SampleTripTile(trip: trip),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

/// Illustrative driver-side trip records; same sandbox-only scope as the
/// commuter sample history above.
class _DriverSampleHistory extends StatelessWidget {
  const _DriverSampleHistory();

  static const _trips = [
    _SampleTrip(
      route: 'Crossing Market → City Hall',
      type: 'Special',
      fare: '₱60.00',
      dateLabel: 'Jul 3',
    ),
    _SampleTrip(
      route: 'Brgy. Real → Crossing Market',
      type: 'Special',
      fare: '₱60.00',
      dateLabel: 'Jun 29',
    ),
    _SampleTrip(
      route: 'Calamba Crossing → SM Calamba',
      type: 'Pooling',
      fare: '₱15.00',
      dateLabel: 'Jun 20',
      commuterName: 'Rico C.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Trip records', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        for (final trip in _trips) ...[
          _SampleTripTile(trip: trip),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _SampleTripTile extends StatelessWidget {
  const _SampleTripTile({required this.trip});

  final _SampleTrip trip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sm),
        Text(trip.route, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          trip.commuterName == null
              ? '${trip.type} · ${trip.dateLabel}'
              : 'Commuter: ${trip.commuterName} · ${trip.type}',
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          trip.fare,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
