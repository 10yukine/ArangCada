import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_controller.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shared_widgets.dart';

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
        ResponsiveGrid(
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
                          : ProgressRow(
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
                    child: ProgressRow(
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
            style: TextStyle(
              color: context.adminColor(AdminColors.success),
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
            backgroundColor: context.adminColor(AdminColors.surface),
            color: context.adminColor(AdminColors.success),
          ),
        ],
      ),
    ),
  );
}
