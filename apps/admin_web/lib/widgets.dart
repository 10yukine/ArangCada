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
        BoxShadow(
          color: const Color(0x1F0F1A28),
          blurRadius: size * .15,
          offset: Offset(0, size * .05),
        ),
      ],
    ),
    child: SvgPicture.asset(
      'assets/branding/arangcada-mark.svg',
      width: size * .9,
      height: size * .9,
    ),
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
          gradient: RadialGradient(
            colors: onBrand
                ? [
                    Colors.white.withValues(alpha: .30),
                    Colors.white.withValues(alpha: 0),
                  ]
                : const [Color(0xFFE4F0FE), Color(0x00E4F0FE)],
          ),
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
      backgroundColor: dark
          ? Theme.of(context).scaffoldBackgroundColor
          : Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Container(
              width: 172,
              height: 172,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [glow, glow.withValues(alpha: 0)],
                ),
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
      // On a phone the toolbar already names the section, so the heading
      // steps down a size instead of taking a third of the screen.
      final phone = constraints.maxWidth < 560;
      final textTheme = Theme.of(context).textTheme;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: phone ? textTheme.headlineSmall : textTheme.headlineLarge,
          ),
          SizedBox(height: phone ? 4 : 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              subtitle,
              style: (phone ? textTheme.bodyMedium : textTheme.bodyLarge)
                  ?.copyWith(color: context.adminColor(AdminColors.muted)),
            ),
          ),
        ],
      );
      if (action == null) return heading;
      if (phone) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 12), action!],
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
      StatusTone.success => (
        context.adminColor(AdminColors.successTint),
        context.adminColor(AdminColors.success),
      ),
      StatusTone.warning => (
        context.adminColor(AdminColors.warningTint),
        context.adminColor(AdminColors.warning),
      ),
      StatusTone.danger => (
        context.adminColor(AdminColors.dangerTint),
        context.adminColor(AdminColors.danger),
      ),
      StatusTone.brand => (
        context.adminColor(AdminColors.primaryTint),
        context.adminColor(AdminColors.primaryPress),
      ),
      StatusTone.neutral => (
        context.adminColor(AdminColors.surface),
        context.adminColor(AdminColors.secondary),
      ),
    };
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
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
          ],
        ),
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
          Row(
            children: [
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
                    color: context.adminColor(AdminColors.muted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontSize: 32, height: 1),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.adminColor(AdminColors.primaryTint),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.inbox_outlined,
              size: 22,
              color: context.adminColor(AdminColors.primary),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: context.adminColor(AdminColors.muted),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String shortTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '${value.month}/${value.day} · $hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
}

/// Bumped when the phone toolbar title is tapped; the visible console page
/// scrolls back to the top (the iPhone "tap the top bar" convention).
final consoleScrollToTop = ValueNotifier<int>(0);

/// The vertical scroll view of a console page. Behaves like
/// SingleChildScrollView and also answers [consoleScrollToTop].
class ConsoleScrollView extends StatefulWidget {
  const ConsoleScrollView({
    super.key,
    required this.padding,
    required this.child,
  });

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  State<ConsoleScrollView> createState() => _ConsoleScrollViewState();
}

class _ConsoleScrollViewState extends State<ConsoleScrollView> {
  final _controller = ScrollController();

  void _toTop() {
    if (!_controller.hasClients || _controller.offset == 0) return;
    _controller.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    consoleScrollToTop.addListener(_toTop);
  }

  @override
  void dispose() {
    consoleScrollToTop.removeListener(_toTop);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _controller,
    padding: widget.padding,
    child: widget.child,
  );
}

/// `TextFormField.errorBuilder` for every console form: the error sits right
/// under its own field with an icon, instead of a summary somewhere else.
Widget adminFieldError(BuildContext context, String message) {
  final color = Theme.of(context).colorScheme.error;
  return Semantics(
    liveRegion: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.error, size: 16, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 13, height: 1.35, color: color),
          ),
        ),
      ],
    ),
  );
}

/// Clears a console form field's error as soon as that field is edited; the
/// error comes back only on the next submit. Wrap each validator with
/// [guard], call [edited] from the field's onChanged, and submit with
/// [validate] instead of `formKey.currentState!.validate()`.
class FieldErrorReset {
  final _edited = <TextEditingController>{};
  bool _submitted = false;

  FormFieldValidator<String> guard(
    TextEditingController field,
    FormFieldValidator<String> rule,
  ) =>
      (value) => _edited.contains(field) ? null : rule(value);

  void edited(TextEditingController field, GlobalKey<FormState> form) {
    if (_submitted && _edited.add(field)) form.currentState?.validate();
  }

  bool validate(GlobalKey<FormState> form) {
    _submitted = true;
    _edited.clear();
    return form.currentState!.validate();
  }
}

/// Rules for every new console password; existing passwords still sign in.
/// Mirrors the mobile app and Supabase Auth's password requirements.
String? adminPasswordProblem(String? value) {
  final password = value ?? '';
  if (password.isEmpty) return 'Create a password';
  if (password.length < 8) return 'Use at least 8 characters';
  if (!password.contains(RegExp('[A-Z]')) ||
      !password.contains(RegExp('[a-z]'))) {
    return 'Use both uppercase and lowercase letters';
  }
  if (!password.contains(RegExp('[0-9]'))) return 'Add at least one number';
  return null;
}

/// Live checklist under a new password: each rule turns green as it is met.
class AdminPasswordRequirements extends StatelessWidget {
  const AdminPasswordRequirements({
    required this.password,
    required this.repeat,
    super.key,
  });

  final TextEditingController password;
  final TextEditingController repeat;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([password, repeat]),
    builder: (context, _) {
      final value = password.text;
      Widget row(bool met, String label) {
        final color = context.adminColor(
          met ? AdminColors.success : AdminColors.muted,
        );
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Semantics(
            label: '$label, ${met ? 'done' : 'not yet'}',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  met ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 13, color: color),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(value.length >= 8, 'At least 8 characters'),
          row(
            value.contains(RegExp('[A-Z]')) && value.contains(RegExp('[a-z]')),
            'Uppercase and lowercase letters',
          ),
          row(value.contains(RegExp('[0-9]')), 'At least one number'),
          row(
            repeat.text.isNotEmpty && repeat.text == value,
            'Both passwords match',
          ),
        ],
      );
    },
  );
}
