export 'map_screen.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'admin_controller.dart';
import 'map_screen.dart';
import 'models.dart';
import 'session.dart';
import 'theme.dart';
import 'widgets.dart';

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
        _ResponsiveGrid(
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
                    const _ProgressRow(
                      label: 'Feature scenarios',
                      value: .82,
                      caption: '9 of 11 checks prepared',
                    ),
                    const SizedBox(height: 18),
                  ],
                  _ProgressRow(
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
                  _ProgressRow(
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

class DriversScreen extends ConsumerWidget {
  const DriversScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    final controller = ref.read(adminProvider.notifier);
    final drivers = controller.visibleDrivers(auth.value!);
    const statuses = [
      'All statuses',
      'Needs review',
      'Enrolled',
      'Documents submitted',
      'Under review',
      'Approved',
      'Rejected',
      'Suspended',
      'Expired',
    ];
    final todas = [
      'All TODAs',
      ...{
        for (final driver in controller.scopedDrivers(auth.value!)) driver.toda,
        for (final boundary in state.boundaries)
          if (auth.value!.role == AdminRole.lgu ||
              boundary.name == auth.value!.toda)
            boundary.name,
      },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          title: 'Driver verification',
          subtitle:
              'Enroll drivers, review submitted records, and preserve an auditable lifecycle.',
          // LGU-initiated enrollment (Spec 20) -- the LGU inputs the
          // driver's email; the flow itself decides whether that email
          // gets an invite or promotes an existing account. Replaces the
          // old passive "Applications submitted in the driver app" pill,
          // which encoded the wrong model: nothing in this app has ever
          // let a driver self-apply.
          action: !state.connected
              ? FilledButton.icon(
                  onPressed: () => _showEnrollment(context, ref),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Enroll driver'),
                )
              : auth.value!.role == AdminRole.lgu
              ? FilledButton.icon(
                  onPressed: () => _showDriverEnrollment(
                    context,
                    ref,
                    state.todaZoneOptions,
                  ),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Enroll driver'),
                )
              : const StatusPill('Enrollment is managed by an LGU administrator'),
        ),
        const SizedBox(height: 22),
        if (state.connected && auth.value!.role == AdminRole.lgu) ...[
          const _PendingDriverInvitesPanel(),
          const SizedBox(height: 18),
        ],
        Panel(
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final fields = [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        onChanged: controller.setDriverQuery,
                        decoration: const InputDecoration(
                          labelText: 'Search drivers',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: DropdownButtonFormField<String>(
                        initialValue: state.driverStatus,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [
                          for (final item in statuses)
                            DropdownMenuItem(
                              value: item,
                              child: Text(
                                item,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            controller.setDriverStatus(value!),
                      ),
                    ),
                    if (auth.value!.role == AdminRole.lgu)
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: state.driverToda,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'TODA'),
                          items: [
                            for (final item in todas)
                              DropdownMenuItem(
                                value: item,
                                child: Text(
                                  item,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              controller.setDriverToda(value!),
                        ),
                      ),
                  ];
                  return Wrap(spacing: 12, runSpacing: 12, children: fields);
                },
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              if (drivers.isEmpty)
                const EmptyState(message: 'No drivers match these filters.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 28,
                    dataRowMinHeight: state.compactDensity ? 48 : 60,
                    dataRowMaxHeight: state.compactDensity ? 48 : 60,
                    columns: const [
                      DataColumn(label: Text('Driver')),
                      DataColumn(label: Text('TODA')),
                      DataColumn(label: Text('Plate')),
                      DataColumn(label: Text('Documents')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Action')),
                    ],
                    rows: [
                      for (final driver in drivers)
                        DataRow(
                          cells: [
                            DataCell(
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    driver.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    driver.enrollmentCode,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            DataCell(Text(driver.toda)),
                            DataCell(Text(driver.plate)),
                            DataCell(Text('${driver.documents}/4')),
                            DataCell(
                              StatusPill(
                                driverStatusLabel(driver.status),
                                tone: driverTone(driver.status),
                              ),
                            ),
                            DataCell(
                              OutlinedButton(
                                onPressed: () =>
                                    _showDriver(context, ref, driver),
                                child: const Text('Review'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lifecycle guide',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill('Enrolled'),
                  Text('→'),
                  StatusPill('Documents submitted', tone: StatusTone.warning),
                  Text('→'),
                  StatusPill('Under review', tone: StatusTone.warning),
                  Text('→'),
                  StatusPill('Approved', tone: StatusTone.success),
                  Text('or'),
                  StatusPill(
                    'Rejected / suspended / expired',
                    tone: StatusTone.danger,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SafetyScreen extends ConsumerStatefulWidget {
  const SafetyScreen({super.key});
  @override
  ConsumerState<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends ConsumerState<SafetyScreen> {
  String? selected;
  Timer? reportedChatPoll;
  bool refreshingChats = false;
  String? chatRefreshError;

  @override
  void initState() {
    super.initState();
    final session = auth.value;
    if (session?.role == AdminRole.lgu && (session?.connected ?? false)) {
      reportedChatPoll = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_refreshReportedChats()),
      );
    }
  }

  @override
  void dispose() {
    reportedChatPoll?.cancel();
    super.dispose();
  }

  Future<void> _refreshReportedChats() async {
    final session = auth.value;
    if (!mounted ||
        refreshingChats ||
        session?.role != AdminRole.lgu ||
        !(session?.connected ?? false)) {
      return;
    }
    setState(() => refreshingChats = true);
    try {
      await ref.read(adminProvider.notifier).refreshReportedChats(session!);
      if (mounted && chatRefreshError != null) {
        setState(() => chatRefreshError = null);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => chatRefreshError =
              'Reported conversations could not be refreshed.',
        );
      }
    } finally {
      if (mounted) setState(() => refreshingChats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);
    final session = auth.value!;
    final reports = ref.read(adminProvider.notifier).visibleReports(session);
    final complaints = ref
        .read(adminProvider.notifier)
        .visibleComplaints(session);
    final reportedChats = ref
        .read(adminProvider.notifier)
        .visibleReportedChats(session);
    if (reports.isNotEmpty && !reports.any((report) => report.id == selected)) {
      selected = reports.first.id;
    }
    final active = reports.where((report) => report.id == selected).firstOrNull;
    final list = Panel(
      padding: const EdgeInsets.all(10),
      child: reports.isEmpty
          ? const EmptyState(message: 'No safety reports in this scope.')
          : Column(
              children: [
                for (final report in reports)
                  _ReportTile(
                    report: report,
                    selected: report.id == selected,
                    onTap: () => setState(() => selected = report.id),
                  ),
              ],
            ),
    );
    final detail = active == null
        ? const Panel(child: EmptyState(message: 'Select a report.'))
        : _SafetyDetail(active);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          title: 'Safety reports',
          subtitle:
              'Review, acknowledge, investigate, and document responses without implying emergency-service dispatch.',
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 950
              ? Column(children: [list, const SizedBox(height: 14), detail])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 380, child: list),
                    const SizedBox(width: 16),
                    Expanded(child: detail),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        // Its own nav tab felt like too much weight for a non-emergency
        // channel -- owner's call, folded in here as a compact secondary
        // panel instead. Visible to both LGU and TODA (visibleComplaints()
        // already scopes it, same as the reports above) -- unlike reported
        // conversations, which stays LGU-only just below.
        _ComplaintsSection(complaints: complaints),
        if (session.role == AdminRole.lgu) ...[
          const SizedBox(height: 18),
          _ReportedConversationSection(
            reportedChats: reportedChats,
            connected: state.connected,
            refreshing: refreshingChats,
            refreshError: chatRefreshError,
            onRefresh: _refreshReportedChats,
          ),
        ],
      ],
    );
  }
}

class _ReportedConversationSection extends StatelessWidget {
  const _ReportedConversationSection({
    required this.reportedChats,
    required this.connected,
    required this.refreshing,
    required this.refreshError,
    required this.onRefresh,
  });

  final List<ReportedTripChat> reportedChats;
  final bool connected;
  final bool refreshing;
  final String? refreshError;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 10,
          children: [
            Text(
              'Reported conversations · LGU only',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            OutlinedButton.icon(
              onPressed: connected && !refreshing ? onRefresh : null,
              icon: refreshing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(refreshing ? 'Refreshing…' : 'Refresh reports'),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          'Only conversations explicitly reported and shared with participant consent are visible. Ordinary trip messages remain private.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (refreshError != null) ...[
          const SizedBox(height: 9),
          Text(
            refreshError!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AdminColors.danger),
          ),
        ],
        const SizedBox(height: 16),
        if (reportedChats.isEmpty)
          const EmptyState(message: 'No consented conversation reports.')
        else
          for (final report in reportedChats)
            _ReportedConversationCard(report: report),
      ],
    ),
  );
}

class _ReportedConversationCard extends StatelessWidget {
  const _ReportedConversationCard({required this.report});

  final ReportedTripChat report;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: AdminColors.border),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(report.reason, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        Text(
          'Reported by ${report.reporterName} · ${report.toda} · consent confirmed ${shortTime(report.consentedAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (report.messages.isEmpty)
          const Text('The reported conversation contained no saved messages.')
        else
          for (final message in report.messages)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${message.senderRole} · ${message.senderName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(message.body),
                  if (message.createdAt != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      shortTime(message.createdAt!),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
      ],
    ),
  );
}

class EvaluationScreen extends ConsumerStatefulWidget {
  const EvaluationScreen({super.key});
  @override
  ConsumerState<EvaluationScreen> createState() => _EvaluationScreenState();
}

class _EvaluationScreenState extends ConsumerState<EvaluationScreen> {
  final checks = <int>{};
  static const criteria = [
    ('Functional suitability', .88, 'Core dispatch and governance scenarios'),
    ('Performance efficiency', .76, 'Observed response and rendering behavior'),
    ('Interaction capability', .84, 'Task clarity and accessibility checks'),
    ('Reliability', .72, 'Recovery and state consistency scenarios'),
    ('Security', .79, 'Role scope and trusted-operation boundaries'),
    ('Safety', .81, 'Safety reporting and response traceability'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);
    final session = auth.value!;
    final summaries = _visibleFeedbackSummaries(state, session);
    final responses = [
      for (final response in state.feedbackResponses)
        if (session.role == AdminRole.lgu || response.toda == session.toda)
          response,
    ];
    final responseCount = summaries.fold<int>(
      0,
      (total, summary) => total + summary.responseCount,
    );
    final uniqueDrivers = summaries.fold<int>(
      0,
      (total, summary) => total + summary.uniqueDrivers,
    );
    final target = summaries.length * state.respondentTarget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          title: 'Driver feedback and evaluation',
          subtitle:
              'Driver app-usage feedback and formal ISO/IEC 25010 quality assessment are separate, clearly labeled study instruments.',
        ),
        const SizedBox(height: 22),
        Text(
          'Driver App Feedback · Objective 4',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Required after every ${state.feedbackInterval} completed trip${state.feedbackInterval == 1 ? '' : 's'} · anonymous unless the driver chooses to share their name.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        _ResponsiveGrid(
          children: [
            MetricCard(
              label: 'Feedback responses',
              value: '$responseCount',
              detail: 'Repeat submissions are counted separately',
              icon: Icons.rate_review_outlined,
            ),
            MetricCard(
              label: 'Unique drivers',
              value: '$uniqueDrivers',
              detail: 'Distinct participants in your scope',
              icon: Icons.groups_outlined,
              tone: AdminColors.success,
            ),
            MetricCard(
              label: 'Participation target',
              value: '$target',
              detail: '${state.respondentTarget} unique drivers per TODA',
              icon: Icons.flag_outlined,
              tone: AdminColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 18),
        SelectionArea(
          child: _DriverFeedbackSection(
            summaries: summaries,
            responses: responses,
            connected: state.connected,
            interval: state.feedbackInterval,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'ISO/IEC 25010:2023 · Objective 3',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Formal evaluator assessment and comparison against traditional manual dispatch; these are not driver feedback scores.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final results = Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Evaluation results',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      StatusPill(
                        state.connected
                            ? 'Awaiting evaluator measurements'
                            : 'Illustrative demo scores',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  for (final item in criteria)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 17),
                      child: state.connected
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.$1,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ),
                                    const StatusPill('Not yet measured'),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  item.$3,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            )
                          : _ProgressRow(
                              label: item.$1,
                              value: item.$2,
                              caption: item.$3,
                            ),
                    ),
                ],
              ),
            );
            final scenarios = Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Test scenario checklist',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  for (final entry in const [
                    'Request and assign a ride',
                    'Contain dispatch inside TODA scope',
                    'Review and approve a driver',
                    'Submit and respond to a safety report',
                    'Recover after refreshing a routed view',
                  ].indexed)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: checks.contains(entry.$1),
                      onChanged: (value) => setState(
                        () => value == true
                            ? checks.add(entry.$1)
                            : checks.remove(entry.$1),
                      ),
                      title: Text(entry.$2),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  const Divider(),
                  Text(
                    '${checks.length} of 5 scenarios checked',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
            return constraints.maxWidth < 940
                ? Column(
                    children: [results, const SizedBox(height: 16), scenarios],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: results),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: scenarios),
                    ],
                  );
          },
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manual baseline comparison',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              const _ComparisonRow(
                'Dispatch visibility',
                'Radio / terminal inquiry',
                'Shared status board',
              ),
              const _ComparisonRow(
                'Driver verification',
                'Paper record lookup',
                'Lifecycle and audit history',
              ),
              const _ComparisonRow(
                'Safety response trace',
                'Separate written log',
                'Report status and notes',
              ),
              const SizedBox(height: 8),
              Text(
                state.connected
                    ? 'Comparison dimensions are a study framework; formal evaluation results have not been collected.'
                    : 'Displayed demo scores are illustrative and must not be cited as study findings.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<TodaFeedbackSummary> _visibleFeedbackSummaries(
    AdminState state,
    AdminSession session,
  ) {
    if (state.feedbackSummaries.isNotEmpty) {
      return [
        for (final summary in state.feedbackSummaries)
          if (session.role == AdminRole.lgu || summary.toda == session.toda)
            summary,
      ];
    }
    final names = <String>{
      ...state.feedbackCounts.keys,
      for (final driver in state.drivers) driver.toda,
      if (session.toda != null) session.toda!,
    };
    return [
      for (final name in names)
        if (session.role == AdminRole.lgu || name == session.toda)
          TodaFeedbackSummary(
            toda: name,
            responseCount: state.feedbackCounts[name] ?? 0,
            uniqueDrivers: state.feedbackCounts[name] ?? 0,
            target: state.respondentTarget,
          ),
    ];
  }
}

class _DriverFeedbackSection extends StatelessWidget {
  const _DriverFeedbackSection({
    required this.summaries,
    required this.responses,
    required this.connected,
    required this.interval,
  });

  final List<TodaFeedbackSummary> summaries;
  final List<DriverAppFeedback> responses;
  final bool connected;
  final int interval;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final progress = Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unique-driver participation by TODA',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              if (summaries.isEmpty)
                const EmptyState(
                  message:
                      'No drivers or app-feedback responses are available yet.',
                )
              else
                for (final item in summaries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _ProgressRow(
                      label: item.toda,
                      value: item.progress,
                      caption:
                          '${item.uniqueDrivers} of ${item.target} unique drivers · ${item.responseCount} total response${item.responseCount == 1 ? '' : 's'}',
                    ),
                  ),
              Text(
                'The app requires feedback after $interval completed trip${interval == 1 ? '' : 's'}. Repeat responses never inflate the unique-driver threshold.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (!connected) ...[
                const SizedBox(height: 10),
                const StatusPill('Local illustrative participant counts'),
              ],
            ],
          ),
        );
        final scores = Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Driver app-usage Likert results',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Five-point scale · only submitted driver responses',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 15),
              for (final entry in feedbackQuestionLabels.entries)
                _FeedbackScoreRow(
                  label: entry.value,
                  responses: responses,
                  summaries: summaries,
                  question: entry.key,
                ),
              const SizedBox(height: 16),
              Text(
                'Recent driver feedback',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (responses.isEmpty)
                const Text('No submitted driver app feedback yet.')
              else
                for (final response in responses.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${response.displayName} · ${response.toda}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (response.comment?.trim().isNotEmpty ?? false)
                          Text(response.comment!),
                        Text(
                          shortTime(response.submittedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );
        return constraints.maxWidth < 930
            ? Column(children: [progress, const SizedBox(height: 16), scores])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: progress),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: scores),
                ],
              );
      },
    );
  }
}

class _FeedbackScoreRow extends StatelessWidget {
  const _FeedbackScoreRow({
    required this.label,
    required this.responses,
    required this.summaries,
    required this.question,
  });

  final String label;
  final List<DriverAppFeedback> responses;
  final List<TodaFeedbackSummary> summaries;
  final String question;

  @override
  Widget build(BuildContext context) {
    final observed = [
      for (final response in responses)
        if (response.scores[question] case final int score) score,
    ];
    double? mean;
    if (observed.isNotEmpty) {
      mean =
          observed.fold<int>(0, (sum, value) => sum + value) / observed.length;
    } else {
      var weighted = 0.0;
      var count = 0;
      for (final summary in summaries) {
        final value = summary.questionMeans[question];
        if (value == null || summary.responseCount == 0) continue;
        weighted += value * summary.responseCount;
        count += summary.responseCount;
      }
      if (count > 0) mean = weighted / count;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: mean == null
          ? Row(
              children: [
                Expanded(child: Text(label)),
                Text(
                  'No responses',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ScoreBar(label, mean),
                if (observed.isNotEmpty)
                  Text(
                    [
                      for (var rating = 1; rating <= 5; rating++)
                        '$rating★ ${observed.where((score) => score == rating).length}',
                    ].join('   '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    final controller = ref.read(adminProvider.notifier);
    final session = auth.value!;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AccountProfilePanel(session: session),
            const SizedBox(height: 16),
            _PasswordSettingsPanel(session: session),
            const SizedBox(height: 16),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Console preferences',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Compact table density'),
                    subtitle: const Text(
                      'Reduce row height on data-heavy views.',
                    ),
                    value: state.compactDensity,
                    onChanged: controller.setCompactDensity,
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Local desktop alerts'),
                    subtitle: Text(
                      state.connected
                          ? 'Play an unobtrusive chime for new SOS reports.'
                          : 'Show local status notifications during evaluation.',
                    ),
                    value: state.desktopAlerts,
                    onChanged: controller.setDesktopAlerts,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Driver app-feedback rules',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    session.role == AdminRole.lgu
                        ? 'Global settings apply to all TODAs and are enforced on the server.'
                        : 'Global settings are managed by the LGU and shown here as read-only.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  _FeedbackIntervalSetting(session: session),
                  const SizedBox(height: 10),
                  Text(
                    'Participation target: ${state.respondentTarget} unique drivers per TODA.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Map and data status',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  const _SettingRow(
                    icon: Icons.map_outlined,
                    title: 'Base map',
                    detail:
                        'MapLibre with OpenStreetMap raster tiles; optional MapTiler key at build time.',
                  ),
                  _SettingRow(
                    icon: Icons.layers_outlined,
                    title: 'TODA boundaries',
                    detail: state.connected
                        ? 'Server-defined jurisdictions; developer test boundary is provisional.'
                        : 'Prototype boundary · evaluation only',
                  ),
                  _SettingRow(
                    icon: Icons.storage_outlined,
                    title: 'Admin records',
                    detail: state.connected
                        ? 'Supabase records secured by administrator scope and row-level security.'
                        : 'Synthetic in-memory records; refresh resets changes.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About this build',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text('ArangCada Admin · Internal MVP'),
                  const SizedBox(height: 5),
                  Text(
                    'Standalone Flutter Web target. It does not import or depend on the commuter/driver mobile client.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  const StatusPill(
                    'Evaluation build · 2026-08-22',
                    tone: StatusTone.brand,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountProfilePanel extends ConsumerStatefulWidget {
  const _AccountProfilePanel({required this.session});

  final AdminSession session;

  @override
  ConsumerState<_AccountProfilePanel> createState() =>
      _AccountProfilePanelState();
}

class _AccountProfilePanelState extends ConsumerState<_AccountProfilePanel> {
  bool _uploading = false;

  bool get _canChange => widget.session.connected;

  Future<void> _changePhoto() async {
    if (!_canChange || _uploading) return;
    // Root cause, confirmed live 9 Sep 2026: an earlier diagnostic
    // SnackBar shown right here -- before ever calling pickImage() --
    // proved the tap itself was landing (it appeared every time), but no
    // file dialog ever followed it. image_picker's web implementation
    // opens the browser's file chooser via a plain synchronous
    // <input type="file">.click() call with nothing awaited first (see
    // image_picker_for_web's getFiles()), which is correct -- but a
    // browser's "user activation" for a click is a one-shot flag, and
    // showing that SnackBar first was enough on its own to consume it,
    // with zero error: the browser just silently refuses the .click(),
    // no onchange/oncancel/onerror ever fires on the input it refused to
    // open, and the awaited Future below hangs forever instead of
    // resolving to null. Nothing may run ahead of this call. Picked
    // generously (maxWidth 2000, no compression) -- the cropper below,
    // not this pick step, does the real sizing/compression, same split
    // apps/mobile's own profile_screen.dart already uses.
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
    );
    if (picked == null || !mounted) return;

    // Square/circle crop before upload, matching apps/mobile's own
    // profile photo flow exactly (image_cropper, same version) --
    // WebUiSettings instead of AndroidUiSettings since this is a browser
    // console, not a phone. image_cropper_for_web works directly against
    // the blob: URL image_picker_for_web's XFile.path already is, no
    // extra plumbing needed for either package to interoperate.
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      maxWidth: 1200,
      maxHeight: 1200,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 85,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        if (mounted) WebUiSettings(context: context),
      ],
    );
    // Null means Cancel on the crop dialog -- nothing uploads, same as
    // tapping Cancel anywhere else in this flow.
    if (cropped == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final bytes = await cropped.readAsBytes();
      // Always a jpg -- compressFormat above fixes it, regardless of what
      // the originally picked file's own extension was.
      final session = await ref
          .read(adminProvider.notifier)
          .changeProfilePhoto(bytes: bytes, fileExtension: 'jpg');
      if (!mounted) return;
      // AdminSession lives outside AdminController's own AdminState (see
      // main.dart's LoginScreen/session restore), so the fresh session with
      // its new avatarUrl is applied the same way sign-in already does.
      auth.value = session;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update your photo. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A photo change updates auth.value in place, on the *same* route --
    // unlike every other place auth.value is set (sign-in, session
    // restore), which always immediately navigates to a different route
    // and so always gets a fresh build for free. Reading widget.session
    // directly (captured once by SettingsScreen's own build) left this
    // panel showing the pre-change session forever after a real,
    // successfully saved photo change -- the write succeeded (confirmed
    // directly against the hosted project), the screen just never asked
    // auth for its current value again. ValueListenableBuilder makes this
    // panel its own listener instead of trusting a parent to have one.
    return ValueListenableBuilder<AdminSession?>(
      valueListenable: auth,
      builder: (context, liveSession, _) {
        final session = liveSession ?? widget.session;
        final avatarUrl = session.avatarUrl;
        return Panel(
          child: Row(
            children: [
              Semantics(
                label: _canChange ? 'Change profile photo' : null,
                button: _canChange,
                // Rebuilt on Material + InkWell rather than a bare
                // GestureDetector -- InkWell is the framework's own
                // battle-tested tap-target implementation (used for every
                // other clickable surface in this app, e.g. Panel's own
                // onTap) instead of a hand-rolled Stack/Positioned
                // combination that already hid one hit-test bug. The
                // ripple is also a real, visible confirmation that a tap
                // landed at all, which the silent GestureDetector version
                // never gave anyone -- owner included -- a way to tell
                // apart from "did nothing."
                //
                // No shape/clipBehavior on this Material -- a CircleBorder
                // clip here clips to the circle *inscribed* in the 56x56
                // box, which cut the corner-positioned edit badge off
                // (it renders outside that inscribed circle by design).
                // customBorder below still gives the ripple itself a
                // circular shape; it just doesn't also clip the child.
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('avatarHitTestBox'),
                    customBorder: const CircleBorder(),
                    onTap: _canChange ? _changePhoto : null,
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: AdminColors.primaryTint,
                            foregroundColor: AdminColors.primaryPress,
                            backgroundImage: avatarUrl == null
                                ? null
                                : NetworkImage(avatarUrl),
                            child: avatarUrl == null
                                ? Text(session.initials)
                                : null,
                          ),
                          if (_uploading)
                            const CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.black45,
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              ),
                            )
                          else if (_canChange)
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: AdminColors.rail,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 4,
                      children: [
                        Text(
                          '${session.deskLabel} ·',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          session.email ?? 'Local demo account',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusPill(session.roleLabel, tone: StatusTone.brand),
            ],
          ),
        );
      },
    );
  }
}

class _PasswordSettingsPanel extends ConsumerStatefulWidget {
  const _PasswordSettingsPanel({required this.session});

  final AdminSession session;

  @override
  ConsumerState<_PasswordSettingsPanel> createState() =>
      _PasswordSettingsPanelState();
}

class _PasswordSettingsPanelState
    extends ConsumerState<_PasswordSettingsPanel> {
  final formKey = GlobalKey<FormState>();
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  bool currentHidden = true;
  bool newHidden = true;
  bool confirmHidden = true;
  bool saving = false;

  bool get canChange =>
      widget.session.connected && (widget.session.email?.isNotEmpty ?? false);

  @override
  void dispose() {
    currentPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    if (!canChange) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connect an administrator account to change its password.',
          ),
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await ref
          .read(adminProvider.notifier)
          .updateOwnPassword(
            session: widget.session,
            currentPassword: currentPassword.text,
            newPassword: newPassword.text,
          );
      currentPassword.clear();
      newPassword.clear();
      confirmPassword.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Password updated.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password could not be updated. Check your current password and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool hidden,
    required VoidCallback toggle,
    required String? Function(String?) validator,
    required Iterable<String> autofillHints,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: controller,
      obscureText: hidden,
      autofillHints: autofillHints,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: hidden ? 'Show password' : 'Hide password',
          onPressed: toggle,
          icon: Icon(
            hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Panel(
    child: Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Change password',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            canChange
                ? 'Enter your current password, then choose a new one.'
                : 'Password changes are available after signing in to the connected console.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          _passwordField(
            controller: currentPassword,
            label: 'Current password',
            hint: 'Enter current password',
            hidden: currentHidden,
            toggle: () => setState(() => currentHidden = !currentHidden),
            validator: (value) => value == null || value.isEmpty
                ? 'Enter your current password.'
                : null,
            autofillHints: const [AutofillHints.password],
          ),
          _passwordField(
            controller: newPassword,
            label: 'New password',
            hint: 'At least 8 characters',
            hidden: newHidden,
            toggle: () => setState(() => newHidden = !newHidden),
            validator: (value) => value == null || value.length < 8
                ? 'Enter at least 8 characters.'
                : null,
            autofillHints: const [AutofillHints.newPassword],
          ),
          _passwordField(
            controller: confirmPassword,
            label: 'Confirm new password',
            hint: 'Re-enter new password',
            hidden: confirmHidden,
            toggle: () => setState(() => confirmHidden = !confirmHidden),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Confirm the new password.';
              }
              return value == newPassword.text
                  ? null
                  : 'Passwords do not match.';
            },
            autofillHints: const [AutofillHints.newPassword],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(saving ? 'Updating…' : 'Update password'),
          ),
        ],
      ),
    ),
  );
}

class _FeedbackIntervalSetting extends ConsumerStatefulWidget {
  const _FeedbackIntervalSetting({required this.session});

  final AdminSession session;

  @override
  ConsumerState<_FeedbackIntervalSetting> createState() =>
      _FeedbackIntervalSettingState();
}

class _FeedbackIntervalSettingState
    extends ConsumerState<_FeedbackIntervalSetting> {
  late final TextEditingController interval = TextEditingController(
    text: '${ref.read(adminProvider).feedbackInterval}',
  );
  bool saving = false;
  String? error;

  @override
  void dispose() {
    interval.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = int.tryParse(interval.text.trim());
    if (value == null || value < 1) {
      setState(() => error = 'Enter a whole number greater than zero.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(adminProvider.notifier)
          .updateFeedbackSettings(
            session: widget.session,
            feedbackInterval: value,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Drivers will provide app feedback after every $value completed trip${value == 1 ? '' : 's'}.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'The global feedback setting could not be saved.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.session.role == AdminRole.lgu;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: interval,
            enabled: canEdit && !saving,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Completed trips between required feedback',
              errorText: error,
              suffixText: 'trip(s)',
            ),
            onSubmitted: canEdit ? (_) => _save() : null,
          ),
        ),
        if (canEdit) ...[
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilledButton(
              onPressed: saving ? null : _save,
              child: Text(saving ? 'Saving…' : 'Save interval'),
            ),
          ),
        ],
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

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = constraints.maxWidth >= 1080
          ? children.length.clamp(1, 4)
          : constraints.maxWidth >= 620
          ? 2
          : 1;
      return GridView.count(
        crossAxisCount: count,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: count == 1
            ? 3.4
            : count == 2
            ? 2.35
            : 2.05,
        children: children,
      );
    },
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

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.caption,
  });
  final String label;
  final double value;
  final String caption;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, ${(value * 100).round()} percent, $caption',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AdminColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 9,
            backgroundColor: AdminColors.surface,
            color: AdminColors.primary,
          ),
        ),
        const SizedBox(height: 5),
        Text(caption, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.report,
    required this.selected,
    required this.onTap,
  });
  final SafetyReport report;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: selected ? AdminColors.primaryTint : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (report.priority == 'critical') ...[
                  const Icon(
                    Icons.priority_high,
                    size: 18,
                    color: AdminColors.danger,
                  ),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    safetyReportLabel(report.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  reportStatusLabel(report.status),
                  tone: reportTone(report.status),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(report.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(
              '${report.toda} · ${shortTime(report.created)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SafetyDetail extends ConsumerWidget {
  const _SafetyDetail(this.report);
  final SafetyReport report;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    safetyReportLabel(report.id),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${report.toda} · submitted ${shortTime(report.created)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            StatusPill(
              reportStatusLabel(report.status),
              tone: reportTone(report.status),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(report.summary, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 18),
        Wrap(
          spacing: 22,
          runSpacing: 12,
          children: [
            _LabelValue('Rider', report.rider),
            _LabelValue('Driver', report.driver),
            _LabelValue('TODA', report.toda),
            if (report.priority == 'critical')
              const _LabelValue('Priority', 'Critical SOS'),
            if (report.latitude != null && report.longitude != null)
              _LabelValue(
                'Reported location',
                '${report.latitude!.toStringAsFixed(5)}, ${report.longitude!.toStringAsFixed(5)}',
              ),
          ],
        ),
        const SizedBox(height: 22),
        Text('Response log', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final note in report.notes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 19,
                  color: AdminColors.success,
                ),
                const SizedBox(width: 9),
                Expanded(child: Text(note)),
              ],
            ),
          ),
        const SizedBox(height: 18),
        if (auth.value?.role != AdminRole.lgu)
          const StatusPill('Read-only · LGU manages safety report status')
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(
                onPressed: report.status == ReportStatus.resolved
                    ? null
                    : () => _updateReport(context, ref, ReportStatus.resolved),
                child: const Text('Mark resolved'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _updateReport(context, ref, ReportStatus.acknowledged),
                child: const Text('Acknowledge'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _updateReport(context, ref, ReportStatus.investigating),
                child: const Text('Investigate'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _updateReport(context, ref, ReportStatus.escalated),
                child: const Text('Escalate'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _updateReport(context, ref, ReportStatus.dismissed),
                child: const Text('Dismiss'),
              ),
            ],
          ),
      ],
    ),
  );

  Future<void> _updateReport(
    BuildContext context,
    WidgetRef ref,
    ReportStatus status,
  ) async {
    final note = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set status to ${reportStatusLabel(status)}?'),
        content: TextField(
          controller: note,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Response note',
            hintText: 'Add context for the audit trail',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      try {
        await ref
            .read(adminProvider.notifier)
            .transitionReport(report.id, status, note.text);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${report.id} is now ${reportStatusLabel(status).toLowerCase()}.',
            ),
          ),
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This safety report could not be updated.'),
          ),
        );
      }
    }
    note.dispose();
  }
}

class _LabelValue extends StatelessWidget {
  const _LabelValue(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(letterSpacing: .7),
        ),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

// Folded into Safety reports as a compact secondary panel (owner's call,
// Spec 19 follow-up) -- see _ComplaintsSection below. _ComplaintTile and
// _ComplaintDetail stay, reused there unchanged.
class _ComplaintsSection extends StatelessWidget {
  const _ComplaintsSection({required this.complaints});
  final List<Complaint> complaints;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Complaints', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Non-emergency issues either party filed about the other -- '
          'driver lateness, disputed fares, and similar. Not for danger; '
          'see the reports above for that.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (complaints.isEmpty)
          const EmptyState(message: 'No complaints in this scope.')
        else
          for (final complaint in complaints)
            _ComplaintTile(
              complaint: complaint,
              selected: false,
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SingleChildScrollView(
                      child: _ComplaintDetail(complaint),
                    ),
                  ),
                ),
              ),
            ),
      ],
    ),
  );
}

class _ComplaintTile extends StatelessWidget {
  const _ComplaintTile({
    required this.complaint,
    required this.selected,
    required this.onTap,
  });
  final Complaint complaint;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: selected ? AdminColors.primaryTint : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    complaintCategoryLabel(complaint.category),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusPill(
                  reportStatusLabel(complaint.status),
                  tone: reportTone(complaint.status),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${complaint.complainantName} about ${complaint.respondentName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              '${complaint.toda} · ${shortTime(complaint.created)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ComplaintDetail extends ConsumerWidget {
  const _ComplaintDetail(this.complaint);
  final Complaint complaint;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    complaintCategoryLabel(complaint.category),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${complaint.toda} · submitted ${shortTime(complaint.created)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            StatusPill(
              reportStatusLabel(complaint.status),
              tone: reportTone(complaint.status),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          complaint.description,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 22,
          runSpacing: 12,
          children: [
            _LabelValue(
              complaint.complainantRole == 'driver' ? 'Driver' : 'Commuter',
              complaint.complainantName,
            ),
            _LabelValue(
              complaint.complainantRole == 'driver' ? 'Commuter' : 'Driver',
              complaint.respondentName,
            ),
            _LabelValue('TODA', complaint.toda),
          ],
        ),
        const SizedBox(height: 22),
        Text('Response log', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final note in complaint.notes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 19,
                  color: AdminColors.success,
                ),
                const SizedBox(width: 9),
                Expanded(child: Text(note)),
              ],
            ),
          ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              onPressed: complaint.status == ReportStatus.resolved
                  ? null
                  : () => _updateComplaint(context, ref, ReportStatus.resolved),
              child: const Text('Mark resolved'),
            ),
            OutlinedButton(
              onPressed: () =>
                  _updateComplaint(context, ref, ReportStatus.acknowledged),
              child: const Text('Acknowledge'),
            ),
            OutlinedButton(
              onPressed: () =>
                  _updateComplaint(context, ref, ReportStatus.investigating),
              child: const Text('Investigate'),
            ),
            OutlinedButton(
              onPressed: () =>
                  _updateComplaint(context, ref, ReportStatus.dismissed),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _updateComplaint(
    BuildContext context,
    WidgetRef ref,
    ReportStatus status,
  ) async {
    final note = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set status to ${reportStatusLabel(status)}?'),
        content: TextField(
          controller: note,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Response note',
            hintText: 'Add context for the audit trail',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      try {
        await ref
            .read(adminProvider.notifier)
            .transitionComplaint(complaint.id, status, note.text);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Complaint is now ${reportStatusLabel(status).toLowerCase()}.',
            ),
          ),
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This complaint could not be updated.')),
        );
      }
    }
    note.dispose();
  }
}

/// Student/Senior Citizen/PWD discount claims, LGU-only: commuters have no
/// TODA affiliation, so there is no per-TODA scope for a claim to belong to
/// (see AdminController.visibleFareClassClaims). See .pipeline/specs.md
/// Spec 14.
class ClaimsScreen extends ConsumerStatefulWidget {
  const ClaimsScreen({super.key});
  @override
  ConsumerState<ClaimsScreen> createState() => _ClaimsScreenState();
}

class _ClaimsScreenState extends ConsumerState<ClaimsScreen> {
  String? selected;

  @override
  Widget build(BuildContext context) {
    final session = auth.value!;
    if (session.role != AdminRole.lgu) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            title: 'Discount claims',
            subtitle:
                'Student/Senior Citizen/PWD fare-class claims are reviewed city-wide.',
          ),
          SizedBox(height: 22),
          Panel(
            child: EmptyState(
              message:
                  'Discount claims are reviewed by an LGU administrator, not a TODA desk -- commuters have no TODA affiliation to scope this by.',
            ),
          ),
        ],
      );
    }
    final claims = ref.read(adminProvider.notifier).visibleFareClassClaims(session);
    if (claims.isNotEmpty && !claims.any((claim) => claim.id == selected)) {
      selected = claims.first.id;
    }
    final active = claims.where((claim) => claim.id == selected).firstOrNull;
    final list = Panel(
      padding: const EdgeInsets.all(10),
      child: claims.isEmpty
          ? const EmptyState(message: 'No discount claims pending review.')
          : Column(
              children: [
                for (final claim in claims)
                  _ClaimTile(
                    claim: claim,
                    selected: claim.id == selected,
                    onTap: () => setState(() => selected = claim.id),
                  ),
              ],
            ),
    );
    final detail = active == null
        ? const Panel(child: EmptyState(message: 'Select a claim.'))
        : _ClaimDetail(active);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          title: 'Discount claims',
          subtitle:
              "Student/Senior Citizen/PWD fare-class claims -- manual ID review, not automatic reading. Approving flips the commuter's billing to the discounted rate on their next booking.",
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 950
              ? Column(children: [list, const SizedBox(height: 14), detail])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 380, child: list),
                    const SizedBox(width: 16),
                    Expanded(child: detail),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({
    required this.claim,
    required this.selected,
    required this.onTap,
  });
  final FareClassClaim claim;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: selected ? AdminColors.primaryTint : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fareClassRequestedClassLabel(claim.requestedClass),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusPill(
                  fareClassClaimStatusLabel(claim.status),
                  tone: fareClassClaimTone(claim.status),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              claim.claimantName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              shortTime(claim.created),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ClaimDetail extends ConsumerWidget {
  const _ClaimDetail(this.claim);
  final FareClassClaim claim;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = claim.status == 'pending_review';
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fareClassRequestedClassLabel(claim.requestedClass),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Submitted ${shortTime(claim.created)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(
                fareClassClaimStatusLabel(claim.status),
                tone: fareClassClaimTone(claim.status),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _LabelValue('Claimant', claim.claimantName),
          if (claim.rejectionReason != null) ...[
            const SizedBox(height: 18),
            Text('Rejection reason', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(claim.rejectionReason!),
          ],
          const SizedBox(height: 22),
          Text('Submitted ID', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _ClaimPhoto(claim: claim),
          const SizedBox(height: 8),
          Text(
            "Only this administrator's view mints a signed link to this file -- it is never a public URL, and it expires in 5 minutes.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (pending) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () => _decide(context, ref, claim, approve: true),
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: () => _decide(context, ref, claim, approve: false),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    FareClassClaim claim, {
    required bool approve,
  }) async {
    String? reason;
    if (!approve) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reject this claim?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Required -- shown to no one but the audit trail',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, controller.text.trim().isNotEmpty),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      reason = controller.text.trim();
      controller.dispose();
      if (confirmed != true || !context.mounted) return;
    }
    try {
      await ref
          .read(adminProvider.notifier)
          .reviewFareClassClaim(
            claimId: claim.id,
            approve: approve,
            rejectionReason: reason,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Claim approved.' : 'Claim rejected.'),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This claim could not be updated.')),
      );
    }
  }
}

class _ClaimPhoto extends ConsumerStatefulWidget {
  const _ClaimPhoto({required this.claim});
  final FareClassClaim claim;
  @override
  ConsumerState<_ClaimPhoto> createState() => _ClaimPhotoState();
}

class _ClaimPhotoState extends ConsumerState<_ClaimPhoto> {
  late Future<String> _url;

  @override
  void initState() {
    super.initState();
    _url = ref
        .read(adminProvider.notifier)
        .fareClassClaimPhotoUrl(widget.claim.idPhotoPath);
  }

  @override
  void didUpdateWidget(covariant _ClaimPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.claim.idPhotoPath != widget.claim.idPhotoPath) {
      _url = ref
          .read(adminProvider.notifier)
          .fareClassClaimPhotoUrl(widget.claim.idPhotoPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox(
            height: 80,
            child: Center(child: Text('Could not load the submitted photo.')),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            snapshot.data!,
            height: 260,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const SizedBox(
              height: 80,
              child: Center(child: Text('Could not load the submitted photo.')),
            ),
          ),
        );
      },
    );
  }
}

/// Read-only -- LGU/TODA administrators read both directions' stars and
/// comments here, but there is no status workflow: a rating is not a case to
/// resolve, only a record to see. See .pipeline/specs.md Spec 13.
class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = auth.value!;
    final ratings = ref.read(adminProvider.notifier).visibleRatings(session);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          title: 'Reviews',
          subtitle:
              'Every trip rating, both directions -- commuter about driver, and driver about commuter.',
        ),
        const SizedBox(height: 22),
        Panel(
          padding: const EdgeInsets.all(10),
          child: ratings.isEmpty
              ? const EmptyState(message: 'No reviews in this scope.')
              : Column(
                  children: [for (final rating in ratings) _RatingTile(rating)],
                ),
        ),
      ],
    );
  }
}

class _RatingTile extends StatelessWidget {
  const _RatingTile(this.rating);
  final TripRating rating;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${rating.raterName} rated ${rating.rateeName}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Row(
              children: [
                for (var star = 1; star <= 5; star++)
                  Icon(
                    star <= rating.stars ? Icons.star : Icons.star_border,
                    size: 18,
                    color: AdminColors.primary,
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${rating.raterRole == 'driver' ? 'Driver' : 'Commuter'} · ${rating.toda} · ${shortTime(rating.created)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (rating.comment != null) ...[
          const SizedBox(height: 6),
          Text(rating.comment!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    ),
  );
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow(this.measure, this.manual, this.arangcada);
  final String measure;
  final String manual;
  final String arangcada;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(measure, style: Theme.of(context).textTheme.titleMedium),
        ),
        Expanded(child: Text(manual)),
        Expanded(
          child: Text(
            arangcada,
            style: const TextStyle(
              color: AdminColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar(this.label, this.score);
  final String label;
  final double score;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Semantics(
      label: '$label, $score out of 5',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                score.toStringAsFixed(1),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 7),
          LinearProgressIndicator(
            value: score / 5,
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
            backgroundColor: AdminColors.surface,
            color: AdminColors.success,
          ),
        ],
      ),
    ),
  );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AdminColors.primaryTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AdminColors.primary),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(detail),
            ],
          ),
        ),
      ],
    ),
  );
}

// =============================================================================
// Driver enrollment by email (Spec 20) -- LGU-initiated, mirrors the admin
// invite system (Spec 19) closely.
// =============================================================================

class _PendingDriverInvitesPanel extends ConsumerStatefulWidget {
  const _PendingDriverInvitesPanel();
  @override
  ConsumerState<_PendingDriverInvitesPanel> createState() =>
      _PendingDriverInvitesPanelState();
}

class _PendingDriverInvitesPanelState
    extends ConsumerState<_PendingDriverInvitesPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    final session = auth.value;
    if (!mounted ||
        session == null ||
        session.role != AdminRole.lgu ||
        !session.connected) {
      return;
    }
    try {
      await ref.read(adminProvider.notifier).refreshDriverInvites();
    } catch (_) {
      // Stays empty -- nothing more specific to show here, same swallow-
      // and-retry-next-visit shape SafetyScreen's own poll already uses.
    }
  }

  @override
  Widget build(BuildContext context) {
    final invites = ref.watch(adminProvider).driverInvites;
    if (invites.isEmpty) return const SizedBox.shrink();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pending driver invites',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Not yet accepted. Inviting the same email again supersedes the link below.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          for (final invite in invites)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invite.email,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${invite.toda ?? 'Unknown TODA'} -- sent ${shortTime(invite.created)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _revoke(context, ref, invite),
                    child: const Text('Revoke'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    DriverInvite invite,
  ) async {
    try {
      await ref.read(adminProvider.notifier).revokeDriverInvite(invite.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite to ${invite.email} revoked.')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This invite could not be revoked.')),
      );
    }
  }
}

Future<void> _showDriverEnrollment(
  BuildContext context,
  WidgetRef ref,
  List<(String id, String name)> todaZoneOptions,
) async {
  final enrolled = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) =>
        _DriverEnrollmentDialog(todaZoneOptions: todaZoneOptions),
  );
  if (enrolled == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Driver enrolled.')));
  }
}

class _DriverEnrollmentDialog extends ConsumerStatefulWidget {
  const _DriverEnrollmentDialog({required this.todaZoneOptions});
  final List<(String id, String name)> todaZoneOptions;

  @override
  ConsumerState<_DriverEnrollmentDialog> createState() =>
      _DriverEnrollmentDialogState();
}

class _DriverEnrollmentDialogState
    extends ConsumerState<_DriverEnrollmentDialog> {
  final _emailFormKey = GlobalKey<FormState>();
  final _detailFormKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _confirmEmail = TextEditingController();
  final _bodyNumber = TextEditingController();
  bool _checking = false;
  bool _submitting = false;
  // null = step 1 (email not checked yet). Non-null = step 2, and whether
  // it is empty decides which of the two branches step 2 shows.
  List<DriverCandidate>? _candidates;
  String? _todaZoneId;

  @override
  void initState() {
    super.initState();
    if (widget.todaZoneOptions.isNotEmpty) {
      _todaZoneId = widget.todaZoneOptions.first.$1;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _confirmEmail.dispose();
    _bodyNumber.dispose();
    super.dispose();
  }

  Future<void> _checkEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _checking = true);
    try {
      final candidates = await ref
          .read(adminProvider.notifier)
          .previewDriverCandidate(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _checking = false;
        _candidates = candidates;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError ? error.message : 'Could not check this email.',
          ),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_detailFormKey.currentState!.validate()) return;
    final todaZoneId = _todaZoneId;
    if (todaZoneId == null) return;
    final found = _candidates!.isNotEmpty;
    setState(() => _submitting = true);
    try {
      if (found) {
        await ref
            .read(adminProvider.notifier)
            .promoteCommuterToDriver(
              email: _email.text.trim(),
              confirmValue: _confirmEmail.text.trim(),
              todaZoneId: todaZoneId,
              bodyNumber: _bodyNumber.text.trim().isEmpty
                  ? null
                  : _bodyNumber.text.trim(),
            );
      } else {
        await ref
            .read(adminProvider.notifier)
            .sendDriverInvite(
              email: _email.text.trim(),
              todaZoneId: todaZoneId,
              bodyNumber: _bodyNumber.text.trim().isEmpty
                  ? null
                  : _bodyNumber.text.trim(),
            );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : found
                ? 'This driver could not be enrolled.'
                : 'The invite could not be sent.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates == null) {
      return AlertDialog(
        title: const Text('Enroll a driver'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _emailFormKey,
            child: TextFormField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: "Driver's email address",
              ),
              validator: (value) => (value?.trim().contains('@') ?? false)
                  ? null
                  : 'Enter a valid email address.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _checking ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _checking ? null : _checkEmail,
            child: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
        ],
      );
    }

    final found = _candidates!.isNotEmpty;
    return AlertDialog(
      title: Text(found ? 'This email already has an account' : 'Enroll a new driver'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _detailFormKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (found) ...[
                  for (final candidate in _candidates!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${candidate.maskedName} -- ${candidate.accountRole}, '
                        'joined ${candidate.joinedOn}, ${candidate.tripCount} trip(s)',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  Text(
                    'Re-type the email to confirm this is the right account -- '
                    'promoting the wrong one cannot be undone from here.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _confirmEmail,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Confirm email'),
                    validator: (value) =>
                        value?.trim().toLowerCase() == _email.text.trim().toLowerCase()
                        ? null
                        : 'Must match the email above exactly.',
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  Text(
                    'No account exists for ${_email.text.trim()} yet -- an invite '
                    'will be emailed to create one.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _todaZoneId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'TODA'),
                  items: [
                    for (final zone in widget.todaZoneOptions)
                      DropdownMenuItem(value: zone.$1, child: Text(zone.$2)),
                  ],
                  onChanged: (value) => setState(() => _todaZoneId = value),
                  validator: (value) => value == null ? 'Select a TODA.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bodyNumber,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Body number (optional)',
                    hintText: 'Matched against the TODA roster if given',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => setState(() => _candidates = null),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(found ? 'Promote to driver' : 'Send invite'),
        ),
      ],
    );
  }
}

Future<void> _showEnrollment(BuildContext context, WidgetRef ref) async {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final plate = TextEditingController();
  String toda = auth.value!.toda ?? 'Brgy. Real';
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Enroll a driver'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (value) => (value?.trim().length ?? 0) >= 3
                        ? null
                        : 'Enter the driver name.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: toda,
                    decoration: const InputDecoration(labelText: 'TODA'),
                    items: [
                      for (final item
                          in auth.value!.role == AdminRole.toda
                              ? [auth.value!.toda!]
                              : ['Brgy. Real', 'Parian', 'Canlubang'])
                        DropdownMenuItem(value: item, child: Text(item)),
                    ],
                    onChanged: (value) => setDialogState(() => toda = value!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile number',
                    ),
                    validator: (value) =>
                        (value?.replaceAll(RegExp(r'\D'), '').length ?? 0) >= 10
                        ? null
                        : 'Enter a valid mobile number.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: plate,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Plate / body number',
                    ),
                    validator: (value) => (value?.trim().length ?? 0) >= 3
                        ? null
                        : 'Enter the plate or body number.',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Create enrollment'),
          ),
        ],
      ),
    ),
  );
  if (submitted == true && context.mounted) {
    final driver = ref
        .read(adminProvider.notifier)
        .enrollDriver(
          name: name.text,
          toda: toda,
          phone: phone.text,
          plate: plate.text,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Enrollment ${driver.enrollmentCode} created.')),
    );
  }
  name.dispose();
  phone.dispose();
  plate.dispose();
}

Future<void> _showDriver(
  BuildContext context,
  WidgetRef ref,
  Driver driver,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(driver.name)),
          StatusPill(
            driverStatusLabel(driver.status),
            tone: driverTone(driver.status),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 24,
                runSpacing: 14,
                children: [
                  _LabelValue('Enrollment', driver.enrollmentCode),
                  _LabelValue('TODA', driver.toda),
                  _LabelValue('Phone', driver.phone),
                  _LabelValue('Plate', driver.plate),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Submitted documents',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final item in const [
                ('drivers_license', 'Driver’s license'),
                ('mtop_franchise', 'MTOP / franchise permit'),
                ('toda_membership', 'TODA membership endorsement'),
                ('or_cr', 'Vehicle OR / CR registration'),
                ('barangay_clearance', 'Barangay clearance (optional)'),
                ('vehicle_photo', 'Vehicle photo (optional)'),
              ].indexed)
                _DriverDocumentRow(
                  driver: driver,
                  documentType: item.$2.$1,
                  label: item.$2.$2,
                  demoIndex: item.$1,
                  connected: auth.value?.connected ?? false,
                ),
              const SizedBox(height: 12),
              Text(
                auth.value?.connected ?? false
                    ? 'Uploaded on the driver’s behalf after their paper submission is checked in person. Only this administrator’s view mints a signed link to a file -- never a public URL, and it expires in 5 minutes.'
                    : 'Local demo mode has no Storage bucket or RPC to call -- upload, view, and review are disabled here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (auth.value?.role == AdminRole.lgu &&
            driver.status == DriverStatus.suspended)
          OutlinedButton(
            onPressed: () => _applyDriverAction(
              context,
              ref,
              driver,
              DriverStatus.approved,
              'Reinstated after administrator review',
            ),
            child: const Text('Reinstate'),
          )
        else if (auth.value?.role == AdminRole.lgu)
          OutlinedButton(
            onPressed: () => _confirmDriverAction(
              context,
              ref,
              driver,
              DriverStatus.suspended,
            ),
            child: const Text('Suspend'),
          ),
        if (auth.value?.role == AdminRole.lgu)
          OutlinedButton(
            onPressed: () => _confirmDriverAction(
              context,
              ref,
              driver,
              DriverStatus.rejected,
            ),
            child: const Text('Reject'),
          ),
        FilledButton(
          onPressed:
              driver.approvedDocuments < 4 ||
                  driver.status == DriverStatus.suspended
              ? null
              : () => _applyDriverAction(
                  context,
                  ref,
                  driver,
                  DriverStatus.approved,
                  'Required driver documents reviewed and accepted',
                ),
          child: const Text('Approve'),
        ),
      ],
    ),
  );
}

class _DriverDocumentRow extends ConsumerStatefulWidget {
  const _DriverDocumentRow({
    required this.driver,
    required this.documentType,
    required this.label,
    required this.demoIndex,
    required this.connected,
  });

  final Driver driver;
  final String documentType;
  final String label;
  final int demoIndex;
  final bool connected;

  @override
  ConsumerState<_DriverDocumentRow> createState() => _DriverDocumentRowState();
}

class _DriverDocumentRowState extends ConsumerState<_DriverDocumentRow> {
  bool _busy = false;

  String? get _status => widget.connected
      ? widget.driver.documentStatuses[widget.documentType]
      : widget.demoIndex < widget.driver.documents
      ? 'approved'
      : null;

  Future<void> _upload() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await picked.readAsBytes();
      final dotIndex = picked.name.lastIndexOf('.');
      final extension = dotIndex == -1
          ? 'jpg'
          : picked.name.substring(dotIndex + 1).toLowerCase();
      await ref
          .read(adminProvider.notifier)
          .uploadDriverDocument(
            driverId: widget.driver.id,
            documentType: widget.documentType,
            bytes: bytes,
            fileExtension: extension,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Document uploaded.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not upload that document.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review({required bool approve}) async {
    final documentId = widget.driver.documentIds[widget.documentType];
    if (documentId == null) return;
    String? reason;
    if (!approve) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reject this document?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Required -- shown to no one but the audit trail',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, controller.text.trim().isNotEmpty),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      reason = controller.text.trim();
      controller.dispose();
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(adminProvider.notifier)
          .reviewDriverDocument(
            documentId: documentId,
            approve: approve,
            rejectionReason: reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Document approved.' : 'Document rejected.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This document could not be updated.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final path = widget.connected
        ? widget.driver.documentPaths[widget.documentType]
        : null;
    final approved = status == 'approved';
    final rejected = status == 'rejected';
    final description = switch (status) {
      'approved' => 'Approved',
      'pending' => 'Pending review',
      'rejected' => 'Rejected',
      _ => 'Missing',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                approved
                    ? Icons.check_circle
                    : rejected
                    ? Icons.cancel
                    : Icons.radio_button_unchecked,
                color: approved
                    ? AdminColors.success
                    : rejected
                    ? AdminColors.danger
                    : AdminColors.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if (path != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: _DriverDocumentPhoto(path: path),
            ),
          ],
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy || !widget.connected ? null : _upload,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(path == null ? 'Upload' : 'Replace'),
                ),
                if (widget.connected && status == 'pending' && path != null) ...[
                  FilledButton(
                    onPressed: _busy ? null : () => _review(approve: true),
                    child: const Text('Approve'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _review(approve: false),
                    child: const Text('Reject'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverDocumentPhoto extends ConsumerStatefulWidget {
  const _DriverDocumentPhoto({required this.path});
  final String path;
  @override
  ConsumerState<_DriverDocumentPhoto> createState() =>
      _DriverDocumentPhotoState();
}

class _DriverDocumentPhotoState extends ConsumerState<_DriverDocumentPhoto> {
  late Future<String> _url;

  @override
  void initState() {
    super.initState();
    _url = ref.read(adminProvider.notifier).driverDocumentPhotoUrl(widget.path);
  }

  @override
  void didUpdateWidget(covariant _DriverDocumentPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _url = ref
          .read(adminProvider.notifier)
          .driverDocumentPhotoUrl(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 100,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox(
            height: 40,
            child: Center(child: Text('Could not load this document.')),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snapshot.data!,
            height: 160,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          ),
        );
      },
    );
  }
}

Future<void> _applyDriverAction(
  BuildContext dialogContext,
  WidgetRef ref,
  Driver driver,
  DriverStatus status,
  String reason,
) async {
  try {
    await ref
        .read(adminProvider.notifier)
        .updateDriver(driver.id, status, reason);
    if (dialogContext.mounted) Navigator.pop(dialogContext);
  } catch (_) {
    if (!dialogContext.mounted) return;
    ScaffoldMessenger.of(dialogContext).showSnackBar(
      const SnackBar(
        content: Text(
          'The requested driver action was not accepted by the server.',
        ),
      ),
    );
  }
}

Future<void> _confirmDriverAction(
  BuildContext dialogContext,
  WidgetRef ref,
  Driver driver,
  DriverStatus status,
) async {
  final reason = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: dialogContext,
    builder: (context) => AlertDialog(
      title: Text('${driverStatusLabel(status)} ${driver.name}?'),
      content: TextField(
        controller: reason,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Reason',
          hintText: 'Required for the audit trail',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, reason.text.trim().isNotEmpty),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  if (confirmed == true && dialogContext.mounted) {
    await _applyDriverAction(dialogContext, ref, driver, status, reason.text);
  }
  reason.dispose();
}

// =============================================================================
// Admins (Spec 19) -- LGU/TODA admin accounts, invite by email
// =============================================================================

class AdminsScreen extends ConsumerStatefulWidget {
  const AdminsScreen({super.key});
  @override
  ConsumerState<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends ConsumerState<AdminsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    final session = auth.value;
    if (!mounted ||
        session == null ||
        session.role != AdminRole.lgu ||
        !session.connected) {
      return;
    }
    try {
      await ref.read(adminProvider.notifier).refreshAdminAccounts(session);
    } catch (_) {
      // The two lists below simply stay empty -- there is nothing more
      // specific to show here, matching how _refreshReportedChats
      // (SafetyScreen) also swallows a transient load failure and relies on
      // the next poll/visit rather than a standing error banner.
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = auth.value!;
    if (session.role != AdminRole.lgu) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            title: 'Admins',
            subtitle: 'LGU and TODA administrator accounts.',
          ),
          SizedBox(height: 22),
          Panel(
            child: EmptyState(
              message:
                  'Administrator accounts are managed by an LGU administrator, not a TODA desk.',
            ),
          ),
        ],
      );
    }

    final state = ref.watch(adminProvider);
    final lgu = state.adminAccounts
        .where((account) => account.role == AdminRole.lgu)
        .toList();
    final toda = state.adminAccounts
        .where((account) => account.role == AdminRole.toda)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          title: 'Admins',
          subtitle:
              'Invite and review LGU and TODA administrator accounts by email.',
          action: FilledButton.icon(
            onPressed: state.connected
                ? () => _showInvite(context, ref, state.todaZoneOptions)
                : null,
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Invite admin'),
          ),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final lguPanel = _AdminAccountList(
              title: 'LGU administrators',
              accounts: lgu,
            );
            final todaPanel = _AdminAccountList(
              title: 'TODA administrators',
              accounts: toda,
            );
            return constraints.maxWidth < 950
                ? Column(
                    children: [
                      lguPanel,
                      const SizedBox(height: 14),
                      todaPanel,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: lguPanel),
                      const SizedBox(width: 16),
                      Expanded(child: todaPanel),
                    ],
                  );
          },
        ),
        if (state.adminInvites.isNotEmpty) ...[
          const SizedBox(height: 22),
          _PendingInvitesPanel(invites: state.adminInvites),
        ],
      ],
    );
  }
}

class _AdminAccountList extends StatelessWidget {
  const _AdminAccountList({required this.title, required this.accounts});
  final String title;
  final List<AdminAccount> accounts;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (accounts.isEmpty)
          const EmptyState(message: 'No accounts yet.')
        else
          for (final account in accounts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    account.toda == null
                        ? account.email
                        : '${account.email} -- ${account.toda}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    account.invitedByName == null
                        ? 'Pre-existing account (not invited)'
                        : 'Invited by ${account.invitedByName}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AdminColors.muted,
                    ),
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}

class _PendingInvitesPanel extends ConsumerWidget {
  const _PendingInvitesPanel({required this.invites});
  final List<AdminInvite> invites;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pending invites', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Not yet accepted. Inviting the same email again supersedes the link below.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        for (final invite in invites)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invite.email,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        invite.scope == AdminRole.toda
                            ? 'TODA${invite.toda != null ? ' -- ${invite.toda}' : ''} -- sent ${shortTime(invite.created)}'
                            : 'LGU -- sent ${shortTime(invite.created)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _revoke(context, ref, invite),
                  child: const Text('Revoke'),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    AdminInvite invite,
  ) async {
    try {
      await ref.read(adminProvider.notifier).revokeAdminInvite(invite.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite to ${invite.email} revoked.')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This invite could not be revoked.')),
      );
    }
  }
}

Future<void> _showInvite(
  BuildContext context,
  WidgetRef ref,
  List<(String id, String name)> todaZoneOptions,
) async {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  String scope = 'lgu';
  String? todaZoneId = todaZoneOptions.isEmpty ? null : todaZoneOptions.first.$1;
  bool sending = false;

  final sent = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Invite an administrator'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: email,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                    ),
                    validator: (value) => (value?.trim().contains('@') ?? false)
                        ? null
                        : 'Enter a valid email address.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: scope,
                    decoration: const InputDecoration(labelText: 'Scope'),
                    items: const [
                      DropdownMenuItem(
                        value: 'lgu',
                        child: Text('LGU administrator -- all TODAs'),
                      ),
                      DropdownMenuItem(
                        value: 'toda',
                        child: Text('TODA administrator -- one TODA'),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() => scope = value!),
                  ),
                  if (scope == 'toda') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: todaZoneId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'TODA'),
                      items: [
                        for (final zone in todaZoneOptions)
                          DropdownMenuItem(value: zone.$1, child: Text(zone.$2)),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => todaZoneId = value),
                      validator: (value) =>
                          value == null ? 'Select a TODA.' : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: sending
                ? null
                : () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: sending
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    setDialogState(() => sending = true);
                    try {
                      await ref
                          .read(adminProvider.notifier)
                          .sendAdminInvite(
                            email: email.text.trim(),
                            scope: scope,
                            todaZoneId: scope == 'toda' ? todaZoneId : null,
                          );
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (error) {
                      setDialogState(() => sending = false);
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              error is StateError
                                  ? error.message
                                  : 'The invite could not be sent.',
                            ),
                          ),
                        );
                      }
                    }
                  },
            child: sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send invite'),
          ),
        ],
      ),
    ),
  );
  email.dispose();
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invite sent.')));
  }
}

// =============================================================================
// Accept invite (Spec 19) -- public route, no session required
// =============================================================================

class AcceptInviteScreen extends ConsumerStatefulWidget {
  const AcceptInviteScreen({super.key, required this.token});
  final String? token;

  @override
  ConsumerState<AcceptInviteScreen> createState() =>
      _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  final formKey = GlobalKey<FormState>();
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  bool passwordHidden = true;
  bool confirmHidden = true;
  bool loading = true;
  bool submitting = false;
  String? email;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_lookup()));
  }

  @override
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'This invite link is missing its token.';
        });
      }
      return;
    }
    try {
      final resolved = await ref
          .read(adminProvider.notifier)
          .lookupAdminInvite(token);
      if (!mounted) return;
      setState(() {
        email = resolved;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error =
            'This invite is invalid or has expired. Ask an LGU administrator to send a new one.';
      });
    }
  }

  Future<void> _submit() async {
    final token = widget.token;
    final resolvedEmail = email;
    if (token == null || resolvedEmail == null) return;
    if (!formKey.currentState!.validate()) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await ref
          .read(adminProvider.notifier)
          .acceptAdminInvite(
            token: token,
            firstName: firstName.text,
            lastName: lastName.text,
            password: password.text,
          );
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) {
        throw StateError(
          'The connected administrator service is unavailable.',
        );
      }
      final session = await repository.signIn(
        email: resolvedEmail,
        password: password.text,
      );
      await ref.read(adminProvider.notifier).connect(session);
      if (!mounted) return;
      auth.value = session;
      context.go('/dashboard');
    } catch (caught) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        error = caught is StateError
            ? caught.message
            : 'The account could not be created. Try again.';
      });
    }
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String? hint,
    required bool hidden,
    required VoidCallback toggle,
    required String? Function(String?) validator,
  }) => TextFormField(
    controller: controller,
    obscureText: hidden,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: IconButton(
        tooltip: hidden ? 'Show password' : 'Hide password',
        onPressed: toggle,
        icon: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final Widget body;
    final resolvedEmail = email;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (resolvedEmail == null) {
      body = Panel(
        child: EmptyState(
          message: error ?? 'This invite is invalid or has expired.',
        ),
      );
    } else {
      body = Panel(
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Create your administrator account',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'for $resolvedEmail',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: firstName,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'First name'),
                validator: (value) => (value?.trim().isNotEmpty ?? false)
                    ? null
                    : 'Enter your first name.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: lastName,
                decoration: const InputDecoration(labelText: 'Last name'),
                validator: (value) => (value?.trim().isNotEmpty ?? false)
                    ? null
                    : 'Enter your last name.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: resolvedEmail,
                enabled: false,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              _passwordField(
                controller: password,
                label: 'Password',
                hint: 'At least 8 characters',
                hidden: passwordHidden,
                toggle: () => setState(() => passwordHidden = !passwordHidden),
                validator: (value) => (value?.length ?? 0) < 8
                    ? 'Enter at least 8 characters.'
                    : null,
              ),
              const SizedBox(height: 12),
              _passwordField(
                controller: confirmPassword,
                label: 'Repeat password',
                hint: null,
                hidden: confirmHidden,
                toggle: () => setState(() => confirmHidden = !confirmHidden),
                validator: (value) =>
                    value == password.text ? null : 'Passwords do not match.',
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: submitting ? null : _submit,
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create account'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AdminColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The mark's non-C details render near-white, meant for a
                // dark surface (the login screen's own navy hero) -- this
                // page's background is light, so they would be invisible
                // without a dark chip of their own behind them.
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AdminColors.rail,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SvgPicture.asset(
                    'assets/branding/arangcada-mark-dark.svg',
                    width: 32,
                    height: 32,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'ArangCada',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Accept driver invite (Spec 20) -- public route, no session required
// =============================================================================

class AcceptDriverInviteScreen extends ConsumerStatefulWidget {
  const AcceptDriverInviteScreen({super.key, required this.token});
  final String? token;

  @override
  ConsumerState<AcceptDriverInviteScreen> createState() =>
      _AcceptDriverInviteScreenState();
}

class _AcceptDriverInviteScreenState
    extends ConsumerState<AcceptDriverInviteScreen> {
  final formKey = GlobalKey<FormState>();
  final fullName = TextEditingController();
  final mobileNumber = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  bool passwordHidden = true;
  bool confirmHidden = true;
  bool loading = true;
  bool submitting = false;
  bool done = false;
  String? email;
  String? todaZoneName;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_lookup()));
  }

  @override
  void dispose() {
    fullName.dispose();
    mobileNumber.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'This invite link is missing its token.';
        });
      }
      return;
    }
    try {
      final resolved = await ref
          .read(adminProvider.notifier)
          .lookupDriverInvite(token);
      if (!mounted) return;
      setState(() {
        email = resolved.email;
        todaZoneName = resolved.todaZoneName;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error =
            'This invite is invalid or has expired. Ask an LGU administrator to send a new one.';
      });
    }
  }

  Future<void> _submit() async {
    final token = widget.token;
    if (token == null || email == null) return;
    if (!formKey.currentState!.validate()) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await ref
          .read(adminProvider.notifier)
          .acceptDriverInvite(
            token: token,
            displayName: fullName.text,
            mobileNumber: mobileNumber.text,
            password: password.text,
          );
      if (!mounted) return;
      // Unlike the admin accept flow, a driver account cannot open an
      // admin_web session at all -- AdminSession.fromProfile requires
      // role = 'admin' -- and this app has no session of its own to offer
      // a driver. The confirmation below is the entire rest of this flow.
      setState(() {
        submitting = false;
        done = true;
      });
    } catch (caught) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        error = caught is StateError
            ? caught.message
            : 'The account could not be created. Try again.';
      });
    }
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String? hint,
    required bool hidden,
    required VoidCallback toggle,
    required String? Function(String?) validator,
  }) => TextFormField(
    controller: controller,
    obscureText: hidden,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: IconButton(
        tooltip: hidden ? 'Show password' : 'Hide password',
        onPressed: toggle,
        icon: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final Widget body;
    final resolvedEmail = email;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (resolvedEmail == null) {
      body = Panel(
        child: EmptyState(
          message: error ?? 'This invite is invalid or has expired.',
        ),
      );
    } else if (done) {
      body = Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Account created',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Open the ArangCada mobile app and sign in with $resolvedEmail '
              'and the password you just set to start receiving dispatch '
              'requests for ${todaZoneName ?? 'your TODA'}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    } else {
      body = Panel(
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Create your driver account',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'for $resolvedEmail -- joining ${todaZoneName ?? 'your TODA'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: fullName,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (value) => (value?.trim().isNotEmpty ?? false)
                    ? null
                    : 'Enter your full name.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: mobileNumber,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  hintText: '09XXXXXXXXX',
                ),
                validator: (value) =>
                    (value?.replaceAll(RegExp(r'\D'), '').length ?? 0) >= 10
                    ? null
                    : 'Enter a valid mobile number.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: resolvedEmail,
                enabled: false,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              _passwordField(
                controller: password,
                label: 'Password',
                hint: 'At least 8 characters',
                hidden: passwordHidden,
                toggle: () => setState(() => passwordHidden = !passwordHidden),
                validator: (value) => (value?.length ?? 0) < 8
                    ? 'Enter at least 8 characters.'
                    : null,
              ),
              const SizedBox(height: 12),
              _passwordField(
                controller: confirmPassword,
                label: 'Repeat password',
                hint: null,
                hidden: confirmHidden,
                toggle: () => setState(() => confirmHidden = !confirmHidden),
                validator: (value) =>
                    value == password.text ? null : 'Passwords do not match.',
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: submitting ? null : _submit,
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create account'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AdminColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AdminColors.rail,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SvgPicture.asset(
                    'assets/branding/arangcada-mark-dark.svg',
                    width: 32,
                    height: 32,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'ArangCada',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
