import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'models.dart';
import 'theme.dart';

/// The ArangCada app tile -- the same white rounded square as the mobile
/// splash and login badge (ArangCadaMark in apps/mobile): ~22% corner,
/// mark at ~90% of the tile, soft ink shadow.
class BrandTile extends StatelessWidget {
  const BrandTile({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(size * .215),
      boxShadow: [
        BoxShadow(color: const Color(0x1F0F1A28), blurRadius: size * .15, offset: Offset(0, size * .05)),
      ],
    ),
    child: SvgPicture.asset('assets/branding/arangcada-mark.svg',
      width: size * .9, height: size * .9),
  );
}

/// The splash moment: the app tile on a soft radial halo. Decorative only.
class BrandStage extends StatelessWidget {
  const BrandStage({super.key, this.size = 360, this.onBrand = false});
  final double size;

  /// On the blue brand gradient the halo is white; on light surfaces it is
  /// the mobile splash's pale blue.
  final bool onBrand;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: onBrand
              ? [Colors.white.withValues(alpha: .30), Colors.white.withValues(alpha: 0)]
              : const [Color(0xFFE4F0FE), Color(0x00E4F0FE)]),
        ),
        child: Center(child: BrandTile(size: size * .46)),
      ),
    ),
  );
}

class AdminLoadingScreen extends StatelessWidget {
  const AdminLoadingScreen({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glow = context.adminColor(AdminColors.primaryTint);
    return Scaffold(
      backgroundColor: dark ? Theme.of(context).scaffoldBackgroundColor : Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Container(
              width: 172,
              height: 172,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [glow, glow.withValues(alpha: 0)]),
              ),
              child: const Center(child: BrandTile(size: 84)),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Center(
                child: SizedBox(
                  width: 160,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: Theme.of(context).colorScheme.primary,
                    backgroundColor: dark
                        ? context.adminColor(AdminColors.surface)
                        : const Color(0xFFF4F7FA),
                    semanticsLabel: label,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: context.adminColor(AdminColors.muted)),
            ),
          ),
        ],
      );
      if (action == null) return heading;
      if (constraints.maxWidth < 560) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 16), action!],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: heading),
          const SizedBox(width: 16),
          // A long note in the action slot shortens instead of overflowing.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .45),
            child: action!,
          ),
        ],
      );
    },
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
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
      StatusTone.success => (context.adminColor(AdminColors.successTint), context.adminColor(AdminColors.success)),
      StatusTone.warning => (context.adminColor(AdminColors.warningTint), context.adminColor(AdminColors.warning)),
      StatusTone.danger => (context.adminColor(AdminColors.dangerTint), context.adminColor(AdminColors.danger)),
      StatusTone.brand => (context.adminColor(AdminColors.primaryTint), context.adminColor(AdminColors.primaryPress)),
      StatusTone.neutral => (context.adminColor(AdminColors.surface), context.adminColor(AdminColors.secondary)),
    };
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6,
            decoration: BoxDecoration(color: foreground, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

enum StatusTone { success, warning, danger, brand, neutral }

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

String fareClassClaimStatusLabel(String status) => switch (status) {
  'approved' => 'Approved',
  'rejected' => 'Rejected',
  _ => 'Pending review',
};

StatusTone fareClassClaimTone(String status) => switch (status) {
  'approved' => StatusTone.success,
  'rejected' => StatusTone.danger,
  _ => StatusTone.warning,
};

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    this.tone = AdminColors.primary,
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: context.adminColor(tone).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: context.adminColor(tone), size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: context.adminColor(AdminColors.muted)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontSize: 32,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
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
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
    child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: context.adminColor(AdminColors.primaryTint), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.inbox_outlined, size: 22, color: context.adminColor(AdminColors.primary)),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: context.adminColor(AdminColors.muted)),
          ),
        ),
      ]),
    ),
  );
}

String shortTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '${value.month}/${value.day} · $hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
}
