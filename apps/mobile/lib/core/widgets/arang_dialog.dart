import 'package:flutter/material.dart';

import '../../app/theme/app_dimensions.dart';

/// An [AlertDialog] whose action buttons behave like dialog actions.
///
/// The app theme deliberately gives `FilledButton`/`OutlinedButton` a
/// `minimumSize` of `Size(double.infinity, 48)`, because a screen's primary
/// call to action is full width. Inside a dialog that is wrong: Flutter lays
/// `actions` out in an `OverflowBar`, and a button demanding infinite minimum
/// width forces the bar to give up and stack vertically -- which is how
/// "Cancel" ends up floating above a full-bleed "Log Out".
///
/// This restores shrink-wrapped actions for dialogs only, keeping the 48px
/// minimum height so the tap target still meets the Android guidance. Screen
/// CTAs are untouched.
class ArangDialog extends StatelessWidget {
  const ArangDialog({
    required this.title,
    required this.actions,
    this.content,
    this.icon,
    super.key,
  });

  final String title;
  final Widget? content;
  final List<Widget> actions;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    const compact = WidgetStatePropertyAll(
      Size(0, AppSizes.minTapTarget),
    );
    const compactPadding = WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
    );

    return Theme(
      data: base.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: base.filledButtonTheme.style?.copyWith(
            minimumSize: compact,
            padding: compactPadding,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: base.outlinedButtonTheme.style?.copyWith(
            minimumSize: compact,
            padding: compactPadding,
          ),
        ),
      ),
      child: AlertDialog(
        icon: icon,
        title: Text(title),
        content: content,
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        actions: actions,
      ),
    );
  }
}
