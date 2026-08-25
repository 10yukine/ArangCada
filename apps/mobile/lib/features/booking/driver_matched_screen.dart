import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../demo/demo_simulation.dart';
import '../../domain/models/booking.dart';
import '../../core/widgets/arang_dialog.dart';

class DriverMatchedScreen extends ConsumerStatefulWidget {
  const DriverMatchedScreen({super.key});

  @override
  ConsumerState<DriverMatchedScreen> createState() =>
      _DriverMatchedScreenState();
}

class _DriverMatchedScreenState extends ConsumerState<DriverMatchedScreen> {
  DemoSimulationRun? _approachRun;
  Timer? _liveTransition;

  @override
  void initState() {
    super.initState();
    final state = ref.read(demoStateProvider);
    if (state.activeBooking?.status == BookingStatus.matched) {
      if (ref.read(liveRideRepositoryProvider) == null) {
        _approachRun = ref
            .read(demoSimulationServiceProvider)
            .scheduleDriverApproachStart(
              state: state,
              onApproachStarted: _onApproachStarted,
            );
      } else {
        _liveTransition = Timer(const Duration(milliseconds: 700), () {
          if (!mounted) return;
          if (state.activeBooking?.status == BookingStatus.matched) {
            state.activeBooking!.beginDriverApproach();
            state.bookingChanged();
          }
          _onApproachStarted();
        });
      }
    }
  }

  void _onApproachStarted() {
    if (mounted) context.go('/trip/approach');
  }

  @override
  void dispose() {
    _approachRun?.cancel();
    _liveTransition?.cancel();
    super.dispose();
  }

  void _showCallSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: AppMotion.sheet,
        reverseDuration: AppMotion.sheet,
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.call_outlined,
                size: 40,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Call Marco', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Calling is unavailable in this academic prototype. No call was placed.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ArangDialog(
        title: 'Cancel ride?',
        content: const Text(
          'Your driver has been matched but has not started heading to you '
          'yet. Cancel this ride request?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Ride'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Ride'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _approachRun?.cancel();
    _liveTransition?.cancel();
    final state = ref.read(demoStateProvider);
    final liveRides = ref.read(liveRideRepositoryProvider);
    if (liveRides == null) {
      state.activeBooking = null;
      state.bookingChanged();
    } else {
      try {
        await liveRides.cancelRide();
      } on Exception {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not cancel the ride. Try again.'),
            ),
          );
        }
        return;
      }
    }
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Driver matched')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final booking = state.activeBooking;
            if (booking == null || booking.status != BookingStatus.matched) {
              return const Center(child: Text('No matched driver.'));
            }
            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (AppSpacing.md * 2),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 60,
                        color: AppColors.green,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Your driver is ready',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      const Text(
                        'Marco is getting ready to head to your pickup point.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SectionCard(
                        child: Column(
                          children: [
                            const CircleAvatar(
                              radius: 34,
                              backgroundColor: AppColors.primaryFill,
                              child: Icon(
                                Icons.person,
                                size: 38,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Marco Dela Cruz',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Text('★ 4.9 · Tricycle 024'),
                            const Text('Calamba TODA'),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        context.push('/chat/thread-active'),
                                    icon: const Icon(Icons.chat_outlined),
                                    label: const Text('Message'),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showCallSheet(context),
                                    icon: const Icon(Icons.call_outlined),
                                    label: const Text('Call'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.dangerDark,
                        ),
                        onPressed: _cancelRide,
                        child: const Text('Cancel ride'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
