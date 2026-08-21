import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/booking.dart';

class RatingScreen extends ConsumerStatefulWidget {
  const RatingScreen({super.key});

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  final _commentController = TextEditingController();
  int _selectedStars = 0;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedStars == 0) return;
    ref
        .read(demoStateProvider)
        .submitTripRating(_selectedStars, _commentController.text);
    context.go('/receipt');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Rate your ride')),
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
                const Icon(
                  Icons.favorite_outline,
                  size: 52,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.sm),
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
                            hintText: 'Tell us about your ride',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ] else if (state.tripRatingComment != null) ...[
                        const Divider(height: AppSpacing.xl),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            state.tripRatingComment!,
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
                    onPressed: _selectedStars == 0 ? null : _submit,
                    child: const Text('Submit Rating'),
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
