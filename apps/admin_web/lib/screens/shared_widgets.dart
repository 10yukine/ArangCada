import 'package:flutter/material.dart';

import '../theme.dart';

/// Wide screens keep the queue visible; phones focus on one record at a time.
class ReviewWorkspace extends StatelessWidget {
  const ReviewWorkspace({
    super.key,
    required this.queue,
    required this.detail,
    required this.showDetail,
    required this.onBack,
  });
  final Widget queue;
  final Widget detail;
  final bool showDetail;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 840) {
        if (!showDetail) return queue;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to queue'),
            ),
            const SizedBox(height: 12),
            detail,
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 320, child: queue),
            const SizedBox(width: 24),
            Expanded(child: detail),
          ],
        ),
      );
    },
  );
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = constraints.maxWidth >= 1080
          ? children.length.clamp(1, 4)
          : constraints.maxWidth >= 620
          ? 2
          : 1;
      final width = (constraints.maxWidth - (count - 1) * 16) / count;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class ProgressRow extends StatelessWidget {
  const ProgressRow({
    super.key,
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: context.adminColor(AdminColors.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: context.adminColor(AdminColors.surface),
            color: context.adminColor(AdminColors.primary),
          ),
        ),
        const SizedBox(height: 4),
        Text(caption, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class LabelValue extends StatelessWidget {
  const LabelValue(this.label, this.value, {super.key, this.width = 180});
  final String label;
  final String value;
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(letterSpacing: .7, fontSize: 11.5),
        ),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}
