import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_controller.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';

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
