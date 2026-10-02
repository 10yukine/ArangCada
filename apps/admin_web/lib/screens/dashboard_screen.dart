import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../admin_controller.dart';
import '../map_screen.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../tricycle_icon.dart';
import '../widgets.dart';

/// The overview. On a desktop-sized window it fits the viewport exactly --
/// the map and lists scroll inside their own panels -- so the whole picture
/// is visible at a glance. Smaller windows fall back to one scrolling page.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static const _minFitWidth = 1000.0;
  static const _minFitHeight = 600.0;

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
    final cancellations = state.driverCancellations
        .where(
          (item) => session.role == AdminRole.lgu || item.toda == session.toda,
        )
        .toList();
    final cancelsByDriver = <String, List<DriverCancellation>>{};
    for (final item in cancellations) {
      (cancelsByDriver[item.driver] ??= []).add(item);
    }
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

    final theme = Theme.of(context);
    final evaluated = todas.fold<int>(
      0,
      (total, toda) => total + (state.feedbackCounts[toda] ?? 0),
    );
    final evaluationTarget = todas.length * state.respondentTarget;

    // ---------------------------------------------------------------- header
    // Phones drop the "Open live map" link: the menu already has Live map.
    Widget heading({bool phone = false}) => PageHeading(
      title: 'Operations overview',
      subtitle: session.role == AdminRole.lgu
          ? 'Calamba City · Dispatch, safety, and driver verification.'
          : '${session.toda} · Your dispatch and review workspace.',
      action: phone
          ? null
          : TextButton(
              onPressed: () => context.go('/live-map'),
              child: const Text('Open live map'),
            ),
    );
    final connection = Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: context.adminColor(
              state.connectionError != null
                  ? AdminColors.danger
                  : state.loading
                  ? AdminColors.warning
                  : AdminColors.success,
            ),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            state.connectionError ??
                (state.loading
                    ? 'Loading live records…'
                    : 'Connected operations · Records are scoped to your access.'),
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (state.connectionError != null)
          TextButton(
            onPressed: state.loading
                ? null
                // refresh() records its own failure in connectionError.
                : () => controller.refresh().catchError((_) {}),
            child: const Text('Retry'),
          ),
      ],
    );

    // --------------------------------------------------------------- metrics
    Widget metricsBand({required bool compact}) => LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 700 ? 2 : 4;
        final metrics = [
          _Metric(
            label: 'OPEN SAFETY REPORTS',
            value: '${reports.length}',
            detail: 'View reports',
            icon: const Icon(Icons.shield_outlined),
            compact: compact,
            onTap: () => context.go('/safety'),
          ),
          _Metric(
            label: 'PENDING REVIEWS',
            value: '${pending.length}',
            detail: 'Driver applications',
            icon: const Icon(Icons.fact_check_outlined),
            compact: compact,
            onTap: openReviews,
          ),
          _Metric(
            label: 'ACTIVE RIDES',
            value: '${rides.length}',
            detail: 'View dispatch',
            icon: const TricycleIcon(),
            compact: compact,
            onTap: () => context.go('/live-map'),
          ),
          _Metric(
            label: 'APPROVED DRIVERS',
            value: '$approved',
            detail: '${drivers.length} enrolled',
            icon: const Icon(Icons.verified_outlined),
            compact: compact,
            onTap: () {
              controller.resetViewFilters();
              controller.setDriverStatus('Approved');
              context.go('/drivers');
            },
          ),
        ];
        final width = (constraints.maxWidth - 14) / columns;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.adminColor(AdminColors.card),
            border: Border.all(color: context.adminColor(AdminColors.border)),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(6),
          child: Wrap(
            children: [
              for (final metric in metrics)
                SizedBox(width: width, child: metric),
            ],
          ),
        );
      },
    );

    // ------------------------------------------------------------ sections
    final attentionRows = <Widget>[
      if (reports.isEmpty && pending.isEmpty && cancellations.isEmpty)
        const EmptyState(
          message:
              'You’re all caught up. New reports and applications will appear here.',
        ),
      if (reports.isNotEmpty) ...[
        _WorkRow(
          icon: Icons.shield_outlined,
          tone: AdminColors.danger,
          title: '${reports.length} open safety reports',
          detail: reports.first.summary,
          action: 'Review reports',
          onTap: () => context.go('/safety'),
        ),
        if (pending.isNotEmpty) const Divider(height: 1),
      ],
      if (pending.isNotEmpty)
        _WorkRow(
          icon: Icons.fact_check_outlined,
          tone: AdminColors.warning,
          title: '${pending.length} driver applications',
          detail: pending.take(3).map((driver) => driver.name).join(', '),
          action: 'Review drivers',
          onTap: openReviews,
        ),
      if (cancellations.isNotEmpty) ...[
        if (reports.isNotEmpty || pending.isNotEmpty) const Divider(height: 1),
        _WorkRow(
          icon: Icons.cancel_outlined,
          tone: AdminColors.warning,
          title:
              '${cancellations.length} driver '
              '${cancellations.length == 1 ? 'cancellation' : 'cancellations'}'
              ' this week',
          detail: [
            for (final MapEntry(key: name, value: items)
                in cancelsByDriver.entries)
              '$name${items.length > 1 ? ' ×${items.length}' : ''}: '
                  '${{for (final item in items) item.reason}.join(', ')}',
          ].join('\n'),
          action: 'Open drivers',
          onTap: () {
            controller.resetViewFilters();
            context.go('/drivers');
          },
        ),
      ],
    ];
    final activityRows = <Widget>[
      if (audit.isEmpty)
        const EmptyState(message: 'No activity in your jurisdiction yet.')
      else
        for (final (index, event) in audit.take(6).indexed)
          _TimelineRow(
            title: event.title,
            detail: event.detail,
            time: shortTime(event.time),
            last: index == audit.take(6).length - 1,
          ),
    ];
    final rideRows = <Widget>[
      for (final (index, ride) in rides.take(6).indexed) ...[
        if (index > 0) const Divider(height: 1),
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.adminColor(AdminColors.primaryTint),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TricycleIcon(
              size: 19,
              color: context.adminColor(AdminColors.primary),
            ),
          ),
          title: Text(ride.driver, style: theme.textTheme.titleSmall),
          subtitle: Text(
            '${ride.rider} · ${ride.toda}\n${ride.status} · Updated ${ride.updatedMinutes} min ago',
            style: theme.textTheme.bodySmall,
          ),
          isThreeLine: true,
          onTap: () {
            controller.selectRide(ride.id);
            context.go('/live-map');
          },
        ),
      ],
    ];
    final terminalRows = <Widget>[
      for (final (index, toda) in todas.indexed) ...[
        if (index > 0) const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.location_city_outlined,
                size: 20,
                color: context.adminColor(AdminColors.muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(toda, style: theme.textTheme.titleSmall),
                    Text(
                      '${drivers.where((driver) => driver.toda == toda && driver.status == DriverStatus.approved).length} approved drivers · ${rides.where((ride) => ride.toda == toda).length} active rides',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ];
    final map = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DashboardMapPreview(rides: rides, connected: state.connected),
    );
    final evaluation = Panel(
      onTap: () => context.go('/evaluation'),
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.insights_outlined,
                color: context.adminColor(AdminColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Evaluation readiness',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.arrow_forward, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$evaluated of $evaluationTarget target drivers',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: evaluationTarget == 0
                  ? 0
                  : (evaluated / evaluationTarget).clamp(0, 1),
              minHeight: 8,
              backgroundColor: context.adminColor(AdminColors.surface),
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = constraints.maxWidth < 600 ? 16.0 : 32.0;
        final fits =
            constraints.hasBoundedHeight &&
            constraints.maxWidth - pad * 2 >= _minFitWidth &&
            constraints.maxHeight >= _minFitHeight + 48;

        if (fits) {
          return Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 24, pad, 24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1500),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading(),
                      const SizedBox(height: 10),
                      connection,
                      const SizedBox(height: 18),
                      metricsBand(compact: true),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _FillPanel(
                                      title: 'Live dispatch map',
                                      subtitle:
                                          'Select a trip to inspect it on the full map.',
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(child: map),
                                          const SizedBox(width: 14),
                                          SizedBox(
                                            width: 250,
                                            child: rides.isEmpty
                                                ? const EmptyState(
                                                    message:
                                                        'No active trips. New dispatch activity will appear here.',
                                                  )
                                                : ListView(children: rideRows),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    height: 150,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: _FillPanel(
                                            title: 'Terminal activity',
                                            child: ListView(
                                              children: terminalRows,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        SizedBox(width: 300, child: evaluation),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: _FillPanel(
                                      title: 'Needs attention',
                                      subtitle:
                                          'Start with safety, then clear the review queue.',
                                      child: ListView(children: attentionRows),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Expanded(
                                    flex: 5,
                                    child: _FillPanel(
                                      title: 'Live activity',
                                      child: ListView(children: activityRows),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // ---------------------------------------------- scrolling fallback
        final narrow = constraints.maxWidth < 980;
        final phone = constraints.maxWidth < 600;
        final dispatch = Panel(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                'Live dispatch map',
                'Select a trip to inspect it on the full map.',
              ),
              const SizedBox(height: 14),
              SizedBox(height: narrow ? 260 : 340, child: map),
              const SizedBox(height: 8),
              if (rides.isEmpty)
                const EmptyState(
                  message:
                      'No active trips. New dispatch activity will appear here.',
                )
              else
                ...rideRows,
            ],
          ),
        );
        Widget listPanel(String title, String? subtitle, List<Widget> rows) =>
            Panel(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(title, subtitle),
                  const SizedBox(height: 6),
                  ...rows,
                ],
              ),
            );
        final work = Column(
          children: [
            listPanel(
              'Needs attention',
              'Start with safety, then clear the review queue.',
              attentionRows,
            ),
            const SizedBox(height: 16),
            listPanel('Live activity', null, activityRows),
          ],
        );
        return Material(
          type: MaterialType.transparency,
          child: ConsoleScrollView(
            padding: EdgeInsets.fromLTRB(pad, 24, pad, 40),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1500),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading(phone: phone),
                    // On a phone the healthy "Connected" line is noise; only
                    // loading or a connection problem is worth the space.
                    if (!phone ||
                        state.loading ||
                        state.connectionError != null) ...[
                      const SizedBox(height: 10),
                      connection,
                    ],
                    const SizedBox(height: 18),
                    // Phones lead with what needs action; the owner found it
                    // several screens down, below the stats and the map.
                    if (phone) ...[
                      listPanel(
                        'Needs attention',
                        'Start with safety, then clear the review queue.',
                        attentionRows,
                      ),
                      const SizedBox(height: 16),
                    ],
                    metricsBand(compact: phone),
                    const SizedBox(height: 16),
                    if (phone) ...[
                      dispatch,
                      const SizedBox(height: 16),
                      listPanel('Live activity', null, activityRows),
                    ] else if (narrow) ...[
                      dispatch,
                      const SizedBox(height: 16),
                      work,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: dispatch),
                          const SizedBox(width: 16),
                          Expanded(flex: 4, child: work),
                        ],
                      ),
                    const SizedBox(height: 16),
                    listPanel('Terminal activity', null, terminalRows),
                    const SizedBox(height: 16),
                    evaluation,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A panel whose body takes the remaining height and scrolls internally.
class _FillPanel extends StatelessWidget {
  const _FillPanel({required this.title, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title, subtitle),
        const SizedBox(height: 10),
        Expanded(child: child),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.subtitle);
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      if (subtitle != null) ...[
        const SizedBox(height: 2),
        Text(
          subtitle!,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.adminColor(AdminColors.muted),
          ),
        ),
      ],
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.compact,
    required this.onTap,
  });
  final String label;
  final String value;
  final String detail;
  final Widget icon;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      hoverColor: context
          .adminColor(AdminColors.primary)
          .withValues(alpha: .08),
      splashColor: context
          .adminColor(AdminColors.primary)
          .withValues(alpha: .12),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.adminColor(AdminColors.muted),
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                IconTheme(
                  data: IconThemeData(
                    size: 18,
                    color: context.adminColor(AdminColors.primary),
                  ),
                  child: icon,
                ),
              ],
            ),
            SizedBox(height: compact ? 8 : 14),
            Text(
              value,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: context.adminColor(AdminColors.ink),
                fontSize: compact ? 36 : 44,
                height: 1,
              ),
            ),
            SizedBox(height: compact ? 6 : 8),
            Row(
              children: [
                Flexible(
                  child: Text(
                    detail,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.adminColor(AdminColors.muted),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: context.adminColor(AdminColors.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.detail,
    required this.action,
    required this.onTap,
  });
  final IconData icon;
  final Color tone;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.adminColor(tone).withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: context.adminColor(tone)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.adminColor(AdminColors.muted),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  minimumSize: const Size(48, 40),
                ),
                child: Text(action),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.title,
    required this.detail,
    required this.time,
    required this.last,
  });
  final String title;
  final String detail;
  final String time;
  final bool last;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 20,
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.adminColor(AdminColors.primary),
                    width: 2.5,
                  ),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.only(top: 4),
                    color: context.adminColor(AdminColors.border),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.adminColor(AdminColors.body),
                  ),
                ),
                const SizedBox(height: 4),
                Text(time, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
