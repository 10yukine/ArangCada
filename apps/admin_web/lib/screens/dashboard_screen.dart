import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../admin_controller.dart';
import '../map_screen.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shared_widgets.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    final session = auth.value!;
    final controller = ref.read(adminProvider.notifier);
    final drivers = controller.scopedDrivers(session);
    final rides = controller.visibleRides(session);
    final reports = controller.visibleReports(session);
    final audit = controller.visibleAudit(session);
    final todas = <String>{
      for (final boundary in state.boundaries)
        if (session.role == AdminRole.lgu || boundary.name == session.toda)
          boundary.name,
      for (final item in state.feedbackSummaries)
        if (session.role == AdminRole.lgu || item.toda == session.toda)
          item.toda,
      for (final driver in drivers) driver.toda,
      if (session.toda != null) session.toda!,
    }.toList();
    final approved = drivers
        .where((driver) => driver.status == DriverStatus.approved)
        .length;
    final pending = drivers
        .where(
          (driver) =>
              driver.status == DriverStatus.review ||
              driver.status == DriverStatus.submitted,
        )
        .length;
    final feedbackParticipants = todas.fold<int>(
      0,
      (total, toda) => total + (state.feedbackCounts[toda] ?? 0),
    );
    final participantTarget = todas.length * state.respondentTarget;
    final readyDrivers = approved + pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          title: 'Good morning, evaluator',
          subtitle:
              'A local snapshot of dispatch activity and governance readiness.',
        ),
        const SizedBox(height: 24),
        ResponsiveGrid(
          children: [
            MetricCard(
              label: 'Approved drivers',
              value: '$approved',
              detail: '${drivers.length} enrolled',
              icon: Icons.verified_user_outlined,
              tone: AdminColors.success,
              onTap: () {
                controller.resetViewFilters();
                controller.setDriverStatus('Approved');
                context.go('/drivers');
              },
            ),
            MetricCard(
              label: 'Active rides',
              value: '${rides.length}',
              detail: state.connected
                  ? 'Updated in real time'
                  : 'Local demo data',
              icon: Icons.location_on_outlined,
              onTap: () => context.go('/live-map'),
            ),
            MetricCard(
              label: 'Pending reviews',
              value: '$pending',
              detail: 'Needs action',
              icon: Icons.hourglass_top_outlined,
              tone: AdminColors.warning,
              onTap: () {
                controller.resetViewFilters();
                controller.setDriverStatus('Needs review');
                context.go('/drivers');
              },
            ),
            MetricCard(
              label: 'Open safety reports',
              value:
                  '${reports.where((report) => report.status != ReportStatus.resolved && report.status != ReportStatus.dismissed).length}',
              detail: '${reports.length} total',
              icon: Icons.shield_outlined,
              tone: AdminColors.danger,
              onTap: () => context.go('/safety'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 900;
            final dispatch = Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Live dispatch map',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => context.go('/live-map'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                        ),
                        icon: const Icon(Icons.arrow_forward, size: 17),
                        iconAlignment: IconAlignment.end,
                        label: const Text('Open live map'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: stack ? 240 : 280,
                      child: DashboardMapPreview(
                        rides: rides,
                        connected: state.connected,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    state.connected
                        ? 'Pan or zoom to inspect live trip and driver GPS positions in your jurisdiction.'
                        : 'Pan or zoom to inspect synthetic positions; prototype boundaries remain on the full map.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
            final hourly = Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Rides per hour · today',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      StatusPill(
                        state.connected ? 'Connected data' : 'Illustrative',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.connected)
                    const EmptyState(
                      message:
                          'Hourly trip-history aggregation has not yet been collected.',
                    )
                  else
                    _HourlyRideChart(activeRides: rides.length),
                  const SizedBox(height: 10),
                  Text(
                    state.connected
                        ? 'No estimated or synthetic ride totals are shown.'
                        : 'Example activity only; not collected trip history.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
            final activity = Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Live activity',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusPill(
                        state.connected
                            ? 'Connected operations'
                            : 'Local event log',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (audit.isEmpty)
                    const EmptyState(message: 'No activity in this TODA yet.')
                  else
                    for (final event in audit.take(5)) _AuditRow(event),
                ],
              ),
            );
            final terminals = Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Terminal activity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  for (final toda in todas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _TerminalActivityRow(
                        toda: toda,
                        approved: drivers
                            .where(
                              (driver) =>
                                  driver.toda == toda &&
                                  driver.status == DriverStatus.approved,
                            )
                            .length,
                        rides: rides.where((ride) => ride.toda == toda).length,
                        enrolled: drivers
                            .where((driver) => driver.toda == toda)
                            .length,
                      ),
                    ),
                  Text(
                    state.connected
                        ? 'Server-scoped live driver and dispatch records.'
                        : 'Scoped local records; terminal queue order is not simulated.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
            final readiness = Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Evaluation readiness',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 18),
                  if (!state.connected) ...[
                    const ProgressRow(
                      label: 'Feature scenarios',
                      value: .82,
                      caption: '9 of 11 checks prepared',
                    ),
                    const SizedBox(height: 18),
                  ],
                  ProgressRow(
                    label: 'Unique driver app-feedback participants',
                    value: participantTarget == 0
                        ? 0
                        : (feedbackParticipants / participantTarget).clamp(
                            0,
                            1,
                          ),
                    caption:
                        '$feedbackParticipants of $participantTarget target drivers',
                  ),
                  const SizedBox(height: 18),
                  ProgressRow(
                    label: 'Driver verification',
                    value: drivers.isEmpty
                        ? 0
                        : (readyDrivers / drivers.length).clamp(0, 1),
                    caption:
                        '$readyDrivers of ${drivers.length} records review-ready',
                  ),
                  const SizedBox(height: 18),
                  Text(
                    state.connected
                        ? 'Participation is counted by unique drivers; repeat feedback does not inflate readiness.'
                        : 'Prototype metrics support the capstone evaluation and do not represent production operations.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
            final primary = Column(
              children: [dispatch, const SizedBox(height: 16), hourly],
            );
            final secondary = Column(
              children: [
                activity,
                const SizedBox(height: 16),
                terminals,
                const SizedBox(height: 16),
                readiness,
              ],
            );
            return stack
                ? Column(
                    children: [primary, const SizedBox(height: 16), secondary],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: primary),
                      const SizedBox(width: 16),
                      Expanded(child: secondary),
                    ],
                  );
          },
        ),
      ],
    );
  }
}

class _HourlyRideChart extends StatelessWidget {
  const _HourlyRideChart({required this.activeRides});

  final int activeRides;

  @override
  Widget build(BuildContext context) {
    const hours = ['6a', '7a', '8a', '9a', '10a', '11a', '12p', '1p'];
    const profile = [.4, .7, 1.0, .75, .55, 1.2, .85, .65];
    final values = [
      for (final factor in profile)
        activeRides == 0
            ? 0
            : (activeRides * factor).round().clamp(1, 99).toInt(),
    ];
    final maximum = values.fold<int>(
      1,
      (largest, value) => value > largest ? value : largest,
    );

    return Semantics(
      label: 'Illustrative hourly ride activity; not collected trip history',
      child: SizedBox(
        height: 132,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final entry in values.indexed)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: entry.$1 == 0 ? 0 : 8),
                  child: Tooltip(
                    message:
                        '${hours[entry.$1]} · ${entry.$2} illustrative rides',
                    child: Column(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: (entry.$2 / maximum).clamp(.06, 1),
                              widthFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: entry.$2 == maximum
                                      ? AdminColors.primary
                                      : AdminColors.primaryTint,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6),
                                    bottom: Radius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          hours[entry.$1],
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TerminalActivityRow extends StatelessWidget {
  const _TerminalActivityRow({
    required this.toda,
    required this.approved,
    required this.rides,
    required this.enrolled,
  });

  final String toda;
  final int approved;
  final int rides;
  final int enrolled;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$toda, $approved approved drivers, $rides active rides',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                toda,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$approved approved · $rides active',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: enrolled == 0 ? 0 : (rides / enrolled).clamp(0, 1),
            minHeight: 7,
            color: AdminColors.primary,
            backgroundColor: AdminColors.surface,
          ),
        ),
      ],
    ),
  );
}

class _AuditRow extends StatelessWidget {
  const _AuditRow(this.event);
  final AuditEvent event;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(top: 5),
          decoration: const BoxDecoration(
            color: AdminColors.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.title, style: Theme.of(context).textTheme.titleMedium),
              Text(event.detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Text(
          shortTime(event.time),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
