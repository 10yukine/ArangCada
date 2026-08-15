import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

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
              color: AppColors.danger.withValues(alpha: 0.08),
              border: Border.all(color: AppColors.danger),
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadii.md),
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
                  backgroundColor: AppColors.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
