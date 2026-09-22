import 'package:flutter/material.dart';

import '../theme.dart';

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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AdminColors.primary),
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
            color: AdminColors.primary,
          ),
        ),
        const SizedBox(height: 5),
        Text(caption, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class LabelValue extends StatelessWidget {
  const LabelValue(this.label, this.value, {super.key});
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
