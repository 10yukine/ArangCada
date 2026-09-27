import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_ui.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/driver_app_feedback.dart';

/// Mandatory app-usage research feedback, distinct from passenger ratings.
class DriverAppFeedbackScreen extends ConsumerStatefulWidget {
  const DriverAppFeedbackScreen({super.key});

  @override
  ConsumerState<DriverAppFeedbackScreen> createState() =>
      _DriverAppFeedbackScreenState();
}

class _DriverAppFeedbackScreenState
    extends ConsumerState<DriverAppFeedbackScreen> {
  final _comment = TextEditingController();
  final Map<String, int> _answers = {};
  bool _anonymous = true;
  bool _consented = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final rides = ref.read(liveRideRepositoryProvider);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (rides == null) {
        // No live repository (a local sandbox/demo session) means there is
        // no server row to submit against. This is only reachable at all if
        // driverFeedbackPending was left true from another account -- which
        // is now cleared on every sign-in -- but the screen must still have
        // an exit rather than silently doing nothing on Submit, since it is
        // otherwise unpoppable (PopScope canPop: false, no back button).
        ref.read(demoStateProvider).clearDriverFeedbackPending();
      } else {
        await rides.submitDriverFeedback(
          answers: Map.unmodifiable(_answers),
          anonymous: _anonymous,
          comment: _comment.text,
        );
      }
      // submitDriverFeedback() ends by calling notifyListeners() on the
      // repository, which is DemoState's refreshListenable for go_router --
      // that alone can trigger the router to re-evaluate its redirect in the
      // same frame this await resumes in. Calling context.go() immediately
      // after raced that redirect re-evaluation against this explicit
      // navigation and produced
      // "'_elements.contains(element)': is not true." on device. Deferring
      // one frame lets the redirect settle first, matching the pattern
      // SplashScreen and SearchingForDriverScreen use for the same class of
      // premature-navigation problem.
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/driver');
        });
      }
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = 'Could not submit yet. Check your connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final complete = _consented && DriverAppFeedback.hasValidAnswers(_answers);
    final total = DriverAppFeedback.questions.length;
    final answered = DriverAppFeedback.questions
        .where((question) => _answers.containsKey(question.key))
        .length;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Required app feedback'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            children: [
              const Text(
                'Help improve ArangCada',
                style: AppTypography.display,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Answer each item before accepting another ride.\n'
                'Sagutin ang bawat tanong bago tumanggap ng susunod na biyahe.',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Your answers support adviser-reviewed app and ISO/IEC 25010 '
                'evaluation. Anonymous is selected by default; your TODA and '
                'completed trip are still linked privately for accurate '
                'research counts.',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.md),
              // Progress keeps a long questionnaire feeling finishable.
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : answered / total,
                        minHeight: 6,
                        color: AppColors.primary,
                        backgroundColor: AppColors.primaryFill,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '$answered of $total answered',
                    style: AppTypography.caption,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              // Flat questions divided by rules, not one box per question.
              for (final question in DriverAppFeedback.questions) ...[
                const Divider(height: AppSpacing.xl),
                Text(question.english, style: AppTypography.label),
                const SizedBox(height: 2),
                Text(question.filipino, style: AppTypography.caption),
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  label:
                      '${question.english}, 1 strongly disagree to 5 strongly agree',
                  child: SegmentedButton<int>(
                    emptySelectionAllowed: true,
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      selectedBackgroundColor: AppColors.primaryFill,
                      selectedForegroundColor: AppColors.primaryText,
                    ),
                    segments: [
                      for (var score = 1; score <= 5; score++)
                        ButtonSegment(value: score, label: Text('$score')),
                    ],
                    selected: {?_answers[question.key]},
                    onSelectionChanged: _submitting
                        ? null
                        : (values) => setState(() {
                            if (values.isEmpty) return;
                            _answers[question.key] = values.single;
                          }),
                  ),
                ),
                const SizedBox(height: 4),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Strongly disagree', style: AppTypography.caption),
                    Text('Strongly agree', style: AppTypography.caption),
                  ],
                ),
              ],
              const Divider(height: AppSpacing.xl),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Submit anonymously'),
                subtitle: const Text('Hindi ipapakita ang iyong pangalan'),
                value: _anonymous,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _anonymous = value),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _comment,
                enabled: !_submitting,
                minLines: 3,
                maxLines: 5,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Suggestions / Mga mungkahi (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I understand these answers will be used for app '
                  'improvement and capstone evaluation.',
                ),
                value: _consented,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _consented = value == true),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              ArangButton(
                label: _submitting ? 'Submitting...' : 'Submit and continue',
                onPressed: _submitting
                    ? null
                    : (!complete
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please answer all questions and check '
                                    'the consent box to continue.',
                                  ),
                                ),
                              );
                            }
                          : _submit),
              ),
              if (!complete) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  answered < total
                      ? '${total - answered} left to answer'
                      : 'Check the consent box to continue',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
