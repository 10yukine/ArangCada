import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/report_issue_sheet.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/state/driver_trip_state_machine.dart';

/// Mirrors [RatingScreen], rating the passenger instead of the driver.
///
/// This did not exist before: `completeTrip()` used to route straight to
/// Earnings, and `DriverTripStateMachine` had no transition out of
/// `completed` at all, so a driver returning to Home after finishing a trip
/// was stuck there with a non-functional online toggle. "Done" here is what
/// actually closes that gap, via `finishDriverTrip()`.
class DriverRatingScreen extends ConsumerStatefulWidget {
  const DriverRatingScreen({super.key});

  @override
  ConsumerState<DriverRatingScreen> createState() => _DriverRatingScreenState();
}

class _DriverRatingScreenState extends ConsumerState<DriverRatingScreen> {
  final _commentController = TextEditingController();
  int _selectedStars = 0;
  bool _submitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedStars == 0 || _submitting) return;
    final liveRides = ref.read(liveRideRepositoryProvider);
    if (liveRides != null) {
      setState(() => _submitting = true);
      try {
        await liveRides.submitRating(
          stars: _selectedStars,
          comment: _commentController.text,
        );
      } on Exception {
        if (mounted) {
          setState(() => _submitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not send your rating. Try again.'),
            ),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    ref
        .read(demoStateProvider)
        .submitDriverTripRating(_selectedStars, _commentController.text);
    setState(() => _submitting = false);
  }

  Future<void> _done() async {
    final state = ref.read(demoStateProvider);
    final liveRides = ref.read(liveRideRepositoryProvider);
    if (liveRides != null) {
      await liveRides.refreshFeedbackState();
      if (!mounted) return;
      if (state.driverFeedbackPending) {
        context.go('/driver/app-feedback');
        return;
      }
    }
    // Skipping the rating entirely is allowed -- the trip still has to
    // finish and hand the driver back to available either way.
    if (state.driverTrip.status == DriverTripStatus.completed) {
      state.finishDriverTrip();
    }
    context.go('/driver');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(
        // Same destination as Skip below -- this is a `go()` route with
        // nothing on the Navigator stack to pop to, so the arrow is an
        // explicit call to the same _done() the Skip button uses.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Skip',
          onPressed: _done,
        ),
        title: const Text('Rate your passenger'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            if (state.driverTrip.status != DriverTripStatus.completed) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No completed trip to rate.'),
                      const SizedBox(height: AppSpacing.md),
                      ArangButton(
                        label: 'Back to Home',
                        onPressed: () => context.go('/driver'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final submitted = state.driverTripRating;
            final reportTripId = state.liveTripId;
            final rides = ref.read(liveRideRepositoryProvider);
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                const Icon(
                  Icons.favorite_outline,
                  size: 52,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  submitted == null
                      ? 'How was ${state.liveCommuterName ?? 'Joshua Adia'}?'
                      : 'Thanks for your feedback',
                  textAlign: TextAlign.center,
                  style: AppTypography.display,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${state.pickup.name} → '
                  '${state.destination?.name ?? 'Calamba City Hall'}',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption,
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionCard(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (var star = 1; star <= 5; star++)
                            if (submitted == null)
                              IconButton(
                                tooltip: '$star star${star == 1 ? '' : 's'}',
                                onPressed: () =>
                                    setState(() => _selectedStars = star),
                                icon: Icon(
                                  star <= _selectedStars
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: AppColors.primary,
                                ),
                              )
                            else
                              Icon(
                                star <= submitted
                                    ? Icons.star
                                    : Icons.star_border,
                                color: AppColors.primary,
                                size: 34,
                              ),
                        ],
                      ),
                      if (submitted == null) ...[
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _commentController,
                          minLines: 3,
                          maxLines: 5,
                          maxLength: 240,
                          decoration: const InputDecoration(
                            labelText: 'Comment (optional)',
                            hintText: 'Tell us about the passenger',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ] else if (state.driverTripRatingComment != null) ...[
                        const Divider(height: AppSpacing.xl),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            state.driverTripRatingComment!,
                            style: AppTypography.body,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (submitted == null) ...[
                  FilledButton(
                    onPressed: _selectedStars == 0 || _submitting
                        ? null
                        : _submit,
                    child: Text(_submitting ? 'Sending...' : 'Submit Rating'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(onPressed: _done, child: const Text('Skip')),
                ] else ...[
                  FilledButton(onPressed: _done, child: const Text('Done')),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: () => showReportIssueFlow(
                      context: context,
                      driver: true,
                      onSubmit: rides == null || reportTripId == null
                          ? null
                          : (category, description) => rides.createComplaint(
                              reportTripId,
                              category,
                              description,
                            ),
                    ),
                    child: const Text('Report an issue with this trip'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
