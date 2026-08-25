import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AdminColors.muted),
          ),
        ],
      );
      if (action == null) return heading;
      if (constraints.maxWidth < 560) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 14), action!],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: heading),
          action!,
        ],
      );
    },
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Card(
      clipBehavior: onTap == null ? Clip.none : Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = StatusTone.neutral});
  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      StatusTone.success => (AdminColors.successTint, AdminColors.success),
      StatusTone.warning => (AdminColors.warningTint, AdminColors.warning),
      StatusTone.danger => (AdminColors.dangerTint, AdminColors.danger),
      StatusTone.clay => (AdminColors.clayTint, AdminColors.clayPress),
      StatusTone.neutral => (AdminColors.surface, AdminColors.secondary),
    };
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

enum StatusTone { success, warning, danger, clay, neutral }

StatusTone driverTone(DriverStatus status) => switch (status) {
  DriverStatus.approved => StatusTone.success,
  DriverStatus.review ||
  DriverStatus.submitted ||
  DriverStatus.enrolled => StatusTone.warning,
  DriverStatus.suspended ||
  DriverStatus.rejected ||
  DriverStatus.expired => StatusTone.danger,
};

StatusTone reportTone(ReportStatus status) => switch (status) {
  ReportStatus.resolved => StatusTone.success,
  ReportStatus.newReport || ReportStatus.escalated => StatusTone.danger,
  ReportStatus.acknowledged || ReportStatus.investigating => StatusTone.warning,
  ReportStatus.dismissed => StatusTone.neutral,
};

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    this.tone = AdminColors.clay,
    this.onTap,
  });
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value. $detail',
    button: onTap != null,
    onTap: onTap,
    excludeSemantics: true,
    child: Panel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: tone, size: 20),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 42),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: .55,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  value,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 35,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: AdminColors.muted),
      ),
    ),
  );
}

String shortTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '${value.month}/${value.day} · $hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
}
