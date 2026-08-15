import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/booking.dart';

class DriverMatchedScreen extends ConsumerWidget {
  const DriverMatchedScreen({super.key});

  void _showDemoContactSheet(BuildContext context, String mode) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
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
  Widget build(BuildContext context, WidgetRef ref) {
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
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 60,
                  color: AppColors.success,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your driver is ready',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                SectionCard(
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 34,
                        backgroundColor: AppColors.primaryContainer,
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
                                  _showDemoContactSheet(context, 'Message'),
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
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: () {
                    booking.beginDriverApproach();
                    state.bookingChanged();
                    context.go('/trip/approach');
                  },
                  child: const Text('Track Driver Approach'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
