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
    return GestureDetector(
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _cancelHold(),
      onTapCancel: _cancelHold,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Semantics(
          button: true,
          label: 'Hold SOS for 3 seconds',
          value: '${(_controller.value * 100).round()}% held',
          child: ExcludeSemantics(
            child: Container(
              width: double.infinity,
              height: AppSizes.buttonHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.dangerBorder),
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppRadii.pill),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      key: const Key('sos-button-fill'),
                      widthFactor: _controller.value,
                      heightFactor: 1,
                      child: const ColoredBox(color: AppColors.danger),
                    ),
                  ),
                  const _SosLabel(color: AppColors.danger),
                  ClipRect(
                    clipper: _SosFillClipper(_controller.value),
                    child: const _SosLabel(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SosLabel extends StatelessWidget {
  const _SosLabel({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sos, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Hold for 3 seconds',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SosFillClipper extends CustomClipper<Rect> {
  const _SosFillClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * progress, size.height);

  @override
  bool shouldReclip(_SosFillClipper oldClipper) =>
      oldClipper.progress != progress;
}

Future<void> showSafetyReportFlow({
  required BuildContext context,
  required bool driver,
  required Future<void> Function() onSubmit,
  Future<void> Function(String reason)? onSubmitReason,
  bool connected = false,
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
            Text(
              connected
                  ? 'Choose what happened. ArangCada LGU/TODA administrators '
                        'will receive the report; emergency services are not contacted.'
                  : 'Choose what happened. This internal build records the report '
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
              child: Text(
                connected ? 'Send safety report' : 'Record safety report',
              ),
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
  try {
    if (onSubmitReason != null) {
      await onSubmitReason(selectedReason!);
    } else {
      await onSubmit();
    }
  } on Exception {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Safety report could not be sent. Please try again.'),
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => ArangDialog(
      icon: const Icon(Icons.shield_outlined, color: AppColors.green),
      title: connected ? 'Administrators notified' : 'Safety report recorded',
      content: Text(
        connected
            ? 'ArangCada administrators received your safety report. '
                  'Police or emergency services were not contacted.'
            : 'The report was saved locally for prototype review. '
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
