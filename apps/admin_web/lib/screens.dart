export 'map_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final todas = [
      for (final boundary in state.boundaries)
        if (session.role == AdminRole.lgu || boundary.name == session.toda)
          boundary.name,
    ];
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
    final surveyResponses = todas.fold<int>(
      0,
      (total, toda) => total + (state.surveyCounts[toda] ?? 0),
    );
    final surveyTarget = todas.length * 10;
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
              detail: 'Simulated now',
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
                      child: DashboardMapPreview(rides: rides),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Synthetic ride positions · inspect prototype boundaries in the full map.',
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
                      const StatusPill('Illustrative'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _HourlyRideChart(activeRides: rides.length),
                  const SizedBox(height: 10),
                  Text(
                    'Example activity only; not collected trip history.',
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
                      const StatusPill('Local event log'),
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
                    'Scoped local records; terminal queue order is not simulated.',
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
                  const _ProgressRow(
                    label: 'Feature scenarios',
                    value: .82,
                    caption: '9 of 11 checks prepared',
                  ),
                  const SizedBox(height: 18),
                  _ProgressRow(
                    label: 'Driver survey sample',
                    value: surveyTarget == 0
                        ? 0
                        : (surveyResponses / surveyTarget).clamp(0, 1),
                    caption:
                        '$surveyResponses of $surveyTarget target responses',
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
                    'Prototype metrics support the capstone evaluation and do not represent production operations.',
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
    const todas = ['All TODAs', 'Brgy. Real', 'Parian', 'Canlubang'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          title: 'Driver verification',
          subtitle:
              'Enroll drivers, review submitted records, and preserve an auditable lifecycle.',
          action: FilledButton.icon(
            onPressed: () => _showEnrollment(context, ref),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Enroll driver'),
          ),
        ),
        const SizedBox(height: 22),
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

  @override
  Widget build(BuildContext context) {
    ref.watch(adminProvider);
    final reports = ref
        .read(adminProvider.notifier)
        .visibleReports(auth.value!);
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
      ],
    );
  }
}

class EvaluationScreen extends StatefulWidget {
  const EvaluationScreen({super.key});
  @override
  State<EvaluationScreen> createState() => _EvaluationScreenState();
}

class _EvaluationScreenState extends State<EvaluationScreen> {
  final checks = <int>{0, 1, 3};
  static const criteria = [
    ('Functional suitability', .88, 'Core dispatch and governance scenarios'),
    ('Performance efficiency', .76, 'Observed response and rendering behavior'),
    ('Interaction capability', .84, 'Task clarity and accessibility checks'),
    ('Reliability', .72, 'Recovery and state consistency scenarios'),
    ('Security', .79, 'Role scope and trusted-operation boundaries'),
    ('Safety', .81, 'Safety reporting and response traceability'),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        title: 'ISO/IEC 25010 evaluation',
        subtitle:
            'Compare the internal MVP against the traditional manual-dispatch baseline using six 2023 product-quality characteristics.',
      ),
      const SizedBox(height: 22),
      LayoutBuilder(
        builder: (context, constraints) {
          final results = Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Evaluation results',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    const StatusPill('Illustrative scores'),
                  ],
                ),
                const SizedBox(height: 18),
                for (final item in criteria)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 17),
                    child: _ProgressRow(
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
              'The displayed scores and comparisons are sample evaluation content, not final research findings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ],
  );
}

class SurveyScreen extends ConsumerStatefulWidget {
  const SurveyScreen({super.key});
  @override
  ConsumerState<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends ConsumerState<SurveyScreen> {
  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(adminProvider).surveyCounts;
    final session = auth.value!;
    final visibleCounts = <String, int>{
      for (final entry in counts.entries)
        if (session.role == AdminRole.lgu || entry.key == session.toda)
          entry.key: entry.value,
    };
    final total = visibleCounts.values.fold<int>(0, (sum, item) => sum + item);
    final target = visibleCounts.length * 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          title: 'TODA driver survey',
          subtitle:
              'Track the fixed sample target of 10 eligible respondents per TODA.',
          action: FilledButton.icon(
            onPressed: () => _showSurvey(context),
            icon: const Icon(Icons.add_chart),
            label: const Text('Record response'),
          ),
        ),
        const SizedBox(height: 22),
        _ResponsiveGrid(
          children: [
            MetricCard(
              label: 'Responses',
              value: '$total',
              detail:
                  'Across ${visibleCounts.length} TODA${visibleCounts.length == 1 ? '' : 's'}',
              icon: Icons.how_to_reg_outlined,
            ),
            MetricCard(
              label: 'Target sample',
              value: '$target',
              detail: '10 per TODA',
              icon: Icons.flag_outlined,
              tone: AdminColors.warning,
            ),
            MetricCard(
              label: 'Completion',
              value: '${target == 0 ? 0 : (total / target * 100).round()}%',
              detail: 'Prototype tracking',
              icon: Icons.donut_large_outlined,
              tone: AdminColors.success,
            ),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final progress = Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sample threshold progress',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 18),
                  for (final entry in visibleCounts.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: _ProgressRow(
                        label: entry.key,
                        value: (entry.value / 10).clamp(0, 1),
                        caption: '${entry.value} of 10 eligible respondents',
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AdminColors.warningTint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AdminColors.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Eligibility: active TODA membership and at least 3 completed trips. The questionnaire still requires validation before research use.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
            final summary = Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Illustrative Likert summary',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  const _ScoreBar('Easy to understand', 4.3),
                  const _ScoreBar('Supports dispatch work', 4.1),
                  const _ScoreBar('Improves safety visibility', 4.4),
                  const _ScoreBar('Would use during evaluation', 4.0),
                  const SizedBox(height: 12),
                  Text(
                    'Sample values only; do not cite as study results.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
            return constraints.maxWidth < 900
                ? Column(
                    children: [progress, const SizedBox(height: 16), summary],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: progress),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: summary),
                    ],
                  );
          },
        ),
      ],
    );
  }

  Future<void> _showSurvey(BuildContext context) async {
    final counts = ref.read(adminProvider).surveyCounts;
    final session = auth.value!;
    String toda = session.toda ?? counts.keys.first;
    double rating = 4;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record survey response'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Confirm respondent eligibility outside this prototype before recording.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: toda,
                  decoration: const InputDecoration(labelText: 'TODA'),
                  items: [
                    for (final name in counts.keys)
                      if (session.role == AdminRole.lgu || name == session.toda)
                        DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (value) => setDialogState(() => toda = value!),
                ),
                const SizedBox(height: 18),
                Text('Overall rating: ${rating.round()} of 5'),
                Slider(
                  value: rating,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '${rating.round()}',
                  onChanged: (value) => setDialogState(() => rating = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit response'),
            ),
          ],
        ),
      ),
    );
    if (submitted == true && context.mounted) {
      ref.read(adminProvider.notifier).recordSurveyResponse(session, toda);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Response recorded for $toda.')));
    }
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    final controller = ref.read(adminProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          title: 'Settings',
          subtitle: 'Local console preferences and evaluation context.',
        ),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            children: [
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
                      subtitle: const Text(
                        'Show simulated status notifications during evaluation.',
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
                    const _SettingRow(
                      icon: Icons.layers_outlined,
                      title: 'TODA boundaries',
                      detail: 'Prototype boundary · evaluation only',
                    ),
                    const _SettingRow(
                      icon: Icons.storage_outlined,
                      title: 'Admin records',
                      detail:
                          'Synthetic in-memory records; refresh resets changes.',
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
                      tone: StatusTone.clay,
                    ),
                  ],
                ),
              ),
            ],
          ),
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
                                      ? AdminColors.clay
                                      : AdminColors.clayTint,
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
            color: AdminColors.clay,
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
            color: AdminColors.clay,
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
              ).textTheme.titleMedium?.copyWith(color: AdminColors.clay),
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
            color: AdminColors.clay,
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
          color: selected ? AdminColors.clayTint : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(report.id, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
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
                    report.id,
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
                  _updateReport(context, ref, ReportStatus.investigating),
              child: const Text('Investigate'),
            ),
            OutlinedButton(
              onPressed: () =>
                  _updateReport(context, ref, ReportStatus.escalated),
              child: const Text('Escalate locally'),
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
      ref
          .read(adminProvider.notifier)
          .transitionReport(report.id, status, note.text);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${report.id} is now ${reportStatusLabel(status).toLowerCase()}.',
          ),
        ),
      );
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
            color: AdminColors.clayTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AdminColors.clay),
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
                'TODA endorsement',
                'Driver identification',
                'Tricycle registration',
                'Safety orientation record',
              ].indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.$1 < driver.documents
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: item.$1 < driver.documents
                        ? AdminColors.success
                        : AdminColors.muted,
                  ),
                  title: Text(item.$2),
                  trailing: Text(
                    item.$1 < driver.documents ? 'Received' : 'Missing',
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Local actions create audit events. Backend verification and storage policies are outside this evaluation build.',
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
        if (driver.status == DriverStatus.suspended)
          OutlinedButton(
            onPressed: () {
              ref
                  .read(adminProvider.notifier)
                  .updateDriver(
                    driver.id,
                    DriverStatus.approved,
                    'Reinstated after local review',
                  );
              Navigator.pop(context);
            },
            child: const Text('Reinstate'),
          )
        else
          OutlinedButton(
            onPressed: () => _confirmDriverAction(
              context,
              ref,
              driver,
              DriverStatus.suspended,
            ),
            child: const Text('Suspend'),
          ),
        OutlinedButton(
          onPressed: () =>
              _confirmDriverAction(context, ref, driver, DriverStatus.rejected),
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: driver.documents < 4
              ? null
              : () {
                  ref
                      .read(adminProvider.notifier)
                      .updateDriver(
                        driver.id,
                        DriverStatus.approved,
                        'Documents accepted in local evaluation',
                      );
                  Navigator.pop(context);
                },
          child: const Text('Approve'),
        ),
      ],
    ),
  );
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
    ref
        .read(adminProvider.notifier)
        .updateDriver(driver.id, status, reason.text);
    Navigator.pop(dialogContext);
  }
  reason.dispose();
}
