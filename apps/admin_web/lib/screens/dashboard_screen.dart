import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../admin_controller.dart';
import '../map_screen.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    final session = auth.value!;
    final controller = ref.read(adminProvider.notifier);
    final drivers = controller.scopedDrivers(session);
    final rides = controller.visibleRides(session);
    final reports = controller
        .visibleReports(session)
        .where(
          (report) =>
              report.status != ReportStatus.resolved &&
              report.status != ReportStatus.dismissed,
        )
        .toList();
    final pending = drivers
        .where(
          (driver) =>
              driver.status == DriverStatus.review ||
              driver.status == DriverStatus.submitted,
        )
        .toList();
    final approved = drivers
        .where((driver) => driver.status == DriverStatus.approved)
        .length;
    final audit = controller.visibleAudit(session);
    final todas = <String>{
      for (final boundary in state.boundaries)
        if (session.role == AdminRole.lgu || boundary.name == session.toda)
          boundary.name,
      for (final driver in drivers) driver.toda,
      if (session.toda != null) session.toda!,
    };
    void openReviews() {
      controller.resetViewFilters();
      controller.setDriverStatus('Needs review');
      context.go('/drivers');
    }

    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            title: 'Operations overview',
            subtitle: session.role == AdminRole.lgu
                ? 'Calamba City · Dispatch, safety, and driver verification.'
                : '${session.toda} · Your dispatch and review workspace.',
            action: TextButton.icon(
              onPressed: () => context.go('/live-map'),
              icon: const Icon(Icons.open_in_full, size: 18),
              label: const Text('Open live map'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            state.connected
                ? 'Connected operations · Records are scoped to your access.'
                : 'Demo workspace · Sample records, not live operations.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 600 ? 2 : 4;
              final metrics = [
                _Metric(
                  label: 'OPEN SAFETY REPORTS',
                  value: '${reports.length}',
                  detail: 'Review and follow up',
                  onTap: () => context.go('/safety'),
                ),
                _Metric(
                  label: 'PENDING REVIEWS',
                  value: '${pending.length}',
                  detail: 'Driver applications',
                  onTap: openReviews,
                ),
                _Metric(
                  label: 'ACTIVE RIDES',
                  value: '${rides.length}',
                  detail: 'View dispatch',
                  onTap: () => context.go('/live-map'),
                ),
                _Metric(
                  label: 'APPROVED DRIVERS',
                  value: '$approved',
                  detail: '${drivers.length} enrolled',
                  onTap: () {
                    controller.resetViewFilters();
                    controller.setDriverStatus('Approved');
                    context.go('/drivers');
                  },
                ),
              ];
              return DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
                child: Wrap(
                  children: [
                    for (final metric in metrics)
                      SizedBox(
                        width: constraints.maxWidth / columns,
                        child: metric,
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          LayoutBuilder(
            builder: (context, constraints) {
              final work = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Needs attention',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text('Start with safety, then clear the review queue.'),
                  const SizedBox(height: 16),
                  if (reports.isEmpty && pending.isEmpty)
                    const EmptyState(
                      message:
                          'You’re all caught up. New reports and applications will appear here.',
                    ),
                  if (reports.isNotEmpty) ...[
                    _WorkRow(
                      icon: Icons.shield_outlined,
                      title: '${reports.length} open safety reports',
                      detail: reports.first.summary,
                      action: 'Review reports',
                      onTap: () => context.go('/safety'),
                    ),
                    const Divider(height: 1),
                  ],
                  if (pending.isNotEmpty)
                    _WorkRow(
                      icon: Icons.fact_check_outlined,
                      title: '${pending.length} driver applications',
                      detail: pending
                          .take(3)
                          .map((driver) => driver.name)
                          .join(', '),
                      action: 'Review drivers',
                      onTap: openReviews,
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Live activity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (audit.isEmpty)
                    const EmptyState(
                      message: 'No activity in your jurisdiction yet.',
                    )
                  else
                    for (final event in audit.take(4))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(event.detail),
                            const SizedBox(height: 4),
                            Text(
                              shortTime(event.time),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                ],
              );
              final dispatch = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Live dispatch map',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text('Select a trip to inspect it on the full map.'),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: constraints.maxWidth < 900 ? 260 : 340,
                      child: DashboardMapPreview(
                        rides: rides,
                        connected: state.connected,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (rides.isEmpty)
                    const EmptyState(
                      message:
                          'No active trips. New dispatch activity will appear here.',
                    )
                  else
                    for (final ride in rides.take(4)) ...[
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        title: Text(ride.driver),
                        subtitle: Text(
                          '${ride.rider} · ${ride.toda}\n${ride.status} · Updated ${ride.updatedMinutes} min ago',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.arrow_forward, size: 18),
                        onTap: () {
                          controller.selectRide(ride.id);
                          context.go('/live-map');
                        },
                      ),
                      const Divider(height: 1),
                    ],
                ],
              );
              return constraints.maxWidth < 900
                  ? Column(
                      children: [work, const SizedBox(height: 32), dispatch],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: work),
                        const SizedBox(width: 40),
                        Expanded(flex: 6, child: dispatch),
                      ],
                    );
            },
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Terminal activity',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          for (final toda in todas)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(toda),
              subtitle: Text(
                '${drivers.where((driver) => driver.toda == toda && driver.status == DriverStatus.approved).length} approved drivers · ${rides.where((ride) => ride.toda == toda).length} active rides',
              ),
            ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Evaluation readiness'),
            subtitle: Text(
              '${todas.fold<int>(0, (total, toda) => total + (state.feedbackCounts[toda] ?? 0))} of ${todas.length * state.respondentTarget} target drivers',
            ),
            trailing: const Icon(Icons.arrow_forward, size: 18),
            onTap: () => context.go('/evaluation'),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.detail,
    required this.onTap,
  });
  final String label;
  final String value;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 4),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              TextButton(onPressed: onTap, child: Text(action)),
            ],
          ),
        ),
      ],
    ),
  );
}
