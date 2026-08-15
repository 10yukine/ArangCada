import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../demo/demo_simulation.dart';
import '../../domain/models/booking.dart';

class DriverMatchedScreen extends ConsumerStatefulWidget {
  const DriverMatchedScreen({super.key});

  @override
  ConsumerState<DriverMatchedScreen> createState() =>
      _DriverMatchedScreenState();
}

class _DriverMatchedScreenState extends ConsumerState<DriverMatchedScreen> {
  DemoSimulationRun? _approachRun;

  @override
  void initState() {
    super.initState();
    final state = ref.read(demoStateProvider);
    if (state.activeBooking?.status == BookingStatus.matched) {
      _approachRun = ref
          .read(demoSimulationServiceProvider)
          .scheduleDriverApproachStart(
            state: state,
            onApproachStarted: _onApproachStarted,
          );
    }
  }

  void _onApproachStarted() {
    if (mounted) context.go('/trip/approach');
  }

  @override
  void dispose() {
    _approachRun?.cancel();
    super.dispose();
  }

  void _showDemoContactSheet(BuildContext context, String mode) {
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
                              backgroundColor: AppColors.clayFill,
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
                                    onPressed: () => _showDemoContactSheet(
                                      context,
                                      'Message',
                                    ),
                                    icon: const Icon(Icons.chat_outlined),
                                    label: const Text('Message'),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _showDemoContactSheet(context, 'Call'),
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
