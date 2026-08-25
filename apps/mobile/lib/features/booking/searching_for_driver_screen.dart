import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/map/live_map_view.dart';
import '../../data/providers/repository_providers.dart';
import '../../demo/demo_simulation.dart';
import '../../domain/models/booking.dart';
import '../../core/widgets/arang_dialog.dart';

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
  bool _liveListenerAttached = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(demoStateProvider);
    if (ref.read(liveRideRepositoryProvider) != null) {
      // Real connected trip: attach the listener unconditionally, not only
      // when activeBooking?.status happens to read as `searching` at this
      // exact moment. A real backend's timing is not deterministic -- the
      // booking may not have synced from the server yet, or a fast driver
      // may already have accepted before this screen finished mounting.
      // Either way that status check fails and the old code never attached
      // a listener at all, so the screen sat on "Finding a driver..."
      // forever no matter what the driver did next. The point of this
      // screen is to observe whatever transition happens while it is
      // showing, so the listener must not depend on catching one specific
      // status at one specific instant.
      state.addListener(_handleLiveTripChange);
      _liveListenerAttached = true;
      // The transition may already have happened before the listener above
      // was wired up (the same race, closed). Checked once via a
      // post-frame callback, not synchronously here -- _handleLiveTripChange
      // can call context.go() through _onMatched(), and navigating from
      // inside initState(), before this widget's own build has completed,
      // is exactly the kind of premature navigation that produced the
      // driver-side "_elements.contains(element)" framework assertion
      // elsewhere in this app. Deferring one frame matches the pattern
      // SplashScreen already uses for the same reason.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleLiveTripChange();
      });
    } else if (state.activeBooking?.status == BookingStatus.searching) {
      // The scripted demo simulation is deterministic, so gating it on the
      // current status is correct here -- unlike the live case above, there
      // is no real backend timing to race against.
      _matchRun = ref
          .read(demoSimulationServiceProvider)
          .scheduleDriverMatch(state: state, onMatched: _onMatched);
    }
  }

  void _handleLiveTripChange() {
    if (!mounted || _navigated) return;
    final booking = ref.read(demoStateProvider).activeBooking;
    if (booking?.status == BookingStatus.matched) _onMatched();
  }

  void _onMatched() {
    if (!mounted || _navigated) return;
    _navigated = true;
    final state = ref.read(demoStateProvider);
    ref
        .read(chatRepositoryProvider)
        .ensureActiveTripThread(
          commuterName: state.currentUser?.displayName ?? 'Commuter',
          driverName: state.liveDriverName ?? 'Marco Dela Cruz',
          bodyNumber: '024',
          todaName: state.liveTodaName ?? 'Calamba TODA',
        );
    final callback = widget.onMatched;
    if (callback != null) {
      callback();
    } else {
      context.go('/booking/driver-matched');
    }
  }

  @override
  void dispose() {
    if (_liveListenerAttached) {
      ref.read(demoStateProvider).removeListener(_handleLiveTripChange);
    }
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
      builder: (context) => ArangDialog(
        title: 'Cancel ride request?',
        content: const Text('ArangCada will stop searching for a driver.'),
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
    final liveRides = ref.read(liveRideRepositoryProvider);
    try {
      if (liveRides == null) {
        booking.cancelSearching();
        ref.read(demoStateProvider).bookingChanged();
      } else {
        await liveRides.cancelRide();
      }
      if (context.mounted) context.go('/home');
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not cancel the request. Try again.'),
        ),
      );
    }
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
              Positioned.fill(
                // Live tiles, same as every other map surface. No routing
                // request here: nothing is routed while we are still looking
                // for a driver, so asking ORS would be a wasted call.
                child: LiveMapView(
                  center: state.pickup.coordinate,
                  borderRadius: BorderRadius.zero,
                  interactive: false,
                  markers: [
                    MapMarker(
                      coordinate: state.pickup.coordinate,
                      color: AppColors.primary,
                      radius: 9,
                    ),
                  ],
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
                              ? 'A testing override is active. Turn it off to continue.'
                              : 'Checking approved drivers in your TODA service area.',
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
        ..color = AppColors.sky.withValues(alpha: 1 - progress)
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
