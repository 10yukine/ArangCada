import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../admin_controller.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shared_widgets.dart';

/// The Evaluation tab's sub-pages. Each has its own URL under /evaluation so
/// it can be bookmarked, reloaded, and reached with the browser's back button.
enum EvaluationSection {
  overview('', 'Overview'),
  feedback('feedback', 'Driver feedback'),
  responses('responses', 'Responses'),
  iso('iso', 'ISO/IEC 25010');

  const EvaluationSection(this.path, this.label);
  final String path;
  final String label;

  String get location => path.isEmpty ? '/evaluation' : '/evaluation/$path';
}

class EvaluationScreen extends ConsumerWidget {
  const EvaluationScreen({
    super.key,
    this.section = EvaluationSection.overview,
  });
  final EvaluationSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    final session = auth.value!;
    final data = _EvaluationData.of(state, session);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          title: 'Driver feedback and evaluation',
          subtitle:
              'Driver app-usage feedback and formal ISO/IEC 25010 quality assessment are separate, clearly labeled study instruments.',
        ),
        const SizedBox(height: 18),
        _SectionTabs(current: section, responseCount: data.responses.length),
        const SizedBox(height: 20),
        _SectionSwitcher(
          index: section.index,
          child: SelectionArea(
            key: ValueKey(section),
            child: switch (section) {
              EvaluationSection.overview => _Overview(data: data),
              EvaluationSection.feedback => _FeedbackPage(data: data),
              EvaluationSection.responses => _ResponsesPage(data: data),
              EvaluationSection.iso => const _IsoPage(),
            },
          ),
        ),
      ],
    );
  }
}

/// Everything the sub-pages read, scoped to the signed-in administrator.
class _EvaluationData {
  const _EvaluationData({
    required this.summaries,
    required this.responses,
    required this.interval,
    required this.respondentTarget,
  });

  factory _EvaluationData.of(AdminState state, AdminSession session) {
    final summaries = state.feedbackSummaries.isNotEmpty
        ? [
            for (final summary in state.feedbackSummaries)
              if (session.role == AdminRole.lgu || summary.toda == session.toda)
                summary,
          ]
        : [
            for (final name in <String>{
              ...state.feedbackCounts.keys,
              for (final driver in state.drivers) driver.toda,
              if (session.toda != null) session.toda!,
            })
              if (session.role == AdminRole.lgu || name == session.toda)
                TodaFeedbackSummary(
                  toda: name,
                  responseCount: state.feedbackCounts[name] ?? 0,
                  uniqueDrivers: state.feedbackCounts[name] ?? 0,
                  target: state.respondentTarget,
                ),
          ];
    return _EvaluationData(
      summaries: summaries,
      responses: [
        for (final response in state.feedbackResponses)
          if (session.role == AdminRole.lgu || response.toda == session.toda)
            response,
      ],
      interval: state.feedbackInterval,
      respondentTarget: state.respondentTarget,
    );
  }

  final List<TodaFeedbackSummary> summaries;
  final List<DriverAppFeedback> responses;
  final int interval;
  final int respondentTarget;

  int get responseCount =>
      summaries.fold(0, (total, summary) => total + summary.responseCount);
  int get uniqueDrivers =>
      summaries.fold(0, (total, summary) => total + summary.uniqueDrivers);
  int get target => summaries.length * respondentTarget;

  /// Mean of every submitted answer, or the response-weighted server means
  /// when individual responses are not loaded. Null when nothing exists.
  double? meanFor(String? question) {
    final observed = [
      for (final response in responses)
        for (final entry in response.scores.entries)
          if (question == null || entry.key == question) entry.value,
    ];
    if (observed.isNotEmpty) {
      return observed.fold<int>(0, (sum, value) => sum + value) /
          observed.length;
    }
    var weighted = 0.0;
    var count = 0;
    for (final summary in summaries) {
      final value = question == null
          ? summary.overallMean
          : summary.questionMeans[question];
      if (value == null || summary.responseCount == 0) continue;
      weighted += value * summary.responseCount;
      count += summary.responseCount;
    }
    return count == 0 ? null : weighted / count;
  }

  String get cadence =>
      'Required after every $interval completed trip${interval == 1 ? '' : 's'} · anonymous unless the driver chooses to share their name.';
}

// ---------------------------------------------------------------- tab strip

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.current, required this.responseCount});
  final EvaluationSection current;
  final int responseCount;

  @override
  Widget build(BuildContext context) {
    final border = context.adminColor(AdminColors.border);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final section in EvaluationSection.values)
              _SectionTab(
                label: section == EvaluationSection.responses
                    ? '${section.label} ($responseCount)'
                    : section.label,
                selected: section == current,
                onTap: () => context.go(section.location),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.adminColor(AdminColors.primary);
    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? primary : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontSize: 15,
                color: selected
                    ? primary
                    : context.adminColor(AdminColors.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- overview

class _Overview extends StatelessWidget {
  const _Overview({required this.data});
  final _EvaluationData data;

  @override
  Widget build(BuildContext context) {
    final overall = data.meanFor(null);
    final participation = data.target == 0
        ? 0.0
        : (data.uniqueDrivers / data.target).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          padding: EdgeInsets.zero,
          child: LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 860 ? 4 : 2;
              final width = box.maxWidth / columns;
              final stats = [
                (
                  'Feedback responses',
                  '${data.responseCount}',
                  'Repeat submissions counted separately',
                ),
                (
                  'Unique drivers',
                  '${data.uniqueDrivers}',
                  'of ${data.target} target across ${data.summaries.length} TODA${data.summaries.length == 1 ? '' : 's'}',
                ),
                (
                  'Average rating',
                  overall == null ? '—' : overall.toStringAsFixed(1),
                  'Five-point scale, all questions',
                ),
                (
                  'ISO/IEC 25010',
                  'Pending',
                  'Evaluator measurements not recorded',
                ),
              ];
              return Wrap(
                children: [
                  for (final (index, stat) in stats.indexed)
                    Container(
                      width: width,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      decoration: BoxDecoration(
                        border: Border(
                          left: index % columns == 0
                              ? BorderSide.none
                              : BorderSide(
                                  color: context.adminColor(AdminColors.border),
                                ),
                          top: index < columns
                              ? BorderSide.none
                              : BorderSide(
                                  color: context.adminColor(AdminColors.border),
                                ),
                        ),
                      ),
                      child: _Stat(
                        label: stat.$1,
                        value: stat.$2,
                        detail: stat.$3,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 860;
            final feedback = _InstrumentCard(
              fillHeight: wide,
              title: 'Driver App Feedback · Objective 4',
              description: data.cadence,
              progress: participation,
              progressLabel:
                  '${data.uniqueDrivers} of ${data.target} target drivers · ${(participation * 100).round()}%',
              action: 'View participation and ratings',
              onTap: () => context.go(EvaluationSection.feedback.location),
            );
            final iso = _InstrumentCard(
              fillHeight: wide,
              title: 'ISO/IEC 25010:2023 · Objective 3',
              description:
                  'Formal evaluator assessment and comparison against traditional manual dispatch; these are not driver feedback scores.',
              progress: null,
              progressLabel: 'Six quality characteristics · not yet measured',
              action: 'Open the assessment',
              onTap: () => context.go(EvaluationSection.iso.location),
            );
            return !wide
                ? Column(children: [feedback, const SizedBox(height: 16), iso])
                : IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: feedback),
                        const SizedBox(width: 16),
                        Expanded(child: iso),
                      ],
                    ),
                  );
          },
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.detail});
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value. $detail',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: context.adminColor(AdminColors.muted),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: 30,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _InstrumentCard extends StatelessWidget {
  const _InstrumentCard({
    required this.title,
    required this.description,
    required this.progress,
    required this.progressLabel,
    required this.action,
    required this.onTap,
    this.fillHeight = false,
  });
  final bool fillHeight;
  final String title;
  final String description;
  final double? progress;
  final String progressLabel;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.adminColor(AdminColors.muted),
            ),
          ),
          const SizedBox(height: 18),
          if (progress != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: context.adminColor(AdminColors.surface),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(progressLabel, style: theme.textTheme.bodySmall),
          if (fillHeight) const Spacer(),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onTap,
            iconAlignment: IconAlignment.end,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(action),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ feedback page

class _FeedbackPage extends StatelessWidget {
  const _FeedbackPage({required this.data});
  final _EvaluationData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final participation = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Participation by TODA', style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            'Unique drivers against the ${data.respondentTarget}-driver target per TODA.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          if (data.summaries.isEmpty)
            const EmptyState(
              message:
                  'No drivers or app-feedback responses are available yet.',
            )
          else
            for (final (index, item) in data.summaries.indexed) ...[
              if (index > 0) const Divider(height: 24),
              ProgressRow(
                label: item.toda,
                value: item.progress,
                caption:
                    '${item.uniqueDrivers} of ${item.target} unique drivers · ${item.responseCount} total response${item.responseCount == 1 ? '' : 's'}',
              ),
            ],
          const SizedBox(height: 14),
          Text(
            '${data.cadence} Repeat responses never inflate the unique-driver threshold.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
    final ratings = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('App-usage ratings', style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            'Five-point Likert scale · mean of submitted driver responses. Hover a bar for the distribution.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          for (final entry in feedbackQuestionLabels.entries)
            _RatingRow(
              label: entry.value,
              mean: data.meanFor(entry.key),
              distribution: [
                for (var rating = 1; rating <= 5; rating++)
                  data.responses
                      .where((response) => response.scores[entry.key] == rating)
                      .length,
              ],
            ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < 1000
          ? Column(
              children: [participation, const SizedBox(height: 16), ratings],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: participation),
                const SizedBox(width: 16),
                Expanded(child: ratings),
              ],
            ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({
    required this.label,
    required this.mean,
    required this.distribution,
  });
  final String label;
  final double? mean;
  final List<int> distribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counted = distribution.fold<int>(0, (a, b) => a + b);
    final breakdown = [
      for (var i = 0; i < 5; i++) '${i + 1}★ ${distribution[i]}',
    ].join('   ');
    return Semantics(
      label: mean == null
          ? '$label, no responses'
          : '$label, ${mean!.toStringAsFixed(1)} out of 5',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Tooltip(
                message: counted == 0
                    ? 'No individual responses loaded'
                    : breakdown,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: mean == null ? 0 : mean! / 5,
                    minHeight: 8,
                    backgroundColor: context.adminColor(AdminColors.surface),
                    color: context.adminColor(AdminColors.success),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 34,
              child: Text(
                mean == null ? '—' : mean!.toStringAsFixed(1),
                textAlign: TextAlign.right,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- responses page

class _ResponsesPage extends StatelessWidget {
  const _ResponsesPage({required this.data});
  final _EvaluationData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.responses.isEmpty) {
      return const Panel(
        child: EmptyState(message: 'No submitted driver app feedback yet.'),
      );
    }
    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${data.responses.length} submitted response${data.responses.length == 1 ? '' : 's'}',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 2),
          Text(
            'Newest first. Open a response to see every answer.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final (index, response) in data.responses.indexed) ...[
            if (index > 0) const Divider(height: 1),
            _ResponseTile(response: response),
          ],
        ],
      ),
    );
  }
}

class _ResponseTile extends StatelessWidget {
  const _ResponseTile({required this.response});
  final DriverAppFeedback response;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scores = response.scores.values;
    final average = scores.isEmpty
        ? null
        : scores.fold<int>(0, (a, b) => a + b) / scores.length;
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 14),
        expandedAlignment: Alignment.centerLeft,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(response.displayName, style: theme.textTheme.titleSmall),
        subtitle: Text(
          '${response.toda} · ${shortTime(response.submittedAt)}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (response.comment?.trim().isNotEmpty ?? false) ...[
              Icon(
                Icons.chat_bubble_outline,
                size: 16,
                color: context.adminColor(AdminColors.muted),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              average == null ? '—' : '${average.toStringAsFixed(1)} / 5',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 6,
            children: [
              for (final entry in feedbackQuestionLabels.entries)
                SizedBox(
                  width: 260,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.value,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        response.scores[entry.key]?.toString() ?? '—',
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (response.comment?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            Text(
              '“${response.comment!.trim()}”',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ ISO/IEC page

class _IsoPage extends StatefulWidget {
  const _IsoPage();
  @override
  State<_IsoPage> createState() => _IsoPageState();
}

class _IsoPageState extends State<_IsoPage> {
  final checks = <int>{};
  static const criteria = [
    ('Functional suitability', 'Core dispatch and governance scenarios'),
    ('Performance efficiency', 'Observed response and rendering behavior'),
    ('Interaction capability', 'Task clarity and accessibility checks'),
    ('Reliability', 'Recovery and state consistency scenarios'),
    ('Security', 'Role scope and trusted-operation boundaries'),
    ('Safety', 'Safety reporting and response traceability'),
  ];
  static const scenarios = [
    'Request and assign a ride',
    'Contain dispatch inside TODA scope',
    'Review and approve a driver',
    'Submit and respond to a safety report',
    'Recover after refreshing a routed view',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quality characteristics', style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            'Awaiting evaluator measurements',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final (index, item) in criteria.indexed) ...[
            if (index > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$1, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(item.$2, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Text(
                    'Not yet measured',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
    final checklist = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Test scenario checklist', style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            '${checks.length} of ${scenarios.length} scenarios checked this session',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          for (final entry in scenarios.indexed)
            CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              value: checks.contains(entry.$1),
              onChanged: (value) => setState(
                () => value == true
                    ? checks.add(entry.$1)
                    : checks.remove(entry.$1),
              ),
              title: Text(entry.$2, style: theme.textTheme.bodyMedium),
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
      ),
    );
    final comparison = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Manual baseline comparison', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          const _ComparisonRow(
            'MEASURE',
            'MANUAL DISPATCH',
            'ARANGCADA',
            header: true,
          ),
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
          const SizedBox(height: 10),
          Text(
            'Comparison dimensions are a study framework; formal evaluation results have not been collected.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, box) => box.maxWidth < 1000
              ? Column(
                  children: [results, const SizedBox(height: 16), checklist],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: results),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: checklist),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        comparison,
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow(
    this.measure,
    this.manual,
    this.arangcada, {
    this.header = false,
  });
  final String measure;
  final String manual;
  final String arangcada;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelSmall;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: header ? context.adminColor(AdminColors.background) : null,
        borderRadius: header ? BorderRadius.circular(8) : null,
        border: header
            ? null
            : Border(
                bottom: BorderSide(
                  color: context.adminColor(AdminColors.border),
                ),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              measure,
              style: header ? headerStyle : theme.textTheme.titleSmall,
            ),
          ),
          Expanded(child: Text(manual, style: header ? headerStyle : null)),
          Expanded(
            child: Text(
              arangcada,
              style: header
                  ? headerStyle
                  : TextStyle(
                      color: context.adminColor(AdminColors.success),
                      fontWeight: FontWeight.w600,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slides the tab content horizontally, in the direction of travel: a tab to
/// the right enters from the right while the old content leaves to the left,
/// and the reverse going back. Instant when the platform asks for reduced
/// motion.
class _SectionSwitcher extends StatefulWidget {
  const _SectionSwitcher({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_SectionSwitcher> createState() => _SectionSwitcherState();
}

class _SectionSwitcherState extends State<_SectionSwitcher> {
  double _direction = 1;

  @override
  void didUpdateWidget(covariant _SectionSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _direction = widget.index > oldWidget.index ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) {
          final incoming = child.key == widget.child.key;
          final offset = Tween<Offset>(
            begin: Offset(incoming ? _direction : -_direction, 0),
            end: Offset.zero,
          ).animate(animation);
          return SlideTransition(position: offset, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
