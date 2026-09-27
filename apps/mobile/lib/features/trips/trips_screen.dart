import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/dashboard_back_button.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/report_issue_sheet.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/mock/demo_state.dart';
import '../../data/remote/supabase_ride_repository.dart';
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
    final liveRides = ref.watch(liveRideRepositoryProvider);
    final isDriver = state.currentUser?.role == DemoRole.driver;
    return Scaffold(
      appBar: AppBar(
        leading: DashboardBackButton(isDriver: isDriver),
        title: const Text('Trips'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([state, liveRides]),
          builder: (context, _) {
            // Illustrative sandbox history for the pre-connection demo only.
            // Once a real Supabase session is live, actual trip records
            // always win -- this branch never runs when liveRides != null.
            if (liveRides == null &&
                !isDriver &&
                state.currentUser?.isDemoAccount == true &&
                state.sampleContentEnabled) {
              return const _CommuterSampleHistory();
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
                    actionLabel: isDriver
                        ? state.driverTrip.isOnline
                              ? 'Open driver dashboard'
                              : 'Go Online'
                        : 'Book a Ride',
                    onAction: () => isDriver
                        ? _openDriverDashboard(context, state, liveRides)
                        : context.go('/home'),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                itemCount: trips.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 66),
                itemBuilder: (context, index) {
                  final trip = trips[index];
                  final status = trip['status'] as String;
                  final completed = status == 'completed';
                  final driverCancelled = status == 'cancelled_by_driver';
                  final rawFare = trip['final_fare'] ?? trip['fare_estimate'];
                  final when = DateTime.tryParse(
                    (trip['completed_at'] ?? trip['requested_at'])
                            as String? ??
                        '',
                  )?.toLocal();
                  final route = isDriver
                      ? '/driver'
                      : completed
                      ? Uri(
                          path: '/receipt',
                          queryParameters: {'trip': trip['id'] as String},
                        ).toString()
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
                        : AppColors.primary,
                    // Pickup is the rider's GPS spot, so the drop-off is the
                    // name that tells trips apart.
                    title:
                        trip['destination_label'] as String? ?? 'Destination',
                    subtitle: [
                      completed
                          ? 'Completed'
                          : driverCancelled
                          ? 'Cancelled by driver'
                          : 'In progress',
                      if (when != null)
                        DateFormat('MMM d · h:mm a').format(when),
                    ].join(' · '),
                    // Only a completed trip was actually paid.
                    amount: completed && rawFare is num
                        ? formatCentavos((rawFare * 100).round())
                        : null,
                    buttonLabel: completed ? 'View summary' : 'Open trip',
                    onButtonPressed: () {
                      if (isDriver && completed) {
                        final rawPesos =
                            trip['final_fare'] ?? trip['fare_estimate'];
                        final fare = rawPesos is num
                            ? formatCentavos((rawPesos * 100).round())
                            : 'Unavailable';
                        _showDriverTripSummarySheet(
                          context,
                          ref,
                          tripId: trip['id'] as String,
                          route:
                              '${trip['pickup_label'] ?? 'Pickup'} → '
                              '${trip['destination_label'] ?? 'Destination'}',
                          passengerName:
                              trip['passenger_name'] as String? ?? 'Passenger',
                          fare: fare,
                          reference:
                              trip['receipt_ref'] as String? ??
                              trip['id'] as String?,
                        );
                      } else {
                        context.go(route);
                      }
                    },
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
              if (!hasRide ||
                  (status == DriverTripStatus.completed &&
                      state.activeBooking == null)) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: EmptyStateCard(
                    icon: Icons.route_outlined,
                    title: 'No driver trips yet',
                    message: 'Accepted and completed rides will appear here.',
                    actionLabel: state.driverTrip.isOnline
                        ? 'Open driver dashboard'
                        : 'Go Online',
                    onAction: () => _openDriverDashboard(context, state, null),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                children: [
                  _TripSummary(
                    icon: status == DriverTripStatus.completed
                        ? Icons.check_circle
                        : Icons.directions_run,
                    iconColor: status == DriverTripStatus.completed
                        ? AppColors.green
                        : AppColors.primary,
                    title: state.destination?.name ?? 'Destination',
                    subtitle:
                        '${status == DriverTripStatus.completed ? 'Completed' : 'In progress'}'
                        ' · ${state.liveCommuterName ?? 'Passenger'}',
                    buttonLabel: status == DriverTripStatus.completed
                        ? 'View summary'
                        : 'Resume trip',
                    onButtonPressed: () {
                      if (status == DriverTripStatus.completed) {
                        _showDriverTripSummarySheet(
                          context,
                          ref,
                          route:
                              '${state.pickup.name} → ${state.destination?.name ?? 'Destination'}',
                          passengerName: state.liveCommuterName ?? 'Passenger',
                          fare: state.activeBooking == null
                              ? 'Unavailable'
                              : formatCentavos(
                                  state
                                      .activeBooking!
                                      .fareQuote
                                      .partyTotalCentavos,
                                ),
                        );
                      } else {
                        context.go('/driver');
                      }
                    },
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
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              children: [
                _TripSummary(
                  icon: booking.status == BookingStatus.completed
                      ? Icons.check_circle
                      : Icons.directions_run,
                  iconColor: booking.status == BookingStatus.completed
                      ? AppColors.green
                      : AppColors.primary,
                  title: booking.destinationName,
                  subtitle: booking.status == BookingStatus.completed
                      ? 'Completed'
                      : 'In progress',
                  amount: formatCentavos(
                    booking.fareQuote.partyTotalCentavos,
                  ),
                  buttonLabel: booking.status == BookingStatus.completed
                      ? 'View receipt'
                      : 'Resume trip',
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

Future<void> _openDriverDashboard(
  BuildContext context,
  DemoState state,
  SupabaseRideRepository? liveRides,
) async {
  if (liveRides == null && state.currentUser?.isDemoAccount != true) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Live driver connection unavailable.')),
    );
    return;
  }
  if (!state.driverTrip.isOnline) {
    try {
      if (liveRides != null) {
        await liveRides.setDriverOnline(true);
      } else {
        if (state.driverTrip.status == DriverTripStatus.declined) {
          state.driverTrip.goOffline();
        }
        state.driverTrip.goOnline();
        state.driverChanged();
      }
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not go online. Check driver approval, required feedback, '
              'GPS, and connection.',
            ),
          ),
        );
      }
      return;
    }
  }
  if (context.mounted) context.go('/driver');
}

/// One trip in the history: route, status and date, fare, and a chevron.
/// The whole row opens the trip; [buttonLabel] names that action for screen
/// readers instead of drawing a full-width button per trip.
class _TripSummary extends StatelessWidget {
  const _TripSummary({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onButtonPressed,
    this.amount,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onButtonPressed;
  final String? amount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $subtitle${amount == null ? '' : ', $amount'}. '
          '$buttonLabel',
      excludeSemantics: true,
      child: InkWell(
        onTap: onButtonPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: AppSizes.rowIcon,
                height: AppSizes.rowIcon,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTypography.caption),
                  ],
                ),
              ),
              if (amount != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  amount!,
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.xxs),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleTrip {
  const _SampleTrip({
    required this.route,
    required this.type,
    required this.fare,
    required this.dateLabel,
  });

  final String route;
  final String type; // 'Special' or 'Pooling'
  final String fare;
  final String dateLabel;
}

/// Illustrative sandbox history so the commuter Trips screen is not empty
/// before a real account has any Supabase-backed trips yet. Fixed demo data,
/// never a live record.
class _CommuterSampleHistory extends StatefulWidget {
  const _CommuterSampleHistory();

  @override
  State<_CommuterSampleHistory> createState() => _CommuterSampleHistoryState();
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
        Text('${trip.type} · ${trip.dateLabel}'),
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

void _showDriverTripSummarySheet(
  BuildContext context,
  WidgetRef ref, {
  required String route,
  required String passengerName,
  required String fare,
  String? reference,
  String? date,
  String? tripId,
}) {
  final rides = ref.read(liveRideRepositoryProvider);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.green,
                  size: 28,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Trip summary',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              child: Column(
                children: [
                  _SummaryRow(label: 'Passenger', value: passengerName),
                  _SummaryRow(label: 'Route', value: route),
                  if (date != null) _SummaryRow(label: 'Date', value: date),
                  if (reference != null)
                    _SummaryRow(label: 'Reference', value: reference),
                  const Divider(height: AppSpacing.lg),
                  _SummaryRow(
                    label: 'Fare collected',
                    value: fare,
                    emphasize: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
              ),
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Close'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  showReportIssueFlow(
                    context: context,
                    driver: true,
                    onSubmit: tripId == null || rides == null
                        ? null
                        : (category, description) => rides.createComplaint(
                            tripId,
                            category,
                            description,
                          ),
                  );
                },
                child: const Text('Report an issue with this trip'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: emphasize
                  ? Theme.of(context).textTheme.headlineSmall
                  : Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}
