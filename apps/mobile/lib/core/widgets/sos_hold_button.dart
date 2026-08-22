import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import 'arang_dialog.dart';

class SosHoldButton extends StatefulWidget {
  const SosHoldButton({required this.onCompleted, super.key});

  final VoidCallback onCompleted;

  @override
  State<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<SosHoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _holding = false;
              widget.onCompleted();
              if (mounted) setState(() {});
              _controller.reset();
            }
          });
  }

  void _startHold() {
    setState(() => _holding = true);
    _controller.forward(from: 0);
  }

  void _cancelHold() {
    if (!_holding) return;
    setState(() => _holding = false);
    _controller.animateBack(0, duration: const Duration(milliseconds: 160));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Hold SOS for 3 seconds',
      child: GestureDetector(
        onTapDown: (_) => _startHold(),
        onTapUp: (_) => _cancelHold(),
        onTapCancel: _cancelHold,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.dangerBorder),
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadii.pill),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sos, color: AppColors.danger),
                    SizedBox(width: AppSpacing.xs),
                    Text(
                      'Hold for 3 seconds',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                LinearProgressIndicator(
                  value: _controller.value,
                  minHeight: 5,
                  color: AppColors.danger,
                  backgroundColor: AppColors.dangerFill,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showSafetyReportFlow({
  required BuildContext context,
  required bool driver,
  required Future<void> Function() onSubmit,
}) async {
  final reasons = driver
      ? const [
          'Passenger threat or harassment',
          'Refusing to pay fare',
          'Damaging tricycle or property',
          'Unsafe passenger behavior',
          'Other emergency',
        ]
      : const [
          'Unsafe driving',
          'Wrong route',
          'Harassment or threat',
          'Other emergency',
        ];
  String? selectedReason;
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppColors.danger,
              size: 38,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              driver ? 'Report passenger issue?' : 'Send emergency report?',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Choose what happened. This internal build records the report '
              'locally and does not contact emergency services.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final reason in reasons) ...[
              Semantics(
                selected: selectedReason == reason,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  onTap: () => setSheetState(() => selectedReason = reason),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: AppSizes.minTapTarget,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: selectedReason == reason
                          ? AppColors.dangerFill
                          : AppColors.surface,
                      border: Border.all(
                        color: selectedReason == reason
                            ? AppColors.danger
                            : AppColors.border,
                      ),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    alignment: Alignment.center,
                    child: Text(reason, textAlign: TextAlign.center),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            const SizedBox(height: AppSpacing.xs),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: selectedReason == null
                  ? null
                  : () => Navigator.pop(sheetContext, true),
              child: const Text('Record safety report'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, false),
              child: Text(
                driver ? 'Cancel — back to trip' : 'Cancel — I’m safe',
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (submitted != true || !context.mounted) return;
  await onSubmit();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => ArangDialog(
      icon: const Icon(Icons.shield_outlined, color: AppColors.green),
      title: 'Safety report recorded',
      content: const Text(
        'The report was saved locally for prototype review. '
        'No emergency service or administrator was contacted.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to trip'),
        ),
      ],
    ),
  );
}
