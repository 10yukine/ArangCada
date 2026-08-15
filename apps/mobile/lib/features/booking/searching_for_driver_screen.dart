import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/painted_calamba_map.dart';
import '../../data/providers/repository_providers.dart';
import '../../demo/demo_simulation.dart';
import '../../domain/models/booking.dart';

class SearchingForDriverScreen extends ConsumerStatefulWidget {
  const SearchingForDriverScreen({this.onMatched, super.key});

  final VoidCallback? onMatched;

  @override
  ConsumerState<SearchingForDriverScreen> createState() =>
      _SearchingForDriverScreenState();
}

class _SearchingForDriverScreenState
    extends ConsumerState<SearchingForDriverScreen> {
  DemoSimulationRun? _matchRun;

  @override
  void initState() {
    super.initState();
    final state = ref.read(demoStateProvider);
    if (state.activeBooking?.status == BookingStatus.searching) {
      _matchRun = ref
          .read(demoSimulationServiceProvider)
          .scheduleDriverMatch(state: state, onMatched: _onMatched);
    }
  }

  void _onMatched() {
    if (!mounted) return;
    final callback = widget.onMatched;
    if (callback != null) {
      callback();
    } else {
      context.go('/booking/driver-matched');
    }
  }

  @override
  void dispose() {
    _matchRun?.cancel();
    super.dispose();
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    DemoBooking booking,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel ride request?'),
        content: const Text('ArangCada will stop searching for a demo driver.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Searching'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    booking.cancelSearching();
    ref.read(demoStateProvider).bookingChanged();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Finding your driver')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final booking = state.activeBooking;
          if (booking == null || booking.status != BookingStatus.searching) {
            return const Center(child: Text('No active driver search.'));
          }
          final noDrivers = state.forceNoDriversAvailable;
          return Stack(
            children: [
              const Positioned.fill(
                child: PaintedCalambaMap(
                  height: double.infinity,
                  borderRadius: BorderRadius.zero,
                  showNearbyDrivers: true,
                  showRoute: false,
                  showDestination: false,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppRadii.sheet),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x1F1F1E1D),
                        blurRadius: 10,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 36,
                          height: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.disabledFill,
                              borderRadius: BorderRadius.all(
                                Radius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (noDrivers)
                          const Icon(
                            Icons.no_transfer_outlined,
                            size: 38,
                            color: AppColors.primary,
                          )
                        else
                          const _ScanningIndicator(),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          noDrivers
                              ? 'No drivers available right now'
                              : 'Searching for a nearby driver',
                          textAlign: TextAlign.center,
                          style: AppTypography.displaySm,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          noDrivers
                              ? 'The Demo Tools override is active. Turn it off to continue the defence flow.'
                              : 'Checking approved drivers in the Calamba TODA demo jurisdiction.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (!noDrivers)
                          const Text(
                            'We will connect you as soon as a nearby driver accepts.',
                            textAlign: TextAlign.center,
                            style: AppTypography.caption,
                          ),
                        if (!noDrivers) const SizedBox(height: AppSpacing.sm),
                        TextButton(
                          onPressed: () => _cancel(context, ref, booking),
                          child: Text(
                            noDrivers
                                ? 'Cancel request'
                                : 'Cancel ride request',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScanningIndicator extends StatefulWidget {
  const _ScanningIndicator();

  @override
  State<_ScanningIndicator> createState() => _ScanningIndicatorState();
}

class _ScanningIndicatorState extends State<_ScanningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 76,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) =>
            CustomPaint(painter: _ScanningIndicatorPainter(_controller.value)),
      ),
    );
  }
}

class _ScanningIndicatorPainter extends CustomPainter {
  const _ScanningIndicatorPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final pulseRadius = 13 + (22 * progress);
    canvas.drawCircle(
      center,
      pulseRadius,
      Paint()
        ..color = AppColors.coral.withValues(alpha: 1 - progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 30),
      (progress * math.pi * 2) - math.pi / 2,
      math.pi * 0.9,
      false,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 15, Paint()..color = AppColors.surface);
    canvas.drawCircle(center, 11, Paint()..color = AppColors.primary);
    final icon = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.location_on_rounded.codePoint),
        style: TextStyle(
          fontSize: 15,
          fontFamily: Icons.location_on_rounded.fontFamily,
          package: Icons.location_on_rounded.fontPackage,
          color: AppColors.surface,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    icon.paint(canvas, center - Offset(icon.width / 2, icon.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ScanningIndicatorPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
