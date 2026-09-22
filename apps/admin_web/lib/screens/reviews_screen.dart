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
class ReviewsScreen extends ConsumerStatefulWidget {
  const ReviewsScreen({super.key});
  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  String direction = 'all';
  String query = '';

  @override
  Widget build(BuildContext context) {
    ref.watch(adminProvider);
    final session = auth.value!;
    final ratings = ref
        .read(adminProvider.notifier)
        .visibleRatings(session)
        .where(
          (rating) =>
              (direction == 'all' || rating.raterRole == direction) &&
              '${rating.raterName} ${rating.rateeName} ${rating.toda} ${rating.comment ?? ''}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          title: 'Reviews',
          subtitle:
              'Every trip rating, both directions -- commuter about driver, and driver about commuter.',
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: constraints.maxWidth < 600 ? constraints.maxWidth : 320,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search reviews',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => query = value.trim()),
                ),
              ),
              SizedBox(
                width: constraints.maxWidth < 600 ? constraints.maxWidth : 240,
                child: DropdownButtonFormField<String>(
                  initialValue: direction,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Written by'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Everyone')),
                    DropdownMenuItem(
                      value: 'commuter',
                      child: Text('Commuters'),
                    ),
                    DropdownMenuItem(value: 'driver', child: Text('Drivers')),
                  ],
                  onChanged: (value) => setState(() => direction = value!),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '${ratings.length} reviews',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        ratings.isEmpty
            ? const EmptyState(message: 'No reviews in this scope.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final rating in ratings) ...[
                    _RatingTile(rating),
                    const Divider(height: 1),
                  ],
                ],
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
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(
              '${rating.raterName} rated ${rating.rateeName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Semantics(
              label: '${rating.stars} out of 5 stars',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var star = 1; star <= 5; star++)
                    Icon(
                      star <= rating.stars ? Icons.star : Icons.star_border,
                      size: 18,
                      color: context.adminColor(AdminColors.primary),
                    ),
                ],
              ),
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
