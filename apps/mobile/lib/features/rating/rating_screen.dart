import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/booking.dart';

class RatingScreen extends ConsumerStatefulWidget {
  const RatingScreen({super.key});

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

/// Said back under the stars, so a tap gets an answer in words.
const _starWords = ['Poor', 'Fair', 'Okay', 'Good', 'Great'];

class _RatingScreenState extends ConsumerState<RatingScreen> {
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
        .submitTripRating(_selectedStars, _commentController.text);
    context.go('/receipt');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(
        // Same destination as Skip below -- this is a `go()` route with
        // nothing on the Navigator stack to pop to.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Skip',
          onPressed: () => context.go('/receipt'),
        ),
        title: const Text('Rate your ride'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final booking = state.activeBooking;
            if (booking == null || booking.status != BookingStatus.completed) {
              return const Center(child: Text('No completed trip to rate.'));
            }
            final submitted = state.tripRating;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                const SizedBox(height: AppSpacing.lg),
                Text(
                  submitted == null
                      ? 'How was your ride?'
                      : 'Thanks for your feedback',
                  textAlign: TextAlign.center,
                  style: AppTypography.display,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${booking.pickupName} → ${booking.destinationName}',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption,
                ),
                const SizedBox(height: AppSpacing.xl),
                // Big stars: this is the one tap the screen exists for.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var star = 1; star <= 5; star++)
                      if (submitted == null)
                        IconButton(
                          tooltip: '$star star${star == 1 ? '' : 's'}',
                          iconSize: 40,
                          onPressed: () =>
                              setState(() => _selectedStars = star),
                          icon: Icon(
                            star <= _selectedStars
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: AppColors.primary,
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            star <= submitted
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: AppColors.primary,
                            size: 36,
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  switch (submitted ?? _selectedStars) {
                    0 => 'Tap a star',
                    final n => _starWords[n - 1],
                  },
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: (submitted ?? _selectedStars) == 0
                        ? AppColors.textMuted
                        : AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (submitted == null)
                  TextField(
                    controller: _commentController,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 240,
                    decoration: const InputDecoration(
                      labelText: 'Comment (optional)',
                      hintText: 'Tell us about your ride',
                      alignLabelWithHint: true,
                    ),
                  )
                else if (state.tripRatingComment != null)
                  Text(
                    state.tripRatingComment!,
                    textAlign: TextAlign.center,
                    style: AppTypography.body,
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
                  TextButton(
                    onPressed: () => context.go('/receipt'),
                    child: const Text('Skip'),
                  ),
                ] else
                  FilledButton(
                    onPressed: () => context.go('/receipt'),
                    child: const Text('View Receipt'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
