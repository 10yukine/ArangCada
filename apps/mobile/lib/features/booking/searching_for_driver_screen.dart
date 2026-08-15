import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/painted_calamba_map.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/booking.dart';

class SearchingForDriverScreen extends ConsumerWidget {
  const SearchingForDriverScreen({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
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
                          const SizedBox.square(
                            dimension: 34,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
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
                          FilledButton.icon(
                            onPressed: () {
                              booking.matchDriver();
                              state.bookingChanged();
                              context.go('/booking/driver-matched');
                            },
                            icon: const Icon(Icons.person_search),
                            label: const Text('Simulate Driver Match'),
                          ),
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
