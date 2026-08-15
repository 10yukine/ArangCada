import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/painted_calamba_map.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../demo/demo_simulation.dart';
import '../../domain/models/booking.dart';

class DriverApproachScreen extends ConsumerStatefulWidget {
  const DriverApproachScreen({super.key});

  @override
  ConsumerState<DriverApproachScreen> createState() =>
      _DriverApproachScreenState();
}

class _DriverApproachScreenState extends ConsumerState<DriverApproachScreen> {
  DemoSimulationRun? _arrivalRun;
  int _secondsRemaining = 0;
  bool _arrived = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(demoStateProvider);
    if (state.activeBooking?.status == BookingStatus.approaching) {
      _arrivalRun = ref
          .read(demoSimulationServiceProvider)
          .scheduleDriverArrival(
            state: state,
            onEtaChanged: (seconds) {
              if (mounted) setState(() => _secondsRemaining = seconds);
            },
            onArrived: () {
              if (mounted) setState(() => _arrived = true);
            },
            onTripStarted: () {
              if (mounted) context.go('/trip/active');
            },
          );
      _secondsRemaining = _arrivalRun!.totalSeconds;
    }
  }

  @override
  void dispose() {
    _arrivalRun?.cancel();
    super.dispose();
  }

  void _showContactSheet(String mode) {
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
              Icon(
                mode == 'Message' ? Icons.chat_outlined : Icons.call_outlined,
                size: 40,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '$mode Marco',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                mode == 'Message'
                    ? 'Demo chat preview only. No message was sent.'
                    : 'Demo call preview only. No call was placed.',
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
      builder: (context) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text(
          'Your driver is already heading to the pickup point. Cancel this ride request?',
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
    _arrivalRun?.cancel();
    final state = ref.read(demoStateProvider);
    state.activeBooking = null;
    state.bookingChanged();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Driver approaching')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final booking = state.activeBooking;
            if (booking == null ||
                booking.status != BookingStatus.approaching) {
              return const Center(child: Text('No approaching driver.'));
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                PaintedCalambaMap(
                  animateDriver: true,
                  driverAnimationDuration:
                      _arrivalRun?.duration ?? const Duration(seconds: 7),
                ),
                const SizedBox(height: AppSpacing.md),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: AppColors.clayFill,
                            child: Icon(
                              Icons.electric_rickshaw,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _arrived
                                      ? 'Marco has arrived'
                                      : 'Marco is on the way',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const Text('Tricycle 024 · Calamba TODA'),
                              ],
                            ),
                          ),
                          Text(
                            _arrived
                                ? 'Arrived'
                                : state.forceEtaFallback
                                ? 'Updating'
                                : '$_secondsRemaining sec',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: AppColors.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (state.forceEtaFallback)
                        const Text('ETA fallback · route estimate unavailable'),
                      Text(
                        _arrived
                            ? 'Your driver is at the pickup point. The trip will start automatically.'
                            : 'Driver is heading to your pickup point.',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Pickup: ${booking.pickupName}'),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showContactSheet('Message'),
                              icon: const Icon(Icons.chat_outlined),
                              label: const Text('Message'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showContactSheet('Call'),
                              icon: const Icon(Icons.call_outlined),
                              label: const Text('Call'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.dangerDark,
                  ),
                  onPressed: _arrived ? null : _cancelRide,
                  child: const Text('Cancel ride'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
